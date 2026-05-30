# innawoods

Privacy-first real-time group coordination & mapping for off-grid crews —
riders, hunters, anyone who heads out with a party and wants to see each other
on a map without being tracked by anyone else.

**Privacy above everything.** The server stores only encrypted blobs. It never
holds the keys, so it never sees a coordinate, a pin, a route, or a message.

---

## Privacy / crypto model

All crypto uses the open-source [`cryptography`](https://pub.dev/packages/cryptography)
package (Apache-2.0). No proprietary or unaudited Signal port.

| Element | What it is | Who sees it |
|---|---|---|
| **Identity keypair** | X25519, generated on first run | public key → server; private key → device keystore only |
| **Group secret** | random 256-bit value per party | **never sent to the server**; travels in the invite |
| **Group key** | `HKDF-SHA256(group secret, salt = party id)` | derived on-device by every member |
| **Payloads** | locations, pins, routes, messages | `XChaCha20-Poly1305` sealed under the group key, server stores ciphertext only |

**Invite link:** `innawoods://join/<CODE>#<SECRET>`
The `CODE` is a public lookup code the server knows. The `SECRET` after `#` is
the key material the server never receives (URL-fragment pattern). A recipient
looks the party up by `CODE`, then derives the group key locally from `SECRET`.

RLS on Supabase is **access control only** (who may read which rows), never
content inspection — content is opaque ciphertext.

## Status — Phase 1 complete ✅

- [x] Supabase schema + RLS policies + lifecycle RPCs (`supabase/migrations/`)
- [x] X25519 identity key generation + secure storage
- [x] Group-key derivation + XChaCha20-Poly1305 payload sealing (`lib/core/crypto/`)
- [x] Verified end-to-end: encrypt → store → read-back-as-ciphertext → decrypt,
      plus RLS enforcement and ephemeral self-destruct

Next: Phase 2 (party UI + invite/join flow), then the map (Phase 3).

## Running

```bash
flutter pub get
flutter test                      # crypto + widget tests (no backend needed)

# End-to-end verification against a Supabase instance:
supabase start                    # local stack (Docker), applies migrations
dart run tool/verify_e2e.dart \
  --url  http://127.0.0.1:54321 \
  --anon <publishable/anon key from `supabase status`>

# The app reads backend config from --dart-define:
flutter run \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon key>
```

## Map regions (offline)

The map renders from a `.pmtiles` vector basemap stored on the device. The
in-app **region download manager** (Settings → Map → Downloaded regions, or
`/maps`) lists supported regions; users tap to download a `.pmtiles` file from
the URL declared in `lib/shared/services/region_catalog.dart`.

There is **no public per-state PMTiles CDN**. You host the `.pmtiles` files
yourself (S3, R2, a GitHub release asset, etc.) and put those URLs in the
catalog. Build a region with the [`pmtiles extract`](https://docs.protomaps.com/pmtiles/cli)
CLI + a bounding-box GeoJSON, against a Protomaps daily dump.

Glyphs (fonts), sprite (icons), and the MapLibre runtime are bundled in the APK
so the map works offline once a region is downloaded. Terrain DEM is currently
fetched live from AWS Terrarium — bundling it per-region is the open
follow-on for fully-offline 3D.

## iOS / TestFlight via Codemagic

`codemagic.yaml` at the repo root defines an `ios` workflow that builds the
`.ipa` and ships it to TestFlight. Before the first build:

1. **App Store Connect:** create an app record with bundle id
   `com.innawoods.innawoods`. Copy its numeric App ID into the workflow's
   `APP_STORE_APPLE_ID` env var.
2. **Codemagic integrations:** add an App Store Connect API key under the name
   `app-store-connect` (matches the `integrations:` block).
3. **Codemagic env-var group:** create one named `supabase-prod` with
   `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
4. Connect the repo to Codemagic and push to `main`.

The Android workflow in the same file produces a release APK from every push
to `main`, using the same Supabase env group.

## Layout

```
lib/core/crypto/     identity keys, group key, AEAD, invite encoding
lib/core/config/     build-time Supabase config (--dart-define)
lib/core/theme/      dark earth-tone theme
supabase/migrations/ schema, RLS, RPCs, realtime, purge
tool/verify_e2e.dart end-to-end privacy proof
test/crypto/         crypto unit tests (incl. zero-plaintext + tamper)
```
