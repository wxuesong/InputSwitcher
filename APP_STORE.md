# App Store 兼容性说明

> 版本 1.1 已提供 `InputSwitcher.xcodeproj`、共享 Scheme、StoreKit 2 专业版购买、隐私清单和九语言资源。当前上架步骤以 `APP_STORE_SUBMISSION.md` 为准。

## 当前状态

InputSwitcher 目前使用**混合模式**，可以在本地和 App Store 两种环境下运行。

## 构建模式

### 1. 本地构建（默认）
```bash
./build.sh
```
- 不启用沙盒
- 使用 LaunchAgent 方式实现开机自启
- 适合个人使用和分发

### 2. App Store 构建

使用 Xcode 打开 `InputSwitcher.xcodeproj`，在 Signing & Capabilities 中选择正式 Team，然后通过 Product > Archive 构建。`build.sh` 仅用于本地开发验证，不用于上传 App Store。

## App Store 沙盒兼容性

### ✅ 已兼容的功能

1. **输入法切换** — 使用 TISSelectInputSource API，沙盒兼容
2. **应用切换监听** — 使用 NSWorkspace 通知，沙盒兼容
3. **菜单栏图标** — 使用 MenuBarExtra，沙盒兼容
4. **规则存储** — 使用 UserDefaults，沙盒兼容
5. **调试日志** — 写入应用自己的 Caches 目录，沙盒兼容

### ⚠️ 有限制的功能

1. **开机自启**
   - 本地构建：使用 LaunchAgent（写入 ~/Library/LaunchAgents/）
   - App Store 构建：需要使用 SMAppService API
   - 当前代码包含条件编译支持，但在 CLI 环境下无法测试 SMAppService

## App Store 提交前需要做的事

### 1. 使用 Xcode 构建
App Store 版本必须用 Xcode 构建，而不是命令行 swiftc：

1. 创建 Xcode 项目
2. 导入所有源文件
3. 配置 Signing & Capabilities：
   - 启用 App Sandbox
   - 添加 Entitlements 文件
4. 使用 Xcode Archive 构建

### 2. 修改 LaunchAtLoginManager
在 Xcode 项目中，将 `LaunchAtLoginManager.swift` 中的条件编译部分替换为真正的 SMAppService 实现：

```swift
import ServiceManagement

@available(macOS 13.0, *)
private func checkSMAppService() -> Bool {
    return SMAppService.mainApp.status == .enabled
}

@available(macOS 13.0, *)
private func setSMAppService(_ enabled: Bool) {
    do {
        if enabled {
            if SMAppService.mainApp.status == .enabled { return }
            try SMAppService.mainApp.register()
        } else {
            if SMAppService.mainApp.status == .notRegistered { return }
            try SMAppService.mainApp.unregister()
        }
    } catch {
        print("Failed to \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)")
    }
}
```

### 3. 更新 Bundle Identifier
将 `com.hans.InputSwitcher` 改为你的 Apple Developer Team ID 对应的 identifier。

### 4. 添加隐私说明（如果需要）
虽然当前不需要特殊权限，但如果将来添加功能，可能需要在 Info.plist 中添加隐私描述。

## 需要的 Entitlements

已创建的 `InputSwitcher.entitlements` 文件包含：
- `com.apple.security.app-sandbox` — 启用沙盒
- `com.apple.security.application-groups` — 支持登录项

## 技术限制

### CLI 构建环境
当前 CLI 环境（Claude Code）有以下限制：
- 无法导入 ServiceManagement 框架（沙盒限制）
- 无法运行 Xcode 项目构建
- 无法测试 App Store 沙盒模式

这些限制只影响开发环境，不影响最终的 App Store 应用。

### 解决方案
- **本地开发**：使用当前的 `./build.sh` 脚本，LaunchAgent 方式工作正常
- **App Store 发布**：使用 Xcode 构建，启用真正的 SMAppService

## 总结

✅ **可以提交 App Store**，但需要：
1. 使用 Xcode 构建（不是命令行 swiftc）
2. 启用真正的 SMAppService API
3. 配置正确的签名和 Entitlements

✅ **当前本地版本完全可用**，所有功能正常工作。

如果只是个人使用或通过 GitHub 分发，当前的构建方式已经足够。
