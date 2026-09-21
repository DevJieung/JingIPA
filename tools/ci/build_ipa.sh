#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/ipa build/ci
app=AllInDefense
project="build/ios/$app.xcodeproj"
keychain="$RUNNER_TEMP/pokerdefense.keychain-db"
profile_path=""
cleanup() {
    if [ -f "$keychain" ]; then security delete-keychain "$keychain"; fi
    if [ -n "$profile_path" ]; then rm -f "$profile_path"; fi
    rm -f "$RUNNER_TEMP/pokerdefense.p12" "$RUNNER_TEMP/pokerdefense.mobileprovision" "$RUNNER_TEMP/profile.plist"
}
trap cleanup EXIT
xcodebuild -version
xcodebuild -list -project "$project"

# Never silently downgrade partially configured signing to an unsigned build.
if [ -z "${IOS_P12_BASE64:-}${IOS_MOBILEPROVISION_BASE64:-}${IOS_TEAM_ID:-}" ]; then
    signing=unsigned
    xcodebuild -project "$project" -scheme "$app" -configuration Release \
        -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$RUNNER_TEMP/derived" \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="" CODE_SIGN_ENTITLEMENTS="" PROVISIONING_PROFILE_SPECIFIER="" \
        DEVELOPMENT_TEAM="" build 2>&1 | tee build/ci/xcodebuild.log
    app_dir="$RUNNER_TEMP/derived/Build/Products/Release-iphoneos/$app.app"
    test -s "$app_dir/Info.plist"
    mkdir -p "$RUNNER_TEMP/unsigned/Payload"
    ditto "$app_dir" "$RUNNER_TEMP/unsigned/Payload/$app.app"
    (cd "$RUNNER_TEMP/unsigned" && zip -qry "$GITHUB_WORKSPACE/build/ipa/pokerdefense.ipa" Payload)
else
    signing=signed
    : "${IOS_P12_BASE64:?Missing IOS_P12_BASE64}"
    : "${IOS_MOBILEPROVISION_BASE64:?Missing IOS_MOBILEPROVISION_BASE64}"
    : "${IOS_TEAM_ID:?Missing IOS_TEAM_ID}"
    python3 - <<'PY'
import base64, os
from pathlib import Path
for key, name in [('IOS_P12_BASE64', 'pokerdefense.p12'), ('IOS_MOBILEPROVISION_BASE64', 'pokerdefense.mobileprovision')]:
    path = Path(os.environ['RUNNER_TEMP']) / name
    path.write_bytes(base64.b64decode(os.environ[key], validate=True))
    path.chmod(0o600)
PY
    security cms -D -i "$RUNNER_TEMP/pokerdefense.mobileprovision" > "$RUNNER_TEMP/profile.plist"
    python3 - <<'PY'
import datetime, fnmatch, os, plistlib
from pathlib import Path
profile = plistlib.loads((Path(os.environ['RUNNER_TEMP']) / 'profile.plist').read_bytes())
team = os.environ['IOS_TEAM_ID']
bundle = os.environ.get('IOS_BUNDLE_ID') or 'com.devjieung.pokerdefense'
assert team in profile['TeamIdentifier'], 'Provisioning profile belongs to a different team'
identifier = profile['Entitlements']['application-identifier'].split('.', 1)[1]
assert fnmatch.fnmatchcase(bundle, identifier), 'Provisioning profile does not cover this game bundle ID'
assert profile['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None), 'Provisioning profile expired'
PY
    profile_uuid="$(plutil -extract UUID raw "$RUNNER_TEMP/profile.plist")"
    export PROFILE_NAME="$(plutil -extract Name raw "$RUNNER_TEMP/profile.plist")"
    profile_dir="$HOME/Library/MobileDevice/Provisioning Profiles"
    mkdir -p "$profile_dir"
    profile_path="$profile_dir/$profile_uuid.mobileprovision"
    cp "$RUNNER_TEMP/pokerdefense.mobileprovision" "$profile_path"
    keychain_password="$(uuidgen)"
    security create-keychain -p "$keychain_password" "$keychain"
    security set-keychain-settings -lut 21600 "$keychain"
    security unlock-keychain -p "$keychain_password" "$keychain"
    security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"
    security import "$RUNNER_TEMP/pokerdefense.p12" -k "$keychain" -P "${IOS_P12_PASSWORD:-}" -T /usr/bin/codesign
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" > /dev/null
    export SIGN_IDENTITY="$(security find-identity -v -p codesigning "$keychain" | sed -nE 's/.*"([^"]+)".*/\1/p' | head -1)"
    test -n "$SIGN_IDENTITY"
    archive="$RUNNER_TEMP/$app.xcarchive"
    xcodebuild -project "$project" -scheme "$app" -configuration Release \
        -destination 'generic/platform=iOS' -archivePath "$archive" \
        CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$IOS_TEAM_ID" CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
        PROVISIONING_PROFILE_SPECIFIER="$PROFILE_NAME" OTHER_CODE_SIGN_FLAGS="--keychain $keychain" \
        archive 2>&1 | tee build/ci/xcodebuild.log
    python3 - <<'PY'
import os, plistlib
from pathlib import Path
bundle = os.environ.get('IOS_BUNDLE_ID') or 'com.devjieung.pokerdefense'
options = dict(method=os.environ.get('IOS_EXPORT_METHOD') or 'debugging', teamID=os.environ['IOS_TEAM_ID'],
               signingStyle='manual', signingCertificate=os.environ['SIGN_IDENTITY'], stripSwiftSymbols=True,
               provisioningProfiles={bundle: os.environ['PROFILE_NAME']})
(Path(os.environ['RUNNER_TEMP']) / 'export-options.plist').write_bytes(plistlib.dumps(options))
PY
    xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$RUNNER_TEMP/export-options.plist" \
        -exportPath "$RUNNER_TEMP/signed-export" 2>&1 | tee -a build/ci/xcodebuild.log
    cp "$RUNNER_TEMP/signed-export/$app.ipa" build/ipa/pokerdefense.ipa
fi
python3 - <<'PY'
import plistlib, zipfile
with zipfile.ZipFile('build/ipa/pokerdefense.ipa') as archive:
    assert archive.testzip() is None
    root = 'Payload/AllInDefense.app/'
    info = plistlib.loads(archive.read(root + 'Info.plist'))
    assert archive.getinfo(root + info['CFBundleExecutable']).file_size > 0
    assert any(n.startswith(root) and n.endswith('.pck') for n in archive.namelist())
    assert not any('/.env' in n for n in archive.namelist())
    print('IPA verified:', info['CFBundleIdentifier'])
PY
{
    echo '### 올인 디펜스 IPA'
    echo "- 파일: pokerdefense.ipa ($signing)"
    if [ "$signing" = unsigned ]; then
        echo '- 서명 없는 IPA입니다. AltStore / Sideloadly에서 본인 Apple ID로 서명하여 설치하세요.'
    fi
} >> "$GITHUB_STEP_SUMMARY"
