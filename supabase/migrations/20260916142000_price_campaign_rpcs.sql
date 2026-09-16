-- Starting a campaign raises every price in its scope; ending it puts them
-- back. Both are idempotent, so the scheduler can run as often as it likes.
create or replace function public.price_campaign_start(p_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_campaign public.price_campaigns%rowtype;
  v_count integer := 0;
begin
  select * into v_campaign from public.price_campaigns where id = p_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if v_campaign.status = 'active' then return 0; end if;
  if v_campaign.status = 'ended' then raise exception 'CAMPAIGN_ENDED'; end if;

  insert into public.price_campaign_items (campaign_id, product_id, base_price, applied_price)
  select
    v_campaign.id,
    p.id,
    p.price,
    round(p.price * (100 + v_campaign.markup_percent) / 100.0, 2)
  from public.products p
  join public.vendors v on v.id = p.vendor_id
  where p.price > 0
    and (
      v_campaign.scope = 'all'
      or (v_campaign.scope = 'vendor' and p.vendor_id = v_campaign.vendor_id)
      or (v_campaign.scope = 'category' and v.category_id = v_campaign.category_id)
    )
    -- A product already inside a running campaign is left alone: two uplifts
    -- on one price would compound.
    and not exists (
      select 1 from public.price_campaign_items i
      join public.price_campaigns c on c.id = i.campaign_id
      where i.product_id = p.id and c.status = 'active'
    )
  on conflict do nothing;

  update public.products p
  set price = i.applied_price
  from public.price_campaign_items i
  where i.campaign_id = v_campaign.id and i.product_id = p.id;

  get diagnostics v_count = row_count;

  update public.price_campaigns
  set status = 'active', started_at = now()
  where id = p_id;

  return v_count;
end;
$$;

create or replace function public.price_campaign_end(p_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
begin
  -- Only prices the campaign itself set are put back. A price the store
  -- changed while the campaign ran is theirs, and is left as it stands.
  update public.products p
  set price = i.base_price
  from public.price_campaign_items i
  where i.campaign_id = p_id
    and i.product_id = p.id
    and p.price = i.applied_price;

  get diagnostics v_count = row_count;

  update public.price_campaigns
  set status = 'ended', ended_at = now()
  where id = p_id and status <> 'ended';

  return v_count;
end;
$$;

create or replace function public.admin_create_price_campaign(
  p_name text,
  p_markup_percent numeric,
  p_scope text,
  p_vendor_id uuid default null,
  p_category_id uuid default null,
  p_starts_at timestamptz default null,
  p_ends_at timestamptz default null,
  p_start_now boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not public.has_permission('catalog.manage') then
    raise exception 'FORBIDDEN';
  end if;
  if coalesce(btrim(p_name), '') = '' then
    raise exception 'NAME_REQUIRED';
  end if;
  if p_markup_percent is null or p_markup_percent <= 0 then
    raise exception 'INVALID_PERCENT';
  end if;
  if p_scope = 'vendor' and p_vendor_id is null then
    raise exception 'VENDOR_REQUIRED';
  end if;
  if p_scope = 'category' and p_category_id is null then
    raise exception 'CATEGORY_REQUIRED';
  end if;
  if p_ends_at is not null and p_starts_at is not null and p_ends_at <= p_starts_at then
    raise exception 'INVALID_SCHEDULE';
  end if;

  insert into public.price_campaigns (
    name, markup_percent, scope, vendor_id, category_id,
    starts_at, ends_at, created_by
  ) values (
    btrim(p_name), p_markup_percent, coalesce(p_scope, 'all'),
    case when p_scope = 'vendor' then p_vendor_id end,
    case when p_scope = 'category' then p_category_id end,
    coalesce(p_starts_at, now()), p_ends_at, auth.uid()
  )
  returning id into v_id;

  if p_start_now or coalesce(p_starts_at, now()) <= now() then
    perform public.price_campaign_start(v_id);
  end if;

  perform public.log_admin_action('catalog.price_campaign', 'price_campaign', v_id,
    jsonb_build_object('percent', p_markup_percent, 'scope', p_scope));

  return v_id;
end;
$$;

create or replace function public.admin_end_price_campaign(p_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  if not public.has_permission('catalog.manage') then
    raise exception 'FORBIDDEN';
  end if;
  v_count := public.price_campaign_end(p_id);
  perform public.log_admin_action('catalog.price_campaign_end', 'price_campaign', p_id,
    jsonb_build_object('restored', v_count));
  return v_count;
end;
$$;

-- Runs on a schedule: starts campaigns whose time has come and ends the ones
-- whose time is up, so an admin never has to be awake for either.
create or replace function public.apply_due_price_campaigns()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_changed integer := 0;
begin
  for r in
    select id from public.price_campaigns
    where status = 'scheduled' and starts_at <= now()
      and (ends_at is null or ends_at > now())
  loop
    perform public.price_campaign_start(r.id);
    v_changed := v_changed + 1;
  end loop;

  for r in
    select id from public.price_campaigns
    where status in ('scheduled', 'active')
      and ends_at is not null and ends_at <= now()
  loop
    perform public.price_campaign_end(r.id);
    v_changed := v_changed + 1;
  end loop;

  return v_changed;
end;
$$;

revoke all on function public.price_campaign_start(uuid) from public, anon, authenticated;
revoke all on function public.price_campaign_end(uuid) from public, anon, authenticated;
revoke all on function public.apply_due_price_campaigns() from public, anon, authenticated;
grant execute on function public.admin_create_price_campaign(text, numeric, text, uuid, uuid, timestamptz, timestamptz, boolean) to authenticated;
grant execute on function public.admin_end_price_campaign(uuid) to authenticated;

select cron.schedule(
  'apply-due-price-campaigns',
  '*/5 * * * *',
  $cron$select public.apply_due_price_campaigns();$cron$
)
where not exists (
  select 1 from cron.job where jobname = 'apply-due-price-campaigns'
);
