#!/usr/bin/env bash
# 打包 随手.dmg(含 build/随手.app)
# 用法: ./scripts/make-dmg.sh [版本号, 默认 1.8.0]
set -e
cd "$(dirname "$0")/.."

VERSION="${1:-1.8.0}"
BUILD_DIR="build/dmg"
APP="build/随手.app"

# 前置:构建 app
if [ ! -d "$APP" ]; then
  echo "==> 未找到 $APP,先执行 build-app.sh";
  ./scripts/build-app.sh
fi

rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"
echo "==> 拷贝 app 到 dmg 目录"
cp -R "$APP" "$BUILD_DIR/"

# 创建 Applications 软链(拖拽安装提示)
ln -s /Applications "$BUILD_DIR/Applications"

echo "==> 创建 DMG"
DMG="build/随手-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "随手 $VERSION" -srcfolder "$BUILD_DIR" -ov -format UDZO "$DMG" >/dev/null

echo "==> 完成: $DMG"
echo "    open \"$DMG\"  # 验证"

