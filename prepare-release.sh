#!/bin/zsh
set -e
cd "${0:A:h}"

if [[ $# != 2 ]]; then
    echo "Usage: ./prepare-release.sh VERSION BUILD_NUMBER" >&2
    echo "Example: ./prepare-release.sh 2.1.0 5" >&2
    exit 2
fi
version=$1
build_number=$2
[[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { echo "Invalid version" >&2; exit 2; }
[[ "$build_number" =~ '^[0-9]+$' ]] || { echo "Invalid build number" >&2; exit 2; }

tag="v$version"
release_dir="$PWD/.build/releases/$tag"
if [[ -e "$release_dir" ]]; then
    echo "Release directory already exists: $release_dir" >&2
    exit 1
fi

APP_VERSION="$version" APP_BUILD="$build_number" ./build.sh
sparkle_dir="$PWD/.build/sparkle-2.9.6"
public_key=$("$sparkle_dir/bin/generate_keys" --account LinkedInGames -p)
bundled_key=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' LinkedInGames.app/Contents/Info.plist)
[[ "$public_key" == "$bundled_key" ]] || { echo "Keychain signing key does not match bundled public key" >&2; exit 1; }

mkdir -p "$release_dir"
archive="LinkedInGames-$version.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent LinkedInGames.app "$release_dir/$archive"
if [[ -n "${RELEASE_NOTES_FILE:-}" ]]; then
    [[ -f "$RELEASE_NOTES_FILE" ]] || { echo "Release notes file missing" >&2; exit 1; }
    cp "$RELEASE_NOTES_FILE" "$release_dir/LinkedInGames-$version.md"
fi

"$sparkle_dir/bin/generate_appcast" \
    --account LinkedInGames \
    --download-url-prefix "https://github.com/pdevh/LinkedInGames/releases/download/$tag/" \
    --maximum-deltas 0 \
    --maximum-versions 1 \
    --embed-release-notes \
    -o "$release_dir/appcast.xml" \
    "$release_dir"

[[ -s "$release_dir/appcast.xml" ]] || { echo "No appcast generated" >&2; exit 1; }
echo "Prepared signed release assets in $release_dir"
echo "Publish: gh release create $tag '$release_dir/$archive' '$release_dir/appcast.xml' --title '$tag' --notes-file <release-notes-file>"
