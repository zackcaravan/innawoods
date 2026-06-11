# Innawoods: Backcountry

Privacy-first real-time group coordination & mapping for off-grid crews —
riders, hunters, anyone who heads out with a party and wants to see each other
on a map without being tracked by anyone else.

**Privacy above everything.** The server stores only encrypted blobs. It never
holds the keys, so it never sees a coordinate, a pin, a route, or a message.

> **Source-available + on-store.** This repo *is* the app. The exact same code
> ships on the iOS App Store and Google Play as **Innawoods: Backcountry**. If
> you'd rather not build it yourself, install from a store. If you'd rather
> trust nothing but what you compile, build from here. Both paths are
> first-class — the licensing model assumes both.

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

## Status

Rough-draft feature-complete, in App Store TestFlight + Play Closed Testing.

- End-to-end encrypted realtime party (locations, pins, routes, chat)
- Anonymous Supabase auth — no email, phone, or password ever asked
- Offline vector basemaps via PMTiles + MapLibre, per-region downloads
- Background tracking + recorded tracks
- Meshtastic LoRa bridge for cell-dead operation
- FCM party-invite push, dead-man switch in progress

## Building from source

If you want to compile the app yourself instead of installing from a store:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test                # crypto + widget tests, no backend needed
```

The store builds point at a Supabase project I run. **Don't ship a binary
pointed at my URL** — host your own:

1. Create a Supabase project at <https://supabase.com>.
2. Apply migrations: `supabase db push` against your project, or copy the SQL
   files in `supabase/migrations/` manually.
3. Build with your own `--dart-define`:

   ```bash
   flutter run --release \
     --dart-define=SUPABASE_URL=https://<your-project>.supabase.co \
     --dart-define=SUPABASE_ANON_KEY=<your-anon-key>
   ```

End-to-end verification against a local Supabase stack:

```bash
supabase start                # Docker; applies migrations
dart run tool/verify_e2e.dart \
  --url http://127.0.0.1:54321 \
  --anon <publishable key from `supabase status`>
```

Android release signing wants your own keystore (`keytool -genkeypair -v
-keystore innawoods.jks -keyalg RSA -keysize 4096 -alias innawoods` and a
matching `android/key.properties`). iOS release signing wants an Apple
Developer account. `codemagic.yaml` documents the full CI release pipeline I
use, including the env-var groups and integrations it expects.

## Map regions (offline)

The map renders from a `.pmtiles` vector basemap stored on the device. The
in-app **region download manager** (Settings → Map → Downloaded regions, or
`/maps`) lists supported regions; users tap to download a `.pmtiles` file from
the URL declared in `lib/shared/services/region_catalog.dart`.

There is **no public per-state PMTiles CDN**. The store build pulls regions
from this repo's GitHub releases. If you fork, host the `.pmtiles` files
wherever you want (S3, R2, your own release page) and update the catalog. Build
a region with the [`pmtiles extract`](https://docs.protomaps.com/pmtiles/cli)
CLI + a bounding-box GeoJSON, against a Protomaps daily dump.

Glyphs (fonts), sprite (icons), and the MapLibre runtime are bundled in the APK
so the map works offline once a region is downloaded. Terrain DEM is currently
fetched live from AWS Terrarium — bundling it per-region is the open follow-on
for fully-offline 3D.

## License

**AGPL-3.0-or-later.** See [`LICENSE`](LICENSE).

Plain language: you're free to use, study, modify, distribute, and self-host
this. If you ship a modified version — *including running it as a service that
users interact with over a network* — you must publish your changes under AGPL
too. This is the same license Signal and Element use, for the same reason:
privacy software's promises only hold up when users (or someone they trust)
can read the source.

Copyright © 2026 Caravan Electric, LLC.

## Layout

```
lib/core/           crypto, config (--dart-define), router, theme
lib/features/       auth, party, map, maps, mesh, tracks, settings, onboarding
lib/shared/         services (region downloader, tile server, mesh, …), models, widgets
supabase/migrations/  schema, RLS, RPCs, realtime, purge
tool/verify_e2e.dart  end-to-end privacy proof
test/crypto/        crypto unit tests (incl. zero-plaintext + tamper)
docs/               privacy policy, support page, store assets (HTML mirrors of the gists)
android/, ios/      platform projects
codemagic.yaml      CI release pipeline (TestFlight + Play Internal)
```
