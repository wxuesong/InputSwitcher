# InputSwitcher App Store 审核拒绝修复指南

## 拒绝原因和修复方案

### 问题 1: 内购产品未提交审核
**Guideline 2.1(b) - Performance - App Completeness**

**修复**: 在 App Store Connect 中：
1. 打开你的 App → 「功能」→「App 内购买项目」
2. 选择 `com.hans.InputSwitcher.pro`
3. 点击「提交审核」
4. 上传一张 App 内购买项目的截图（可以是 Pro 升级窗口的截图）
5. 确保「已批准的应用内购买项目」部分中包含了该产品

---

### 问题 2: 支持 URL 无效
**Guideline 1.5 - Safety**

**修复**: 已创建支持页面 `docs/support/index.html`。需要部署到 GitHub Pages：

```bash
cd /Users/hans/Claude\ projects/InputSwitcher

# 将 docs 文件夹推送到 GitHub Pages
git add docs/support/
git commit -m "添加支持页面"
git push origin main
```

然后在 GitHub 仓库设置中：
1. 进入 Settings → Pages
2. Source 选择 "Deploy from a branch"
3. Branch 选择 `main`，文件夹选择 `/docs`
4. 保存后，页面会在 `https://wxuesong.github.io/InputSwitcher/support/` 可用

---

### 问题 3: 购买成功后显示错误消息 ✅ 已修复
**Guideline 2.1(b) - Performance - App Completeness**

**修复内容**:
1. ✅ 移除了 `activityGeneration` 计数器
2. ✅ 购买成功后立即设置 `hasProEntitlement = true`
3. ✅ 购买成功后发送 `proEntitlementDidChange` 通知
4. ✅ 简化了所有状态转换逻辑

**需要重新构建并上传**: 用 Xcode 构建新版本 (Build 5) 并上传到 App Store Connect

---

## 完整操作步骤

### 第一步: 部署支持页面
```bash
cd /Users/hans/Claude\ projects/InputSwitcher
git add docs/
git commit -m "添加支持页面"
git push origin main
```
然后去 GitHub 仓库设置中启用 Pages。

### 第二步: 构建新版本
用 Xcode 打开项目，构建并上传到 App Store Connect。

### 第三步: 提交内购产品
在 App Store Connect 中提交内购产品审核。

### 第四步: 提交审核
在 App Store Connect 中选择新版本，提交审核。

---

## 审核备注建议
在提交审核时，在审核备注中写上：
"Fixed: Purchase status now updates correctly after successful payment. Added support page. IAP products submitted for review."