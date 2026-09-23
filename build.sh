#!/bin/zsh
set -e
mkdir -p .build/module-cache
if [[ ! -d LinkedInGames.app && -d Zip.app ]]; then
    mv Zip.app LinkedInGames.app
fi
mkdir -p LinkedInGames.app/Contents/MacOS LinkedInGames.app/Contents/Resources
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/module-cache"
cp Zip.swift .build/main.swift
/usr/bin/swiftc -O -framework AppKit -emit-executable .build/main.swift GamesHome.swift PatchSelection.swift Patches.swift PatchesUI.swift PatchesTests.swift AdaptiveDifficulty.swift ProgressStore.swift RegressionTests.swift DifficultyToast.swift GameStatistics.swift StatisticsScreen.swift -o LinkedInGames.app/Contents/MacOS/LinkedInGames
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
<key>CFBundleShortVersionString</key><string>2.0.1</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [[ -f Assets/LinkedInGames.icns ]]; then
    cp Assets/LinkedInGames.icns LinkedInGames.app/Contents/Resources/AppIcon.icns
fi
rm -f LinkedInGames.app/Contents/MacOS/Zip
codesign --force --sign - LinkedInGames.app
echo "Built $PWD/LinkedInGames.app"
