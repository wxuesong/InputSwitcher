#!/bin/bash
# 从 icon_1024x1024.png 生成 InputSwitcher.icns
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f "icon_1024x1024.png" ]; then
    echo "错误: 找不到 icon_1024x1024.png"
    exit 1
fi

echo "开始生成 InputSwitcher.icns..."

# 创建临时 iconset 目录
mkdir -p AppIcon.iconset

# 生成各种尺寸
echo "生成各种尺寸的图标..."
sips -z 16 16     icon_1024x1024.png --out AppIcon.iconset/icon_16x16.png
sips -z 32 32     icon_1024x1024.png --out AppIcon.iconset/icon_16x16@2x.png
sips -z 32 32     icon_1024x1024.png --out AppIcon.iconset/icon_32x32.png
sips -z 64 64     icon_1024x1024.png --out AppIcon.iconset/icon_32x32@2x.png
sips -z 128 128   icon_1024x1024.png --out AppIcon.iconset/icon_128x128.png
sips -z 256 256   icon_1024x1024.png --out AppIcon.iconset/icon_128x128@2x.png
sips -z 256 256   icon_1024x1024.png --out AppIcon.iconset/icon_256x256.png
sips -z 512 512   icon_1024x1024.png --out AppIcon.iconset/icon_256x256@2x.png
sips -z 512 512   icon_1024x1024.png --out AppIcon.iconset/icon_512x512.png
sips -z 1024 1024 icon_1024x1024.png --out AppIcon.iconset/icon_512x512@2x.png

# 生成 .icns 文件
echo "生成 .icns 文件..."
iconutil -c icns AppIcon.iconset -o InputSwitcher.icns

# 清理临时文件
rm -rf AppIcon.iconset

echo "✓ 成功生成 InputSwitcher.icns"
echo "现在可以运行 ../build.sh 重新构建应用"
