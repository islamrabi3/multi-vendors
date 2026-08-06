-- Ads: placements, a schedule, video, and numbers to sell against.
--
-- `banners` is one flat list that appears in exactly one carousel, is either
-- on or off, and reports nothing. That is a decoration, not ad space. The
-- table is extended rather than replaced so every existing banner keeps
-- working — they become home-carousel image ads that started in the past and
-- never end.

alter table public.banners
  -- Where it appears. A single list could only ever fill one slot.
  add column if not exists placement text not null default 'home_carousel'
    check (placement in (
      'home_carousel',   -- the offers strip at the top of the home page
      'home_inline',     -- between sections on the home page
      'vendor_top',      -- above a store's menu
      'cart',            -- the cart screen
      'order_tracking'   -- while the customer waits
    )),
  add column if not exists media_type text not null default 'image'
    check (media_type in ('image', 'video')),
  -- Videos autoplay muted and looping; a poster covers the first frame.
  add column if not exists video_url text,
  add column if not exists poster_url text,
  -- A campaign runs between dates rather than being switched on by hand at
  -- midnight. Null start = live now, null end = until switched off.
  add column if not exists starts_at timestamptz,
  add column if not exists ends_at timestamptz,
  -- Who it is worth showing to.
  add column if not exists audience text not null default 'all'
    check (audience in ('all', 'new_customers', 'returning_customers')),
  -- What it cost and who bought it, so the numbers below mean something
  -- commercially rather than only operationally.
  add column if not exists advertiser text,
  -- Counters, kept on the row: an ad list has to sort and filter by them, and
  -- an aggregate over an events table on every admin page load is a waste.
  add column if not exists impressions bigint not null default 0,
  add column if not exists clicks bigint not null default 0,
  -- Where tapping it goes when it is not a coupon or a store.
  add column if not exists link_url text;

comment on column public.banners.placement is
  'Which surface the ad renders on. Adding a value here needs a matching '
  'widget in the app; an unknown placement simply never renders.';

create index if not exists banners_placement_idx
  on public.banners (placement, sort_order) where is_active;

-- What the customer app asks for: everything live for one surface, right now.
--
-- The schedule is applied here rather than in the client so an ad cannot run
-- early or late because a phone's clock is wrong.
create or replace function public.active_ads(
  p_placement text,
  p_is_new_customer boolean default false
)
returns setof public.banners
language sql
stable
security definer
set search_path = public
as $$
  select *
  from public.banners b
  where b.is_active
    and b.placement = p_placement
    and (b.starts_at is null or b.starts_at <= now())
    and (b.ends_at is null or b.ends_at > now())
    and (
      b.audience = 'all'
      or (b.audience = 'new_customers' and p_is_new_customer)
      or (b.audience = 'returning_customers' and not p_is_new_customer)
    )
    -- A store's ad is pulled the moment the store is closed or suspended;
    -- sending customers to a shut restaurant is worse than showing nothing.
    and (
      b.vendor_id is null
      or exists (
        select 1 from public.vendors v
        where v.id = b.vendor_id
          and v.is_active
          and v.approval_status = 'active'
          and public.is_owner_active(v.owner_id)
      )
    )
  order by b.sort_order, b.created_at desc;
$$;

grant execute on function public.active_ads(text, boolean) to anon, authenticated;

-- Impressions and clicks.
--
-- Counted server-side because the numbers are billable: a client that can
-- write them directly can inflate them. Both are deliberately cheap and
-- fire-and-forget — an ad that fails to record a view must still render.
create or replace function public.record_ad_event(
  p_ad_id uuid,
  p_event text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_event = 'impression' then
    update public.banners set impressions = impressions + 1 where id = p_ad_id;
  elsif p_event = 'click' then
    update public.banners set clicks = clicks + 1 where id = p_ad_id;
  else
    raise exception 'INVALID_EVENT';
  end if;
end;
$$;

grant execute on function public.record_ad_event(uuid, text) to anon, authenticated;

-- Whether this customer has ever had an order served, for the audience rule.
-- Cheap enough to call once when the home page loads.
create or replace function public.is_new_customer()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not exists (
    select 1 from public.orders
    where customer_id = auth.uid()
      and status not in ('cancelled', 'rejected')
  );
$$;

grant execute on function public.is_new_customer() to authenticated;
