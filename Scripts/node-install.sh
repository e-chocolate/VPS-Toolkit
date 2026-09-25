#!/usr/bin/env bash
set -Eeuo pipefail

node_version="${1:-}"
node_root='/usr/local/node'

if [[ -z "$node_version" ]]; then
    echo "用法：sudo $0 <版本>"
    echo "示例：sudo $0 v24.21.0"
    exit 1
fi

# 同时支持 24.21.0 和 v24.21.0
[[ "$node_version" == v* ]] || node_version="v${node_version}"

case "$(uname -m)" in
    x86_64)
        node_arch='x64'
        ;;
    aarch64 | arm64)
        node_arch='arm64'
        ;;
    *)
        echo "不支持的系统架构：$(uname -m)" >&2
        exit 1
        ;;
esac

archive="node-${node_version}-linux-${node_arch}.tar.xz"
download_url="https://nodejs.org/dist/${node_version}"
target_dir="${node_root}/${node_version}"

if [[ $EUID -ne 0 ]]; then
    echo "请使用 root 权限运行此脚本。" >&2
    exit 1
fi

if [[ -e "$target_dir" ]]; then
    echo "该版本已经存在：${target_dir}" >&2
    exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

echo "正在下载 Node.js ${node_version} (${node_arch})……"

wget -q --show-progress \
    "${download_url}/${archive}" \
    -O "${tmp_dir}/${archive}"

wget -q \
    "${download_url}/SHASUMS256.txt" \
    -O "${tmp_dir}/SHASUMS256.txt"

echo "正在验证 SHA-256……"

(
    cd "$tmp_dir"

    checksum_line="$(
        awk -v filename="$archive" '$2 == filename { print }' SHASUMS256.txt
    )"

    if [[ -z "$checksum_line" ]]; then
        echo "官方校验文件中没有找到：${archive}" >&2
        exit 1
    fi

    printf '%s\n' "$checksum_line" | sha256sum --check -
)

echo "正在解压到 ${target_dir}……"

mkdir "${tmp_dir}/extracted"

tar -xJf "${tmp_dir}/${archive}" \
    --strip-components=1 \
    --directory="${tmp_dir}/extracted"

install -d -m 0755 "$node_root"
mv "${tmp_dir}/extracted" "$target_dir"
chown -R root:root "$target_dir"

echo
echo "安装完成："
"${target_dir}/bin/node" --version
PATH="${target_dir}/bin:${PATH}" \
    "${target_dir}/bin/npm" --version
echo "安装目录：${target_dir}"
echo
echo "该版本尚未启用，可执行："
echo "sudo node-switch.sh ${node_version}"
