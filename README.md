# Marketflow (Flutter + Supabase)

Production-grade Flutter e-commerce app backed by Supabase.

For full onboarding and environment setup, use [SETUP.md](SETUP.md).

## Highlights

- Email/password authentication with email verification
- Product catalog, search, product details, wishlist, cart, checkout
- Payment flows: Cash on Delivery and ABA PayWay QR
- Profile management with map-based address picker
- Customer support chat and dedicated support dashboard
- Staff dashboard for products, users, orders, events, and support requests
- Role model: `customer`, `support_agent`, `delivery`, `cashier`, `staff`, `super_admin`
- Optional backend proxy path for Vercel/web deployments

## Stack

- Flutter (Dart `^3.10.7`)
- Provider state management
- Supabase Auth + Postgres + Storage + RPC + Edge Functions
- Google Maps / geolocation (`google_maps_flutter`, `geolocator`, `geocoding`)

## Quick Start

1. Install dependencies:

```bash
flutter pub get
```

2. Run `supabase/schema.sql` in your Supabase SQL Editor.

Optional seed data: `supabase/seed_fake_products.sql`.

3. Deploy required edge functions and secrets:

```bash
supabase functions deploy resend-email
supabase secrets set RESEND_API_KEY=YOUR_RESEND_API_KEY
supabase secrets set RESEND_FROM_EMAIL="Marketflow <noreply@your-domain.com>"
supabase secrets set APP_BRAND_NAME=Marketflow
```

Optional PayWay QR:

```bash
supabase functions deploy payway-qr
supabase secrets set PAYWAY_MERCHANT_ID=YOUR_PAYWAY_MERCHANT_ID
supabase secrets set PAYWAY_API_KEY=YOUR_PAYWAY_API_KEY
supabase secrets set PAYWAY_BASE_URL=YOUR_PAYWAY_BASE_URL
```

4. Create local runtime config:

Windows PowerShell:

```powershell
Copy-Item .env.example .env
```

macOS/Linux:

```bash
cp .env.example .env
```

5. Set at least these keys in `.env`:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

6. Run app:

Windows PowerShell:

```powershell
flutter run -d chrome --dart-define-from-file=.env
```

macOS/Linux:

```bash
flutter run -d chrome --dart-define-from-file=.env
```

## Runtime Config Keys

`.env.example` contains all supported keys. Keys are centrally listed in `scripts/env-keys.txt` and used by local run scripts and Vercel build script.

Required:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

Common optional:

- `AUTH_EMAIL_FUNCTION_NAME` (default: `Resend-email`)
- `PAYWAY_FUNCTION_NAME` (default: `Payway`)
- `PAYWAY_CALLBACK_URL`
- `PAYWAY_CURRENCY` (default: `USD`)
- `PAYWAY_QR_TEMPLATE` (default: `template3_color`)
- `PAYWAY_QR_LIFETIME_MINUTES` (default: `15`)
- `SUPPORT_EMAIL`, `SUPPORT_PHONE`, support social/contact links
- `BACKEND_PROXY_URL`, `BACKEND_DATA_PROXY_URL`, `BACKEND_PROXY_TIMEOUT_SECONDS`

## Google Maps Keys

These are platform-local, not in `.env`:

- Android: `android/gradle.properties` -> `GOOGLE_MAPS_ANDROID_API_KEY`
- iOS: `ios/Flutter/Debug.xcconfig` and `ios/Flutter/Release.xcconfig` -> `GOOGLE_MAPS_IOS_API_KEY`
- Web: `web/index.html` script tag -> `YOUR_GOOGLE_MAPS_WEB_API_KEY`

## Role Routing

- `/support`: `support_agent`
- `/staff`: `staff`, `cashier`, `delivery`, `super_admin`
- `/admin`: legacy alias of `/staff`

## Deploy to Vercel

1. Import the repository in Vercel.
2. `vercel.json` uses `bash ./scripts/vercel-build.sh` and outputs `build/web`.
3. Set Vercel project environment variables for all required runtime keys (same names as `.env.example`).
4. Redeploy after env changes.

For backend proxy mode, add:

- `BACKEND_PROXY_URL=/api/supabase-function-proxy`
- `BACKEND_DATA_PROXY_URL=/api/supabase-data-proxy`
- `SUPABASE_SERVICE_ROLE_KEY` (optional but recommended for server-side proxy calls)
- Optional allow-lists: `PROXY_ALLOWED_FUNCTIONS`, `PROXY_ALLOWED_RPCS`, `PROXY_ALLOWED_TABLES`

## Developer Commands

```bash
flutter analyze
flutter test
dart format lib test
```

## Project Layout

- `lib/app/`: app entry composition and route gatekeeping
- `lib/config/`: environment/runtime config, routes, theme
- `lib/core/`: shared primitives and network proxy clients
- `lib/features/`: feature modules (`data`, `domain`, `presentation`)
- `api/`: Vercel serverless proxy endpoints
- `scripts/`: run/build/deploy helper scripts
- `supabase/`: SQL schema and edge function source
