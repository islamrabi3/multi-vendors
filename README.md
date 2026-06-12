# Multi Vendor — marketplace delivery app

A multi-vendor marketplace built with **Flutter + Supabase**, launching as a food
delivery app (Talabat / HungerStation style). The database uses industry-neutral
naming (`vendors`, `products`, `vendor_categories`) so other verticals
(electronics, grocery, …) can be added later without schema changes.

Three roles in one app, picked at signup:

| Role | What they get |
|---|---|
| **Customer** | Browse vendors by category, search, banners, product options/add-ons, cart, coupons, COD or Paymob card checkout, realtime order tracking with a live driver map, addresses, favorites, reviews |
| **Vendor** | Realtime incoming-order dashboard (accept / reject / prepare / ready), menu management (sections, products, option groups, images), store settings (open/closed, fees) |
| **Driver** | Online/offline toggle, realtime pool of ready orders, claim (race-safe), active delivery map, live GPS broadcast to the customer, delivery history |

## Architecture

- **State management:** `flutter_bloc` (Cubits), feature-first folders under `lib/features/`
- **Backend:** Supabase — Postgres with RLS, Auth (email+password), Storage, Realtime
- **Realtime:** order rows stream to customer/vendor/driver screens; driver GPS is
  broadcast on a `order-tracking:{orderId}` Realtime channel (no DB writes per ping)
- **Payments:** Cash on delivery, plus Paymob unified checkout via two Edge Functions
  (`paymob-create-intention`, `paymob-webhook` with HMAC verification)
- **Maps:** `flutter_map` (OpenStreetMap) + `geolocator` — no API keys needed

## Setup

### 1. Apply the database migrations

The full schema lives in `supabase/migrations/` (enums → tables → triggers →
RPCs → RLS → realtime/storage → seed). Apply them in filename order with the
Supabase CLI:

```bash
supabase link --project-ref dvfbeaafekqdcwxogbqc
supabase db push
```

(or paste each file into the Supabase SQL editor in order).

The seed creates demo data including a demo vendor login:
`demo.vendor@example.com` / `Demo1234!`

> **Dev tip:** disable "Confirm email" under Auth → Providers → Email in the
> Supabase dashboard so signups can log in immediately.

### 2. Deploy the Edge Functions (Paymob — optional)

COD works without this step.

```bash
supabase functions deploy paymob-create-intention
supabase functions deploy paymob-webhook --no-verify-jwt
supabase secrets set \
  PAYMOB_SECRET_KEY=sk_... \
  PAYMOB_PUBLIC_KEY=pk_... \
  PAYMOB_INTEGRATION_ID=123456 \
  PAYMOB_HMAC_SECRET=...
```

Then in the Paymob dashboard set the transaction processed callback to
`https://<project>.supabase.co/functions/v1/paymob-webhook`.

### 3. Run the app

The Supabase publishable/anon key is injected at build time:

```bash
flutter pub get
flutter run --dart-define=SUPABASE_ANON_KEY=<your anon or sb_publishable key>
```

`SUPABASE_URL` can also be overridden with another `--dart-define` (defaults to
this project's URL).

## Testing the full flow locally

1. Sign up three accounts (customer / vendor / driver) — or use the demo vendor.
2. Vendor: toggle the store **Open** in Settings, add menu items.
3. Customer: add an address, order from the store (COD), watch the status stepper.
4. Vendor: accept → preparing → ready for pickup (updates appear in realtime).
5. Driver: go online, claim the order, watch the customer's map track you, mark delivered.

## Tests

```bash
flutter analyze
flutter test
```
