#!/bin/zsh
set -eu

task_root="${0:A:h:h}"
task_output="${1:?请提供助手输出目录}"
task_version="${2:?请提供应用版本}"
task_build="${3:?请提供构建号}"
task_app="$task_output/卸载旧版本.app"
task_work="$task_root/.build/MacUninstaller"
task_sdk=$(/usr/bin/xcrun --sdk macosx --show-sdk-path)
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources" "$task_work"

for task_arch in arm64 x86_64; do
    /usr/bin/xcrun swiftc -O -parse-as-library -D INSTALLER_STANDALONE \
        -target "$task_arch-apple-macos14.0" -sdk "$task_sdk" \
        "$task_root/native-mac-installer/Sources/InstallerCore/OldApplications.swift" \
        "$task_root/native-mac-installer/Sources/Uninstaller/UninstallerApp.swift" \
        -o "$task_work/TokenfieldUninstaller-$task_arch"
done
/usr/bin/lipo -create "$task_work/TokenfieldUninstaller-arm64" "$task_work/TokenfieldUninstaller-x86_64" \
    -output "$task_app/Contents/MacOS/TokenfieldUninstaller"

/usr/bin/xcrun actool "$task_root/brand/uninstaller/QuotaUninstallerIcon.icon" \
    --compile "$task_app/Contents/Resources" --platform macosx \
    --minimum-deployment-target 14.0 --target-device mac \
    --app-icon QuotaUninstallerIcon --enable-on-demand-resources NO \
    --bundle-identifier space.lysandra.quotakeeper.uninstaller \
    --output-partial-info-plist "$task_work/icon-info.plist" \
    --output-format human-readable-text --warnings --notices

/usr/bin/python3 - "$task_app" "$task_version" "$task_build" <<'PY'
from pathlib import Path
import plistlib,sys
app,version,build=Path(sys.argv[1]),sys.argv[2],sys.argv[3]
info={
    'CFBundleIdentifier':'space.lysandra.quotakeeper.uninstaller',
    'CFBundleExecutable':'TokenfieldUninstaller',
    'CFBundleName':'卸载旧版本',
    'CFBundleDisplayName':'卸载旧版本',
    'CFBundlePackageType':'APPL',
    'CFBundleShortVersionString':version,
    'CFBundleVersion':build,
    'CFBundleIconFile':'QuotaUninstallerIcon',
    'CFBundleIconName':'QuotaUninstallerIcon',
    'LSMinimumSystemVersion':'14.0',
    'LSApplicationCategoryType':'public.app-category.utilities',
    'NSHighResolutionCapable':True,
    'TokenfieldLatestVersion':version,
    'TokenfieldLatestBuild':build,
}
with (app/'Contents/Info.plist').open('wb') as f:plistlib.dump(info,f)
PY
/usr/bin/xattr -dr com.apple.FinderInfo "$task_app"
/usr/bin/codesign --force --sign - --timestamp=none "$task_app"
/usr/bin/codesign --verify --deep --strict "$task_app"
/usr/bin/lipo "$task_app/Contents/MacOS/TokenfieldUninstaller" -verify_arch arm64
/usr/bin/lipo "$task_app/Contents/MacOS/TokenfieldUninstaller" -verify_arch x86_64
print "已生成卸载助手：$task_app"
