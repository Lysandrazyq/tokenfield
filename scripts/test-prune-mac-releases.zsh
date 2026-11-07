#!/bin/zsh
set -eu

task_script="${0:A:h}/prune-mac-releases.zsh"
task_fixture=$(/usr/bin/mktemp -d /private/tmp/tokenfield-release-retention.XXXXXX)
mkdir -p "$task_fixture/versions" "$task_fixture/single" "$task_fixture/empty"

for task_version in 1.0.0 1.1.0 1.9.0 1.10.0; do
    /usr/bin/touch "$task_fixture/versions/额度终端-$task_version-macOS-universal.dmg"
    /usr/bin/touch "$task_fixture/versions/额度终端-$task_version-macOS-universal.dmg.sha256"
done
/usr/bin/touch "$task_fixture/versions/其他应用-0.1.0.dmg" "$task_fixture/versions/说明.txt"
mkdir "$task_fixture/versions/额度终端-0.0.1-macOS-universal.dmg"

/bin/zsh "$task_script" "$task_fixture/versions"
for task_version in 1.9.0 1.10.0; do
    [[ -f "$task_fixture/versions/额度终端-$task_version-macOS-universal.dmg" ]]
    [[ -f "$task_fixture/versions/额度终端-$task_version-macOS-universal.dmg.sha256" ]]
done
for task_version in 1.0.0 1.1.0; do
    [[ ! -e "$task_fixture/versions/额度终端-$task_version-macOS-universal.dmg" ]]
    [[ ! -e "$task_fixture/versions/额度终端-$task_version-macOS-universal.dmg.sha256" ]]
done
[[ -f "$task_fixture/versions/其他应用-0.1.0.dmg" ]]
[[ -f "$task_fixture/versions/说明.txt" ]]
[[ -d "$task_fixture/versions/额度终端-0.0.1-macOS-universal.dmg" ]]

/usr/bin/touch "$task_fixture/single/额度终端-1.0.0-macOS-universal.dmg"
/bin/zsh "$task_script" "$task_fixture/single"
[[ -f "$task_fixture/single/额度终端-1.0.0-macOS-universal.dmg" ]]
/bin/zsh "$task_script" "$task_fixture/empty"
print 'PASS: 数字版本排序、仅保留两版、配套校验文件清理、无关文件及目录保留、单版与空目录。'
