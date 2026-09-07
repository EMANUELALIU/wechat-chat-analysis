# 阶段 A · 导出技术手册（Mac 微信 4.x）

> 本文档是实战验证过的完整 SOP（2026-09，微信 4.1.11，Apple Silicon M5，macOS）。
> 所有"❌ 不要走"的条目都是真实踩过的坑，直接跳过可省几小时。

## 0. 关键事实速查（先建立认知）

| 事实 | 内容 |
|---|---|
| 微信 4.x 数据位置 | `~/Library/Containers/com.tencent.xinWeChat/Data/Documents/xwechat_files/<wxid>_<hash>/db_storage/` |
| 关键库 | `message/message_0.db`（聊天正文）、`contact/contact.db`（联系人姓名）、`session/session.db`（会话列表）、`message/media_0.db`（语音索引） |
| 加密方式 | WCDB / SQLCipher 4 变体，**密钥 = 原始 32 字节，直接用作 AES-256-CBC key（主密钥无 PBKDF2）** |
| 页面参数 | page 4096，reserve 80（IV 16 + HMAC 64），salt = 文件前 16 字节 |
| HMAC 校验 | mac_key = PBKDF2-HMAC-SHA512(key, salt^0x3a, 2, 32)；HMAC-SHA512(mac_key, page1[16:4032] + LE(page_no)) |
| 密钥存放 | 4.1.10+ 内存里只有 passphrase/原始 key，**不在磁盘上可推导** |
| 抓密钥唯一可靠法 | **lldb 断点 `CCCryptorCreate`**，arm64 下 x3=key 指针、x4=keyLength(==32)，读 x3 处 32 字节 |
| SIP | **不需要关闭**。只需一次 ad-hoc 重签微信（实测 SIP 开启时 attach + 读内存均正常） |
| 4 个密钥 | 足够覆盖 message_0 / contact / session / hardlink 四个核心库（实测） |

## 1. 环境侦查（一条命令）

```bash
# 微信版本 + 数据目录 + 加密状态 + 架构
/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" /Applications/WeChat.app/Contents/Info.plist
uname -m   # arm64 = Apple Silicon
ls ~/Library/Containers/com.tencent.xinWeChat/Data/Documents/xwechat_files/
head -c 16 "$HOME/Library/Containers/com.tencent.xinWeChat/Data/Documents/xwechat_files/<wxid>_<hash>/db_storage/message/message_0.db" | xxd
# 文件头不是 "SQLite format 3" → 已加密；是 → 未加密，直接用 sqlite3 读即可
```

- 微信 3.x（旧版）走 `Message/*.db` 结构，用 wcdb-key-tool 老版内存扫描即可；**本手册只覆盖 4.x**。
- 若数据目录不存在：用户需先在手机「聊天记录迁移与备份 → 迁移到电脑」，并在 Mac 微信上把目标聊天完整刷出来（本地才有数据）。

## 2. 准备工具（助手执行，无需 sudo）

```bash
bash ~/.dsh/skills/wechat-chat-analysis/scripts/setup.sh
# 等效手动步骤：
#   cd ~ && python3 -m venv wechat-export/venv
#   ./wechat-export/venv/bin/pip install -i https://pypi.tuna.tsinghua.edu.cn/simple pycryptodome zstandard
#   cd ~/wechat-export && curl -sL https://codeload.github.com/rmqg/wechat-mac-export/tar.gz/refs/heads/main -o rmqg.tar.gz && tar xzf rmqg.tar.gz -C rmqg --strip-components=1
```

要点：
- 用系统 Python 3.9 即可（`from __future__ import annotations` 保证 `|` 注解可解析）；venv 里只装 pycryptodome + zstandard。
- 网络走清华 PyPI 镜像；github.com 本机可达，raw.githubusercontent.com 偶尔超时，用 `api.github.com` 或 codeload 代替。
- rmqg 的 CLI：`python -m wxexport`（需 `PYTHONPATH=<rmqg目录>`，命令：`copy / match / decrypt / export / build`，默认工作目录 `--work ~/wx-export`）。

## 3. 抓密钥（用户执行，唯一需要 sudo 的环节）

**为什么必须用户跑**：agent 的沙箱禁止 sudo；而 macOS 不允许无 sudo 附加调试器（即使同用户进程也会被拒）。且抓取过程需要用户在微信里互动。

分工脚本：`scripts/capture.sh`（= 自检 diag + 抓取 + 日志 + 修权限），用户运行：

```bash
~/wechat-export/capture.sh   # 或 skill 内的 scripts/capture.sh
```

**给用户的四步指令（必须逐条讲清，否则抓 0 个密钥）**：

