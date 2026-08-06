-- Every admin action that costs money, ends an account, or changes what a
-- store is paid now asks for its own permission and leaves a record.
--
-- `has_permission` still lets an unrestricted admin through, so an existing
-- deployment behaves exactly as before until somebody is actually given a
-- limited role.

create or replace function public.admin_set_user_blocked(
  p_user_id uuid,
  p_blocked boolean,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_permission('users.block') then
    raise exception 'FORBIDDEN';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'CANNOT_BLOCK_SELF';
  end if;
  if exists (select 1 from public.profiles
             where id = p_user_id and role = 'admin') then
    raise exception 'CANNOT_BLOCK_ADMIN';
  end if;

  update public.profiles
  set is_blocked = p_blocked,
      blocked_reason = case when p_blocked then p_reason else null end,
      blocked_at = case when p_blocked then now() else null end
  where id = p_user_id;

  if p_blocked then
    update public.drivers set is_online = false where id = p_user_id;
  end if;

  perform public.log_admin_action(
    case when p_blocked then 'user.block' else 'user.unblock' end,
    'profile', p_user_id, jsonb_build_object('reason', p_reason));
end;
$$;

create or replace function public.admin_delete_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_permission('users.delete') then
    raise exception 'FORBIDDEN';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'CANNOT_DELETE_SELF';
  end if;
  if exists (select 1 from public.profiles
             where id = p_user_id and role = 'admin') then
    raise exception 'CANNOT_DELETE_ADMIN';
  end if;

  update public.vendors
  set is_active = false, is_open = false, approval_status = 'suspended'
  where owner_id = p_user_id;

  update public.drivers set is_online = false where id = p_user_id;

  update public.profiles
  set deleted_at = now(),
      is_blocked = true,
      full_name = 'Deleted user',
      phone = null,
      avatar_url = null,
      fcm_token = null
  where id = p_user_id;

  perform public.log_admin_action('user.delete', 'profile', p_user_id);
end;
$$;

create or replace function public.admin_set_vendor_status(
  p_vendor_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_permission('vendors.approve') then
    raise exception 'FORBIDDEN';
  end if;
  if p_status not in ('pending', 'active', 'suspended', 'rejected') then
    raise exception 'INVALID_STATUS';
  end if;

  update public.vendors
  set approval_status = p_status,
      -- A suspended store must not keep taking orders while it argues.
      is_open = case when p_status = 'active' then is_open else false end,
      is_active = case when p_status = 'active' then is_active else false end
  where id = p_vendor_id;

  perform public.log_admin_action('vendor.status', 'vendor', p_vendor_id,
    jsonb_build_object('status', p_status));
end;
$$;

create or replace function public.admin_set_driver_status(
  p_driver_id uuid,
  p_status text,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_permission('drivers.approve') then
    raise exception 'FORBIDDEN';
  end if;
  if p_status not in ('pending', 'active', 'suspended', 'rejected') then
    raise exception 'INVALID_STATUS';
  end if;

  update public.drivers
  set approval_status = p_status,
      approved_at = case when p_status = 'active' then now() else approved_at end,
      rejection_reason = case when p_status in ('rejected', 'suspended')
                              then p_reason else null end,
      -- Comes off the road in the same statement.
      is_online = case when p_status = 'active' then is_online else false end
  where id = p_driver_id;

  perform public.log_admin_action('driver.status', 'driver', p_driver_id,
    jsonb_build_object('status', p_status, 'reason', p_reason));
end;
$$;

create or replace function public.admin_refund_order_to_wallet(p_order_id uuid)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_amount numeric;
begin
  if not public.has_permission('payments.refund') then
    raise exception 'FORBIDDEN';
  end if;

  select * into v_order from public.orders where id = p_order_id;
  if not found then
    raise exception 'ORDER_NOT_FOUND';
  end if;
  if v_order.payment_status <> 'paid' then
    raise exception 'ORDER_NOT_PAID';
  end if;
  if v_order.payment_method = 'cod' then
    raise exception 'NOT_A_CARD_ORDER';
  end if;
  if v_order.status not in ('cancelled', 'rejected') then
    raise exception 'ORDER_NOT_CANCELLED';
  end if;
  if v_order.payment_status = 'refunded' then
    raise exception 'ALREADY_REFUNDED';
  end if;

  v_amount := v_order.total;

  insert into public.wallets (user_id, balance)
  values (v_order.customer_id, v_amount)
  on conflict (user_id) do update set balance = public.wallets.balance + v_amount;

  insert into public.wallet_transactions
    (user_id, type, amount, reference_id, description)
  values (v_order.customer_id, 'refund', v_amount, p_order_id::text,
          'Refund for order ' || v_order.order_number);

  update public.orders set payment_status = 'refunded' where id = p_order_id;

  perform public.log_admin_action('order.refund', 'order', p_order_id,
    jsonb_build_object('amount', v_amount));

  return v_amount;
end;
$$;

create or replace function public.admin_set_vendor_recommended(
  p_vendor_id uuid,
  p_recommended boolean,
  p_rank integer default 0
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_permission('vendors.promote') then
    raise exception 'FORBIDDEN';
  end if;

  update public.vendors
  set is_recommended = p_recommended,
      recommended_rank = case when p_recommended then coalesce(p_rank, 0) else 0 end
  where id = p_vendor_id;

  perform public.log_admin_action('vendor.recommend', 'vendor', p_vendor_id,
    jsonb_build_object('recommended', p_recommended, 'rank', p_rank));
end;
$$;

create or replace function public.admin_assign_driver(
  p_order_id uuid,
  p_driver_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_permission('orders.assign') then
    raise exception 'FORBIDDEN';
  end if;

  update public.orders
  set driver_id = p_driver_id,
      status = case when status = 'ready_for_pickup' then 'out_for_delivery'::order_status
                    else status end,
      picked_up_at = coalesce(picked_up_at, now())
  where id = p_order_id;

  perform public.log_admin_action('order.assign', 'order', p_order_id,
    jsonb_build_object('driver_id', p_driver_id));
end;
$$;

-- The terms trigger gets the same treatment: an admin without the finance
-- permission may not change what a store is charged.
create or replace function public.guard_vendor_platform_terms()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.delivery_fee is distinct from old.delivery_fee
     or new.commission_rate is distinct from old.commission_rate
     or new.billing_model is distinct from old.billing_model
     or new.subscription_fee is distinct from old.subscription_fee
     or new.subscription_renews_at is distinct from old.subscription_renews_at then
    if not public.has_permission('vendors.terms') then
      raise exception 'PLATFORM_TERMS_ADMIN_ONLY';
    end if;
  end if;

  if new.approval_status is distinct from old.approval_status
     or new.is_recommended is distinct from old.is_recommended
     or new.recommended_rank is distinct from old.recommended_rank then
    if not public.is_admin() then
      raise exception 'PLATFORM_TERMS_ADMIN_ONLY';
    end if;
  end if;

  return new;
end;
$$;
