# EasyControlNext · HarmonyOS NEXT

易控（EasyControlNext）的 **HarmonyOS NEXT** 客户端工程（Stage 模型），与 Android 工程 `../easycontrolnext` 并列，互不嵌套。

| | 路径 |
|---|---|
| 本工程（鸿蒙） | `harmonyos/` |
| Android 工程 | `../easycontrolnext/` |
| bundleName | `com.shiyunjin.easycontrolnext` |

## 用 DevEco Studio 打开

1. 安装 [DevEco Studio](https://developer.huawei.com/consumer/cn/deveco-studio/)（建议 5.0+ / 6.0，API 12+）。
2. **File → Open**，选择本目录 `harmonyos/`（含 `build-profile.json5`、`AppScope/`、`entry/`）。
3. 等待同步：下载/扩展 SDK、执行 `ohpm install`（如提示）。
4. 配置签名后运行到真机或模拟器。

> **完整编译需要 DevEco Studio / HarmonyOS SDK。**  
> 本仓库只提供可打开的 Stage 脚手架；未在无 SDK 环境下执行 HAP 编译。本机若已安装 DevEco，可把 `local.properties` 中的 `sdk.dir` 指到实际 SDK（默认示例为 DevEco 自带 `Contents/sdk`）。

## AI Skill（已安装）

按 [harmonyos-ai-skill](https://github.com/DengShiyingA/harmonyos-ai-skill) 的 Cursor / 项目级说明安装：

| 文件 | 用途 |
|---|---|
| `.cursor/rules/harmonyos.mdc` | Cursor 规则（编辑 `.ets` / `module.json5` 等时激活） |
| `.claude/skills/harmonyos-development/SKILL.md` | Claude Code 项目级 skill |
| `AGENTS.md` | AGENTS.md 标准（Codex / opencode 等） |

在本目录用 Cursor 打开工程后，提问 ArkTS / ArkUI / Stage 相关问题即可自动带上鸿蒙知识。

## 工程结构（摘要）

```
harmonyos/
├── IMPLEMENTATION_PLAN.md      # 控制器移植实施计划（进度 / 验收门）
├── AppScope/app.json5
├── entry/                      # 入口 HAP（ArkUI + 数据层）
├── native/                     # Rust：protocol + ohos-rs adb_core
├── scripts/                    # host tests / OHOS .so / server jar 拷贝
├── build-profile.json5
└── README.md
```

生产基线：**HarmonyOS 6.1.1 / API 24 Release**。鸿蒙端只做控制器；受控端仍是 Android，复用现有 `server` JAR。

## 常用命令

```bash
./scripts/run_host_tests.sh          # Gate A：协议单元测试
export OHOS_NDK_HOME=.../openharmony
./scripts/build_native_ohos.sh       # Gate B：arm64 libadb_core.so
./scripts/copy_server_jar.sh         # 从 Android Gradle 输出拷贝 server jar
```

## 与 Android 的关系

- Android 实现位于 `../easycontrolnext`（Gradle / Kotlin / Compose）。
- 鸿蒙实现独立演进；协议与产品能力可对齐，但构建系统与 UI 栈不同，请勿把鸿蒙模块放进 Android 目录。
- 详细架构、阶段与验收标准见 [`IMPLEMENTATION_PLAN.md`](./IMPLEMENTATION_PLAN.md)。
