# InputSwitcher 隐私申报稿

更新日期：2026-07-26

本文件依据当前代码行为整理，用于维护 Privacy Manifest、填写 App Store Connect 隐私营养标签，以及发布隐私政策。若后续加入分析、广告、崩溃上报、自建服务器或第三方 SDK，必须重新审查。

## 1. Privacy Manifest

随 App 打包的文件：`Resources/PrivacyInfo.xcprivacy`

当前声明：

- `NSPrivacyTracking`: `false`
- `NSPrivacyTrackingDomains`: 空
- `NSPrivacyCollectedDataTypes`: 空
- `NSPrivacyAccessedAPITypes`: `NSPrivacyAccessedAPICategoryUserDefaults`
- UserDefaults 使用原因：`CA92.1`，用于读取和保存仅供本 App 使用的偏好设置

当前代码还会读取自身调试日志的文件大小。文件大小不属于文件时间戳必需原因 API；不要为未使用的 API 类别增加声明。

## 2. App Store 隐私营养标签

App Store Connect 建议填写：

| 问题 | 当前版本答案 |
| --- | --- |
| Do you or your third-party partners collect data from this app? | No |
| Data Used to Track You | None |
| Data Linked to You | None |
| Data Not Linked to You | None |
| Privacy label shown on the store | Data Not Collected |

适用前提：

- 无广告、分析、遥测或第三方崩溃上报 SDK。
- 无开发者运营的服务器或账户系统。
- iCloud 同步仅使用用户私人 iCloud KVS，开发者不接收或访问其中内容。
- StoreKit 交易由 Apple 处理，App 只在设备上读取产品信息和当前权益，不将交易数据发送给开发者。

如果上述任一前提改变，提交新版本前需更新营养标签和 Manifest。

## 3. 实际处理的数据

InputSwitcher 为实现输入法规则，会在设备上处理：

- 当前最前方 App 的名称和 Bundle Identifier。
- 当前及可用输入法的标识符和显示名称。
- 用户创建的规则、快捷键和其他偏好设置。
- 启用智能学习后生成的本地观察记录。
- 用户主动启用调试模式后生成的本地日志。

App 不读取或记录键盘输入内容，不读取剪贴板内容。只有用户主动执行“复制 Bundle ID”时才会向剪贴板写入文本。

启用 iCloud 同步时，规则及相关设置会写入用户的私人 iCloud KVS，以供同一 Apple 账户下的 Mac 同步。数据不经过开发者运营的服务器。

## 4. 对外隐私政策草案

### InputSwitcher 隐私政策

InputSwitcher 以本地处理为原则。App 不包含广告、用户分析或跟踪服务，也不会把数据发送到开发者运营的服务器。

为自动切换输入法，InputSwitcher 会读取当前最前方 App 的名称、Bundle Identifier 和当前输入法状态。App 不读取、记录或存储用户键入的文字。

规则、偏好设置、智能学习记录及用户主动启用的调试日志默认保存在 Mac 本地。用户主动使用导出功能时，App 才会在用户选择的位置创建规则文件。

用户选择启用 iCloud 同步后，规则和相关设置将通过 Apple 的 iCloud KVS 存储在用户的私人 iCloud 空间，用于同一 Apple 账户下设备间同步。开发者不运营中转服务器，也不接收这些数据。iCloud 数据的处理同时受 Apple 的服务条款和隐私政策约束。

专业版购买由 Apple 通过 StoreKit 处理。InputSwitcher 只读取购买状态以解锁功能，不接收银行卡或付款资料。

InputSwitcher 不出售数据，不将数据用于广告，也不与数据经纪商共享数据。

本政策如因 App 功能或依赖项变化而更新，将在发布新版本时同步修订。正式发布前，请将本政策部署到公开 HTTPS 页面，并在此处补充支持邮箱和隐私政策 URL。

英文公开版本见 [`PRIVACY_POLICY_EN.md`](PRIVACY_POLICY_EN.md)。
