# Setup Guide

This guide covers local setup for the `marketflow` Flutter app with Supabase.

## 1. Prerequisites

- Flutter SDK with Dart `^3.10.7`
- Supabase project
- Supabase CLI (for edge function deployment)
- Optional PayWay credentials for QR payments

Quick checks:

```bash
flutter --version
flutter doctor -v
supabase --version
```

## 2. Install Dependencies

From project root:

```bash
flutter pub get
```

## 3. Configure Supabase Database

1. Open Supabase Dashboard.
2. Go to SQL Editor.
3. Run `supabase/schema.sql`.

Notes:

- Re-run the latest `supabase/schema.sql` after pulling backend changes from the repo.
- The current schema includes support-desk order recovery RPCs, including support-side delivery address updates.

Optional seed data:

- Run `supabase/seed_fake_products.sql`.

## 4. Deploy Auth Email Edge Function

The app uses `resend-email` for signup verification and optional promotional email.

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase functions deploy resend-email
supabase secrets set RESEND_API_KEY=YOUR_RESEND_API_KEY
supabase secrets set RESEND_FROM_EMAIL="Marketflow <noreply@your-domain.com>"
supabase secrets set APP_BRAND_NAME=Marketflow
```

Source:

- `supabase/functions/resend-email/index.ts`

## 5. Deploy PayWay Edge Function (Optional)

Skip if you only need Cash on Delivery.

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase functions deploy payway-qr
supabase secrets set PAYWAY_MERCHANT_ID=YOUR_PAYWAY_MERCHANT_ID
supabase secrets set PAYWAY_API_KEY=YOUR_PAYWAY_API_KEY
supabase secrets set PAYWAY_BASE_URL=YOUR_PAYWAY_BASE_URL
```

Source:

- `supabase/functions/payway-qr/index.ts`

Optional automation (reads OS env vars first, then `.env`):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\deploy-payway.ps1 -Token YOUR_SUPABASE_ACCESS_TOKEN
```

## 6. Configure 6-Digit Email Verification Template

In Supabase dashboard:

1. Authentication -> Providers -> Email
2. Enable Confirm email
3. Authentication -> Email Templates -> Confirm signup
4. Use `{{ .Token }}` (not `{{ .ConfirmationURL }}`)

Example template:

```html
<h2>Confirm your signup</h2>
<p>Enter this 6-digit code in the app:</p>
<p><strong>{{ .Token }}</strong></p>
```

## 7. Configure Local Runtime Values

Create local config file:

Windows PowerShell:

```powershell
Copy-Item .env.example .env
```

macOS/Linux:

```bash
cp .env.example .env
```

Set required keys:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

Common optional keys:

- `AUTH_EMAIL_FUNCTION_NAME`
- `PAYWAY_FUNCTION_NAME`
- `PAYWAY_CALLBACK_URL`
- `PAYWAY_CURRENCY`
- `PAYWAY_QR_TEMPLATE`
- `PAYWAY_QR_LIFETIME_MINUTES`
- `SUPPORT_EMAIL`
- `SUPPORT_PHONE`
- `SUPPORT_WHATSAPP_URL`
- `SUPPORT_TELEGRAM_URL`
- `SUPPORT_FACEBOOK_URL`
- `SUPPORT_MESSENGER_URL`
- `SUPPORT_STORE_LOCATION_URL`
- `SUPPORT_FAQ_URL`
- `SUPPORT_HOURS`
- `BACKEND_PROXY_URL`
- `BACKEND_DATA_PROXY_URL`
- `BACKEND_PROXY_TIMEOUT_SECONDS`
- `STOREFRONT_PUBLIC_URL`

Notes:

- `.env.example` is safe to commit.
- `.env` is gitignored.
- Supported runtime keys are listed in `scripts/env-keys.txt`.
- Set `STOREFRONT_PUBLIC_URL` in production so shared product links use your public storefront domain.

## 8. Configure Google Maps API Keys

Android and iOS keys stay platform-local. Web helper builds can read the web key from `.env` or Vercel env:

- Android: set `GOOGLE_MAPS_ANDROID_API_KEY` in OS env or repo-root `.env` (Gradle reads OS env first, then `.env`, then `android/gradle.properties` as a legacy fallback)
- iOS: set `GOOGLE_MAPS_IOS_API_KEY` in:
  - `ios/Flutter/Debug.xcconfig`
  - `ios/Flutter/Release.xcconfig`
- Web helper builds and local helper runs: set `GOOGLE_MAPS_WEB_API_KEY` in `.env` or your Vercel env
  If it is unset, the helper scripts remove the Google Maps web script and web map features stay disabled cleanly.
- Direct local `flutter run -d chrome` without helpers: replace `YOUR_GOOGLE_MAPS_WEB_API_KEY` in `web/index.html`

## 9. Run the App

Windows PowerShell:

```powershell
.\scripts\run-web.ps1
```

macOS/Linux:

```bash
./scripts/run-web.sh
```

Explicit fallback (without `.env` define file):

```bash
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

