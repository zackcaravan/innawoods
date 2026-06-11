# Contributing to Innawoods

Bug reports, fixes, and feature PRs are welcome. Read this first — it's short.

## License & contribution grant

This project is licensed under **AGPL-3.0-or-later** (see [`LICENSE`](LICENSE)).

By submitting a patch you agree your contribution is licensed under the same
terms as the project, and that you have the right to make that grant.

We don't use a CLA (Contributor License Agreement). We do require a **DCO
sign-off** on every commit. The DCO is a one-line attestation that the patch
is yours to give, with a public archive at <https://developercertificate.org>.

To sign off, add `-s` to every commit:

```bash
git commit -s -m "your message"
```

That appends a `Signed-off-by: Your Name <you@example.com>` trailer using your
`git config user.name` and `user.email`. PRs whose commits aren't signed off
will be asked to amend before merge.

## Before you open a PR

Run the things CI would run:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart format --set-exit-if-changed .
flutter analyze
flutter test
```

If you touched anything under `lib/core/crypto/`, also run the end-to-end
verifier against a local Supabase stack:

```bash
supabase start
dart run tool/verify_e2e.dart \
  --url http://127.0.0.1:54321 \
  --anon <publishable key from `supabase status`>
```

## Source headers

Every committed `.dart` source file starts with:

```dart
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.
```

Generated files (`*.g.dart`, `*.freezed.dart`, `*.mocks.dart`) are excluded.

If you add a brand-new source file, prepend the header. If you don't, the
review will. Don't change the SPDX tag — license changes go through a
deliberate process, not a drive-by.

## Scope of changes

- **Bug fixes**: any size, just include or update a test.
- **Small features**: open a PR directly; if it doesn't fit, we'll discuss in
  review.
- **Large features or anything touching the crypto / wire protocol**: open an
  issue first so we can talk through the threat-model implications before you
  invest the time. The whole point of this app is that the threat model is
  airtight; PRs that compromise it (e.g. "let's just store one tiny bit of
  plaintext on the server") will not merge, no matter how nice the code is.

## Style

- Follow the existing patterns in the file you're editing — comment density,
  naming, indentation. The codebase is intentionally consistent.
- `dart format .` for whitespace.
- No new dependencies without justification; every package added has to be
  reviewed for license (must be permissive or AGPL-compatible) and supply-chain
  risk.

## Reporting security issues

**Don't open a public GitHub issue for security bugs.** Email
<zack.caravan@gmail.com> with details. Subject prefix `[security]` so it
doesn't get lost. Responsible disclosure window is 90 days from acknowledgement
or until a fix ships, whichever comes first.

---

Thanks for taking the time. The off-grid crowd is small but mighty and this is
the kind of software they deserve.
