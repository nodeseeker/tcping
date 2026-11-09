# AGENTS.md

tcping：基于 Go 的高性能 TCP Ping 工具（跨平台 Linux/Windows/macOS）。

## 仓库与远程

| 远程 | 地址 | 说明 |
|---|---|---|
| `origin` | https://github.com/2959916298/tcping | GitHub |
| `cnb` | https://cnb.cool/l1094/tcping | CNB（国内直连） |

代码改动需同时推两个远程：`git push origin main` 和 `git push cnb main`。

## 版本与发布（重要）

- 版本号唯一来源：`src/version.txt`（纯数字，如 `1.9.12`；Go 侧 `go:embed` 同源）。
- `tools/compiler.sh` 会把版本写成 `bin/VERSION = v<version>`（**已带 `v` 前缀**）。
- **CI 拼 release tag 用 `${ver}-${bt}`，不要额外加 `v`**，否则会出现 `vv1.9.12`（踩过）。
- 发布方式：**推 tag 才发版**，普通 push 不会自动构建/发版。

发版步骤：

1. 修改 `src/version.txt`
2. `git commit -am "chore: 版本号提升至 vX.Y.Z"`，推 `main` 到两个远程
3. `git tag vX.Y.Z`，推 tag 到两个远程：`git push origin vX.Y.Z` / `git push cnb vX.Y.Z`
4. 两端 CI 各自全平台编译并发布 Release，release tag 为 `v<version>-<yyyymmdd-hhmmss>`

## CI 触发方式

| 平台 | 配置文件 | 触发条件 |
|---|---|---|
| GitHub | `.github/workflows/release.yml` | `on.push.tags: ['v*']`；另保留 `workflow_dispatch` 手动 |
| CNB | `.cnb/release.yml`（由 `.cnb.yml` `include`） | `"v*": tag_push`；另保留 `web_trigger_build_release` 手动按钮（按钮定义在 `.cnb/web_trigger.yml`） |

- 构建发布流程只在 `.cnb/release.yml` 顶层锚点 `.release_base` 里写一次，`tag_push` 与手动按钮共用（yml 级复用）。
- **CNB 的触发过滤只支持「分支/tag 名 glob」**（一级 key，如 `main`、`"v*"`、`(main|dev)`、`$`），**没有 GitHub 的 `paths` 文件路径过滤**。若需"仅某文件变化才构建"，只能在 stage 脚本里用 `git diff --name-only` 自行判断，或改用 tag 触发。

## 目录结构

- `src/main.go`：主程序（flag 解析、TCP ping、统计、CSV 输出）
- `src/version.txt`：版本号唯一来源
- `tools/compiler.sh`：全平台编译（GitHub Actions 与 CNB 共用同一份）
- `install_github.sh` / `install_cnb.sh`：安装/更新/卸载脚本

## 安装脚本约定

- `-o <目录>` / `-O`：**不安装模式**，只下载并输出二进制到指定目录 / 当前目录（无需 root）
- `-u` 卸载、`-f` 强制（跳过确认）、`-v` 详细输出
- 默认安装到 `/usr/local/bin`（在默认 PATH 中，需 root）；非 root 或不可写时用 `-o/-O` 输出后自行加 PATH

## CLI 参数约定

- 次数：`-n` / `--count`
- **`-c` 是 `-n` 的次数别名**（历史版本 `-c` 表示彩色；彩色现已默认开启，关闭用 `--no-color`）
- 端口：`-p` / `--port`，或位置参数 `<主机> [端口]`
- 注意与 Windows 版 `tcping.exe` 区分：后者次数用 `-n`、端口是位置参数、没有 `-p`

## 行尾与编码

- `.gitattributes` 固定 `*.sh` / `*.yml` / `*.yaml` 为 **LF**。
- 不要提交 CRLF 的 shell/CI 文件（Linux 上会报 `\r` 语法错误，如 `未预期的记号 $'\r'`）。
- 脚本统一 UTF-8、无 BOM。

## 本机网络约定（Windows 开发机）

- 访问 GitHub API / raw 内容用 `curl.exe -k`（本机证书链问题，不加 `-k` 会失败）。
- CNB 可直连（cnb.cool）。
