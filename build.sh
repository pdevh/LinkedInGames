#!/bin/zsh
set -e
mkdir -p .build/module-cache Zip.app/Contents/MacOS
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/module-cache"
cp Zip.swift .build/main.swift
/usr/bin/swiftc -O -framework AppKit -emit-executable .build/main.swift AdaptiveDifficulty.swift ProgressStore.swift RegressionTests.swift DifficultyToast.swift GameStatistics.swift StatisticsScreen.swift -o Zip.app/Contents/MacOS/Zip
codesign --force --sign - Zip.app
echo "Built $PWD/Zip.app"
