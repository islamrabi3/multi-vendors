-- Core enums for the multi-vendor marketplace.
create type public.user_role as enum ('customer', 'vendor', 'driver', 'admin');

create type public.order_status as enum (
  'pending',
  'accepted',
  'preparing',
  'ready_for_pickup',
  'out_for_delivery',
  'delivered',
  'cancelled',
  'rejected'
);

create type public.payment_method as enum ('cod', 'paymob');

create type public.payment_status as enum ('unpaid', 'pending', 'paid', 'failed', 'refunded');

create type public.discount_type as enum ('percentage', 'fixed');
