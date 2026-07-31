#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "$script_directory/.." && pwd)"
dist_directory="${DIST_DIRECTORY:-$root/dist}"
app_name="TurboFieldfare"
app_path="$dist_directory/$app_name.app"
dmg_path="$dist_directory/$app_name.dmg"
binary_directory="$root/.build/release"
launcher_name="TurboFieldfareLauncher"
sign_identity="${SIGN_IDENTITY:--}"
version="${VERSION:-0.3}"
build_number="${BUILD_NUMBER:-3}"

build_arguments=(-c release)
if [[ "${SWIFT_DISABLE_SANDBOX:-0}" == "1" ]]; then
  build_arguments+=(--disable-sandbox)
fi

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  swift build "${build_arguments[@]}"
fi

required_binaries=(
  TurboFieldfareMac
  TurboFieldfareServer
)
required_bundles=(
  TurboFieldfare_TurboFieldfare.bundle
  TurboFieldfare_TurboFieldfareAppCore.bundle
  TurboFieldfare_TurboFieldfareMac.bundle
  swift-crypto_Crypto.bundle
  swift-nio_NIOPosix.bundle
  swift-transformers_Hub.bundle
)

for name in "${required_binaries[@]}" "${required_bundles[@]}"; do
  if [[ ! -e "$binary_directory/$name" ]]; then
    echo "error: required release artifact is missing: $binary_directory/$name" >&2
    exit 1
  fi
done

mkdir -p "$dist_directory"
rm -rf "$app_path" "$dmg_path"
mkdir -p \
  "$app_path/Contents/MacOS" \
  "$app_path/Contents/Helpers" \
  "$app_path/Contents/Resources"
signing_work="$(mktemp -d "${TMPDIR:-/tmp}/turbofieldfare-signing.XXXXXX")"
trap 'rm -rf "$signing_work"' EXIT

cp "$root/Packaging/Info.plist" "$app_path/Contents/Info.plist"
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleShortVersionString $version" \
  -c "Set :CFBundleVersion $build_number" \
  "$app_path/Contents/Info.plist"

sign_binary() {
  local path="$1"
  if [[ "$sign_identity" == "-" ]]; then
    codesign --force --sign - "$path"
  else
    codesign --force --options runtime --timestamp \
      --sign "$sign_identity" "$path"
  fi
}

for name in "${required_binaries[@]}"; do
  install -m 755 "$binary_directory/$name" "$signing_work/$name"
  sign_binary "$signing_work/$name"
  install -m 755 "$signing_work/$name" "$app_path/Contents/Helpers/$name"
done

# SwiftPM executable resource accessors resolve bundles relative to
# Bundle.main.bundleURL. Running the SwiftPM executables from the standard
# Contents/Helpers location lets their bundles live beside them while the
# outer app retains a valid code-signing layout.
for name in "${required_bundles[@]}"; do
  resource_bundle="$signing_work/$name"
  mkdir -p "$resource_bundle/Contents/Resources"
  ditto "$binary_directory/$name" "$resource_bundle/Contents/Resources"
  resource_identifier="$(
    printf '%s' "${name%.bundle}" | tr '[:upper:]_' '[:lower:]-'
  )"
  cat > "$resource_bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.turbofieldfare.resources.$resource_identifier</string>
    <key>CFBundleName</key>
    <string>${name%.bundle}</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleVersion</key>
    <string>$build_number</string>
</dict>
</plist>
PLIST
  sign_binary "$resource_bundle"
  ditto "$resource_bundle" "$app_path/Contents/Helpers/$name"
done

install -m 644 "$root/Packaging/TurboFieldfare.icns" \
  "$app_path/Contents/Resources/TurboFieldfare.icns"
xcrun clang \
  -arch arm64 \
  -mmacosx-version-min=26.0 \
  "$root/Packaging/launcher.c" \
  -o "$signing_work/$launcher_name"
sign_binary "$signing_work/$launcher_name"
install -m 755 \
  "$signing_work/$launcher_name" \
  "$app_path/Contents/MacOS/$launcher_name"

plutil -lint "$app_path/Contents/Info.plist"
for name in "${required_binaries[@]}"; do
  if [[ "$(file "$app_path/Contents/Helpers/$name")" != *"arm64"* ]]; then
    echo "error: $name is not an arm64 executable" >&2
    exit 1
  fi
done
if [[ "$(file "$app_path/Contents/MacOS/$launcher_name")" != *"arm64"* ]]; then
  echo "error: $launcher_name is not an arm64 executable" >&2
  exit 1
fi

if [[ "$sign_identity" == "-" ]]; then
  codesign --force --sign - "$app_path"
else
  codesign --force --options runtime --timestamp \
    --sign "$sign_identity" "$app_path"
fi
codesign --verify --deep --strict --verbose=2 "$app_path"

dmg_source="$(mktemp -d "${TMPDIR:-/tmp}/turbofieldfare-dmg.XXXXXX")"
trap 'rm -rf "$signing_work" "$dmg_source"' EXIT
ditto "$app_path" "$dmg_source/$app_name.app"
ln -s /Applications "$dmg_source/Applications"
hdiutil create \
  -volname "$app_name" \
  -srcfolder "$dmg_source" \
  -format UDZO \
  -ov \
  "$dmg_path"

if [[ "$sign_identity" != "-" ]]; then
  codesign --force --timestamp --sign "$sign_identity" "$dmg_path"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  if [[ "$sign_identity" == "-" ]]; then
    echo "error: NOTARY_PROFILE requires a Developer ID SIGN_IDENTITY" >&2
    exit 1
  fi
  xcrun notarytool submit "$dmg_path" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$dmg_path"
fi

hdiutil verify "$dmg_path"
echo "Created $app_path"
echo "Created $dmg_path"
