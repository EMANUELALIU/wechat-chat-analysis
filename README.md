# wechat-chat-analysis · 使用说明

微信聊天记录导出 + 人物关系分析 skill（面向 AI 助手，需配合支持 Skill 机制的 AI 平台使用）。

## 这个包是什么

- `SKILL.md` — 给 AI 的指令入口（含触发词）
- `references/` — 技术手册与分析框架
- `scripts/` — 可复用脚本（setup / 抓密钥 / 自检）

⚠️ 它不是一个双击就能跑的 App，而是一套**交给 AI 助手执行的流程**。你需要有一个支持 Skill 的 AI 工具（如 DeepSeek Harness / Claude Code / Codex / OpenCode 等）。

## 安装（1 分钟）

1. 解压本包，把整个 `wechat-chat-analysis` 文件夹放进你所用平台的技能目录：
   - DSH：`~/.dsh/skills/wechat-chat-analysis/`
   - Claude Code：`~/.claude/skills/wechat-chat-analysis/`
   - Codex：`~/.codex/skills/wechat-chat-analysis/`
2. **新开一个对话**（技能目录在会话启动时加载），对 AI 说触发词即可：
   - 「帮我导出微信聊天记录」
   - 「分析一下这个人 / 对比这几个男生」
   - 「写一篇 dating 日记」

## 环境要求

| 功能 | 要求 |
|---|---|
| 分析/对比/日记（阶段 B） | 任何设备均可；直接贴聊天文本也能用，无需导出 |
| 导出微信记录（阶段 A） | Mac（Apple Silicon 已验证，微信 4.x 已登录）+ Xcode 命令行工具（lldb）+ 本机 sudo 密码 |

导出时需要：重签一次微信（`sudo codesign --force --deep --sign - /Applications/WeChat.app`，仅影响本机调试权限，微信更新后需重做）、运行 `scripts/capture.sh` 时在微信里持续滚动聊天 90 秒。全程不联网、密钥仅存本机。

## 隐私与边界

- 只用于**你自己设备、自己账号**的数据。
- 分析建议仅供参考，最终决定永远由你自己做。
- 微信版本更新可能导致导出方法需要适配，请以当时 AI 的侦查结果为准。
