# InputSwitcher - App Store 上架准备清单

## 📦 版本信息
- **应用名称**: InputSwitcher / 输入法切换
- **Bundle ID**: com.hans.InputSwitcher
- **版本号**: 1.1 (Build 2)
- **最低系统**: macOS 13.0
- **架构**: Apple Silicon (arm64)

## ✅ 已完成项目

### 代码相关
- [x] 沙盒兼容（使用 SMAppService）
- [x] 九种语言支持（英文、简中、繁中、日语、韩语、德语、法语、西班牙语、巴西葡萄牙语）
- [x] StoreKit 2 非消耗型专业版购买与恢复购买
- [x] 免费版 5 条规则限制和统一专业版权限控制
- [x] App Privacy 隐私清单
- [x] 添加隐私权限说明
- [x] 版本号和 Copyright 信息

### 功能特性
- [x] 自动切换输入法
- [x] 批量编辑规则
- [x] 规则搜索/过滤
- [x] 导入/导出规则
- [x] 锁定功能（强制输入法）
- [x] 默认输入法设置
- [x] 切换通知（HUD）
- [x] 清理无效规则
- [x] 开机自启（沙盒兼容）
- [x] iCloud 同步（专业版，等待正式签名后双机验证）

## 📝 待准备材料

### 1. 开发者账号相关
- [ ] Apple Developer Program 审核通过
- [ ] 创建 App ID: com.hans.InputSwitcher
- [ ] 创建 Distribution/Development 证书和 App Store 配置文件
- [ ] 启用 App Sandbox 和 Hardened Runtime
- [ ] 为 `com.hans.InputSwitcher` 启用 iCloud Key-Value Storage

### 2. App Store Connect
- [ ] 创建新应用
- [ ] 填写应用信息
- [ ] 上传构建版本

### 3. 应用图标
需要准备以下尺寸的图标：
- [ ] 16x16
- [ ] 32x32
- [ ] 64x64
- [ ] 128x128
- [ ] 256x256
- [ ] 512x512
- [ ] 1024x1024

建议设计：
- 键盘图标 + 箭头符号
- 或者字母 "A" + 中文符号
- 使用品牌色

### 4. App Store 截图
至少需要 3 张截图（1280x800 或更大）：
- [ ] 主界面截图（规则列表）
- [ ] 通用设置截图
- [ ] 功能演示截图（切换通知 HUD）

### 5. 应用描述

#### 英文（参考）
**Title**: InputSwitcher - Auto Input Method Switcher

**Subtitle**: Automatically switch input methods per app

**Description**:
InputSwitcher automatically switches your input method when you switch between applications. No more manual switching!

Features:
• Auto-switch input methods per application
• Lock input method for specific apps
• Batch edit and manage rules
• Import/Export rules for backup
• Visual notification on switch
• Search and filter rules
• Clean up invalid rules
• Launch at login
• Supports multiple languages

Perfect for:
- Multilingual users
- Developers (English for coding, local language for docs)
- Content creators
- Anyone tired of manual input switching

#### 简体中文
**标题**: InputSwitcher - 输入法自动切换

**副标题**: 为不同应用自动切换输入法

**描述**:
InputSwitcher 可以在切换应用时自动切换到对应的输入法，告别手动切换的烦恼！

功能特点：
• 为每个应用设置专属输入法
• 锁定输入法，禁止手动切换
• 批量编辑和管理规则
• 导入/导出规则备份
• 切换时显示 HUD 通知
• 搜索和过滤规则
• 清理无效规则
• 开机自启
• 支持多语言

适合人群：
- 多语言用户
- 程序员（编程用英文，文档用中文）
- 内容创作者
- 厌倦手动切换输入法的所有人

#### 繁体中文
**標題**: InputSwitcher - 輸入法自動切換

**副標題**: 為不同應用程式自動切換輸入法

**描述**:
InputSwitcher 可以在切換應用程式時自動切換到對應的輸入法，告別手動切換的煩惱！

功能特點：
• 為每個應用程式設定專屬輸入法
• 鎖定輸入法，禁止手動切換
• 批次編輯和管理規則
• 匯入/匯出規則備份
• 切換時顯示 HUD 通知
• 搜尋和篩選規則
• 清理無效規則
• 開機自動啟動
• 支援多語言

適合族群：
- 多語言使用者
- 程式設計師（程式設計用英文，文件用中文）
- 內容創作者
- 厭倦手動切換輸入法的所有人

### 6. 关键词
英文: input method, keyboard, IME, auto switch, productivity, multilingual
中文: 输入法,自动切换,效率工具,多语言,键盘

### 7. 分类
- **主分类**: 效率工具 (Productivity)
- **副分类**: 工具 (Utilities)

### 8. 定价
- [x] 免费下载
- [x] 专业版非消耗型内购：美国区 $4.99 价格点
- [x] 产品 ID：`com.hans.InputSwitcher.pro`

### 9. 隐私政策（如果 App Store 要求）
可选，但建议准备：
- 说明不收集用户数据
- 说明需要辅助功能权限的原因
- 托管在 GitHub Pages 或个人网站

## 🔧 构建和提交流程

### 1. 使用正式证书签名
```bash
# 需要先在 Apple Developer 创建证书
codesign --deep --force --verify --verbose \
  --sign "Developer ID Application: Your Name (TEAM_ID)" \
  --options runtime \
  --entitlements InputSwitcher.entitlements \
  InputSwitcher.app
```

### 2. 创建安装包（可选）
如果想支持直接下载：
```bash
productbuild --component InputSwitcher.app /Applications \
  --sign "Developer ID Installer: Your Name (TEAM_ID)" \
  InputSwitcher.pkg
```

### 3. 公证（Notarization）
```bash
xcrun notarytool submit InputSwitcher.app.zip \
  --apple-id your@email.com \
  --team-id TEAM_ID \
  --password app-specific-password
```

### 4. 提交到 App Store
使用 Xcode 或 Transporter 上传

## 📊 预估时间线

- **准备材料**: 1-2 天
- **设计图标**: 1 天
- **截图和描述**: 半天
- **提交审核**: 10 分钟
- **审核等待**: 1-2 周

## 🚀 上架后运营

### 初期推广
- 在 Product Hunt 发布
- Reddit /r/macapps 分享
- 知乎、V2EX 等中文社区
- GitHub 开源（如果愿意）

### 用户反馈收集
- 设置反馈邮箱
- 创建 GitHub Issues
- 监控 App Store 评论

### 后续更新
根据用户反馈优先实现：
- 快捷键支持
- 应用分组
- iCloud 同步
- 更多语言支持（日语、韩语等）

## ⚠️ 注意事项

1. **Bundle ID 必须唯一**：如果 com.hans.InputSwitcher 已被占用，需要更换
2. **StoreKit 商品必须随 1.1 首次提交审核**：否则购买按钮无法取得正式商品
3. **iCloud 与购买必须使用正式签名测试**：ad-hoc 构建不会获得系统权限
4. **上传必须使用 Xcode Archive**：`build.sh` 仅用于本地开发验证
5. **隐私政策需要公开 URL**：提交前托管 `PRIVACY_POLICY.md`

## 📞 联系信息

准备好以下信息用于 App Store Connect：
- 支持邮箱
- 隐私政策 URL（可选）
- 营销 URL（可选，可以是 GitHub 仓库）

---

**当前状态**: 代码和商品配置已准备，等待开发者账号审核、正式签名及沙盒购买测试

**下一步**: 注册 Apple Developer 账号 或 设计应用图标