## 10. Bootstrap Staff and Other Roles

Create a user once in the app, then update profile role in SQL Editor:

```sql
update public.profiles
set account_type = 'staff'
where id = 'YOUR_USER_UUID';
```

Other examples:

```sql
update public.profiles set account_type = 'cashier' where id = 'YOUR_USER_UUID';
update public.profiles set account_type = 'support_agent' where id = 'YOUR_USER_UUID';
update public.profiles set account_type = 'delivery' where id = 'YOUR_USER_UUID';
update public.profiles set account_type = 'super_admin' where id = 'YOUR_USER_UUID';
```

Canonical account types:

- `customer`
- `support_agent`
- `delivery`
- `cashier`
- `staff`
- `super_admin`

Legacy aliases normalized by app logic:

- `rider` -> `delivery`
- `admin` -> `staff`

Find latest users:

```sql
select id, email, created_at
from auth.users
order by created_at desc;
```

## 11. Optional: Configure Backend Proxy (Web/Vercel)

Use this when you want browser traffic to call your Vercel backend proxy endpoints instead of hitting Supabase endpoints directly.

Runtime keys:

- `BACKEND_PROXY_URL=/api/supabase-function-proxy`
- `BACKEND_DATA_PROXY_URL=/api/supabase-data-proxy`
- `BACKEND_PROXY_TIMEOUT_SECONDS=20`

Vercel server env (for proxy handlers):

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY` (optional, recommended for server-side function auth)
- `GOOGLE_MAPS_WEB_API_KEY` (required if you use the web map picker)

Optional allow-lists:

- `PROXY_ALLOWED_FUNCTIONS`
- `PROXY_ALLOWED_RPCS`
- `PROXY_ALLOWED_TABLES`

Proxy files:

- `api/supabase-function-proxy.js`
- `api/supabase-data-proxy.js`
- `scripts/vercel-build.sh`
- `scripts/flutter-version.txt`

Vercel note:

- `scripts/vercel-build.sh` now bootstraps Flutter automatically when `flutter` is missing from PATH in Linux CI
- Default CI Flutter version comes from `scripts/flutter-version.txt`
- You can override that version in Vercel with `FLUTTER_VERSION`

## 12. Configure Release Identifiers and Signing

- Android application id / namespace default to `com.marketflow.app`
- iOS bundle identifier default is `com.marketflow.app`
- For Android release signing, copy `android/key.properties.example` to `android/key.properties` and add your keystore values

## 13. Verify Setup

Checklist:

- App launches without `Missing SUPABASE_URL or SUPABASE_ANON_KEY`
- Sign up and sign in work
- Email verification sends and confirms successfully
- Product list loads
- Cart and checkout complete using Cash on Delivery
- Optional PayWay flow returns a QR payload
- Staff/support roles can open their dashboards
- Blocked delivery orders show recovery actions in customer order history
- Support-agent dashboard can open a linked recovery order from a support request
- Support-agent dashboard can apply a customer-provided updated delivery address after the latest schema is applied
- Support-agent dashboard can move requests through `Pending`, `Address applied`, and `Resolved`

## 14. Common Commands

```bash
flutter analyze
flutter test
dart format lib test
```

## 15. Troubleshooting

- `Missing SUPABASE_URL or SUPABASE_ANON_KEY`:
  set keys in `.env` and run with `--dart-define-from-file=.env`.
- Email send fails with missing Resend secrets:
  set `RESEND_API_KEY` and `RESEND_FROM_EMAIL`, then redeploy `resend-email`.
- PayWay function fails with missing merchant/API/base URL:
  set PayWay secrets and redeploy `payway-qr`.
- Map picker cannot access location:
  grant runtime location permission.
- Staff/support routes unavailable:
  ensure `public.profiles.account_type` is set correctly.
- Support desk can open linked orders but `Apply updated address` fails:
  run the latest `supabase/schema.sql` so `rpc_staff_update_order_address` exists in Supabase.
