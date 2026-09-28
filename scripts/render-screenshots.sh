#!/usr/bin/env bash
# README 이미지(docs/images/*.png)를 앱의 실제 SwiftUI 뷰와 예시 데이터로 렌더링한다.
# 화면 녹화 권한 없이 오프스크린 창을 캡처하므로 개인 데이터가 들어가지 않는다.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

swiftc -O -parse-as-library -emit-library -static -module-name BackgroundCheckCore \
    -emit-module -emit-module-path "$OUT/BackgroundCheckCore.swiftmodule" \
    Sources/BackgroundCheckCore/*.swift -o "$OUT/libBackgroundCheckCore.a"

APP=Sources/BackgroundCheck
swiftc -O -I "$OUT" -L "$OUT" -lBackgroundCheckCore \
    "$APP/MenuStyle.swift" "$APP/SessionRowView.swift" "$APP/MenuPanelView.swift" \
    "$APP/SettingsView.swift" "$APP/MenuBarLabel.swift" \
    Tools/Screenshots/Stubs.swift Tools/Screenshots/main.swift \
    -o "$OUT/render"

mkdir -p docs/images
"$OUT/render" docs/images
