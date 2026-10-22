# ShortSign for iOS

Sign Apple Shortcuts on the iPhone itself: pick an unsigned shortcut, get a
signed `.shortcut` file, share it into Shortcuts. No Mac, no server, no Apple ID.

Download the latest unsigned IPA from
[Releases](https://github.com/dan1165/shortsign/releases/latest).

## How it works

A modern `.shortcut` is an AEA1 archive containing `Shortcut.wflow` (a binary
plist) plus an ECDSA P-256 signature. ShortSign builds that archive on-device
with [libshortcutsign](https://github.com/0xilis/libshortcutsign) and
[libNeoAppleArchive](https://github.com/0xilis/libNeoAppleArchive). The crypto
is OpenSSL, statically linked for arm64 iOS.

Because the signing key is ours and not Apple's, the shortcut imports only on
devices that trust the ShortSign root certificate. **Install the certificate on
every device that will import the signed shortcut.**

## Use

1. Install the IPA with your sideloader.
2. In ShortSign, tap **Share Certificate**, save it to Files, tap it and install
   the profile. Enable full trust in General › About › Certificate Trust Settings.
3. Tap **Choose Shortcut File** and pick an unsigned `.shortcut`, `.wflow` or
   plist. If the picker cannot select the file, paste an https URL in
   **Or choose a URL** and tap **Download Shortcut**.
4. Tap **Sign Shortcut**, then **Share Signed Shortcut** and choose Shortcuts.

Unsigned inputs can be produced by Shortcuts exports on old iOS versions,
`shortcuts`-format plist editors, or any tool that writes a `WFWorkflow*` plist.
A file that already starts with `AEA1` is signed and is rejected.

## Limits

- Self-signed only. There is no way to get Apple's signing identity on a stock
  iPhone; Shortcuts validates the certificate chain at import. Sharing a signed
  shortcut with someone who has not installed the certificate will fail.
- iCloud share links, "anyone" signing and App Store distribution are out of
  scope.
- The bundled signing key is public by construction. This is a convenience
  identity, not a security boundary; only install the certificate on devices you
  control.
- Shortcuts internals change between iOS releases. Built for iOS 17+; if an
  import is rejected on a newer iOS, open an Issue.

## Build

The unsigned IPA is built by the `Build and release unsigned IPA` GitHub Actions
workflow on every push to `main`, and manually via workflow dispatch.

- Runner: `macos-26-intel`.
- Toolchain: Swift 6.3, native SwiftUI, Xcode 26 on macOS 26.
- Version: `1.0.<run number>` with build number `<run number>`.
- Tag/release: `v1.0.<run number>`, IPA and `CHANGELOG.md` attached as release
  assets.
- Output: `xtool/ShortSign-1.0.<run number>.ipa`.
- The IPA is unsigned. Sign it with your own signing service before installing.
- Local Linux builds need an Xcode SDK; use CI instead.

## Signing identity

`Sources/ShortSign/Resources` holds `key.dat`, `auth.plist` and
`ShortSign.cer`. Regenerate them with:

```bash
python3 tools/make_identity.py
```

Then rebuild, reinstall the new root certificate and re-trust it. Old signed
shortcuts will stop importing.

## Layout

- `Sources/ShortSign` — SwiftUI app, plist parsing and the C bridge.
- `Sources/CShortcutSign` — vendored libshortcutsign sign code, libNeoAppleArchive
  and lzfse, plus a small C wrapper.
- `Vendor/OpenSSL.xcframework` — static OpenSSL from shortcut-sign's iOS support.
- `tools/make_identity.py` — creates the self-signed certificate chain, auth data
  and raw X9.63 key.

## Licences

libshortcutsign and libNeoAppleArchive are MIT (Snoolie K / 0xilis). lzfse is
BSD-3-Clause (Apple). libzbitmap is MIT (Corellium). OpenSSL is Apache-2.0. Full
texts are in `Licenses/`.
