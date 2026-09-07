#!/bin/bash
# ============================================================
# 微信导出 · 抓密钥脚本（用户在终端运行，含 sudo）
# 方法：lldb 断点 CCCryptorCreate 抓微信 4.1.11 原始 32 字节密钥（rmqg 方案）
# 前置：微信已 ad-hoc 重签、微信正在运行并已登录
# 输出：$WORK/rawkeys.txt + $WORK/capture_log.txt（自检+抓取全程日志）
# ============================================================
set -uo pipefail

WORK="${1:-$HOME/wechat-export}"
LLDB_PY="$WORK/rmqg/wxexport/lldb_capture.py"
DIAG_PY="$WORK/diag_test.py"
OUT="$WORK/rawkeys.txt"
LOG="$WORK/capture_log.txt"
ME_UID=$(id -u); ME_GID=$(id -g)

mkdir -p "$WORK"

PID=$(pgrep -x WeChat | head -1 || true)
if [ -z "$PID" ]; then
  echo "❌ 微信没在运行！请先打开微信并登录，确认能看到聊天列表，再重跑本脚本"
  exit 1
fi
echo "✓ 已找到微信进程 PID=$PID"
echo ""

# ---------- 1. 自检：附加/断点/内存读取 ----------
echo "===== [1/2] 自检：调试器附加/断点解析/内存读取 ====="
sudo lldb --batch \
  -o "command script import $DIAG_PY" \
  -o "diagtest $PID" \
  -o "quit" 2>&1 | tee "$LOG"
echo ""

# ---------- 2. 抓取（90 秒） ----------
echo "===== [2/2] 抓取密钥（90 秒）====="
echo "这 90 秒请务必在微信里【持续滚动聊天历史】触发数据库解密："
echo "  · 打开目标联系人的聊天，不停往上翻（加载老消息）"
echo "  · 滚到头就换几个群/其他联系人继续滚"
echo "  · 不滚动 = 抓不到（密钥只在数据库页被解密时经过断点）"
read -r -p "准备好了按回车，马上开始..." _
echo ">>> 开始！现在去微信里滚动聊天窗口 <<<"
echo ""
sudo lldb --batch \
  -o "command script import $LLDB_PY" \
  -o "wxcapture $PID 90 $OUT" \
  -o "quit" 2>&1 | tee -a "$LOG"
echo ""

# ---------- 收尾 ----------
if [ -f "$OUT" ]; then
  sudo chown "$ME_UID:$ME_GID" "$OUT"
  CNT=$(sort -u "$OUT" 2>/dev/null | wc -l | tr -d ' ')
  echo "✅ 抓到 $CNT 个不同密钥（≥3 即可，实测 4 个够覆盖核心库）"
else
  echo "⚠️ 没抓到密钥（0 个）。常见原因：微信没在运行 / 抓取时没滚动聊天 / 断点未命中"
  echo "   请把上面日志（ATTACH_OK / BP_locations / READ_OK / KEYS 等行）贴给 AI 判断"
fi
sudo chown "$ME_UID:$ME_GID" "$LOG" 2>/dev/null || true
echo "日志: $LOG"
echo ""
echo "请【退出微信】(Cmd+Q) 让数据完整落盘，然后把自检输出贴给 AI，后续解密导出由 AI 完成。"
