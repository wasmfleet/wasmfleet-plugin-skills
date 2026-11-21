# 常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| `git push` 报 `refusing to allow an OAuth App to create or update workflow ... without workflow scope` | `gh` 的登录没有 `workflow` 权限 | 用户运行 `gh auth refresh -h github.com -s workflow`，然后重新推送 |
| Actions 报 `未设置 Secret RELEASE_TOKEN` | 源码仓库没有配置这个 Secret | 用户生成读写令牌，运行 `gh secret set RELEASE_TOKEN --repo <用户>/<名称>` |
| `gh release create` 报 403 或 `Resource not accessible` | 令牌没有授权发布仓库，或 Contents 只给了只读 | 重新生成令牌：只选发布仓库，Contents 选 Read and write |
| `gh release create` 报找不到仓库或分支 | 发布仓库是空的（没有任何提交），无法打 tag | 用 `gh repo create ... --add-readme` 重新创建，或者往发布仓库推一个 README |
| 令牌过期后发布失败 | 细粒度令牌有有效期 | 重新生成令牌，再运行一次 `gh secret set` 覆盖，然后在 Actions 页面重新运行 |
| 中控里看不到新版本 | Release 是草稿或预发布；或者这个版本没有本平台可用的附件（「最新版本」是第一个有可用附件的版本） | 发布正式版（`gh release create` 不要加 `--draft` / `--prerelease`） |
| 中控拒绝安装，提示校验失败 | `SHA256SUMS` 和附件不一致，例如重新上传了附件但没有更新校验文件 | 重新运行工作流：它会一起覆盖附件和 `SHA256SUMS` |
| 中控找不到本平台的程序 | 附件名里没有架构词和系统词；上传的是压缩包；或者只发了 Windows `.exe` | 附件命名为 `server-<target>`，直接上传 macOS / Linux 可执行文件 |
| 中控报多个附件符合 | 有两个附件都同时包含本机的架构词和系统词，例如 `-gnu` 和 `-musl` 同时发布 | 每个平台只发一个附件 |
| 插件被反复重启 | 程序以非 0 退出（例如端口被占用、缺少参数），中控按「失败时重启」退避重启 | 看中控里的 stderr 日志（标红）修复原因 |
| 后台任务跑完就停了，不再重启 | 退出码 0 在默认策略下表示正常结束 | 想常驻就不要以 0 退出，或者在中控里设为「总是重启」 |
| 停止插件时丢数据 | 没有处理 SIGTERM，5 秒后被 SIGKILL | 处理 SIGTERM，保存数据后退出（见 runtime.md） |
| 中控里看不到日志，或者日志成批出现 | stdout 不是终端时被缓冲 | 每行及时 flush（Python 用 `-u`） |
| 访问插件地址返回 503 / 502 | 503：插件没有运行。502：被识别成后台任务（启动 10 秒内没有监听端口），或者是 HTTP 服务但还没监听端口、连接被拒绝 | 检查程序是否监听了 `PORT`，或者在中控里手动指定类型 |
| 插件显示已退出并被反复重启，但服务其实还在跑；停止后端口仍被占用 | 程序自己转到了后台（daemonize、fork 后父进程退出、`setsid`、`nohup &`），脱离了中控管理的进程组 | 让程序在前台一直运行 |
| 手动上传的测试程序过一会儿被换掉了 | 手动上传会清空版本号，自动更新在下一次检查（最多 10 分钟）时装回仓库里的最新版本 | 测试期间先关掉自动更新 |
| 公开发布仓库偶尔报 403 | 没有填令牌时，GitHub 对每个 IP 限流为每小时 60 次 | 公开仓库也填一个只读令牌 |
| 按访问者 IP 做的限制不起作用 | 经中控转发后没有 `X-Forwarded-For`，所有请求都来自 127.0.0.1 | 不要依赖对方 IP，改用其他鉴权方式 |
| 插件启动即退出：`required arguments were not provided: --port` | 程序只认 `--port`，而中控是用 `PORT` 环境变量传端口 | 让参数支持 `env = "PORT"` |
| 经中控访问时页面没有样式，或点导航跳出插件 | 页面用了以 `/` 开头的绝对路径 | 全部改成相对路径（见 runtime.md） |
| 页面显示的接口地址端口不对、缺少 `/p/<名称>` | 用服务端的真实端口拼接地址 | 端口和前缀从 `location` 取（见 runtime.md） |
| 识别出的「内网 IP」是 `198.18.x.x` | 机器开着代理或 VPN，默认路由走虚拟网卡 | 枚举网卡，排除 `198.18.0.0/15`，优先使用 RFC 1918 地址 |
| 提交作者邮箱是 `xxx@某某-Mac.local` | 本机没有配置 git 身份 | 只对这个仓库设置：`git config user.email "<id>+<用户名>@users.noreply.github.com"` |
