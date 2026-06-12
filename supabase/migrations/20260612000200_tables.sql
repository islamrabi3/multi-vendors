-- Industry-neutral marketplace tables. "vendors" / "products" naming keeps the
-- schema reusable for verticals beyond food (electronics, grocery, ...).

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null default '',
  phone text,
  avatar_url text,
  role public.user_role not null default 'customer',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.vendor_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  image_url text,
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.vendors (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null unique references public.profiles (id) on delete cascade,
  category_id uuid references public.vendor_categories (id) on delete set null,
  name text not null,
  description text,
  logo_url text,
  cover_url text,
  phone text,
  address_text text,
  lat double precision,
  lng double precision,
  is_open boolean not null default false,
  is_active boolean not null default true,
  delivery_fee numeric(10, 2) not null default 0,
  min_order_amount numeric(10, 2) not null default 0,
  avg_prep_minutes int not null default 20,
  rating_avg numeric(3, 2) not null default 0,
  rating_count int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.product_categories (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid not null references public.vendors (id) on delete cascade,
  name text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid not null references public.vendors (id) on delete cascade,
  category_id uuid references public.product_categories (id) on delete set null,
  name text not null,
  description text,
  image_url text,
  price numeric(10, 2) not null check (price >= 0),
  is_available boolean not null default true,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create table public.product_option_groups (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id) on delete cascade,
  name text not null,
  min_select int not null default 0,
  max_select int not null default 1,
  sort_order int not null default 0
);

create table public.product_options (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.product_option_groups (id) on delete cascade,
  name text not null,
  price_delta numeric(10, 2) not null default 0,
  is_available boolean not null default true
);

create table public.addresses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  label text not null default 'Home',
  street text not null,
  building text,
  floor text,
  apartment text,
  notes text,
  lat double precision,
  lng double precision,
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);

-- One active cart per user, bound to a single vendor.
create table public.carts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.profiles (id) on delete cascade,
  vendor_id uuid not null references public.vendors (id) on delete cascade,
  updated_at timestamptz not null default now()
);

create table public.cart_items (
  id uuid primary key default gen_random_uuid(),
  cart_id uuid not null references public.carts (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete cascade,
  quantity int not null check (quantity > 0),
  -- Array of selected option ids: [{"option_id": "...", "group_id": "..."}].
  -- Prices are recomputed server-side at checkout; never trusted from the client.
  selected_options jsonb not null default '[]'::jsonb,
  notes text,
  created_at timestamptz not null default now()
);

create table public.coupons (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  vendor_id uuid references public.vendors (id) on delete cascade, -- null = platform-wide
  discount_type public.discount_type not null,
  value numeric(10, 2) not null check (value > 0),
  min_order_amount numeric(10, 2) not null default 0,
  max_discount numeric(10, 2),
  expires_at timestamptz,
  usage_limit int,
  used_count int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique,
  customer_id uuid not null references public.profiles (id),
  vendor_id uuid not null references public.vendors (id),
  driver_id uuid references public.profiles (id),
  -- Snapshot of the delivery destination (and customer contact) at order time.
  delivery_address jsonb not null,
  delivery_lat double precision,
  delivery_lng double precision,
  status public.order_status not null default 'pending',
  subtotal numeric(10, 2) not null,
  delivery_fee numeric(10, 2) not null default 0,
  discount numeric(10, 2) not null default 0,
  total numeric(10, 2) not null,
  payment_method public.payment_method not null default 'cod',
  payment_status public.payment_status not null default 'unpaid',
  coupon_id uuid references public.coupons (id),
  customer_notes text,
  rejection_reason text,
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  ready_at timestamptz,
  picked_up_at timestamptz,
  delivered_at timestamptz,
  cancelled_at timestamptz,
  updated_at timestamptz not null default now()
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  product_id uuid references public.products (id) on delete set null,
  product_name text not null,
  unit_price numeric(10, 2) not null,
  quantity int not null check (quantity > 0),
  -- Snapshot: [{"option_id": "...", "name": "...", "price_delta": 0}].
  selected_options jsonb not null default '[]'::jsonb,
  line_total numeric(10, 2) not null
);

create table public.order_status_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  status public.order_status not null,
  changed_by uuid references public.profiles (id),
  created_at timestamptz not null default now()
);

create table public.drivers (
  id uuid primary key references public.profiles (id) on delete cascade,
  vehicle_type text not null default 'motorcycle',
  is_online boolean not null default false,
  current_lat double precision,
  current_lng double precision,
  location_updated_at timestamptz
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  provider text not null default 'paymob',
  amount numeric(10, 2) not null,
  status public.payment_status not null,
  provider_transaction_id text,
  provider_order_id text,
  raw_payload jsonb,
  created_at timestamptz not null default now()
);

create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders (id) on delete cascade,
  customer_id uuid not null references public.profiles (id) on delete cascade,
  vendor_id uuid not null references public.vendors (id) on delete cascade,
  rating int not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now()
);

create table public.favorites (
  user_id uuid not null references public.profiles (id) on delete cascade,
  vendor_id uuid not null references public.vendors (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, vendor_id)
);

create table public.banners (
  id uuid primary key default gen_random_uuid(),
  image_url text not null,
  vendor_id uuid references public.vendors (id) on delete cascade,
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create index idx_vendors_category on public.vendors (category_id);
create index idx_products_vendor on public.products (vendor_id);
create index idx_products_category on public.products (category_id);
create index idx_option_groups_product on public.product_option_groups (product_id);
create index idx_options_group on public.product_options (group_id);
create index idx_addresses_user on public.addresses (user_id);
create index idx_cart_items_cart on public.cart_items (cart_id);
create index idx_orders_customer on public.orders (customer_id);
create index idx_orders_vendor on public.orders (vendor_id);
create index idx_orders_driver on public.orders (driver_id);
create index idx_orders_status on public.orders (status);
create index idx_order_items_order on public.order_items (order_id);
create index idx_status_history_order on public.order_status_history (order_id);
create index idx_payments_order on public.payments (order_id);
create index idx_reviews_vendor on public.reviews (vendor_id);
