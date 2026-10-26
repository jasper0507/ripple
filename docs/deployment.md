# 单机手动部署

适用于 `india-3x`（Ubuntu 24.04、amd64、约 836 MiB 内存）上的低流量作品演示。
域名为 `ripple.jasperlab.dev`。本地构建镜像，上传后运行四个容器：Caddy、Go、MySQL 8.4、Redis 7.4。
Caddy 同源托管前端并反代 `/api/*` 和 `/ping`；MySQL、Redis、后端均不发布宿主端口。
服务器原有 what2eat、Tunnel 和 openlist 使用各自的 Compose 项目，不需要改动。

## 构建和上传

本地需要 Docker（linux/amd64 构建）、Git、Bash、gzip 和 SSH。前端位于相邻的 `ripple_frontend` 目录。
前端在镜像构建中运行类型检查、lint、测试、契约快照检查和生产构建。
契约检查只保证前端本地快照与类型匹配，后端接口发生变化时仍需检查兼容性。
构建使用两个仓库的**当前工作区内容**，不会替你提交；`sources.txt` 记录提交号、工作区状态和镜像 ID。

```bash
# 在后端仓库执行；版本号一旦使用，不要重复构建覆盖。
version=$(date -u +%Y%m%dT%H%M%SZ)
bash deploy/build.sh ../ripple_frontend "$version"
ssh india-3x "mkdir -p ~/ripple/releases/$version"
rsync -a --info=progress2 "dist/releases/$version/" "india-3x:ripple/releases/$version/"
ssh -t india-3x "bash ~/ripple/releases/$version/apply.sh"
```

构建包包含全部镜像，VPS 不需要 Go、Node、源码或镜像仓库账号。
**镜像包不包含本地 MySQL/Redis 数据卷。** 首次部署会在 VPS 新建 `ripple-prod_mysql_data` 和 `ripple-prod_redis_data`，仅建表并初始化社区；本地 `ripple_mysql_data`、`ripple_redis_data` 中的账号、帖子、评论和排行榜不会自动随镜像上传。
需要保留本地业务数据时，应另行安排迁移：先备份线上库，停服导入本地 MySQL 业务库，再使用 `rebuild` 重建线上 Redis 排行榜并验收。Redis 中的刷新凭据及本地测试 DB 不应作为排行榜重建的一部分复制，用户重新登录即可。
`apply.sh` 使用独立项目名 `ripple-prod`，首次生成 `~/ripple/.env`（权限 600），保存数据库密码和 JWT 密钥。
密钥不放入镜像或版本目录，不应上传到 Git。初始化后修改环境变量不会自动修改 MySQL 中已有账号的密码。

首次启动顺序：加载镜像、校验 Caddy、等待数据库和 Redis、执行迁移、幂等初始化社区、启动应用和入口、查询社区接口。
成功后 `~/ripple/current` 指向当前版本；后续更新成功后 `~/ripple/previous` 指向上一版本。
启动成功只说明容器与数据库查询正常，公网 HTTPS 和真实业务仍需验收。

## 域名、HTTPS 与 Cloudflare

1. 在 Cloudflare 为 `ripple` 添加 A 记录，指向 `india-3x` 的公网 IPv4 `20.219.15.150`。本次按用户选择保留 **Proxied（橙云）**，先尝试自动签发证书。
2. 云平台安全组允许 TCP 80/443；主机已有防火墙时同样放行。Docker 发布端口可能绕过 UFW，应检查云安全组与 Docker 防火墙链。保留现有 SSH 规则。
3. 等待 DNS 生效，Caddy 自动申请证书。检查 Caddy 日志中的签发结果，并执行 `curl -I https://ripple.jasperlab.dev`。橙云下浏览器看到的是边缘证书，还需确认源站证书已签发。若 ACME 验证被边缘重定向或规则阻断，再暂时切灰云并重试。
4. 确认使用 **Proxied（橙云）**，SSL/TLS 选择 **Full (strict)**。若区域内其他站点使用不同 TLS 模式，先评估全区域切换的影响或使用可用的主机级配置。
5. `/api/*` 和 `/ping` 使用缓存绕过规则，不添加 Cache Everything。关闭影响本域名的自动挑战规则；API 客户端无法完成浏览器挑战。
6. 从目标用户网络验证页面和完整业务。不要把本机压测的 1000 RPS 当作这台 VPS 的容量。

