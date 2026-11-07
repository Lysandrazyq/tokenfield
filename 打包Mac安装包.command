#!/bin/zsh
set -eu

task_root="${0:A:h}"
cd "$task_root"
task_derived="$task_root/.build/MacReleaseDerivedData"
task_product="$task_derived/Build/Products/Release/TokenfieldMac.app"
task_log="$task_root/.build/logs/mac-dmg-release-build.log"
mkdir -p "$task_root/.build/logs" "$task_root/releases"

print '正在构建 Mac 通用版（Apple 芯片和 Intel）…'
if ! /usr/bin/xcodebuild \
    -project "$task_root/native-ios/Tokenfield.xcodeproj" \
    -scheme TokenfieldMac -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$task_derived" \
    'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_ENTITLEMENTS=Config/TokenfieldMacLocal.entitlements \
    clean build > "$task_log" 2>&1; then
    print "编译没有完成，日志：$task_log"
    /usr/bin/tail -n 35 "$task_log"
    exit 1
fi

task_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$task_product/Contents/Info.plist")
task_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$task_product/Contents/Info.plist")
task_temp_base="${TMPDIR:-/tmp}"
task_staging=$(/usr/bin/mktemp -d "${task_temp_base%/}/tokenfield-dmg.XXXXXX")
task_volume="$task_staging/volume"
task_app="$task_volume/额度终端.app"
task_dmg="$task_root/releases/额度终端-$task_version-macOS-universal.dmg"
mkdir -p "$task_volume"

# 临时目录不受 Desktop 文件服务影响，避免 FinderInfo 破坏签名。
/usr/bin/ditto --noextattr --norsrc "$task_product" "$task_app"
/usr/bin/xattr -dr com.apple.FinderInfo "$task_app"
/usr/bin/codesign --force --sign - --timestamp=none \
    --entitlements "$task_root/native-ios/Config/TokenfieldMacLocal.entitlements" "$task_app"
/usr/bin/codesign --verify --deep --strict "$task_app"
/usr/bin/lipo "$task_app/Contents/MacOS/TokenfieldMac" -verify_arch arm64
/usr/bin/lipo "$task_app/Contents/MacOS/TokenfieldMac" -verify_arch x86_64
/bin/ln -s /Applications "$task_volume/Applications"

print '正在构建旧版本卸载助手…'
/bin/zsh "$task_root/scripts/build-mac-uninstaller.zsh" "$task_volume" "$task_version" "$task_build"

/bin/cat > "$task_volume/安装说明.txt" <<'TEXT'
额度终端 · Mac 本地测试版

安装方法
1. 如果之前装过额度终端，请先正常退出原应用。
2. 如需清理旧版，双击「卸载旧版本.app」，勾选要移走的旧应用并确认。
3. 将「额度终端.app」拖进旁边的「Applications」文件夹。
4. 从「应用程序」打开「额度终端」，即可开始使用。
5. 安装后可以推出此磁盘映像。无需安装 Xcode。

卸载旧版本
卸载助手会检查 /Applications、你自己的 Applications 文件夹和历史本地运行副本。
其他位置的旧应用可点击「选择其他位置」手动检查。
助手显示版本号和完整路径，默认不勾选；确认后将所选旧应用移到废纸篓。
正在运行的对应旧版本会先正常退出，不会强制结束未保存的工作。
只移走可识别的旧版额度终端，不删除账号、用量、月报、设置或 JSON 备份。
相同版本、更高版本、无法确认版本的应用和安装包里的应用不会被卸载。
需要恢复时，可从废纸篓取回应用；助手不会清空废纸篓。

Dock 图标
更新前退出旧应用，更新后从「应用程序」打开新版。
若保留的 Dock 快捷方式指向其他副本，可先从 Dock 移除它，再将新版拖回 Dock。

系统要求
macOS 14 或更新版本，支持 Apple 芯片和 Intel Mac。
macOS 26 或更新版本使用系统液态玻璃外观。

当前版本
账号、用量与撤销、到期事项、历史月报账本和 JSON 备份可在本地使用。
美元兑人民币汇率默认自动更新，来源为 ECB / Frankfurter，每次成功后缓存 6 小时；断网沿用原值。
可在「设置 → 美元兑人民币」改用手动或立即更新。参考日期与同步时间分别显示，已保存月报不重算。
设置中的「价格目录」可导入维护后的目录，无需重装应用。
此安装包尚未启用 iCloud，设备之间暂不自动同步。
应用内「设置 → 导入备份」可以迁移已有网站或原生版记录。

Codex 实时看板（Mac）
从边栏「Codex 实时」或按 Command-4 打开。
打开应用自动检测本机 ~/.codex 日志，已保存的目录优先恢复。
自定义位置或权限受限时，可点击「选择目录」授权一次；主动断开会关闭下次自动连接。
看板每秒检查本机任务活动，显示日志已上报的额度；没有上报时会明确显示未知或过期。
任务进度显示活动与状态，不编造完成百分比；其他 AI 服务仍需手动记用量。
不保存聊天正文、推理或命令输出，不读取登录凭据，不把本机任务发送到手机。
右上角状态栏圆环显示两窗中较低的剩余额度；中心活动弧、勾号和方块分别表示活动、完成和停止。
虚线圈表示等待有效上报；点圆环可打开看板或额度提醒。关闭窗口后仍更新，退出应用后停止。
额度提醒默认关闭，可在「Codex 实时 → 额度提醒」确认来源后开启：20% 预警可关闭，10% 紧急提醒始终保留。
同一目录切换 Codex 账号后，请在提醒设置中重新确认，并等待新额度上报。
历史账本只由原生版备份保留，经过旧网站再次导出会丢失账本部分。

首次打开
本测试包采用临时签名，尚未经过苹果开发者签名和公证。
macOS 可能提示无法验证开发者或阻止打开。
确认安装包来自你信任的开发者后，可按 macOS 系统提供的流程，
在「系统设置 → 隐私与安全性」查看「仍要打开」选项。
如果没有该选项或设备受公司管理，请联系开发者获取已签名的版本。
不需要关闭系统安全保护。

更新与数据
更新前建议从「设置 → 导出备份」保存一份 JSON。
记录保存在你自己的 Mac；此安装包不包含开发者或其他人的使用数据。
TEXT

/usr/bin/hdiutil create -volname '额度终端' -srcfolder "$task_volume" \
    -format UDZO -imagekey zlib-level=9 -ov "$task_dmg"
/usr/bin/hdiutil verify "$task_dmg"
(
    cd "$task_root/releases"
    /usr/bin/shasum -a 256 "${task_dmg:t}" > "${task_dmg:t}.sha256"
    /usr/bin/shasum -a 256 -c "${task_dmg:t}.sha256"
)
/bin/zsh "$task_root/scripts/prune-mac-releases.zsh" "$task_root/releases"
print "已生成：$task_dmg"
print '安装包目录仅保留最新两版及各自的校验文件。'
print '这是尚未公证的本地测试包；正式分发和 iCloud 需要开发者签名与苹果公证。'
