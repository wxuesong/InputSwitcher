# 多语言支持

InputSwitcher 已支持以下 9 种语言：

## 支持的语言

1. **English** (en) - 英语
2. **简体中文** (zh-Hans) - Simplified Chinese
3. **繁體中文** (zh-Hant) - Traditional Chinese
4. **日本語** (ja) - Japanese
5. **한국어** (ko) - Korean
6. **Deutsch** (de) - German
7. **Français** (fr) - French
8. **Español** (es) - Spanish
9. **Português (Brasil)** (pt-BR) - Brazilian Portuguese

## 工作原理

应用会自动检测系统语言设置，并使用对应的本地化文本：

- 系统设置为简体中文 → 显示简体中文界面
- 系统设置为英语 → 显示英文界面
- 系统设置为其他语言 → 回退到英文

## 本地化文件位置

所有翻译文本存储在：
```
Resources/Localizations/
├── en.strings          # 英语
├── zh-Hans.strings     # 简体中文
├── zh-Hant.strings     # 繁體中文
├── ja.strings          # 日本語
├── ko.strings          # 한국어
├── de.strings          # Deutsch
├── fr.strings          # Français
├── es.strings          # Español
└── pt-BR.strings       # Português (Brasil)
```

## 本地化的界面元素

### 菜单栏
- 启用/禁用自动切换
- 为当前应用设置输入法
- 最近使用的应用
- 调试菜单
- 规则设置
- 退出

### 规则设置窗口
- 窗口标题
- 表格列标题
- 按钮文本
- 开关标签
- 空状态提示

### 应用信息对话框
- 对话框标题
- 应用信息字段
- 按钮文本

## 添加新语言

如需添加新语言支持：

1. 在 `Resources/Localizations/` 目录创建新的 `.strings` 文件
2. 使用标准语言代码命名（如 `ko.strings` 为韩语）
3. 复制 `en.strings` 的内容并翻译所有字符串
4. 在 `Sources/Localization.swift` 的 `detectLanguage()` 函数中添加语言映射
5. 在 `Info.plist` 的 `CFBundleLocalizations` 数组中添加语言代码
6. 重新构建应用

## 测试不同语言

macOS 系统：
1. 打开 **系统设置** → **通用** → **语言与地区**
2. 点击 **首选语言** 下的 **+** 按钮
3. 添加要测试的语言
4. 重启 InputSwitcher

或者使用命令行测试：
```bash
# 测试英文
defaults write com.hans.InputSwitcher AppleLanguages '("en")'

# 测试简体中文
defaults write com.hans.InputSwitcher AppleLanguages '("zh-Hans")'

# 测试日语
defaults write com.hans.InputSuitcher AppleLanguages '("ja")'

# 恢复系统默认
defaults delete com.hans.InputSwitcher AppleLanguages
```

## 翻译质量

所有翻译均经过仔细校对，力求准确和地道。如果发现翻译问题，欢迎提交改进建议。

## 代码实现

本地化系统使用自定义的 `L10n` 类：

```swift
// 简单文本
L10n.string("menu.quit")  // "退出" / "Quit" / "Beenden" ...

// 带参数的文本
L10n.string("menu.set_input_for", appName)  // "为「Chrome」设置输入法"

// 带多个参数
L10n.string("menu.rules_count", count)  // "已配置 5 条规则"
```

所有 UI 文本都通过 `L10n.string()` 函数加载，确保完整的多语言支持。
