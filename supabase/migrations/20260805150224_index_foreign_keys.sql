-- Index every foreign key that did not have one.
--
-- An unindexed FK column costs twice: joins across it sequential-scan the
-- child table, and every delete or key update on the parent scans the child to
-- enforce the constraint. Both show up here — deleting a coupon scanned all
-- redemptions, and the driver wallet screen scanned every transaction in the
-- system to find one driver's.
--
-- Two of these were already covered by a wider composite index and are still
-- listed for completeness; `if not exists` makes that a no-op.

create index if not exists banners_vendor_id_idx on public.banners (vendor_id);
create index if not exists cart_items_product_id_idx on public.cart_items (product_id);
create index if not exists carts_vendor_id_idx on public.carts (vendor_id);
create index if not exists chat_messages_order_id_idx on public.chat_messages (order_id);
create index if not exists chat_messages_sender_id_idx on public.chat_messages (sender_id);
create index if not exists coupon_redemptions_user_id_idx on public.coupon_redemptions (user_id);
create index if not exists coupons_vendor_id_idx on public.coupons (vendor_id);
create index if not exists customer_reports_order_id_idx on public.customer_reports (order_id);
create index if not exists customer_reports_user_id_idx on public.customer_reports (user_id);
create index if not exists customer_reports_vendor_id_idx on public.customer_reports (vendor_id);
create index if not exists driver_tips_driver_id_idx on public.driver_tips (driver_id);
create index if not exists favorites_vendor_id_idx on public.favorites (vendor_id);
create index if not exists loyalty_history_user_id_idx on public.loyalty_history (user_id);
create index if not exists notification_campaigns_created_by_idx on public.notification_campaigns (created_by);
create index if not exists order_status_history_changed_by_idx on public.order_status_history (changed_by);
create index if not exists orders_coupon_id_idx on public.orders (coupon_id);
create index if not exists profiles_admin_role_id_idx on public.profiles (admin_role_id);
create index if not exists reviews_customer_id_idx on public.reviews (customer_id);
create index if not exists support_messages_sender_id_idx on public.support_messages (sender_id);
create index if not exists wallet_transactions_user_id_idx on public.wallet_transactions (user_id);
