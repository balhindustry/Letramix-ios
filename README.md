# LETRAMIX for iPhone — v0.2

Native SwiftUI word game: welcome → FI/EN setup → 1–6 players → 30–180 s turns → live rear camera reads the tiles → every correct word scores. iOS 17+, portrait iPhone. AVFoundation + Apple Vision on device; no web view, cloud OCR, upload or login. Offline word lists are bundled. No camera image is ever saved.

## How a turn works

1. Press **Aloita / Start** — the clock runs.
2. Lay words on the table. When the camera has read a word twice and it is in the word list, it is **saved to the turn automatically** (green ✓ + "+5 KALA"). Words can also be typed; the **◇** key inserts a joker.
3. When time runs out (or **Valmis / Done**), the review screen lists every saved word with its points. Remove misreads with ✕, add any word the camera missed, then **accept**: *all* saved words score at once (10 correct words in a minute = points for all 10).
4. Next player. After the last round the results screen shows the ranking, best word and every player's words.

Rules: at least 2 letters · points by tile value (`Core/TileRules.swift`), ◇ = 0 · each word scores once per game · a joker word asks which word it stands for when there are several options.

## What changed in 0.2 (from the Codex prototype)

- **Scoring fixed**: words are collected during the turn and all scored at the end, instead of one tap per word that only worked while the clock ran.
- **Word history**: per-turn word list, per-player word list, results screen, and a saved **game history**. The game in progress is saved continuously and can be continued after closing the app.
- **Finnish inflected forms** are accepted (KALAT, TALOSSA, KADULLA, PUHUU…) — the Kotus list only has base forms. Optional "accept anyway" house rule for anything else.
- Rounds (1/2/3/5/∞), early "Done", end-game with results, rematch.
- Camera: 1080p, near-focus, two-read stability filter against OCR noise, flashlight button, coloured overlay (saved / valid / already played / not found).
- Jokers: works with inflected forms, fast lookup (no scanning of 100 000 words), dedicated ◇ key.
- Code split into `Core/` (pure Swift rules, testable anywhere) and `Views/`; `tests/CoreChecks.swift` runs in CI.

## Current limits

Camera accuracy needs a physical iPhone test; clear block capitals work best. Words must be horizontal with upright letters. Finnish forms are a heuristic: common noun cases, plurals, possessives, clitics and simple verb forms; rare stem types need the house rule.

## Tests

`swiftc -O Letramix/Core/*.swift tests/CoreChecks.swift -o /tmp/core-checks && /tmp/core-checks Letramix/Resources` (macOS or Linux). The GitHub **iOS build check** runs this before building.

## Windows workflow

1. Push the branch or open its pull request. **Actions → iOS build check** compiles the simulator app on macOS. This does not install on an iPhone.
2. Create the iOS app in App Store Connect. The default bundle ID is `fi.balh.letramix`; choose your own registered ID if needed.
3. In this repository store the credentials below under **Settings → Secrets and variables → Actions**, never in source or chat. The upload job uses the **testflight** environment; environment-scoped secrets can also be used.
4. Merge the workflows to the default branch once reviewed. **Actions → Upload to TestFlight → Run workflow** builds, signs and uploads the selected branch. It never uploads on ordinary pushes.
5. Wait for Apple's processing, complete any required export-compliance details, then add the build to your internal TestFlight tester group.

Variables: `APPLE_TEAM_ID`, `BUNDLE_ID` (optional, defaults to `fi.balh.letramix`).

Secrets:
- `APPLE_CERTIFICATE_BASE64`: Base64 Apple Distribution `.p12` certificate **including its private key**.
- `APPLE_CERTIFICATE_PASSWORD`: that certificate's password.
- `APPLE_PROFILE_BASE64`: Base64 App Store distribution provisioning profile matching the team and bundle ID.
- `ASC_PRIVATE_KEY_BASE64`: Base64 App Store Connect API `.p8` private key.
- `ASC_KEY_ID`: the individual App Store Connect API key ID. The user owning this key must have upload access to LETRAMIX. An issuer ID is not needed for this individual-key workflow.

A developer membership alone does not populate these secrets. The simulator check needs no Apple credentials. Upload has not been tested until actual signing assets are configured.

## Local development on a Mac

`brew install xcodegen`, `xcodegen generate`, then open `Letramix.xcodeproj`. The project is generated from `project.yml`. Do not commit certificates, API keys, profiles or archives. See `Letramix/Resources/NOTICES.txt` for word-list attribution and licenses.
