#!/usr/bin/env bash
# 将 SPM 可执行文件打包为独立运行的【随手.app】（release 模式）
# 内含：图标生成（make-icon.swift → png → icns）、资源合并、ad-hoc 签名
set -e
cd "$(dirname "$0")/.."

echo "==> swift build -c release"
swift build -c release

BIN=".build/release/MarkNote"
APP="build/随手.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp "$BIN" "$APP/Contents/MacOS/MarkNote"

cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>随手</string>
  <key>CFBundleDisplayName</key><string>随手</string>
  <key>CFBundleIdentifier</key><string>com.gzhysu.marknote</string>
  <key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
  <key>CFBundleVersion</key><string>1.1</string>
  <key>CFBundleShortVersionString</key><string>1.1.0</string>
  <key>CFBundleExecutable</key><string>MarkNote</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# ── App 图标 ──────────────────────────────────────────────
echo "==> 生成 AppIcon.icns"
if [ ! -f "build/AppIcon.icns" ] || [ "scripts/make-icon.swift" -nt "build/AppIcon.icns" ]; then
  swift scripts/make-icon.swift build/icon-1024.png >/dev/null
  ICONSET="build/icon.iconset"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$(($s * 2))
    sips -z $d $d build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o build/AppIcon.icns
fi
mkdir -p "$APP/Contents/Resources"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# ── 资源（SPM bundle 内置于 Contents/Resources/Resources） ──
RES="build/Resources-copied"
rm -rf "$RES"
if [ -d ".build/release/MarkNote_MarkNote.bundle/Resources" ]; then
  cp -R ".build/release/MarkNote_MarkNote.bundle/Resources" "$RES"
  cp -R "$RES" "$APP/Contents/Resources/Resources"
fi

# ── 签名（ad-hoc，本机直接运行） ──
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

# ── 部署到 应用程序 目录（桌面外运行 → 不再触发"访问桌面"TCC 询问） ──
DEST="$HOME/Applications/随手.app"
rm -rf "$DEST"
mkdir -p "$HOME/Applications"
cp -R "$APP" "$DEST"
codesign --force --deep --sign - "$DEST" >/dev/null 2>&1 || true

echo "==> 完成: $APP"
echo "    open \"$APP\"                       # 开发目录调试版"
echo "    open \"$DEST\"                       # 应用目录部署版（推荐，无 TCC 弹窗）"
