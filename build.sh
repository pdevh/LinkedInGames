#!/bin/zsh
set -e
cd "${0:A:h}"

# Official Sparkle 2.9.6 binary distribution, pinned by SHA-256.
SPARKLE_VERSION=2.9.6
SPARKLE_SHA256=52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192
SPARKLE_DIR="$PWD/.build/sparkle-$SPARKLE_VERSION"
if [[ ! -d "$SPARKLE_DIR/Sparkle.framework" ]]; then
    archive="$PWD/.build/Sparkle-$SPARKLE_VERSION.tar.xz"
    mkdir -p .build
    curl -fL --retry 3 -o "$archive" "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
    actual=$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')
    [[ "$actual" == "$SPARKLE_SHA256" ]] || { echo "Sparkle download checksum mismatch" >&2; exit 1; }
    mkdir -p "$SPARKLE_DIR"
    /usr/bin/tar -xf "$archive" -C "$SPARKLE_DIR"
fi

APP_VERSION=${APP_VERSION:-2.1.0}
APP_BUILD=${APP_BUILD:-5}
[[ "$APP_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { echo "APP_VERSION must be major.minor.patch" >&2; exit 1; }
[[ "$APP_BUILD" =~ '^[0-9]+$' ]] || { echo "APP_BUILD must be an integer" >&2; exit 1; }
CODE_SIGN_IDENTITY=${CODE_SIGN_IDENTITY:--}
mkdir -p .build/module-cache
if [[ ! -d LinkedInGames.app && -d Zip.app ]]; then
    mv Zip.app LinkedInGames.app
fi
mkdir -p LinkedInGames.app/Contents/MacOS LinkedInGames.app/Contents/Resources LinkedInGames.app/Contents/Frameworks
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/module-cache"
cp Zip.swift .build/main.swift
/usr/bin/swiftc -O -framework AppKit -F "$SPARKLE_DIR" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks -emit-executable .build/main.swift UpdateService.swift GameUIStyle.swift GamesHome.swift PatchSelection.swift Patches.swift PatchesUI.swift PatchesTests.swift AdaptiveDifficulty.swift ProgressStore.swift RegressionTests.swift DifficultyToast.swift GameStatistics.swift StatisticsScreen.swift -o LinkedInGames.app/Contents/MacOS/LinkedInGames
cat > LinkedInGames.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LinkedInGames</string>
<key>CFBundleIdentifier</key><string>local.philipp.zipgame</string>
<key>CFBundleName</key><string>LinkedInGames</string>
<key>CFBundleDisplayName</key><string>LinkedInGames</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>__APP_VERSION__</string>
<key>CFBundleVersion</key><string>__APP_BUILD__</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>SUFeedURL</key><string>https://github.com/pdevh/LinkedInGames/releases/latest/download/appcast.xml</string>
<key>SUPublicEDKey</key><string>KIyFEwlsWVpLFKAfPJwxCB4O9sfnAiQKUQ1pdkXfZbw=</string>
<key>SURequireSignedFeed</key><true/>
<key>SUVerifyUpdateBeforeExtraction</key><true/>
<key>SUEnableAutomaticChecks</key><true/>
<key>SUAutomaticallyUpdate</key><false/>
</dict></plist>
PLIST
/usr/bin/sed -i '' -e "s/__APP_VERSION__/$APP_VERSION/g" -e "s/__APP_BUILD__/$APP_BUILD/g" LinkedInGames.app/Contents/Info.plist
if [[ -f Assets/LinkedInGames.icns ]]; then
    cp Assets/LinkedInGames.icns LinkedInGames.app/Contents/Resources/AppIcon.icns
fi
/usr/bin/ditto "$SPARKLE_DIR/Sparkle.framework" LinkedInGames.app/Contents/Frameworks/Sparkle.framework
rm -f LinkedInGames.app/Contents/MacOS/Zip
if [[ "$CODE_SIGN_IDENTITY" == "-" ]]; then
    /usr/bin/codesign --force --deep --sign - LinkedInGames.app
else
    /usr/bin/codesign --force --deep --options runtime --sign "$CODE_SIGN_IDENTITY" LinkedInGames.app
fi
/usr/bin/codesign --deep --verify --strict LinkedInGames.app
echo "Built $PWD/LinkedInGames.app"
