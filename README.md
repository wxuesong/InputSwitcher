# InputSwitcher — 按应用自动切换输入法

macOS 菜单栏小工具:切换到某个应用时,自动切换到你为它指定的输入法。

- 仅菜单栏图标,不在程序坞显示(`LSUIElement`)
- 仅支持 Apple 芯片(arm64),要求 macOS 13+
- 无需辅助功能等任何系统权限

## 构建与运行

```bash
./build.sh
open build/InputSwitcher.app
```

也可以打开 `InputSwitcher.xcodeproj`。共享的 `InputSwitcher` Scheme 已关联 `StoreKit/InputSwitcher.storekit`，用于在 Xcode 中测试专业版购买、恢复购买和退款后的权益变化。App Store 上传必须使用 Xcode Archive。

版本 1.1 采用免费下载加专业版买断：免费版最多 5 条规则，并可锁定其中 1 条；`com.hans.InputSwitcher.pro` 是美国区 $4.99 的非消耗型内购，解锁无限规则、智能学习、无限规则锁定与全局锁定、导入导出、清理和 iCloud 同步。批量编辑与删除属于免费功能。

默认构建使用 ad-hoc 签名，因此 iCloud 同步会显示为不可用。普通构建不会再让用户误以为同步已经生效。

隐私清单、App Store 隐私营养标签填写建议和对外隐私政策草案见 [`APP_PRIVACY.md`](APP_PRIVACY.md)；英文公开版本见 [`PRIVACY_POLICY_EN.md`](PRIVACY_POLICY_EN.md)。

App Store 中英文名称和副标题见 [`APP_STORE_METADATA.md`](APP_STORE_METADATA.md)。

## iCloud 同步构建

先在 Apple Developer 后台为 `com.hans.InputSwitcher` 启用 iCloud Key-Value Storage，并创建匹配的 macOS provisioning profile。两台 Mac 必须安装由同一个 Team 和 App ID 签名的应用。

```bash
ENABLE_ICLOUD=true \
DEVELOPMENT_TEAM=YOUR_TEAM_ID \
CODE_SIGN_IDENTITY="Apple Development: Your Name (YOUR_TEAM_ID)" \
PROVISIONING_PROFILE="/path/to/InputSwitcher.provisionprofile" \
./build.sh
```

若 App Identifier Prefix 与 Team ID 不同，额外设置 `TEAM_IDENTIFIER_PREFIX`；也可以用 `KVS_IDENTIFIER` 明确指定 Developer Portal 中配置的完整 KVS identifier。构建脚本会在缺少证书、描述文件或签名 entitlement 时停止并报错。

## 使用

1. 点击菜单栏的键盘图标
2. 切到目标应用后,再点菜单里的「为「某某应用」设置输入法」选择输入法;或打开「规则设置…」批量从 /Applications 添加
3. 之后每次切换到该应用,输入法会自动变成你指定的那个

规则保存在 `UserDefaults`(`com.hans.InputSwitcher`),重启后保留。

## 代码结构

- `Sources/InputSwitcherApp.swift` — App 入口,`MenuBarExtra` + 设置窗口
- `Sources/AppDelegate.swift` — 监听 `NSWorkspace.didActivateApplicationNotification`,触发切换
- `Sources/InputSourceManager.swift` — Carbon TIS API 封装(枚举/读取/选择输入法)
- `Sources/RuleStore.swift` — 规则数据模型与持久化
- `Sources/MenuContent.swift` — 菜单栏菜单
- `Sources/SettingsView.swift` — 规则设置窗口

## 开机自启(可选)

把 `build/InputSwitcher.app` 拷到 `/Applications`,然后在
系统设置 → 通用 → 登录项 中添加。