公网 API 和源站都使用 HTTPS。刷新 Cookie 维持 HttpOnly、Secure、SameSite=Lax。
Caddy 只信任 Cloudflare 官方 IP 段提供的 `CF-Connecting-IP`，覆盖转发给 Gin 的 `X-Forwarded-For` 和 `X-Real-IP`。
Gin 仅信任内网固定的 Caddy 地址 `172.30.50.2`，直接访问源站时不会接受用户伪造的 Cloudflare 头。
Cloudflare IP 段变化时需更新 `deploy/Caddyfile`，来源为 [IPv4](https://www.cloudflare.com/ips-v4) / [IPv6](https://www.cloudflare.com/ips-v6)。
内网网段固定为 `172.30.50.0/28`；换机器时检查路由及 Docker 网络是否冲突，改动时同时调整 Compose 和应用配置中的代理地址。

## 验收和观察

本地需要 Python 3，脚本会注册一个随机账号，创建帖子、评论和投票，验证 Redis 排行投影、刷新令牌轮换及退出。
默认清理帖子和评论，账号会保留；`--keep` 保留内容用于重启验收。
脚本使用 `User-Agent: Ripple-Deployment-Check/1.0` 标明验收客户端；当前 Cloudflare 设置会拒绝 Python 默认客户端标识。

```bash
python3 deploy/smoke.py https://ripple.jasperlab.dev --keep
ssh india-3x 'docker stats --no-stream; free -m'
```

在服务器上使用当前版本的 Compose：

```bash
cd ~/ripple/current
dc() { docker compose -p ripple-prod --env-file "$HOME/ripple/.env" --env-file images.env -f compose.yaml "$@"; }
dc ps
dc logs --tail=80 app mysql redis web
dc restart app redis
dc up -d --wait
```

重启后，用上次输出的帖子 ID 验证持久化：

```bash
python3 deploy/smoke.py https://ripple.jasperlab.dev --verify-post POST_ID
```

`/ping` 仅证明进程能响应，不能证明数据库、Redis 或 Worker 正常；完整冒烟才覆盖这些链路。
验收应确认容器没有 OOMKilled 或持续重启，MySQL 无崩溃恢复循环，Swap 没有持续增长。
容器内存上限分别为 MySQL 384 MiB、Redis 80 MiB、Go 96 MiB、Caddy 64 MiB；实际使用应低于上限。
Go 的 `GOMEMLIMIT` 是软目标，不能替代 Docker 硬限制。
MySQL 关闭 Performance Schema 和 binlog，缩小缓存及连接数；此配置牺牲观测能力和吞吐量，不提供基于 binlog 的时间点恢复。
Redis AOF 每秒刷盘，最多可能损失约一秒最近写入；`maxmemory=24mb`、`noeviction` 到限后写入会失败，不能靠驱逐刷新凭据维持写入。
Redis AOF 重写、MySQL 初始化和并发请求都有额外内存峰值，已有 Swap 不能保证免于 OOM。

## 预置演示数据

2026-10-16 追加了 24 个虚构用户和一个公开测试账号 `test / 123456`，以及 30 篇帖子、105 条评论（含 45 条回复）、288 条投票。
五个社区各有 6 篇帖子，发布时间分散在最近三周；内容与用户均为演示数据，不代表真实社区活跃度。
`test` 是离线预置的账号，密码使用 bcrypt 存储，普通注册的密码校验没有调整。
导入使用单个 MySQL 事务追加记录，并通过已有 Outbox 同步 Redis，没有清空已有内容或重建整个线上排行榜。

本批次的 SQL 和新增记录 ID 保存在服务器 `~/ripple/demo-data/demo-20261016/`；`ids.tsv` 可用于后续按批次核对、清理。
导入前备份为 `~/ripple/backups/before-demo-20261016T094931Z.sql.gz`。这些文件含数据库内容，应继续保持私有，不提交到 Git。
清理时先备份，以批次记录的 ID 为范围，保留导入后用户新增的内容；不要通过清空业务表来删除演示数据。

## 更新、备份与回退

### 仅更新前端（2026-10-16）

性能优化已部署为 `20261016T101648Z-frontend-perf`，镜像为 `ripple-web:20261016T101648Z-frontend-perf-retained`。
本次只执行 `docker compose up -d --no-deps --wait web`，不运行全量 `apply.sh`，不迁移数据库或重启 app、MySQL、Redis。
新版本沿用上一版的 Compose、Caddy 和数据库配置，并在镜像中保留上一版哈希静态资源，兼容尚未刷新的旧页面。
`~/ripple/current` 指向本次版本，`~/ripple/previous` 保留 `20261016-manual-01`；需要回退此次前端时，在上一版目录使用下方 Compose 参数，仅启动 `web` 即可。

本次版本目录内的 `manifest.json`、`sources.txt`、`deployment-result.json` 记录镜像、来源、更新前后容器状态。
`deploy-web.py` 会校验预期的上一版本、镜像包摘要及原有配置，更新失败时恢复旧前端；已成功发布后再次执行会因版本已变化而拒绝。
该目录中的 `images.tar.gz` **只包含前端镜像**，新机器恢复其余服务仍需上一份完整发布包。
本次镜像内通过 243 项前端测试、类型检查、lint、契约检查与构建；公网验证覆盖新旧静态资源、深层路由、公开 API、并行请求、列表缓存和帖子预加载。公开资源摘要与本地构建一致。

### 全量更新

重复构建、上传和 `apply.sh` 即可更新。更新会短暂停止旧应用，在迁移前备份 MySQL 到 `~/ripple/backups/`。
备份在同一台机器，只防部署误操作，不防整机丢失；重要数据需另行下载到其他机器保存。
不要删除命名数据卷；`docker compose down -v` 会销毁该项目的数据。

手动备份（在上文已经定义 `dc` 的服务器 shell 中）：

```bash
umask 077
backup_file="$HOME/ripple/backups/$(date -u +%Y%m%dT%H%M%SZ).sql.gz"
set -o pipefail
dc stop app
dc exec -T mysql sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" exec mysqldump -u"$MYSQL_USER" --single-transaction --no-tablespaces "$MYSQL_DATABASE"' | gzip > "$backup_file"
dc up -d --wait app
```

应用镜像回退仅适用于当前数据库仍兼容上一版本的情况。迁移使用 Gorm AutoMigrate，没有版本化数据库回滚。
**不要通过执行旧版本 `apply.sh` 回退数据库。** 验证兼容性后仅切换 app/web：

```bash
cd ~/ripple/previous
dc() { docker compose -p ripple-prod --env-file "$HOME/ripple/.env" --env-file images.env -f compose.yaml "$@"; }
dc up -d --no-deps --wait app web
```

成功回退后把 `~/ripple/current` 更新为已经验证的版本目录；保留失败版本和日志便于排查。
如果迁移不兼容，需要停服、恢复迁移前备份，再使用对应版本；恢复会丢弃备份之后的数据。
不要在有数据的数据库上直接覆盖导入备份；先另建空库验证恢复，确认后安排替换。

先在独立的空库中演练恢复（`ripple_restore` 已存在时创建命令应失败，先检查旧演练库，不要直接覆盖）：

```bash
set -euo pipefail
backup_file="$HOME/ripple/backups/替换为备份文件.sql.gz"
dc exec -T mysql sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -e "CREATE DATABASE ripple_restore CHARACTER SET utf8mb4"'
gzip -dc "$backup_file" | dc exec -T mysql sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot ripple_restore'
dc exec -T mysql sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -e "SELECT COUNT(*) FROM ripple_restore.posts"'
```

验证后清理演练库；真正替换业务库前，应停服并额外保留当前数据库快照。

Redis 投影丢失时（先确保 MySQL 正常）：

```bash
dc stop app
dc run --rm --no-deps --entrypoint /usr/local/bin/rebuild app
dc up -d --wait app
```

重建会恢复排行榜，不会恢复已丢失的刷新凭据；用户需要重新登录。

## 本地隔离验证

使用独立 Compose 项目名及未占用的私有网段，避免连接开发或生产数据。
通过临时 override 将 `web` 的固定内网地址和 `private` 网段一并更换，应用代理地址也必须相应更换。
`SITE_ADDRESS=https://localhost` 会使用 Caddy 本地 CA；将 CA 证书导出后用 `smoke.py --ca CA_FILE` 验证，不要关闭 TLS 校验。
验证结束仅清理本次临时项目的容器、网络及数据卷。

## 已验证范围（2026-10-16）

- 后端 server、migrate、rebuild 三个入口均已构建；前端类型、lint、237 项测试、契约快照检查及生产构建通过。Lint 保留原有 3 项 Fast Refresh 警告。
- 本地隔离环境通过完整 HTTPS 业务冒烟、MySQL/Redis 重启持久化、更新前备份、恢复到独立空库、版本指针切换及排行榜重建验证；测试容器和数据卷已清理。
- 直接访问源站时伪造转发头不会改变应用识别的客户端 IP。
- 实际 VPS 上四个容器健康，源站 Let’s Encrypt 正式证书有效；保持 Cloudflare 橙云完成 HTTP-01 签发，前提是云安全组放行 TCP 80。
- 公网 HTTPS 已通过页面/API 路由、注册登录、发帖评论、投票、Outbox 排行投影、刷新 Cookie 轮换和退出验证。测试帖子和评论已清理，验证账号保留。
- 这是低流量演示验收，没有在该 VPS 进行容量压测，也没有执行破坏性的数据库回退。
