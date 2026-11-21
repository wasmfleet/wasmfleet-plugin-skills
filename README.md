# wasmfleet-plugin-skills

给 AI 编程助手（Claude Code、Codex 等）用的 **wasmfleet 中控插件开发与发布**技能（skill）。

装上之后，让助手「写一个 wasmfleet 插件」「把这个服务改成 wasmfleet 插件」「给插件配置自动发布」，它就会按 wasmfleet 的约定来做：

- **运行约定**：从 `PORT` 读端口、只监听 `127.0.0.1`、在 `/p/<路径名>/` 反向代理前缀下正常工作、数据放在工作目录、处理 SIGTERM、日志写 stdout/stderr；
- **发布模式**：区分私有插件、公开闭源、公开开源三种情况。闭源时源码仓库和发布仓库（`<名称>-releases`）分开；开源时源码和 Release 放在同一个仓库，不需要额外的发布令牌；
- **发布约定**：推送到 `main` 后由 GitHub Actions 自动编译并发布正式版 Release，附件是不打包的 `server-<平台>` 和 `SHA256SUMS`，中控可以直接安装、更新、回退；
- **模板**：GitHub Actions 工作流（Rust，默认编 macOS arm64 + Linux x64 musl）和本地编译脚本；
- **排错**：推送被拒、令牌权限、附件挑选、反复重启、页面跳出前缀等常见问题。

## 目录

```
skills/wasmfleet-plugin/
├── SKILL.md                     # 入口：约定概要和标准流程
├── references/
│   ├── runtime.md               # 环境变量、生命周期、日志、反向代理、前端写法
│   ├── release.md               # 附件挑选规则、令牌、版本号、CI 速度、发布后校验
│   └── troubleshooting.md       # 常见问题
└── templates/
    ├── release.yml              # GitHub Actions 自动发布
    └── build.sh                 # 本地编译 / 运行
```

## 安装

### Claude Code

作为插件安装（推荐，之后可以随仓库更新）：

```
/plugin marketplace add Char1esOrz/wasmfleet-plugin-skills
/plugin install wasmfleet-plugin-skills@wasmfleet
```

或者直接复制技能目录：

```bash
git clone https://github.com/Char1esOrz/wasmfleet-plugin-skills.git
mkdir -p ~/.claude/skills && cp -r wasmfleet-plugin-skills/skills/wasmfleet-plugin ~/.claude/skills/
```

只想在某个插件项目里使用时，复制到该项目的 `.claude/skills/wasmfleet-plugin/`。

### Codex

把技能目录复制到 Codex 的 skills 目录：

```bash
git clone https://github.com/Char1esOrz/wasmfleet-plugin-skills.git
mkdir -p ~/.codex/skills && cp -r wasmfleet-plugin-skills/skills/wasmfleet-plugin ~/.codex/skills/
```

### 其他助手

在插件项目的 `AGENTS.md`（或者对应助手的说明文件）里加一句，让它先读技能文件：

```markdown
开发和发布 wasmfleet 插件时，先阅读 wasmfleet-plugin 技能：<技能目录>/SKILL.md，并遵守其中的运行约定和发布约定。
```

## 使用示例

- 「用 Rust 写一个 wasmfleet 插件，提供一个计数器页面」
- 「把当前的 HTTP 服务改成符合 wasmfleet 约定的插件」
- 「给这个插件配置 GitHub Actions 自动发布」
- 「中控安装插件时报找不到本平台的程序，帮我查一下」

## 许可

[MIT](LICENSE)
