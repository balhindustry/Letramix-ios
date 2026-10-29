#!/bin/bash
set -euo pipefail
# No tracing: never print signing credentials or API keys.
for name in APPLE_TEAM_ID BUNDLE_ID APPLE_CERTIFICATE_BASE64 APPLE_CERTIFICATE_PASSWORD APPLE_PROFILE_BASE64 ASC_PRIVATE_KEY_BASE64 ASC_KEY_ID ASC_ISSUER_ID; do
  if [[ -z "${!name:-}" ]]; then echo "Missing required GitHub secret or variable: $name"; exit 1; fi
done
SIGNING_DIR="$RUNNER_TEMP/letramix-signing"
mkdir -p "$SIGNING_DIR/private_keys"
printf '%s' "$APPLE_CERTIFICATE_BASE64" | base64 --decode > "$SIGNING_DIR/certificate.p12"
printf '%s' "$APPLE_PROFILE_BASE64" | base64 --decode > "$SIGNING_DIR/profile.mobileprovision"
printf '%s' "$ASC_PRIVATE_KEY_BASE64" | base64 --decode > "$SIGNING_DIR/private_keys/AuthKey_${ASC_KEY_ID}.p8"
chmod 600 "$SIGNING_DIR/private_keys/"*.p8 "$SIGNING_DIR/certificate.p12"
security cms -D -i "$SIGNING_DIR/profile.mobileprovision" > "$SIGNING_DIR/profile.plist"
PROFILE_UUID=$(/usr/libexec/PlistBuddy -c 'Print UUID' "$SIGNING_DIR/profile.plist")
PROFILE_APP=$(/usr/libexec/PlistBuddy -c 'Print Entitlements:application-identifier' "$SIGNING_DIR/profile.plist")
if [[ "$PROFILE_APP" != "$APPLE_TEAM_ID.$BUNDLE_ID" ]]; then echo 'Provisioning profile does not match configured team and bundle ID'; exit 1; fi
KEYCHAIN_PATH="$RUNNER_TEMP/letramix.keychain-db"
KEYCHAIN_PASSWORD=$(openssl rand -hex 24)
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$SIGNING_DIR/certificate.p12" -P "$APPLE_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security list-keychains -d user -s "$KEYCHAIN_PATH" "$HOME/Library/Keychains/login.keychain-db"
mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
cp "$SIGNING_DIR/profile.mobileprovision" "$HOME/Library/MobileDevice/Provisioning Profiles/$PROFILE_UUID.mobileprovision"
export PROFILE_UUID
python3 - <<'PY'
import os,plistlib
with open(os.environ['RUNNER_TEMP']+'/letramix-signing/export.plist','wb') as f:
 plistlib.dump({'method':'app-store-connect','teamID':os.environ['APPLE_TEAM_ID'],'signingStyle':'manual','signingCertificate':'Apple Distribution','provisioningProfiles':{os.environ['BUNDLE_ID']:os.environ['PROFILE_UUID']},'uploadSymbols':True},f)
PY
xcodebuild -project Letramix.xcodeproj -scheme Letramix -destination 'generic/platform=iOS' -archivePath build/Letramix.xcarchive DEVELOPMENT_TEAM="$APPLE_TEAM_ID" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='Apple Distribution' PROVISIONING_PROFILE_SPECIFIER="$PROFILE_UUID" CURRENT_PROJECT_VERSION="$GITHUB_RUN_NUMBER" archive
xcodebuild -exportArchive -archivePath build/Letramix.xcarchive -exportPath build/export -exportOptionsPlist "$SIGNING_DIR/export.plist"
API_PRIVATE_KEYS_DIR="$SIGNING_DIR/private_keys" xcrun altool --upload-app --type ios --file build/export/Letramix.ipa --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
