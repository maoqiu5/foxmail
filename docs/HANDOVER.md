# Foxmail / NAS 邮件归档交接说明

> 更新时间：2026-08-25
> 接手原则：本地 `D:\codex\foxmail` 为开发源码；另有备份 `C:\Users\12514\Documents\ChatGPT\foxmail`，当前一致。
> 该项目主要运行在 NAS，不属于标准 VPS 业务项目。

## 1. 项目一句话

在 NAS 上部署 Dovecot 邮件归档服务，让 Foxmail 通过 IMAP/SMTP 使用 WPS 邮箱凭据，并把邮件归档到 NAS Maildir。

## 2. 当前状态

- 本地目录：`D:\codex\foxmail`
- 部署目录：`deploy/`
- 技术栈：Docker / Dovecot / Shell 脚本
- 线上无 `/foxmail` 路由
- 本地测试：`9 passed` ✅（`test/deployment-config.test.mjs`）
- 备份副本 `C:\Users\12514\Documents\ChatGPT\foxmail` 当前与本地一致
- NAS 部署状态（2026-08-25 检查）：
  - `nas-mail-tailscale`、`nas-mail-dovecot` 均 Up 9 days
  - Tailscale 在线：`100.122.207.88`（`nas-mail`）
  - IMAPS `993` 通过 Tailnet IP 可达；本机 MagicDNS 主机名未解析，可用 IP 作为 Foxmail 服务器
  - 无公网 SMTP 监听（25/465/587）
  - 同步由 NAS cron 每 3 分钟触发一次性 `latest-minute` / `sent-latest` 容器；常驻 `nas-mail-sync` 容器当前为 Exited (137)，属预期/历史状态
  - 本地 `deploy/` 与 NAS `/data_n006/apps/mail-archive` 关键文件一致
  - `verify.ps1` 已修正：Tailscale socket 路径、Dovecot 容器内 openssl、Tailnet IP fallback、读取近期 runner 日志

## 3. 核心组件

- `deploy/docker-compose.yml`
- `deploy/dovecot/`：Dovecot 配置和 Dockerfile
- `deploy/sync/`：同步循环
- `deploy/runtime-scripts/`：定时同步、健康检查
- `deploy/scripts/`：部署、密钥、验证脚本
- `docs/foxmail-setup.md`：客户端配置说明

## 4. 注意

- 涉及邮箱账号、授权码、私钥，不得写入文档或聊天
- 部署目标通常是 NAS，不是 VPS
- 与 Maildesk 的邮件采集是不同链路，不要混淆

## 5. 新对话接续

```text
这是 foxmail / NAS 邮件归档项目对话。
请先读 D:\codex\HANDOVER_INDEX.md 和 D:\codex\foxmail\docs\HANDOVER.md，
再检查 NAS 部署状态，然后开始工作。
```
