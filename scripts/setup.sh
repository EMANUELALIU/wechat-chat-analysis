#!/bin/bash
# ============================================================
# 微信导出 · 一次性准备脚本（无需 sudo）
# 建 venv、装依赖、克隆 rmqg/wechat-mac-export、部署抓取脚本
# 用法: bash setup.sh [工作目录，默认 ~/wechat-export]
# ============================================================
set -euo pipefail

WORK="${1:-$HOME/wechat-export}"
SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
PYPI="https://pypi.tuna.tsinghua.edu.cn/simple"

echo "==> 工作目录: $WORK"
mkdir -p "$WORK"

# 1. venv + 依赖
if [ ! -x "$WORK/venv/bin/python" ]; then
  echo "==> [1/4] 创建 venv"
  python3 -m venv "$WORK/venv"
fi
echo "==> [2/4] 安装依赖 (pycryptodome, zstandard)"
"$WORK/venv/bin/pip" install -q -i "$PYPI" pycryptodome zstandard

# 2. 克隆 rmqg/wechat-mac-export（微信 4.1.11 验证过的解密+导出工具）
if [ ! -f "$WORK/rmqg/wxexport/__main__.py" ]; then
  echo "==> [3/4] 下载 rmqg/wechat-mac-export"
  curl -sL --max-time 90 "https://codeload.github.com/rmqg/wechat-mac-export/tar.gz/refs/heads/main" -o "$WORK/rmqg.tar.gz"
  mkdir -p "$WORK/rmqg"
  tar xzf "$WORK/rmqg.tar.gz" -C "$WORK/rmqg" --strip-components=1
  rm -f "$WORK/rmqg.tar.gz"
fi

# 3. 部署抓取脚本 + 诊断模块
echo "==> [4/4] 部署 capture.sh / diag_test.py"
cp "$SKILL_DIR/capture.sh" "$WORK/capture.sh"
cp "$SKILL_DIR/diag_test.py" "$WORK/diag_test.py"
chmod +x "$WORK/capture.sh"

echo ""
echo "✅ 准备完成。下一步（需要用户在终端执行，含 sudo）："
echo "   1) 重签微信:  sudo codesign --force --deep --sign - /Applications/WeChat.app"
echo "   2) 打开微信并登录，确认能看到聊天列表"
echo "   3) 运行:      $WORK/capture.sh   （抓取 90 秒内持续滚动目标聊天）"
echo "   4) 抓完 Cmd+Q 退出微信，把终端里自检输出（ATTACH_OK/READ_OK 等）贴给 AI"
