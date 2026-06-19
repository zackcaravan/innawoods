# Play Console submission — Background Location Use

Source-of-truth for the Background Location Use form in Play Console's
**Policy → App content** section. Copy/paste the text below; record the
video using the script below; submit. Same operator as Switchboard, which
got through review without revisions.

Last revised: 2026-06-18.

---

## Why the app accesses location in the background

> Innawoods is a privacy-first map app for off-grid backcountry crews —
> hunters, riders, hikers, search-and-rescue volunteers. The core feature
> is **real-time encrypted position sharing** among consenting members of
> a private party.
>
> Background location access is essential because users carry their phones
> in a pocket or pack while moving through areas where cellular coverage
> is often weak or absent. Without background access, a user's last
> position would freeze on every other party member's map the moment the
> screen turns off, defeating the only reason the app exists.
>
> Background location is shared only with members of the user's active
> party. Position data is end-to-end encrypted on the device with a key
> our server never holds; the server stores ciphertext only. No data is
> shared with third parties, used for advertising, or sold.
>
> The feature is gated behind an in-app prominent disclosure screen
> (see `lib/features/onboarding/screens/background_disclosure_screen.dart`)
> that the user must explicitly accept before the OS permission prompt
> fires, and is turned off automatically when the user leaves the party.
> A persistent notification informs the user whenever the foreground
> service is active.

---

## Foreground service type

`location` — granular subtype required on Android 14+, declared via
`FOREGROUND_SERVICE_LOCATION` in `AndroidManifest.xml` and surfaced
automatically by `geolocator`'s `ForegroundNotificationConfig`.

---

## Video demo script

**Length target:** 60–90 seconds. **Format:** screen recording from two
devices side by side OR alternating cuts. **Narration:** voiceover or
on-screen captions.

### Scene 1 — Setup (10s)
- Both phones visible
- Captioned: "Two friends. Heading out backcountry."
- Phone A opens Innawoods, taps "Start party"
- Phone A shows the invite QR
- Phone B scans the QR, joins the party

### Scene 2 — Foreground sharing works (15s)
- Both phones show the live party map
- One member's dot is visible on the other's screen
- Captioned: "While the app is open, both can see each other."

### Scene 3 — Background problem (15s)
- Phone A locks its screen
- Phone B's map shows phone A's dot, watch the "last seen" indicator
  climb (Innawoods displays a stale-timer per member)
- Captioned: "Without background access, the dot freezes the moment the
  screen sleeps. The other crew member can't see where you are."

### Scene 4 — Enable background sharing (15s)
- Phone A unlocks, opens Settings inside the app
- Scrolls to "Background sharing", taps **Enable**
- The prominent disclosure screen appears — captioned text quickly
  highlights the key points: "Encrypted. Only your party. Stops when
  you leave."
- User taps **Continue**
- Android system prompt appears — user selects **Allow all the time**

### Scene 5 — Background sharing works (20s)
- Phone A locks its screen again
- Person carrying phone A walks across the parking lot / yard
- Phone B's map shows phone A's dot updating in real time
- Captioned: "Now your crew can see you even while your phone is in
  your pocket."
- Persistent notification visible on phone A's lock screen
- Captioned: "A persistent notification reminds you it's running. Tap
  to open. Leave the party to stop."

### Scene 6 — Stops on leave (10s)
- Phone A unlocks, opens Innawoods, taps "Leave party"
- Persistent notification disappears
- Phone B's map shows phone A's dot go gray / disappear
- Captioned: "Background sharing turns off automatically the moment you
  leave the party."

### Closing card (5s)
- App icon + text:
  "Innawoods — End-to-end encrypted real-time GPS for off-grid crews"

---

## Upload checklist

- [ ] Record video (above script)
- [ ] Upload to **unlisted** YouTube
- [ ] Copy the URL
- [ ] Go to Play Console → App content → Background location
- [ ] Paste the justification text
- [ ] Paste the video URL
- [ ] Submit
- [ ] Expect ~3–5 business day review

If rejected, the rejection email lists the specific clause. Most rejections
are for one of three reasons:
1. **Missing prominent disclosure in the video** — the video must show
   the in-app disclosure screen explicitly, not just narrate it.
2. **Foreground service type missing in manifest** — already declared.
3. **Privacy policy doesn't mention background location** — already
   does (gist linked from in-app Settings).

---

## Related files

- `android/app/src/main/AndroidManifest.xml` — permission declarations
- `ios/Runner/Info.plist` — iOS usage descriptions + UIBackgroundModes
- `lib/features/party/providers/party_provider.dart` — geolocator
  foreground service config
- `lib/features/onboarding/screens/background_disclosure_screen.dart` —
  the disclosure shown before the OS prompt
- `lib/features/settings/screens/settings_screen.dart` — Settings tile
  that triggers the disclosure → upgrade flow
- `https://gist.github.com/zackcaravan/3fbe150e19f4b39eb6fafc667d34f15c`
  — privacy policy URL pasted into Play Console
