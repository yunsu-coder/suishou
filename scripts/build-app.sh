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
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key>
  <array><string>en</string><string>zh-Hans</string></array>
  <key>CFBundleVersion</key><string>1.1</string>
  <key>CFBundleShortVersionString</key><string>1.1.0</string>
  <key>CFBundleExecutable</key><string>MarkNote</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Markdown 文档</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Owner</string>
      <key>CFBundleTypeExtensions</key>
      <array><string>md</string><string>markdown</string><string>mdown</string></array>
      <key>LSItemContentTypes</key>
      <array><string>net.daringfireball.markdown</string></array>
    </dict>
    <dict>
      <key>CFBundleTypeName</key><string>纯文本</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>CFBundleTypeExtensions</key>
      <array><string>txt</string></array>
      <key>LSItemContentTypes</key>
      <array><string>public.plain-text</string></array>
    </dict>
  </array>
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

# ── 资源：SPM 访问器（Bundle.module）只认「.app 根部 MarkNote_MarkNote.bundle」或
#    「.build/release/…」两条固定路径 —— 必须把 bundle 放进 app 本体（真正自包含，不依赖本机 .build 残留）。
#    双保险：bundle 根级根 + Contents/Resources 各放一份（不同 SwiftPM 版本的访问器 base 不同）。
SRC_BUNDLE=".build/release/MarkNote_MarkNote.bundle"
if [ -d "$SRC_BUNDLE" ]; then
  rm -rf "$APP/MarkNote_MarkNote.bundle"
  cp -R "$SRC_BUNDLE" "$APP/MarkNote_MarkNote.bundle"
  rm -rf "$APP/Contents/Resources/MarkNote_MarkNote.bundle"
  cp -R "$SRC_BUNDLE" "$APP/Contents/Resources/MarkNote_MarkNote.bundle"
fi
# 资源强制以仓库为准（SPM 增量可能产出陈旧 bundle 资源 —— 打包一致性兜底）。
# 关键：Bundle.module 访问器优先命中「.app 根部 bundle」，如不刷这里 —— 导出器会跑旧 preview.js！
for BUNDLE_DIR in "$APP/MarkNote_MarkNote.bundle/Resources" \
                 "$APP/Contents/Resources/MarkNote_MarkNote.bundle/Resources"; do
  if [ -d "$BUNDLE_DIR" ]; then
    rm -rf "$BUNDLE_DIR"
    cp -R Sources/MarkNote/Resources "$BUNDLE_DIR"
  fi
done
rm -rf "$APP/Contents/Resources/Resources"
cp -R Sources/MarkNote/Resources "$APP/Contents/Resources/Resources" 2>/dev/null || true

# ── 签名（ad-hoc，本机直接运行） ──
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

# ── 部署到 应用程序 目录（桌面外运行 → 不再触发"访问桌面"TCC 询问） ──
DEST="$HOME/Applications/随手.app"
rm -rf "$DEST"
mkdir -p "$HOME/Applications"
cp -R "$APP" "$DEST"
codesign --force --deep --sign - "$DEST" >/dev/null 2>&1 || true

# ── 重新注册 LaunchServices（每次重签名后绑定失效 → Finder 打开方式/双击生效） ──
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREG" -f "$DEST" >/dev/null 2>&1 || true
# 强制「.md 默认打开 = 随手」（写入系统 LaunchServices 默认库，不依赖 LS 的 Owner 猜测）
defaults write com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers -array-add '<dict><key>LSHandlerContentType</key><string>net.daringfireball.markdown</string><key>LSHandlerRoleAll</key><string>com.gzhysu.marknote</string></dict>' 2>/dev/null || true

echo "==> 完成: $APP"
echo "    open \"$APP\"                       # 开发目录调试版"
echo "    open \"$DEST\"                       # 应用目录部署版（推荐，无 TCC 弹窗）"
