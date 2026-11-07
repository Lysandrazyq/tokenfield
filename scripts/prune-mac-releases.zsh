#!/bin/zsh
set -eu

task_releases="${1:?需要指定安装包目录}"
[[ -d "$task_releases" ]]

# 仅匹配本应用的正式命名文件；按数字版本倒序，保留最新两版。
typeset -a task_packages
task_packages=("$task_releases"/额度终端-<->.<->.<->-macOS-universal.dmg(N.nOn))
for ((task_index = 3; task_index <= ${#task_packages}; task_index++)); do
    task_package="${task_packages[$task_index]}"
    /bin/rm -f -- "$task_package" "$task_package.sha256"
    print "已清理旧安装包：${task_package:t}"
done
