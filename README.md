# LETRAMIX for iPhone

Native SwiftUI prototype: welcome → FI/EN setup → 1–6 players → 30/60/90/120-second turns → live rear camera and word scoring. iOS 17+, portrait iPhone. Uses AVFoundation + Apple Vision on device; no web view, cloud OCR, photo upload or account login. Offline word lists are bundled. No recording is saved.

## Current limits

This is an initial prototype, not a TestFlight release. GitHub's `iOS build check` must pass before signing. Camera performance and handwriting accuracy require a physical iPhone test. Clear block capitals are the first target. Arbitrary rotated/intersecting cube grids and full Finnish morphology are not yet implemented. The Vision language selection uses the languages supported by the device/OS, with English fallback if Finnish is unavailable; Finnish dictionary validation is separate. Recognition suggestions are never auto-scored. Each word scores at most once per game. Tap a detected word to edit it.

## Windows workflow

1. Push the branch or open its pull request. **Actions → iOS build check** compiles the simulator app on macOS. This does not install on an iPhone.
2. Create the iOS app in App Store Connect. The default bundle ID is `fi.balh.letramix`; choose your own registered ID if needed.
3. In this repository create the GitHub environment **testflight**. Store the credentials below in that environment, never in source or chat. Consider adding a required reviewer.
4. Merge the workflows to the default branch once reviewed. **Actions → Upload to TestFlight → Run workflow** builds, signs and uploads the selected branch. It never uploads on ordinary pushes.
5. Wait for Apple's processing, complete any required export-compliance details, then add the build to your internal TestFlight tester group.

Variables: `APPLE_TEAM_ID`, `BUNDLE_ID` (optional, defaults to `fi.balh.letramix`).

Secrets:
- `APPLE_CERTIFICATE_BASE64`: Base64 Apple Distribution `.p12` certificate **including its private key**.
- `APPLE_CERTIFICATE_PASSWORD`: that certificate's password.
- `APPLE_PROFILE_BASE64`: Base64 App Store distribution provisioning profile matching the team and bundle ID.
- `ASC_PRIVATE_KEY_BASE64`: Base64 App Store Connect API `.p8` private key.
- `ASC_KEY_ID`, `ASC_ISSUER_ID`: App Store Connect API identifiers with appropriate upload access.

A developer membership alone does not populate these secrets. The simulator check needs no Apple credentials. Upload has not been tested until actual signing assets are configured.

## Local development on a Mac

`brew install xcodegen`, `xcodegen generate`, then open `Letramix.xcodeproj`. The project is generated from `project.yml`. Do not commit certificates, API keys, profiles or archives. See `Letramix/Resources/NOTICES.txt` for word-list attribution and licenses.
