# 菜单栏图标制作指南

## 图标规格

**尺寸：**
- `MenuBarIcon.png` — 22×22 像素（@1x，标准分辨率）
- `MenuBarIcon@2x.png` — 44×44 像素（@2x，Retina 显示器）

**设计要求：**
- 格式：PNG，带透明背景
- 颜色：纯黑色（#000000）
- 风格：简洁、扁平化，线条清晰
- 系统会自动处理浅色/深色模式的适配

## 制作方法

### 方法一：使用 SF Symbols（最简单）

如果想用系统图标风格：

1. 打开 SF Symbols 应用（macOS自带，或从 Apple 开发者网站下载）
2. 搜索合适的图标（如 keyboard、globe、textformat.abc 等）
3. 导出为 PNG
4. 使用 sips 命令调整大小：

```bash
cd "/Users/hans/Claude projects/InputSwitcher/Resources"

# 生成 @1x 版本（22×22）
sips -z 22 22 原图.png --out MenuBarIcon.png

# 生成 @2x 版本（44×44）
sips -z 44 44 原图.png --out MenuBarIcon@2x.png
```

### 方法二：从应用图标提取

如果想使用应用图标的简化版本：

```bash
cd "/Users/hans/Claude projects/InputSwitcher/Resources"

# 从 .icns 提取 PNG（需要先安装 imagemagick）
# brew install imagemagick
convert InputSwitcher.icns[0] temp.png

# 调整大小并转为黑色剪影
sips -z 22 22 temp.png --out MenuBarIcon.png
sips -z 44 44 temp.png --out MenuBarIcon@2x.png

rm temp.png
```

### 方法三：使用在线工具

1. 在 Figma/Sketch/Illustrator 等工具中设计图标
2. 导出为 22×22 和 44×44 的 PNG
3. 命名为 `MenuBarIcon.png` 和 `MenuBarIcon@2x.png`
4. 放到这个 Resources 目录

### 方法四：使用 iconutil（从 iconset）

如果有完整的图标集：

```bash
# 从 iconset 提取
iconutil -c iconset InputSwitcher.icns -o temp.iconset

# 选择合适尺寸的图标并重命名
cp temp.iconset/icon_16x16@2x.png MenuBarIcon.png      # 32×32 缩小到 22×22
cp temp.iconset/icon_32x32@2x.png MenuBarIcon@2x.png   # 64×64 缩小到 44×44

# 调整到正确尺寸
sips -z 22 22 MenuBarIcon.png
sips -z 44 44 MenuBarIcon@2x.png

rm -rf temp.iconset
```

## 设计建议

**推荐图标元素：**
- 🎹 键盘（简化版，3-4个按键）
- 🔄 循环箭头 + 字母
- A/中 字符切换
- 输入光标 + 语言符号

**设计原则：**
- 线条粗细：2-3 像素
- 留白：周围至少留 2 像素边距
- 可识别性：在小尺寸下仍能清楚看到图案
- 对称性：视觉上平衡居中

## 测试

放置好图标后运行：

```bash
cd "/Users/hans/Claude projects/InputSwitcher"
./build.sh
open build/InputSwitcher.app
```

查看菜单栏右上角的图标效果。

## 回退到系统图标

如果不想使用自定义图标，只需删除或重命名 `MenuBarIcon.png` 文件，应用会自动使用系统的 keyboard 图标。
