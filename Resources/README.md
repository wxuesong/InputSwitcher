# 如何添加应用图标

## 方法一：使用现有的 .icns 文件

如果你已经有一个 `.icns` 格式的图标文件：

1. 将图标文件命名为 `AppIcon.icns`
2. 放到这个 `Resources` 目录下
3. 运行 `./build.sh` 重新构建

## 方法二：从 PNG 图片生成 .icns

### 准备图片
创建一个 1024×1024 像素的 PNG 图片（建议使用透明背景）

### 使用 macOS 自带工具生成

```bash
# 1. 创建临时图标集目录
mkdir AppIcon.iconset

# 2. 生成不同尺寸的图片（假设原图为 icon.png）
sips -z 16 16     icon.png --out AppIcon.iconset/icon_16x16.png
sips -z 32 32     icon.png --out AppIcon.iconset/icon_16x16@2x.png
sips -z 32 32     icon.png --out AppIcon.iconset/icon_32x32.png
sips -z 64 64     icon.png --out AppIcon.iconset/icon_32x32@2x.png
sips -z 128 128   icon.png --out AppIcon.iconset/icon_128x128.png
sips -z 256 256   icon.png --out AppIcon.iconset/icon_128x128@2x.png
sips -z 256 256   icon.png --out AppIcon.iconset/icon_256x256.png
sips -z 512 512   icon.png --out AppIcon.iconset/icon_256x256@2x.png
sips -z 512 512   icon.png --out AppIcon.iconset/icon_512x512.png
sips -z 1024 1024 icon.png --out AppIcon.iconset/icon_512x512@2x.png

# 3. 生成 .icns 文件
iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns

# 4. 清理临时文件
rm -rf AppIcon.iconset
```

### 使用在线工具
也可以使用在线 icns 生成器，例如：
- https://cloudconvert.com/png-to-icns
- https://iconverticons.com/online/

上传你的 PNG 图片，下载生成的 `.icns` 文件，重命名为 `AppIcon.icns` 并放到这个目录。

## 方法三：使用 SF Symbols（系统图标）

如果想临时使用系统键盘图标作为应用图标：

```bash
# 创建一个简单的键盘图标（需要有 SF Symbols app）
# 或者从网上下载一个键盘图标 PNG，然后用方法二转换
```

## 推荐的图标设计

考虑到这是一个输入法切换工具，推荐的图标元素：
- 🎹 键盘图标
- 🔄 切换/循环箭头
- 🌐 语言/地球图标
- A/中 字符组合

图标应该：
- 简洁清晰，在小尺寸下依然可识别
- 使用圆角矩形背景（macOS Big Sur 风格）
- 考虑深色模式下的显示效果
