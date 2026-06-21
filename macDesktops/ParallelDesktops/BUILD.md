# Building & Distributing Parallel Project Desktops

## Run locally (contributors)

```bash
cd ParallelDesktops
./make-app.sh && open ParallelDesktops.app
```

`make-app.sh` wraps the SwiftPM executable in a real `.app` bundle (needed for the
menu-bar icon) and signs it with the best identity it finds:

1. **Developer ID Application** — distributable + notarizable (best)
2. **Apple Development** — stable local identity; Accessibility grant survives rebuilds
3. **ad-hoc** — fallback; the Accessibility grant resets on every rebuild

First launch: grant **Accessibility** (System Settings ▸ Privacy & Security ▸
Accessibility) and enable **Switch to Desktop N** shortcuts (System Settings ▸
Keyboard ▸ Keyboard Shortcuts ▸ Mission Control). The in-app onboarding banner
links to both. Tests: `swift test`.

> Building from a `git clone` is **not** quarantined, so contributors avoid
> Gatekeeper entirely — no notarization needed to run from source.

## Distribute a downloadable DMG (one-time setup, then one command)

A DMG someone downloads is quarantined, so it must be **Developer ID signed +
notarized** to launch cleanly. One-time setup:

1. **Create a Developer ID Application certificate** (paid Apple Developer account):
   Xcode ▸ Settings ▸ Accounts ▸ your team ▸ Manage Certificates ▸ **+** ▸
   *Developer ID Application*. (Or developer.apple.com ▸ Certificates.)
   You currently have only an *Apple Development* cert, which cannot be notarized.

2. **Store notarization credentials** in the keychain (profile name `PPDS`):

   ```bash
   xcrun notarytool store-credentials PPDS \
     --apple-id "varma.shrikant@gmail.com" \
     --team-id  "5U62T4K686" \
     --password "<app-specific-password>"
   ```

   Create the app-specific password at <https://account.apple.com> ▸ Sign-In &
   Security ▸ App-Specific Passwords. (An App Store Connect API key works too.)

Then, to cut a release:

```bash
./make-dmg.sh        # builds release, signs w/ Developer ID, notarizes, staples
```

Output: `ParallelDesktops.dmg`, ready to attach to a **GitHub Release**.

## Git hygiene
- Commit **source only**. `.build/`, `*.app`, and `*.dmg` are gitignored.
- **Never** commit certificates, private keys, or app-specific passwords.
- Ship built DMGs as **GitHub Release assets**, not in the repo tree.

## Later: Xcode migration (plan KTD-7)
Notarization works fine from SwiftPM + these scripts, so Xcode isn't required.
Migrate to an `.xcodeproj` only if you want Xcode-managed entitlements/archives or
an `LSUIElement` Info.plist baked in (vs. the runtime `.accessory` policy used now).
