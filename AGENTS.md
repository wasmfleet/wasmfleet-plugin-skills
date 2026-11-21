# AGENTS.md

本仓库是 wasmfleet 中控插件开发与发布的技能（skill），供 Claude Code、Codex 等 AI 编程助手使用。

- 技能入口：[skills/wasmfleet-plugin/SKILL.md](skills/wasmfleet-plugin/SKILL.md)。开发或发布 wasmfleet 插件时，先读它，再按需读 `references/` 下的文档。
- 修改本仓库时：
  - `SKILL.md` 只放约定概要和流程，细节放在 `references/`，模板放在 `templates/`。
  - 约定以 wasmfleet 中控的实际行为为准。改动约定时，同步更新 `SKILL.md`、`references/` 和 `templates/`。
  - 这是公开仓库：不要写入任何人的令牌、内网 IP、私有仓库名，也不要写中控的内部接口。只描述插件能看到的行为：环境变量、工作目录、信号、Release 约定、代理行为。
  - 修改 `.claude-plugin/plugin.json` 后，把 `version` 加一。