1. **先打开微信并登录**，确认能看到聊天列表（最常见失败原因：微信没运行，脚本第一步就退出）。
2. 运行 capture.sh，第 1 段是自检（几秒），正常输出应为：
   ```
   ATTACH_OK pid=xxxx
   BP_CCCryptorCreate_locations=1
   READ_OK pc=... bytes=...
   DETACHED
   ```
   - `ATTACH_FAIL` → 重签没生效，重跑 `sudo codesign --force --deep --sign - /Applications/WeChat.app` 后重启微信；
   - `READ_FAIL` → 极罕见，若出现再考虑关 SIP（实测未遇到）。
3. 第 2 段抓取 90~180 秒，**期间必须在微信里持续滚动聊天**：打开目标联系人聊天不停上翻加载老消息，滚到头换几个群继续（数据库页被解密时密钥才会经过断点）。
4. 结束后 Cmd+Q 退出微信（触发 WAL checkpoint，数据完整落盘），并把自检输出贴给助手。

成功标志：`work/rawkeys.txt` 存在且 `DETACHED keys=N`（N≥3 即可，实测 4 个够用）。

**一次性前置**：重签微信（更新微信后需重做）：
```bash
sudo codesign --force --deep --sign - /Applications/WeChat.app
```

## 4. 解密 + 导出（助手执行，无需 sudo）

```bash
cd ~/wechat-export
export PYTHONPATH="$HOME/wechat-export/rmqg"

# 4.1 数据快照（WeChat 已退出后重新拷贝，保证 WAL 已 checkpoint）
rm -rf work/xwechat_files && cp -Rc "$HOME/Library/Containers/com.tencent.xinWeChat/Data/Documents/xwechat_files" work/

# 4.2 密钥 → 数据库匹配（HMAC 逐库验证）
./venv/bin/python -m wxexport --work "$HOME/wechat-export/work" match

# 4.3 解密 + 4.4 导出（build = match+decrypt+export）
./venv/bin/python -m wxexport --work "$HOME/wechat-export/work" decrypt
./venv/bin/python -m wxexport --work "$HOME/wechat-export/work" export
```

产出：`work/export/text/<名字>__<md5>.txt`（每会话一个）、`index.csv`、`index.html`。

## 5. 交付：按人打包 CSV + zip

```python
# 每个目标联系人：解析 txt → (时间,发送人,内容) CSV（utf-8-sig 防 Excel 乱码）→ txt+csv 打包 zip
# 消息正则: ^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] (.+?): (.*)$，后续无前缀行并入上一条内容
```

要点：CSV 用 `utf-8-sig`；zip 内放 `<名字>.txt` + `<名字>.csv`；文件名空格换下划线。

## 6. 已排除的死路（❌ 别重试）

| 路径 | 结论 |
|---|---|
| PyWxDump（pip 最新 2.x） | 依赖 pywin32，Windows-only，Mac 装不了 |
| wcdb-key-tool `extract`（passphrase→PBKDF2 256000 轮） | 对 4.1.11 已失效，PBKDF2 派生后 0 密钥验证通过 |
| `key_info.db` 直接派生 | `LoginKeyInfoTable.key_info_data` 是 180 字节 protobuf（field1=168B：0-13 常量头、24-27 时间戳、28-31 长度 32、32-63 为 32 字节跨库常量、64-167 变体）。**32 字节常量不是密钥**；试遍 4995 种派生（直接取/滑窗/异或/AES-ECB/CBC 正反）全部 HMAC 失败 → 被机器专属密钥加密，文件内不可推导 |
| macOS 钥匙串 | 无微信相关条目 |
| 无 sudo 附加 lldb | 系统直接拒绝（连自己的进程都不行） |
| 内存扫描 `x'<96hex>'` | 4.1.x 不再以十六进制文本存密钥，且 Mach VM 读不到密钥所在区域 |

## 7. 故障排查

| 现象 | 原因 | 处置 |
|---|---|---|
| rawkeys.txt 不存在 | ①微信没在运行（脚本第一步退出）②抓取时没滚动聊天 | 让用户先开微信登录；强调抓取期间持续滚动 |
| 自检 `ATTACH_FAIL` | 重签失效/未重签 | 重新 codesign 并重启微信 |
| match 后缺 `message_0.db` | 抓取时没打开目标聊天 | 重抓，强调打开目标人聊天上翻 |
| 导出缺最近消息 | 拷贝时微信还在运行（WAL 未落盘） | 先 Cmd+Q 微信再重拷数据 |
| 语音/图片内容缺失 | 语音在 media_0.db，需另行抓取+转写；导出仅覆盖文字 | 预期行为，向用户说明 |

## 8. 安全边界

- 仅限用户**本人设备、本人账号**的数据；工具不联网不外传，密钥仅存 `~/wechat-export/work/`（可删）。
- 重签微信只影响本机调试权限，微信更新后自动还原；不影响账号、不触发封号（工具作者明确）。
- 完成后建议：`rm -f ~/wechat-export/work/rawkeys.txt`（密钥文件可清理，其余留存）。
