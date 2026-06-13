-- Demo/seed data so the app has something to show immediately.
-- Demo vendor login: demo.vendor@example.com / Demo1234!

create extension if not exists pgcrypto;

-- Vendor categories (cuisines today; other verticals like Electronics later).
insert into public.vendor_categories (id, name, image_url, sort_order) values
  ('11111111-0000-0000-0000-000000000001', 'Burgers',  'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=400', 1),
  ('11111111-0000-0000-0000-000000000002', 'Pizza',    'https://images.unsplash.com/photo-1513104890138-7c749659a591?w=400', 2),
  ('11111111-0000-0000-0000-000000000003', 'Sushi',    'https://images.unsplash.com/photo-1579871494447-9811cf80d66c?w=400', 3),
  ('11111111-0000-0000-0000-000000000004', 'Desserts', 'https://images.unsplash.com/photo-1551024506-0bccd828d307?w=400', 4),
  ('11111111-0000-0000-0000-000000000005', 'Drinks',   'https://images.unsplash.com/photo-1544145945-f90425340c7e?w=400', 5),
  ('11111111-0000-0000-0000-000000000006', 'Grocery',  'https://images.unsplash.com/photo-1542838132-92c53300491e?w=400', 6);

insert into public.banners (image_url, sort_order) values
  ('https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=800', 1),
  ('https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=800', 2),
  ('https://images.unsplash.com/photo-1540189549336-e6e99c3679fe?w=800', 3);

insert into public.coupons (code, discount_type, value, min_order_amount, max_discount) values
  ('WELCOME10', 'percentage', 10, 50, 30),
  ('SAVE20', 'fixed', 20, 100, null);

-- Demo vendor auth user (triggers profile creation).
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
) values (
  '00000000-0000-0000-0000-000000000000',
  '22222222-0000-0000-0000-000000000001',
  'authenticated', 'authenticated',
  'demo.vendor@example.com',
  extensions.crypt('Demo1234!', extensions.gen_salt('bf')),
  now(),
  '{"provider":"email","providers":["email"]}',
  '{"full_name":"Demo Vendor","role":"vendor","phone":"+201000000001"}',
  now(), now(), '', '', '', ''
);

insert into auth.identities (
  id, user_id, provider_id, identity_data, provider,
  last_sign_in_at, created_at, updated_at
) values (
  gen_random_uuid(),
  '22222222-0000-0000-0000-000000000001',
  '22222222-0000-0000-0000-000000000001',
  '{"sub":"22222222-0000-0000-0000-000000000001","email":"demo.vendor@example.com","email_verified":true}',
  'email', now(), now(), now()
);

insert into public.vendors (
  id, owner_id, category_id, name, description, logo_url, cover_url, phone,
  address_text, lat, lng, is_open, delivery_fee, min_order_amount, avg_prep_minutes
) values (
  '33333333-0000-0000-0000-000000000001',
  '22222222-0000-0000-0000-000000000001',
  '11111111-0000-0000-0000-000000000001',
  'Burger Lab',
  'Smash burgers, loaded fries and shakes — made fresh to order.',
  'https://images.unsplash.com/photo-1571091718767-18b5b1457add?w=400',
  'https://images.unsplash.com/photo-1550547660-d9450f859349?w=800',
  '+201000000001',
  '12 Tahrir Square, Cairo', 30.0444, 31.2357,
  true, 25, 50, 25
);

insert into public.product_categories (id, vendor_id, name, sort_order) values
  ('44444444-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000001', 'Burgers', 1),
  ('44444444-0000-0000-0000-000000000002', '33333333-0000-0000-0000-000000000001', 'Sides', 2),
  ('44444444-0000-0000-0000-000000000003', '33333333-0000-0000-0000-000000000001', 'Drinks', 3);

insert into public.products (id, vendor_id, category_id, name, description, image_url, price, sort_order) values
  ('55555555-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000001', '44444444-0000-0000-0000-000000000001',
   'Classic Smash', 'Single smash patty, american cheese, pickles, lab sauce.',
   'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=400', 95, 1),
  ('55555555-0000-0000-0000-000000000002', '33333333-0000-0000-0000-000000000001', '44444444-0000-0000-0000-000000000001',
   'Double Trouble', 'Two smash patties, double cheese, caramelized onions.',
   'https://images.unsplash.com/photo-1553979459-d2229ba7433b?w=400', 140, 2),
  ('55555555-0000-0000-0000-000000000003', '33333333-0000-0000-0000-000000000001', '44444444-0000-0000-0000-000000000002',
   'Loaded Fries', 'Fries topped with cheese sauce, jalapenos and lab sauce.',
   'https://images.unsplash.com/photo-1573080496219-bb080dd4f877?w=400', 60, 1),
  ('55555555-0000-0000-0000-000000000004', '33333333-0000-0000-0000-000000000001', '44444444-0000-0000-0000-000000000003',
   'Vanilla Shake', 'Hand-spun vanilla milkshake.',
   'https://images.unsplash.com/photo-1572490122747-3968b75cc699?w=400', 55, 1);

insert into public.product_option_groups (id, product_id, name, min_select, max_select, sort_order) values
  ('66666666-0000-0000-0000-000000000001', '55555555-0000-0000-0000-000000000001', 'Size', 1, 1, 1),
  ('66666666-0000-0000-0000-000000000002', '55555555-0000-0000-0000-000000000001', 'Add-ons', 0, 3, 2),
  ('66666666-0000-0000-0000-000000000003', '55555555-0000-0000-0000-000000000002', 'Add-ons', 0, 3, 1);

insert into public.product_options (group_id, name, price_delta) values
  ('66666666-0000-0000-0000-000000000001', 'Regular', 0),
  ('66666666-0000-0000-0000-000000000001', 'Large', 25),
  ('66666666-0000-0000-0000-000000000002', 'Extra Cheese', 10),
  ('66666666-0000-0000-0000-000000000002', 'Bacon', 20),
  ('66666666-0000-0000-0000-000000000002', 'Fried Egg', 12),
  ('66666666-0000-0000-0000-000000000003', 'Extra Cheese', 10),
  ('66666666-0000-0000-0000-000000000003', 'Bacon', 20);
