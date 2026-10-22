#!/bin/zsh
# 김비서.app 만들기: 릴리스 빌드 → .app 구조로 복사 → ad-hoc 서명
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product KimBiseo
APP=build/KimBiseo.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/KimBiseo" "$APP/Contents/MacOS/KimBiseo"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "만들었어요: $PWD/$APP"
