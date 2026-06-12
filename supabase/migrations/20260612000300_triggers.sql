-- Profile bootstrap, updated_at maintenance, order numbering,
-- status history logging, and vendor rating aggregation.

-- Create a profile (and driver row when applicable) for every new auth user.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.user_role;
begin
  v_role := coalesce(
    nullif(new.raw_user_meta_data ->> 'role', '')::public.user_role,
    'customer'
  );

  insert into public.profiles (id, full_name, phone, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.raw_user_meta_data ->> 'phone',
    v_role
  );

  if v_role = 'driver' then
    insert into public.drivers (id) values (new.id);
  end if;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Generic updated_at bump.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger trg_profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

create trigger trg_vendors_updated_at
  before update on public.vendors
  for each row execute function public.set_updated_at();

create trigger trg_carts_updated_at
  before update on public.carts
  for each row execute function public.set_updated_at();

create trigger trg_orders_updated_at
  before update on public.orders
  for each row execute function public.set_updated_at();

-- Human-readable order numbers: ORD-260612-0001.
create sequence public.order_number_seq;

create or replace function public.set_order_number()
returns trigger
language plpgsql
as $$
begin
  if new.order_number is null or new.order_number = '' then
    new.order_number :=
      'ORD-' || to_char(now(), 'YYMMDD') || '-' ||
      lpad(nextval('public.order_number_seq')::text, 4, '0');
  end if;
  return new;
end;
$$;

create trigger trg_orders_order_number
  before insert on public.orders
  for each row execute function public.set_order_number();

-- Audit trail of every status the order goes through (including creation).
create or replace function public.log_order_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    insert into public.order_status_history (order_id, status, changed_by)
    values (new.id, new.status, auth.uid());
  end if;
  return new;
end;
$$;

create trigger trg_orders_log_status
  after insert or update of status on public.orders
  for each row execute function public.log_order_status();

-- Keep vendors.rating_avg / rating_count in sync with reviews.
create or replace function public.apply_review_to_vendor()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.vendors
  set rating_avg = round(
        ((rating_avg * rating_count) + new.rating) / (rating_count + 1), 2),
      rating_count = rating_count + 1
  where id = new.vendor_id;
  return new;
end;
$$;

create trigger trg_reviews_apply
  after insert on public.reviews
  for each row execute function public.apply_review_to_vendor();
