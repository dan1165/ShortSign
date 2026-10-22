# ShortSign

Sign Apple Shortcuts on a stock iPhone. Pick an unsigned shortcut, sign it
locally, share it into Shortcuts. No Mac, server, or Apple ID.

[Download the latest unsigned IPA](https://github.com/dan1165/shortsign/releases/latest)

## Use

1. Install the IPA with your sideloader.
2. If the **Certificate** section appears, tap **Install Certificate**, save it
   to Files, tap the profile, and enable full trust in Settings › General ›
   About › Certificate Trust Settings. ShortSign detects the installed
   certificate and hides the section automatically. If it stays or imports fail,
   re-check the trust toggle.
3. Choose an unsigned `.shortcut`, `.wflow` or plist, or paste an https URL.
4. Tap **Sign Shortcut**. The share sheet opens automatically; choose
   Shortcuts. If you cancel it, tap **Share Again**.

Signed shortcuts import only on devices that trust the certificate. Files that
already start with `AEA1` are signed and rejected.

## Limits

- Self-signed and per-device. This is not Apple signing and not usable for
  public or iCloud sharing.
- The bundled key is public by construction; only trust the certificate on
  devices you control.
- iOS 17+. Re-sign files after updating from v1.0.2 or earlier — those builds
  wrote invalid AEA checksums.

## Build

GitHub Actions (`macos-26-intel`, xtool, Xcode 26) builds an unsigned IPA on
every push to `main` and publishes `v1.0.<run>` with the IPA and changelog.
Local Linux builds need an Xcode SDK; use CI.

## Signing identity

`Sources/ShortSign/Resources` holds the key, auth data and root certificate.
Regenerate with:

```bash
python3 tools/make_identity.py
```

Then rebuild, install the new root certificate and re-trust it. Old signed
shortcuts will stop importing.

## Credits

Vendored libshortcutsign and libNeoAppleArchive by Snoolie K / 0xilis (MIT),
building on his on-device Lina AAR/AEA app and jailbreak work. lzfse is
BSD-3-Clause (Apple), libzbitmap is MIT (Corellium), OpenSSL is Apache-2.0.
Full texts are in `Licenses/`.

The vendored signer is patched to write AEA segment checksums and support
multi-segment archives; upstream leaves them stale, which makes Shortcuts fail
with "Failed to extract shortcut data".
