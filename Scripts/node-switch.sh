#!/usr/bin/env bash
set -Eeuo pipefail

node_version="${1:-}"
node_root='/usr/local/node'
current_link="${node_root}/current"
profile_file='/etc/profile.d/node.sh'

if [[ -z "$node_version" ]]; then
    echo "用法：sudo $0 <版本>"
    echo "示例：sudo $0 v24.21.0"
    exit 1
fi

[[ "$node_version" == v* ]] || node_version="v${node_version}"

target_dir="${node_root}/${node_version}"

if [[ $EUID -ne 0 ]]; then
    echo "请使用 root 权限运行此脚本。" >&2
    exit 1
fi

if [[ ! -x "${target_dir}/bin/node" ]]; then
    echo "Node.js ${node_version} 尚未安装。" >&2
    echo "找不到：${target_dir}/bin/node" >&2
    exit 1
fi

ln -sfnT "$target_dir" "$current_link"

cat > "$profile_file" <<'EOF'
export NODE_HOME=/usr/local/node/current
export PATH="$NODE_HOME/bin:$PATH"
EOF

chmod 0644 "$profile_file"

echo "当前 Node.js 已切换到：${node_version}"
echo "链接：${current_link} -> ${target_dir}"
echo
"${current_link}/bin/node" --version
PATH="${target_dir}/bin:${PATH}" \
    "${target_dir}/bin/npm" --version
echo
echo "当前终端请执行以下命令刷新环境："
echo "source /etc/profile.d/node.sh"
echo "hash -r"
