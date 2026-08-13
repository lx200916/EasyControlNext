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

Always-on 只有项目规则；鸿蒙百科在 skill `references/` 里按需加载，避免重复灌进上下文。

| 文件 | 用途 |
|---|---|
| `AGENTS.md` | 本工程 always-on（控制器边界、API 24、DeviceStore、native `.so`、fold/split） |
| `.cursor/rules/harmonyos.mdc` | 短提醒：跟 AGENTS.md；编辑 `.ets` / `json5` 时激活 |
| `.claude/skills/harmonyos-development/` | 百科 canonical：瘦 `SKILL.md` + `references/` / `recipes/` / `examples/` |
| `.cursor/skills/harmonyos-development/` | Cursor 发现入口（指向同一套 references） |
| `.cursor/skills/easycontrol-harmonyos-port/` | 配对 / 直播 / native 移植脚注 |

提问 ArkTS / Kit API 时：先看 `AGENTS.md`，再按 skill 路由表读**一个** reference，不要整本百科贴进回答。

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
export OHOS_NDK_HOME=.../openharmony # 可选；默认探测 DevEco openharmony SDK
./scripts/build_native_ohos.sh       # Gate B：重建并 stage → entry/libs/arm64-v8a/libadb_core.so
./scripts/copy_server_jar.sh         # 从 Android Gradle 输出拷贝 server jar
```

### 为什么 Assemble 里的 `.so` 以前总是旧的？

`libadb_core.so` 是 **Rust (cargo/ohrs)** 产物，**不是** CMake / `externalNativeOptions` 编出来的。  
DevEco Assemble 只会把 `entry/libs/arm64-v8a/` 里已有的 prebuilt `.so` 打进 HAP（任务 `default@ProcessLibs`）。  
`entry/libs/` 还在 `.gitignore` 里，所以单纯点 Assemble **不会**跟着改 Rust 源码。

现已在 `entry/hvigorfile.ts` 挂了 `buildNativeOhos`：Assemble / `hvigorw assembleHap` 会在 `ProcessLibs` 之前自动跑  
`scripts/build_native_ohos.sh --if-needed`（源码比 staged `.so` 新才重建）。

```bash
# 正常：DevEco Assemble 或
./hvigorw assembleHap -p product=default

# 强制立刻重编 native（不看 mtime）
./scripts/build_native_ohos.sh --force

# 本机缺 Rust/NDK、只想用已有 staged .so 时
SKIP_NATIVE_OHOS=1 ./hvigorw assembleHap
# 或
./hvigorw assembleHap -p skipNativeOhos=true
```

前提：本机已装 `rustup` 目标 `aarch64-unknown-linux-ohos`，且能访问 DevEco 的 `OHOS_NDK_HOME`（含 `native/llvm`）。

## 与 Android 的关系

- Android 实现位于 `../easycontrolnext`（Gradle / Kotlin / Compose）。
- 鸿蒙实现独立演进；协议与产品能力可对齐，但构建系统与 UI 栈不同，请勿把鸿蒙模块放进 Android 目录。
- 详细架构、阶段与验收标准见 [`IMPLEMENTATION_PLAN.md`](./IMPLEMENTATION_PLAN.md)。
