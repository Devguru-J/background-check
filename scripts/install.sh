#!/usr/bin/env bash
# 빌드 → 실행 중인 앱 종료 → ~/Applications에 설치 → 실행
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh
pkill -x BackgroundCheck || true
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/Background Check.app"
cp -R "build/Background Check.app" "$HOME/Applications/"
open "$HOME/Applications/Background Check.app"
