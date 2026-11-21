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
- 只有文件名含 `sha256sum` 的附件（不区分大小写）才会被用来校验。单独的 `xxx.sha256` 文件不会被当作程序，但也不会用来校验；想要校验，就发布 `SHA256SUMS`。
- 每行是「64 位十六进制摘要  文件名」，文件名前可以带 `*` 或 `./`。`sha256sum` 和 `shasum -a 256` 的输出都符合。
- 存在这个文件时，它必须包含所选附件的摘要；缺少或不一致都会拒绝安装。

**版本**：
- 按 Release 的发布时间从新到旧排列，tag 格式不限制。
- 「最新版本」是第一个有可用附件的版本。自动更新会在「最新版本的 tag 和已安装的不一样」时安装。
- 附件最大 256 MiB。
- 在中控里手动上传过程序文件的插件，版本号会被清空。这时如果开着自动更新，下一次检查（最多 10 分钟后）就会被换成仓库里的最新版本。想临时测试自己编的程序，先关掉自动更新。

## 发布模式：私有、公开闭源、开源

开始前先问清楚两件事：插件要不要公开给别人安装？源码要不要开源？然后选一种模式：

| | 私有插件 | 公开、闭源 | 公开、开源 |
|---|---|---|---|
| 源码仓库 `<名称>` | 私有 | 私有 | **公开，Release 也发在这里** |
| 发布仓库 `<名称>-releases` | 私有 | 公开 | 不需要 |
| 工作流 `RELEASE_REPO` | `${{ github.repository }}-releases` | `${{ github.repository }}-releases` | `${{ github.repository }}` |
| Actions 发布令牌 `RELEASE_TOKEN` | 需要 | 需要 | **不需要**（用 Actions 自带的令牌） |
| 中控令牌（只读） | **必须**，否则读不到私有仓库 | 可不填，但建议填（避免限流） | 可不填，但建议填（避免限流） |
| 谁能安装 | 只有持有只读令牌的人 | 任何人 | 任何人 |
| 谁能看到源码 | 只有你 | 只有你 | 任何人 |

**为什么闭源时要分两个仓库**：中控的只读令牌需要 Contents: Read-only 权限才能读 Release，而这个权限同样能读源码。GitHub 没有「只读 Release」这种权限。源码和 Release 放在同一个私有仓库，拿到令牌的人就能读到源码；拆开以后，令牌只授权发布仓库，读不到源码。开源的话源码本来就公开，自然不用拆。

> 只给自己用、不在乎令牌能读到源码时，私有插件也可以只用一个私有仓库：`RELEASE_REPO` 设为 `${{ github.repository }}`，不需要 `RELEASE_TOKEN`，中控令牌授权这个仓库即可。默认还是建议分开。

### 各模式的创建步骤

发布仓库必须先有一个提交（用 `--add-readme`），才能在上面创建 tag。

```bash
# 私有插件
gh repo create <owner>/<名称>-releases --private --add-readme
gh repo create <owner>/<名称> --private --source . --remote origin

# 公开、闭源
gh repo create <owner>/<名称>-releases --public --add-readme
gh repo create <owner>/<名称> --private --source . --remote origin

# 公开、开源（只有一个仓库）
gh repo create <owner>/<名称> --public --source . --remote origin
```

开源时还要把工作流里的 `RELEASE_REPO` 改成 `${{ github.repository }}`，并添加 LICENSE。中控里填的仓库地址就是这个源码仓库。

### 令牌

- **发布令牌**（只有分仓库时需要）：细粒度令牌，只选发布仓库，Contents: Read and write。存在源码仓库的 Actions Secret `RELEASE_TOKEN` 里。Actions 自带的令牌只能写它所在的仓库，写不了另一个仓库，所以需要这个令牌。
- **中控令牌**：细粒度令牌，只选中控要读的那个仓库（分仓库时是发布仓库，开源时是源码仓库），Contents: Read-only（Metadata 会自动变成只读），其他权限都不给。中控会先用它读一次版本列表，读不到就不保存。
- **公开仓库也建议填只读令牌**：不填时，GitHub 对每个 IP 的接口请求限流为每小时 60 次。每个开着自动更新的插件每 10 分钟检查一次，插件多了可能超出，超出后报 403。
- 两个令牌都建议设有效期。发布令牌过期后 Actions 会失败，重新生成后运行一次 `gh secret set RELEASE_TOKEN` 覆盖即可。
- 两个令牌不要混用。

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
R=<owner>/wasmfleet-plugin-<名称>-releases
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
