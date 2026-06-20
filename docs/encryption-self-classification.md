# Encryption Self-Classification Declaration

**Application:** Innawoods: Backcountry
**Bundle Identifier:** com.innawoods.innawoods
**Apple App ID:** 6777637554
**Developer:** Caravan Electric, LLC
**Contact:** zack.caravan@gmail.com
**Source:** https://github.com/zackcaravan/innawoods
**Date:** 2026-06-19

---

## Summary

Innawoods implements standard, published encryption algorithms for the
purpose of end-to-end encryption of user data among consenting members
of a private party. All algorithms are widely recognized as standard by
international standard bodies (IETF). The software qualifies for the
mass-market encryption exemption under **§740.17(b)(1)** of the U.S.
Export Administration Regulations (EAR), Category 5 Part 2.

## Encryption Algorithms Used

| Purpose | Algorithm | Standard |
|---|---|---|
| Key exchange | X25519 (Curve25519 Diffie-Hellman) | IETF RFC 7748 |
| Key derivation | HKDF with SHA-256 | IETF RFC 5869 |
| Authenticated encryption | XChaCha20-Poly1305 | IETF RFC 8439 + draft-irtf-cfrg-xchacha-03 |
| Transport (Apple OS) | TLS via URLSession / NSURLSession | Apple OS provided |

No proprietary, non-standard, or custom cryptography is implemented.

## Implementation

All cryptographic primitives are provided by the open-source
`cryptography` package distributed via pub.dev
(https://pub.dev/packages/cryptography), licensed Apache 2.0.

The application **does not** implement any cryptographic algorithm
itself. It calls into the above third-party library and Apple's own
Network framework (for TLS).

## Purpose of Encryption

Innawoods is a privacy-first real-time GPS application for small
private groups (parties) of off-grid users — hunters, hikers, riders,
search-and-rescue volunteers. End-to-end encryption is used to seal:

- Live GPS position updates among party members
- Group chat messages
- User-placed map pins
- Multi-waypoint routes

The session key is derived per-party from a random 256-bit secret that
travels in the URL fragment of the invite link, which the server never
receives. The application server stores only opaque ciphertext.

## Export Classification

**ECCN:** 5D992.c (Mass-market commodity; information security software
that uses standard encryption for data privacy purposes)

**Exemption Claimed:** §740.17(b)(1) of the U.S. Export Administration
Regulations.

**Eligibility Basis:**

1. The software performs standard cryptographic operations on
   information at rest and in transit.
2. The cryptographic functionality is ancillary to the primary
   purpose of the application (party coordination, not cryptography
   as a service).
3. The software is generally available to the public via the Apple
   App Store and Google Play Store.
4. The source code is published openly at
   https://github.com/zackcaravan/innawoods under the GNU AGPL-3.0
   license — meeting the publicly-available criterion of
   §734.7 of the EAR.

This is the same exemption claimed by Signal, Bitwarden, Element,
Standard Notes, Tailscale, and other mainstream end-to-end encrypted
applications distributed through public app stores.

## Annual Self-Classification Report

Caravan Electric, LLC will file the annual self-classification report
required under §740.17(e)(3) of the EAR with the U.S. Bureau of
Industry and Security (BIS) at crypt-supp2@bis.doc.gov and the
National Security Agency (NSA) at enc@nsa.gov by **February 1, 2027**
for the calendar year 2026.

## Contact

**Caravan Electric, LLC**
Whidbey Island, Washington, USA
zack.caravan@gmail.com

---

*This declaration is provided pursuant to Apple's App Store Connect
encryption export compliance requirements and the U.S. Department of
Commerce Bureau of Industry and Security regulations.*
