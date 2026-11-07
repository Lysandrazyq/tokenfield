# 构建 Tokenfield

原生项目使用 SwiftUI 和本地 Swift Package。本次发行使用 Xcode 27.2 构建；最低运行环境为 macOS 14、iOS 17。iPhone 需要通过 Xcode 和自己的签名安装，当前 Release 只提供 Mac DMG。

## 运行与打包

打开 `native-ios/Tokenfield.xcodeproj`，Mac 选择 `TokenfieldMac`，iPhone 选择 `Tokenfield`。

在项目根目录打包 Mac 通用版：

```sh
zsh './打包Mac安装包.command'
```

输出为 `releases/` 中的 DMG 与 SHA-256 文件，主应用和卸载助手均包含 arm64、x86_64 两种架构。脚本使用临时签名，不进行 Apple 公证。正式 Developer ID 签名、公证或 iCloud 发行配置需由开发者自行配置，不要提交私钥、证书或本地开发者配置。

## 本地回归

```sh
swift test --package-path native-ios/Packages/TokenfieldCore
swift test --package-path native-ios/Tests/MacMonitor
swift test --package-path native-ios/Tests/MacQuotaAlerts
swift test --package-path native-mac-installer
```

iOS 单元测试位于 `native-ios/TokenfieldTests`，UI 测试位于 `native-ios/TokenfieldUITests`，可在 Xcode Test 中运行。

## 数据边界

Codex 连接只读取授权日志中的任务元数据和额度，不读取认证文件。自动汇率只请求固定 USD/CNY 货币对，不携带账本、账号或 Codex 数据。业务数据默认保存在设备上，JSON 备份用于端间迁移；当前公开安装包尚未配置 iCloud。
