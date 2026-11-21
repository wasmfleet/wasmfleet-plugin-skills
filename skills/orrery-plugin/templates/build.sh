#!/usr/bin/env bash
# Orrery 插件本地编译脚本模板（自己调试用；正式发布由 GitHub Actions 完成）
#
# 用法：
#   ./build.sh                 编译 release 版本到 dist/<程序名>
#   ./build.sh run [端口]      编译后直接启动（模拟中控：PORT 环境变量，只监听 127.0.0.1）
#   ./build.sh debug           编译 debug 版本（编译更快）
set -euo pipefail
cd "$(dirname "$0")"

# 程序名取自 Cargo.toml 的 [package] name
NAME=$(sed -n 's/^name *= *"\(.*\)"/\1/p' Cargo.toml | head -1)
MODE="${1:-release}"

command -v cargo >/dev/null 2>&1 || { echo "错误：未找到 cargo，请先安装 Rust：https://rustup.rs" >&2; exit 1; }

case "$MODE" in
    release|run) PROFILE=release; cargo build --release ;;
    debug)       PROFILE=debug;   cargo build ;;
    -h|--help)   sed -n '2,7p' "$0"; exit 0 ;;
    *)           echo "未知参数：$MODE" >&2; sed -n '2,7p' "$0"; exit 1 ;;
esac

mkdir -p dist
cp "target/$PROFILE/$NAME" "dist/$NAME"
echo ">> 编译完成：dist/$NAME（$PROFILE，$(du -h "dist/$NAME" | cut -f1)）"

if [[ "$MODE" == "run" ]]; then
    PORT="${2:-8080}"
    echo ">> 启动：http://127.0.0.1:$PORT/   （Ctrl+C 停止，工作目录为 dist/）"
    cd dist
    PORT="$PORT" exec "./$NAME"
fi
