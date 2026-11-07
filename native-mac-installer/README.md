# 额度终端旧版卸载助手

DMG 中的「卸载旧版本.app」是独立的通用 macOS 应用，无需 Xcode。最低 macOS 14。其独立灰白液态玻璃回收图标和可编辑源文件见 `brand/uninstaller`。

打开后会检查 `/Applications`、`~/Applications`、当前用户的临时运行位置，以及早期的 `/private/tmp/TokenfieldLocal/TokenfieldMac.app`。只浅层检查应用程序文件夹，不递归遍历用户文件。其他位置可通过系统文件选择器检查。

候选应用须具有额度终端 Bundle ID、完整的可执行应用结构和可确认的较旧版本号。当前版、更高版本、其他软件、符号链接和安装源不列入清理。版本相同但构建号较旧时可清理。

列表默认不勾选。确认窗口显示完整路径与版本。请求退出前及移到废纸篓前各复核一次快照；仅正常退出与所选路径一致的进程，退出被阻止时不强退。移动失败会显示原因。所有操作仅针对 `.app`，不会清理 Library、账号记录、月报、偏好设置或备份；不清空废纸篓。

测试：

```sh
swift test --package-path native-mac-installer --scratch-path .build/MacInstallerTests
```

独立构建：

```sh
zsh scripts/build-mac-uninstaller.zsh /private/tmp/TokenfieldUninstaller 1.1.4 7
```

正式本地打包入口是根目录「打包Mac安装包.command」。助手版本参数取自本次构建的主应用，不需要手工维护。该入口会干净构建主应用、构建两个架构的助手、签名、生成并验证 DMG。当前应用和助手均为临时签名，正式分发仍需 Developer ID 与公证。
