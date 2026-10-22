# ShortSign

Sign Apple Shortcuts on a stock iPhone. Pick an unsigned or signed shortcut,
sign it locally, share it into Shortcuts. No Mac, server, or Apple ID.

[Download the latest unsigned IPA](https://github.com/dan1165/shortsign/releases/latest)

## Use

1. Install the IPA with your sideloader.
2. If the **Certificate** section appears, tap **Install Certificate**, save it
   to Files, tap the profile, and enable full trust in Settings › General ›
   About › Certificate Trust Settings. ShortSign detects the installed
   certificate and hides the section automatically. If it stays or imports fail,
   re-check the trust toggle.
3. Choose one or more unsigned or signed `.shortcut`, `.wflow` or plist files,
   paste an https URL, or open a file in ShortSign from Files. Signed inputs are
   extracted and re-signed.
4. Tap **Sign Shortcut** (or **Sign N Shortcuts**). The share sheet opens
   automatically; choose Shortcuts. If you cancel it, tap **Share Again**.

The gear shows certificate status and fingerprint, and lets you reinstall the
certificate at any time.

Signed shortcuts are extracted and re-signed with your local certificate. The
result imports only on devices that trust the certificate.

## Public links

Once the shortcut is in Shortcuts, share it normally:

1. Open the shortcut in Shortcuts.
2. **Share → Copy iCloud Link**.
3. Send the link — recipients don't need the ShortSign certificate.

Shortcuts uploads its own Apple-signed copy to iCloud, so the public link works
for anyone. The self-signed certificate is only needed for the initial import
on your device.

Tips: the link is public to anyone who has it, so don't include secrets.
Recipients may need the apps or actions the shortcut uses, and creating a link
requires being signed into iCloud.

## Limits

- Direct file sharing is self-signed and per-device. For a public link, import
  the shortcut first, then use Shortcuts → Copy iCloud Link.
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
