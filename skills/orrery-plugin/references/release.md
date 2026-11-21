# 发布约定细节

## 中控如何挑选附件

1. 先排除下面这些附件：
   - 校验或签名文件：文件名含 `sha256sum`，或以 `.sha256`、`.sig`、`.asc`、`.txt`、`.md` 结尾；
   - 压缩包和安装包：`.zip` `.tar.gz` `.tgz` `.tar.xz` `.tar.zst` `.tar` `.gz` `.xz` `.dmg` `.pkg` `.deb` `.rpm` `.msi` `.exe` `.apk`。
2. 剩下只有一个时，直接用它。
3. 剩下多个时，选文件名**同时包含**本机架构词和系统词的那一个，不区分大小写：
   - 架构词：`aarch64` / `arm64`、`x86_64` / `amd64` / `x64`
   - 系统词：`apple-darwin` / `darwin` / `macos` / `mac`、`linux`

   恰好一个符合才会安装，零个或多个符合都会报错。
4. 中控只在 macOS 和 Linux 上运行，上传时会检查文件格式（Mach-O / ELF）。Windows 的 `.exe` 会被忽略；你可以照常发布 Windows 版给别的用途，不影响中控挑选。

推荐的附件名（就是 Rust 的 target 三元组）：

| 平台 | 附件名 |
|---|---|
| macOS Apple Silicon | `server-aarch64-apple-darwin` |
| macOS Intel | `server-x86_64-apple-darwin` |
| Linux x64 | `server-x86_64-unknown-linux-musl`（或 `-gnu`） |
| Linux ARM64 | `server-aarch64-unknown-linux-musl`（或 `-gnu`） |

**SHA256SUMS**：
- 文件名含 `sha256sum` 的附件（不区分大小写）就是校验文件。
- 每行是「64 位十六进制摘要  文件名」，文件名前可以带 `*` 或 `./`。`sha256sum` 和 `shasum -a 256` 的输出都符合。
- 存在这个文件时，它必须包含所选附件的摘要；缺少或不一致都会拒绝安装。

**版本**：
- 按 Release 的发布时间从新到旧排列，tag 格式不限制。
- 「最新版本」是第一个有可用附件的版本。自动更新会在「最新版本的 tag 和已安装的不一样」时安装。
- 附件最大 256 MiB。

## 仓库与令牌

| | 源码仓库 `orrery-plugin-<名称>` | 发布仓库 `orrery-plugin-<名称>-releases` |
|---|---|---|
| 内容 | 源码、`.github/workflows/release.yml` | 只有一个 README 和 Release |
| 可见性 | 通常私有 | 私有或公开（公开时中控不需要令牌） |

- **发布令牌**：细粒度令牌，只选发布仓库，Contents: Read and write。存在源码仓库的 Actions Secret `RELEASE_TOKEN` 里，供 Actions 创建 Release。GitHub 自动给 Actions 的内置令牌只能写它所在的仓库，所以需要这个令牌。
- **中控令牌**：细粒度令牌，只选发布仓库，Contents: Read-only（Metadata 会自动变成只读），其他权限都不给。填在中控里，中控会先用它读一次版本列表，读不到就不保存。
- 两个令牌都建议设有效期。发布令牌过期后 Actions 会失败，重新生成后运行一次 `gh secret set RELEASE_TOKEN` 覆盖即可。

## 版本号

模板用 `<主版本>.<次版本>.<运行序号>`：主版本和次版本取自 `Cargo.toml`，补丁号是工作流的运行序号 `github.run_number`，每次推送自动递增，不用手动改。想升主版本或次版本时修改 `Cargo.toml` 的 `version`。

CI 通过环境变量 `APP_VERSION` 把版本号注入程序（见 runtime.md）。源码仓库会打同名 tag，方便对照某个版本对应哪个提交。

## CI 速度

一个小型 axum + 内置 SQLite 的插件，实测耗时如下：

| 任务 | 第一次（无缓存） | 之后（有缓存） |
|---|---|---|
| macOS arm64 | 编译约 26 秒 + 首次保存缓存约 80 秒 | 约 30 秒 |
| Windows x64 | 编译约 170 秒 | 约 100 秒 |

- `Swatinem/rust-cache` 是提速的关键。第一次运行慢，主要是在编译依赖和保存缓存；修改 `Cargo.toml` 或 `Cargo.lock` 后会再慢一次。
- Windows 托管 runner 的磁盘 I/O 明显慢，编译 C 代码（比如 `rusqlite` 的 `bundled` 特性）也更慢。中控用不了 Windows 版，没有其他用途就不要编它。
- **musl 不会让编译变快**。它是 Linux 的 C 库，只影响 Linux 程序的链接方式：用 musl 编出来的是静态链接程序，不依赖系统的 glibc 版本，任何发行版都能直接运行，所以 Linux 插件推荐用 `x86_64-unknown-linux-musl`。它对 macOS、Windows 目标没有作用。
- 只开启用得到的依赖特性。例如 tokio 不要用 `full`，只开 `rt-multi-thread`、`macros`、`net`、`signal` 这些需要的。
- 多个平台在矩阵里并行编译，总耗时取决于最慢的那个平台。

## 发布后校验

```bash
R=<owner>/orrery-plugin-<名称>-releases
TAG=$(gh release list --repo $R --limit 1 --json tagName -q '.[0].tagName')
gh release view $TAG --repo $R --json isDraft,isPrerelease,assets \
  -q '"draft=\(.isDraft) prerelease=\(.isPrerelease)", (.assets[] | "\(.name)  \(.size)")'
mkdir -p /tmp/rel && gh release download $TAG --repo $R --dir /tmp/rel --clobber
cd /tmp/rel && shasum -a 256 -c SHA256SUMS && file server-*
chmod +x server-aarch64-apple-darwin && PORT=28777 ./server-aarch64-apple-darwin   # 在对应平台上试运行
```

检查项：

- 不是草稿，也不是预发布；
- 每个平台都有一个附件，且 `SHA256SUMS` 全部 OK；
- `file` 显示的格式正确（Mach-O arm64 / ELF x86-64）；
- 程序能用 `PORT` 启动，`--version` 显示的就是这个 tag。
