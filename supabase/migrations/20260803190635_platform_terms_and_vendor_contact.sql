-- ---------------------------------------------------------------------------
-- 1. Commercial terms belong to the platform, not to the store.
--
-- `delivery_fee` and `commission_rate` sat on `vendors` behind a policy that
-- let the owner update any column of their own row — so a store could set its
-- own delivery fee, and undercut or gouge the platform's pricing at will. The
-- columns stay where they are (every total reads them); what changes is who
-- may write them.
-- ---------------------------------------------------------------------------
alter table public.vendors
  -- How the platform earns from this store. Picked once at sign-up, changed
  -- afterwards only by an admin.
  add column if not exists billing_model text not null default 'commission'
    check (billing_model in ('commission', 'subscription')),
  -- Charged per period when the model is `subscription`; commission is then
  -- not taken, which is the whole point of the choice.
  add column if not exists subscription_fee numeric(10,2) not null default 0,
  add column if not exists subscription_renews_at timestamptz;

comment on column public.vendors.billing_model is
  'commission = platform takes commission_rate% of each order. '
  'subscription = platform takes subscription_fee per period and 0% per order.';

create or replace function public.guard_vendor_platform_terms()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Admins set terms; nobody else may, however they reach the table.
  if public.is_admin() then
    return new;
  end if;

  if new.delivery_fee is distinct from old.delivery_fee
     or new.commission_rate is distinct from old.commission_rate
     or new.billing_model is distinct from old.billing_model
     or new.subscription_fee is distinct from old.subscription_fee
     or new.subscription_renews_at is distinct from old.subscription_renews_at
     -- Approval is the admin's word too, and it was writable the same way.
     or new.approval_status is distinct from old.approval_status
     or new.is_recommended is distinct from old.is_recommended
     or new.recommended_rank is distinct from old.recommended_rank then
    raise exception 'PLATFORM_TERMS_ADMIN_ONLY';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_vendor_platform_terms on public.vendors;
create trigger trg_guard_vendor_platform_terms
  before update on public.vendors
  for each row execute function public.guard_vendor_platform_terms();

-- The one place a vendor still chooses: the model they sign up on. Called
-- during onboarding, before there is anything to bill.
create or replace function public.vendor_choose_billing_model(
  p_vendor_id uuid,
  p_model text,
  p_subscription_fee numeric default 0
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_model not in ('commission', 'subscription') then
    raise exception 'INVALID_BILLING_MODEL';
  end if;
  if not exists (
    select 1 from public.vendors
    where id = p_vendor_id and owner_id = auth.uid()
  ) then
    raise exception 'FORBIDDEN';
  end if;
  -- Only before the store goes live. After that it is a commercial change and
  -- goes through an admin, or a store could drop to a subscription the moment
  -- it got busy.
  if exists (
    select 1 from public.vendors
    where id = p_vendor_id and approval_status = 'active'
  ) then
    raise exception 'BILLING_MODEL_LOCKED';
  end if;

  update public.vendors
  set billing_model = p_model,
      subscription_fee = case when p_model = 'subscription'
                              then coalesce(p_subscription_fee, 0) else 0 end,
      commission_rate = case when p_model = 'subscription' then 0
                             else commission_rate end
  where id = p_vendor_id;
end;
$$;

revoke execute on function public.vendor_choose_billing_model(uuid, text, numeric)
  from public, anon;
grant execute on function public.vendor_choose_billing_model(uuid, text, numeric)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 2. The driver's line to the store.
--
-- A driver at a locked door, or holding an order that is missing an item, had
-- the customer's number and no way to reach the restaurant: `vendors.phone` is
-- readable, but only for stores the customer catalogue exposes, and the driver
-- needs it for the specific order they are carrying.
-- ---------------------------------------------------------------------------
create or replace function public.order_vendor_contact(p_order_id uuid)
returns table (name text, phone text)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  return query
    select v.name, v.phone
    from public.orders o
    join public.vendors v on v.id = o.vendor_id
    where o.id = p_order_id
      -- The people actually involved in this delivery.
      and (o.driver_id = auth.uid()
           or o.customer_id = auth.uid()
           or public.is_admin())
      and v.phone is not null
      and v.phone <> '';
end;
$$;

revoke execute on function public.order_vendor_contact(uuid) from public, anon;
grant execute on function public.order_vendor_contact(uuid) to authenticated;
