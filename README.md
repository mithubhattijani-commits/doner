# Doner — Android App (1.0.0)

Flutter app for the Aman Blood Donor Society of Pakistan: donor
directory, social home feed, and in-app updates. Forked from the Aman
Blood Donor app 1.3.4 source (repo `mithubhattijani-commits/aman-blood-app`,
branch `main`); this repo never modifies that source repo.

## What is in 1.0.0
- **Home:** society slogan, 24-hour central contact (call + WhatsApp),
  patient-blood-group → compatible donor groups lookup, plus the
  existing member-code photo updates feed.
- **Social feed (NEW):** members post daily-work updates with a camera
  photo + text; posts show newest first with photo + text + author
  name + time. Any member can like (toggle per member) and add text
  comments. Posting, liking and commenting are gated by the same
  session-only member-code mechanism as the existing home feed.
  Privacy rule: feed posts show name + photo + text ONLY — never phone
  numbers (phones stay admin-only). The feed starts EMPTY: no post,
  like or comment is ever seeded or faked. If the backend is
  unavailable, the tab shows an honest error / "not set up" state —
  never a crash, never fake data.
- **Directory:** full Pakistan structure — 7 provinces, 160 districts,
  known areas — with search, plus LIVE public donors from the society
  API (name + blood group + address only, never phones).
- **Become a donor:** registration form (name, phone, province, district,
  area, blood group, address) posted to the server; the phone is stored
  under a separate admin-only key and never shown publicly.
- **Admin:** PIN-gated phone list (app-only, PIN session-only) via the
  admin endpoint — the ONLY view that renders phone numbers.
- **Server config + updater:** remote config from
  `nigraantv.xyz/apps/doner-config.json` (fail-soft defaults) and the
  in-app updater against `nigraantv.xyz/apps/doner-version.json`
  (manifest format `{"versionCode","versionName","url","notes"}`; the
  manifest file itself is published separately from the website side).
  Same package + same key + higher versionCode = update, never reinstall.
- **Info:** mission, 4 donation steps, eligibility, blood-group
  compatibility table, leadership (Sami Ullah Watto — Founder & Central
  Chairman; Rai Ghulam Jillani Bhatti — Spokesperson), FAQ, footer.

## Backend
Society API base: `https://aman-blood-donor-society.mithubhattijani.workers.dev`
(Cloudflare Worker + KV, shared with the society website backend).
Existing donor endpoints (`/api/donors`, `/api/admin/donors`) are
untouched. New social-feed endpoints (KV-backed, same Worker):
`GET /api/feed/posts`, `POST /api/feed/posts` (X-Member-Code),
`POST /api/feed/posts/:id/like` (X-Member-Code + X-Member-Id),
`GET|POST /api/feed/posts/:id/comments` (POST: X-Member-Code).
All member-gated writes fail closed with 401 while `MEMBER_CODE` is
unset or the code does not match; no `MEMBER_CODE` or `ADMIN_KEY`
values are stored in this repo. The legacy blood-request feed
(`GET|POST /api/feed`) is unchanged.

## Ads — Google TEST units only
This first build wires Google TEST ad units only (Banner,
Interstitial, Native, App Open; Rewarded intentionally unwired — no
unlockable feature). It earns nothing yet. Real AdMob units need a NEW
AdMob app registration later (a new app/package must not reuse Aman's
AdMob app or unit IDs); only then replace the test IDs in
`lib/services/ad_service.dart` and `AndroidManifest.xml`.

## Build
Free GitHub Actions cloud build (`.github/workflows/build-apk.yml`):
checkout → free disk space → Temurin 17 → Flutter stable →
`flutter pub get` → `flutter analyze` → keystore-signed
`flutter build apk --debug` → verification (aapt2 badging, apksigner
fingerprint, size + md5, unzip clean, updater URL present, zero
`com.amanblood` references) → upload artifact.
Local Gradle builds do not work in the build VM (loopback blocked) —
use the cloud route only. DEBUG build, NO shrinking/compression (an
uncompressed build is mandatory — a compressed build previously crashed
on the user's phone).
App label: "Doner". Package: `com.doner.app`. Version: 1.0.0+1.
targetSdk 36, minSdk 24. Signing: fresh Doner day-1 keystore (alias
`doner`, RSA 2048, 10,000-day validity), stored ONLY in this repo's
GitHub Actions secrets (`KEYSTORE_BASE64`, `KEYSTORE_STORE_PASSWORD`,
`KEYSTORE_KEY_PASSWORD`) — never committed, never reused from
Aman/TJ, never an ephemeral CI key.

## Honest limitation
The society's live donor records live in its Cloudflare KV store and are
NOT bundled in this app. No donor is ever invented. Device testing was
not possible from the build environment (no emulator path); the user's
phone test is the verdict — this build is not claimed device-tested.
