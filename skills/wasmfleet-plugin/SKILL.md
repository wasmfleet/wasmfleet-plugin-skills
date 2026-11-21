---
name: wasmfleet-plugin
description: 开发、打包、发布 wasmfleet 中控插件。适用于：新建 wasmfleet 插件（HTTP 服务或后台任务）；让已有程序适配 wasmfleet（PORT 环境变量、只监听 127.0.0.1、在 /p/<路径名>/ 反向代理前缀下正常工作、处理 SIGTERM、数据放在 WASMFLEET_PLUGIN_DATA）；配置 GitHub Actions，在独立的发布仓库自动发布 Release，供中控安装、更新、回退；排查插件安装、启动或发布失败。用户提到 wasmfleet、中控插件、插件发布、releases 仓库、SHA256SUMS 时使用。
---

# wasmfleet 插件开发与发布

wasmfleet 中控在 **macOS 和 Linux** 上运行，以独立进程运行插件：从 GitHub Release 下载一个可执行文件，用环境变量告诉它端口和工作目录，再把 `http://<中控>:18080/p/<路径名>/` 反向代理到插件（18080 是中控的默认端口，可以修改）。插件可以用任何语言写，只要遵守下面的运行约定和发布约定。

参考文档（按需读取）：

- [references/runtime.md](references/runtime.md)：环境变量、生命周期与信号、日志、反向代理行为、前缀下的前端写法
- [references/release.md](references/release.md)：附件挑选规则、发布仓库与令牌、版本号、CI 提速、发布后校验
- [references/troubleshooting.md](references/troubleshooting.md)：常见错误及处理
- 模板：[templates/release.yml](templates/release.yml)（GitHub Actions，Rust）、[templates/build.sh](templates/build.sh)（本地编译）

## 运行约定（必须遵守）

1. **端口**：从环境变量 `PORT` 读取，并**只监听 `127.0.0.1`**。外部访问一律经过中控转发。
2. **路径前缀**：插件挂在 `/p/<路径名>/` 下，中控转发时会去掉前缀。页面里的链接、静态资源和接口请求一律**用相对路径**（`api/items`、`static/app.js`），不要以 `/` 开头；需要绝对路径时，用 `WASMFLEET_BASE_PATH`（如 `/p/hello`，没有结尾斜杠）来拼。
3. **数据放在工作目录**：进程的当前目录就是 `WASMFLEET_PLUGIN_DATA`，用相对路径（如 `data.db`）即可。更新、回退、重启时都会保留，只有在中控里删除插件时才删除。
4. **在前台运行，不要自己转到后台**（不要 daemonize、`setsid`、`nohup &`），否则会脱离中控管理的进程组。**处理 SIGTERM**：中控停止插件时，给整个进程组发 SIGTERM，5 秒后发 SIGKILL。收到后要在 5 秒内保存数据并退出。
5. **退出码有含义**：在默认的「失败时重启」策略下，非 0 退出会被重启（退避 1、2、4……秒，最长 60 秒），退出码 0 表示正常结束、不再重启。常驻服务不要以 0 退出。
6. **日志写 stdout / stderr**，一行一条，不要输出颜色控制码，及时 flush。中控按行采集，stderr 在页面上标红。
7. **单个可执行文件**：静态资源打进程序（Rust 用 `include_str!`，Go 用 `embed`），不依赖额外文件。stdin 为空。
8. 建议提供 `--version`，并在页面或接口上显示版本号。

## 发布模式（先和用户确认）

| | 私有插件 | 公开、闭源 | 公开、开源 |
|---|---|---|---|
| 仓库 | 私有源码仓库 + 私有发布仓库 `<名称>-releases` | 私有源码仓库 + 公开发布仓库 `<名称>-releases` | **一个公开仓库**，源码和 Release 都在里面 |
| 工作流 `RELEASE_REPO` | `${{ github.repository }}-releases` | `${{ github.repository }}-releases` | `${{ github.repository }}` |
| Actions 发布令牌 `RELEASE_TOKEN` | 需要 | 需要 | 不需要 |
| 中控只读令牌 | 必须 | 建议（避免限流） | 建议（避免限流） |

闭源时必须拆成两个仓库：GitHub 没有「只读 Release」这种权限，能读 Release 的令牌也能读源码。拆开以后，中控令牌只授权发布仓库。开源时源码本来就公开，放在一个仓库就行。各模式的创建命令和令牌设置见 [references/release.md](references/release.md)。

## 发布约定（中控按此挑选）

- **插件名称取自中控所读仓库的名字**：去掉结尾的 `-releases` 和开头的 `wasmfleet-plugin-`（不区分大小写）。例如 `wasmfleet-plugin-hello-releases` 或 `wasmfleet-plugin-hello`，名称都是 `hello`，路径名是 `/p/hello/`。
- **正式版 Release**：草稿和预发布不会显示。中控按发布时间从新到旧列出版本，可以选择和回退。tag 格式不限制，建议用 `vX.Y.Z`。
- **附件是直接可执行的程序，不打包**，文件名带上架构和系统：`server-aarch64-apple-darwin`、`server-x86_64-apple-darwin`、`server-x86_64-unknown-linux-musl`、`server-aarch64-unknown-linux-gnu`。中控会忽略压缩包、安装包和 `.exe`。
- **附带 `SHA256SUMS`**：每行 `<sha256>  <文件名>`。有这个文件时，中控会校验所选的附件，摘要缺少或不一致都会拒绝安装。
- 附件不超过 256 MiB。

完整的挑选规则见 release.md。

## 新插件的标准流程

1. **确认发布模式**：私有、公开闭源，还是开源。
2. 按运行约定写好程序。本地用 `PORT=8080 ./程序` 验证，再用带前缀的代理验证页面（见 runtime.md）。
3. 复制 `templates/build.sh` 用于本地编译。复制 `templates/release.yml` 到 `.github/workflows/release.yml`，修改 `env.BIN`、`env.RELEASE_REPO`（按模式）和平台矩阵。开源时添加 LICENSE。
4. 按模式创建仓库（命令见 release.md）。命名建议用 `wasmfleet-plugin-<功能>`，发布仓库再加 `-releases`。
5. 让 `gh` 能推送 workflow 文件：`gh auth refresh -h github.com -s workflow`。需要用户在浏览器里确认。
6. **只有分仓库时需要**：由用户本人在 GitHub 网页上生成发布令牌（细粒度令牌，只选发布仓库，Contents: Read and write），然后运行 `gh secret set RELEASE_TOKEN --repo <owner>/<源码仓库>`，在提示时粘贴。
7. `git push`，等 Actions 跑完，按 release.md 的「发布后校验」检查。
8. 由用户本人生成中控的只读令牌（只选中控要读的那个仓库，Contents: Read-only），在中控「添加插件 → 从 GitHub」里填写仓库和令牌。私有插件必须填；公开仓库可以不填，但建议填。已有插件可以在详情页的「来源」里绑定仓库，之后可以安装新版本、回退，或开启自动更新。

## 注意事项

- 细粒度令牌不能通过 API 创建，只能由用户在网页上生成。Agent 不要索要、显示或保存令牌的值，也不要把它写进仓库。
- 两个令牌不要混用：**读写令牌**只给 Actions 用（只有分仓库时需要），存在源码仓库的 Secret 里；**只读令牌**只给中控用。
- 每次推送到 `main` 都会自动发布新版本，中控又可能开着自动更新，所以 `main` 上的每个提交都应当能直接上线。
- 改数据库表结构时，要能从任意旧版本迁移过来（用户可能跨版本升级，也可能回退）。不能直接丢弃的数据先备份。
