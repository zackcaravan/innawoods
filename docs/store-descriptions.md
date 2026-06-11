# Store listing copy — Innawoods: Backcountry

Source-of-truth for App Store Connect + Google Play Console descriptions.
Update this file, then mirror to the dashboards.

Last revised: 2026-06-11 (added AGPL / source-available paragraph).

---

## Apple App Store

### Name (30 char max)
```
Innawoods: Backcountry
```

### Subtitle (30 char max)
```
Off-grid crew GPS + mesh chat
```

### Promotional Text (170 char max — editable without a new build)
```
End-to-end encrypted party GPS for the backcountry. Works offline with
downloaded maps. Bridges over LoRa mesh when there's no cell. Source on
GitHub.
```

### Description (4000 char max)
```
Innawoods is private real-time GPS for off-grid crews. Hunters, riders,
backcountry skiers, search-and-rescue — anyone who heads out as a party and
wants to see each other on a map without being tracked by anyone else.

EVERYTHING IS END-TO-END ENCRYPTED
Your locations, pins, routes, and chat messages are sealed with a key only
your party holds. Our server stores ciphertext. It never sees a coordinate,
a place name, or a message — even if it's subpoenaed, breached, or curious.

NO ACCOUNT, NO EMAIL, NO PHONE NUMBER
Sign-in is anonymous. There's no name, email, phone, or password attached
to your account. You install, you join a party with an invite link, you're
in. Uninstall and the only thing left on the server is an inert UUID with
nothing readable attached to it.

WORKS WITHOUT CELL
Download a region (Washington, Oregon, Idaho, Montana, Colorado at launch)
and the map renders fully offline. Pair a Meshtastic LoRa radio over
Bluetooth and your party stays connected — locations and chat — out past
where cell coverage ends. Same encrypted payloads, just a different
transport.

WHAT YOU GET
• Live map of your whole party — locations update in real time
• Drop pins (waypoints, hazards, glassing spots) the whole party sees
• Plan routes together with multi-point waypoints
• Encrypted group chat
• Background tracking of your own movement; review your tracks later
• Offline vector basemaps with topo contours
• Meshtastic LoRa bridge for cell-dead operation
• Push notifications when someone invites you to a party

SOURCE AVAILABLE
Innawoods is open source under the GNU AGPL-3.0 license — a strong
copyleft license that requires anyone running a derivative as a service
to publish their changes. The repository at github.com/zackcaravan/innawoods
is the exact code you're installing. Build it yourself if you'd rather
trust the toolchain than a signed binary; install from the App Store if
you'd rather skip the build steps. Both paths are first-class.

PRIVACY MODEL
• Identity: X25519 keypair, private key never leaves the device's secure
  enclave / keystore.
• Party key: HKDF-SHA256 derived from a random 256-bit secret that travels
  in the invite link's URL fragment — the part the server never receives.
• Payloads: XChaCha20-Poly1305 (AEAD) sealed under the party key.
• No analytics SDKs. No ad SDKs. No third-party trackers.

Made by a small operation on Whidbey Island for our hunting buddies.
Email zack.caravan@gmail.com — we answer real questions.
```

### Keywords (100 char max, comma-separated, no spaces around commas)
```
gps,offline maps,hunting,backcountry,party,encryption,meshtastic,lora,off-grid,topo,sar,privacy
```

### What's New (4000 char max, per-release)
```
First public release. End-to-end encrypted party GPS, offline vector basemaps
for WA/OR/ID/MT/CO, Meshtastic LoRa bridge, anonymous accounts, encrypted
party chat. Source available on GitHub under AGPL-3.0.
```

### Support URL
<https://gist.github.com/zackcaravan/3494d880581510bd12e98ae51e1a70cc>

### Privacy Policy URL
<https://gist.github.com/zackcaravan/3fbe150e19f4b39eb6fafc667d34f15c>

### Marketing URL (optional)
<https://github.com/zackcaravan/innawoods>

---

## Google Play Console

### App name (50 char max)
```
Innawoods: Backcountry
```

### Short description (80 char max)
```
End-to-end encrypted GPS for backcountry crews. Offline maps. LoRa-ready.
```

### Full description (4000 char max)
```
Innawoods is private real-time GPS for off-grid crews. Hunters, riders,
backcountry skiers, search-and-rescue — anyone who heads out as a party and
wants to see each other on a map without being tracked by anyone else.

EVERYTHING IS END-TO-END ENCRYPTED
Your locations, pins, routes, and chat messages are sealed with a key only
your party holds. Our server stores ciphertext. It never sees a coordinate,
a place name, or a message — even if it's subpoenaed, breached, or curious.

NO ACCOUNT, NO EMAIL, NO PHONE NUMBER
Sign-in is anonymous. There's no name, email, phone, or password attached
to your account. You install, you join a party with an invite link, you're
in. Uninstall and the only thing left on the server is an inert UUID with
nothing readable attached to it.

WORKS WITHOUT CELL
Download a region (Washington, Oregon, Idaho, Montana, Colorado at launch)
and the map renders fully offline. Pair a Meshtastic LoRa radio over
Bluetooth and your party stays connected — locations and chat — out past
where cell coverage ends. Same encrypted payloads, just a different
transport.

WHAT YOU GET
• Live map of your whole party — locations update in real time
• Drop pins (waypoints, hazards, glassing spots) the whole party sees
• Plan routes together with multi-point waypoints
• Encrypted group chat
• Background tracking of your own movement; review your tracks later
• Offline vector basemaps with topo contours
• Meshtastic LoRa bridge for cell-dead operation
• Push notifications when someone invites you to a party

SOURCE AVAILABLE
Innawoods is open source under the GNU AGPL-3.0 license — a strong
copyleft license that requires anyone running a derivative as a service
to publish their changes. The repository at github.com/zackcaravan/innawoods
is the exact code you're installing. Build it yourself if you'd rather
trust the toolchain than a signed binary; install from Google Play if
you'd rather skip the build steps. Both paths are first-class.

PRIVACY MODEL
• Identity: X25519 keypair, private key never leaves the device's secure
  enclave / keystore.
• Party key: HKDF-SHA256 derived from a random 256-bit secret that travels
  in the invite link's URL fragment — the part the server never receives.
• Payloads: XChaCha20-Poly1305 (AEAD) sealed under the party key.
• No analytics SDKs. No ad SDKs. No third-party trackers.

Made by a small operation on Whidbey Island for our hunting buddies.
Email zack.caravan@gmail.com — we answer real questions.
```

### What's new (500 char max, per release)
```
First public release. End-to-end encrypted party GPS, offline vector basemaps
for WA/OR/ID/MT/CO, Meshtastic LoRa bridge, anonymous accounts, encrypted
chat. Source available on GitHub under AGPL-3.0.
```

### Privacy Policy URL
<https://gist.github.com/zackcaravan/3fbe150e19f4b39eb6fafc667d34f15c>

### Account deletion URL
<https://gist.github.com/zackcaravan/5270a8fd74720691d524e40ada18d6eb>

### Website (optional)
<https://github.com/zackcaravan/innawoods>

---

## Notes on the "Source Available" paragraph

Both stores allow you to mention open-source status in your description —
that's editorial copy about your product. What they push back on is
**pointing at off-store distribution as an alternative purchase path**
(e.g. "or download a free APK from our site").

The current wording threads the needle: it says the source exists and you
can build it yourself, but it doesn't direct readers to a competing
binary distribution. Linking the GitHub repo as the "Marketing URL" or
"Website" is fine on both stores — many open-source projects do exactly
this.

If a reviewer ever pushes back, the safe edit is to shorten the SOURCE
AVAILABLE section to one sentence and let the website link carry the
context.
