# EasyControlNext

用一台 **Android** 或 **HarmonyOS NEXT** 设备，通过无线调试（或 Android 端 USB）镜像并控制另一台 **Android** 设备。

控制端负责配对、投屏解码、触控与音频转接；被控端仍是 Android，通过本仓库自带的 `server` JAR（基于 [scrcpy](https://github.com/Genymobile/scrcpy) 服务端改造）在 `app_process` 中运行，无需在被控机安装独立 App。

本仓库是 [Easycontrol](https://github.com/mingzhixian/Easycontrol) / [daitj/Easycontrol](https://github.com/daitj/easycontrol) 的硬分叉，以支持 **Android 11+ 无线调试配对码 / 二维码**，并增加 HarmonyOS 控制端。Android 包名为 `com.shiyunjin.easycontrolnext.app`，鸿蒙 bundleName 为 `fun.saltedfish.easycontrol.next`。

[<img src="https://img.shields.io/endpoint?url=https://apt.izzysoft.de/fdroid/api/v1/shield/com.shiyunjin.easycontrolnext.app&logo=data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAMAAABg3Am1AAADAFBMVEUA0////wAA0v8A0v8A0////wD//wAFz/QA0/8A0/8A0/8A0/8A0v///wAA0/8A0/8A0/8A0/8A0//8/gEA0/8A0/8B0/4A0/8A0/8A0/+j5QGAwwIA0//C9yEA0/8A0/8A0/8A0/8A0/8A0/+n4SAA0/8A0/8A0/+o6gCw3lKt7QCv5SC+422b3wC19AC36zAA0/+d1yMA0/8A0/+W2gEA0/+w8ACz8gCKzgG7+QC+9CFLfwkA0/8A0////wAA0/8A0/8A0/8A0/+f2xym3iuHxCGq5BoA1P+m2joI0vONyiCz3mLO7oYA0/8M1Piq3Ei78CbB8EPe8LLj9Ly751G77zWQ1AC96UYC0fi37CL//wAA0/8A0////wD//wCp3jcA0/+j3SGj2i/I72Sx4zHE8FLB8zak1kYeycDI6nRl3qEA0/7V7psA0v6WzTa95mGi2RvB5XkPy9zH5YJ3uwGV1yxVihRLiwdxtQ1ZkAf//wD//wD//wD//wD//wCn5gf//wD//wD//wD//wD//wAA0/+h4A3R6p8A0/+X1w565OD6/ARg237n9csz2vPz+gNt37V/vifO8HW68B/L6ZOCwxXY8KRQsWRzhExAtG/E612a1Rd/pTBpmR9qjysduKVhmxF9mTY51aUozK+CsDSA52T//wD//wAA0////wD//wBJ1JRRxFWjzlxDyXRc0pGT1wCG0CWB3VGUzSTh8h6c0TSr5CCJ5FFxvl6s4H3m8xML0/DA5CvK51EX1N+Y2gSt4Dag3ChE3fax2ki68yO57NF10FRZnUPl88eJxhuCxgCz5EOLwEGf1DFutmahzGW98x0W1PGk3R154MHE6bOn69qv3gy92oG90o+Hn07B7rhCmiyMwECv1nO+0pQfwrCo57xF2daXsVhKrEdenQAduaee1Bsjr42z5D9RoCXy+QNovXpy2Z5MtWDO/TiSukaF3UtE1K6j3B4YwLc5wXlzpyIK0u5zy3uJqg4pu5RTpkZmpVKyAP8A0wBHcExHcEyBUSeEAAABAHRSTlP///9F9wjAAxD7FCEGzBjd08QyEL39abMd6///8P/ZWAnipIv/cC6B//7////////L/1Dz/0D///////86/vYnquY3/v///5T//v///17///////////////84S3QNB/8L/////////////7r/////NP////9l/////wPD4yis/x7Ym2lWSP+em////0n////////v///////////////////7//7pdGN3Urr6/+v/6aT////+//H/o2P/1v+7r7jp4PM/3p4g////g///K///481LxO///v////9w////8v/////9/p3J///a+P9v/5KR/+n///+p/xf//8P//wAAe7FyaAAABCZJREFUSMdj+E8iYKBUgwIHnwQ3N7cEHxcH+///VayoAE0Dh41qR7aBnCIQ8MsJKHH9/99czYYMWlA0cIkJGjMgAKfq//9RNYzIgLcBWYOTiCgDMhDn+B9bh6LebiWyH6L5UZQzONoAHWSHoqEpDkkDsyKqelv1//9rG1HUN9YihZK9AKp6BkG+/6xNqA5ajhSsCkrIipmYGGRa//9vQXVQXSySBnkWJOUMfn5Myuz/G3hR1NdEIUUchwiy+bkTsg4dbW/fu6W/e1c3XMMy5JiOZkFxUFZo74mgKTqaKXu0+2HqVwkja3BH9kFu361JwcHTfPJD4mdfe8ULAdVRyGlJAcVFfg+CQOozZ4XrJ85+JgwBsVXIGriQw5Tp4ZScezd8JiWnBupru30qwJZa+ZAjmWlC8fUZM4qB6kPnLNSPLMWqQQ5ZQ5aOzs1HmamBaQHzFs6y+qAmJCTE8f9/QgKSBg4DJPWc6zVDQkIC09JkZSPD38kukpExFpT4z67uYI/QwCOOCCK/izvu5CWl6AcEWMnKWml7LWbKZfH9/99UkknQHhGsynDz+65eWXv3/JmJrq5eXienVlRUfH/z8VvCf45soKQIH1yDEQsszrp6gwq9C73T87xcXadKl5TkFev4A/2tygmSBqYXqAYJmK+ZuoJydDR1vP09DA0NOy2kpdML81+U/heCpH1JU3jig7lJ5nKOT4i/t6ZHkqGzs4lJmIVHfrj+JR4HqLQSD0yDkCNEpGNn5ix9D03/eJdElTZdKV2TpNOhkwt8YUlNUgimgV0dLMBvf1gz1MolPd5FRcVNSkpDQ8owJeBCDyIhrIDnOD5QcuIU+3/2QKSs9laQ+noNLS0zLWdtqyP7mBAFAw88TwsJgMuJYweBGjYngtWbmeuZOW+bvNQToUFOAlFqOBk4Ov3/L7Z60/aN0p1tUhpa5nqWlub7C3p2I9QzyAghlUvczOz/1fhzPT3XSIfpSmmYAdVbmm1gV0dSz8DSilpUQsqCddIWIA3meuZaJqdMJZEzl6gRqgZIWZAxUdoizERXN8yi5MltcZTChzMaRQM3JNUWHS8rL/+yaPGvMmvr5ywoGoxtkDWwQ+Pb89ycBeWfGSJeL/la+RS1eOPnRtbQKgMRjZg+t8x6PkP273nWQAoFOPAgaeAThKXAmXMrK39Kmr5fsuBlBqoXfJGLe3VbmHjG9Mczi9T//3h7vygXtcDlQtJg44iQiIjIBRbGPO7gghPJy0ZIxT2HOLIUgwxQzsgYrUR350HSIMaJLidhgKY+mw+pflBDrX8E7OGBjPCAPc76gQFSTqAIiYrb/8dRP4CyosJ/rmwU5XIxHMilt4QBJwsSkBMClxOQULBlkRRwEONmR2kJcDGjADX2/+xO8r5iqjExqmLyrWpcPFRta1BfAwCtyN3XpuJ4RgAAAABJRU5ErkJggg==" alt="IzzyOnDroid">](https://apt.izzysoft.de/packages/com.shiyunjin.easycontrolnext.app)
[<img src="https://shields.rbtlog.dev/simple/com.shiyunjin.easycontrolnext.app" alt="RB Status">](https://shields.rbtlog.dev/com.shiyunjin.easycontrolnext.app)

---

## 工作方式

```
┌──────────────────────────── 控制端 ────────────────────────────┐
│  Android（Compose）            HarmonyOS NEXT（ArkUI）          │
│  无线 ADB / USB ADB            无线 ADB（Rust libadb_core.so）  │
│  全屏 / 悬浮窗 / 迷你条         全屏会话（折叠屏自适应）          │
└───────────────────────────────┬────────────────────────────────┘
                                │ ADB（TCP / TLS）+ EasyControl 协议
                                ▼
                    被控 Android 设备（不安装独立 App）
                    推送 easycontrolnext_server.jar
                    app_process 启动画面 / 相机 / 虚拟屏捕获
```

| | 控制端 | 被控端 |
|---|---|---|
| **Android** | `easycontrolnext/` · `com.shiyunjin.easycontrolnext.app` | 同一台或另一台 Android 手机 / 平板 / TV |
| **HarmonyOS** | `harmonyos/` · `fun.saltedfish.easycontrol.next` | **仅 Android**（复用同一套 server JAR） |

两端共享设备模型、连接预设、无线配对语义与 server 启动参数；UI 栈与构建系统相互独立，请勿把鸿蒙模块放进 Android 工程。

---

## 功能一览

| 能力 | Android 控制端 | HarmonyOS 控制端 | 被控端要求 |
|---|:---:|:---:|---|
| 无线 ADB 连接 | ✓ | ✓ | 同一局域网 / 热点 |
| Android 11+ 配对码 | ✓ | ✓ | 开发者选项 → 无线调试 |
| 二维码配对 | ✓（控制端出示，被控机扫描） | ✓（控制端出示，被控机扫描） | 双方同一 Wi‑Fi |
| USB 有线 ADB | ✓ | — | USB 调试 |
| 全屏镜像与触控 | ✓ | ✓ | — |
| 悬浮窗 / 迷你条 | ✓ | — | 需悬浮窗权限 |
| 屏幕镜像 | ✓ | ✓ | — |
| 摄像头镜像 | ✓ | ✓ | Android 12+ |
| 单应用虚拟屏 | ✓ | ✓ | Android 11+ |
| 音频转接 | ✓ | ✓（Opus / AAC 硬件解码播放） | Android 12+ |
| H.264 | ✓ | ✓ | — |
| H.265 | ✓（默认） | ✓（默认；本机无 HEVC 时回退 H.264） | 双方解码器支持 |
| 剪贴板同步 | ✓ | ✓ | — |
| 返回 / 主页 / 多任务 / 电源 / 旋转 / 背光 | ✓ | ✓ | — |
| 连接预设（普通 / 相机 / 单应用） | ✓ | ✓ | — |
| 启动时自动连接 | ✓ | ✓ | — |
| 连接探测超时 | ✓ | ✓ | — |
| 错误日志 | ✓ | ✓ | — |
| 桌面服务卡片 | — | ✓（Form Kit 2×2 / 2×4） | — |
| 折叠屏 / 分屏自适应 | 宽屏主从布局 | 折叠姿态 + 分屏优先 | — |
| 中英语言切换 | ✓ | 跟随系统 | — |

---

## 系统要求

**控制端**

- **Android**：minSdk 23（Android 6+），建议 Android 9+。已在手机与部分 Android TV（如基于 Android 11 的 Philips TV）上验证。
- **HarmonyOS NEXT**：HarmonyOS 6.1.1 / API 24，设备类型 `phone` / `tablet` / `2in1`（折叠屏为一等公民）。

**被控端**

- Android 设备，并开启 **开发者选项**。
- 无线连接：Android 11+ 建议使用 **无线调试**（配对码或二维码）；旧设备可使用 `adb tcpip` 固定端口（常见 5555）。
- 相机镜像、音频转接：被控端 **Android 12+**。
- 单应用虚拟屏：被控端 **Android 11+**。

---

## 下载

[<img src="https://github.com/machiav3lli/oandbackupx/blob/034b226cea5c1b30eb4f6a6f313e4dadcbb0ece4/badge_github.png" alt="Get it on GitHub" height="80">](https://github.com/shiyunjin/EasyControlNext/releases/latest)
[<img src="https://gitlab.com/IzzyOnDroid/repo/-/raw/master/assets/IzzyOnDroid.png" alt="Get it on IzzyOnDroid" height="80">](https://apt.izzysoft.de/packages/com.shiyunjin.easycontrolnext.app)

- Android APK：GitHub Releases / IzzyOnDroid（包名 `com.shiyunjin.easycontrolnext.app`，当前版本 1.3.0）。
- HarmonyOS HAP：使用 DevEco Studio 自行编译本仓库 `harmonyos/`（见下方构建说明）。

与原 fork（`com.daitj.easycontrolfork`）可同时安装，互不影响。

---

## 使用说明

### 1. 被控端准备

1. 打开 **设置 → 关于手机**，连续点击版本号开启开发者选项。
2. 开启 **USB 调试**（有线）或 **无线调试**（无线）。
3. Android 11+ 无线调试：记下 **配对端口 / 配对码**，或使用 **二维码配对**。配对成功后，再使用 **连接端口**（与配对端口不是同一个）。

控制端与被控端需在同一局域网或同一热点。首次连接会请求授权本机 ADB 公钥。

### 2. 添加设备

1. 控制端主页点 **+** 添加设备。
2. 填写主机地址（IPv4 / IPv6 / 域名）。Android 端也可从局域网扫描结果点选填入。
3. 填写 **ADB 连接端口**（无线调试界面上的连接端口，不是配对端口）与 **Server 端口**（默认 `25166`）。
4. 首次无线调试：到「配对」分区输入配对端口与 6 位配对码，或让控制端出示二维码、被控机扫描。
5. 可选：应用连接预设、调整分辨率 / 帧率 / 码率 / H.265、开启音频、连接时唤醒或关背光等。
6. **保存** 或 **保存并连接**。

HarmonyOS 端名称可留空，首次探测成功后会用被控机型号自动填写。默认优先 H.265；本机没有 HEVC 硬件解码时，会话会自动回退 H.264。

### 3. 连接与会话

连接后，控制端会通过 ADB：

1. 探测地址与端口是否可达（超时可在设置中调整）。
2. 推送 `easycontrolnext_server.jar` 到 `/data/local/tmp/`。
3. 用 `app_process` 启动服务端，建立主通道 + 视频通道。
4. 解码画面并转发触控 / 按键 / 控制事件；若开启音频，再解码 Opus 或 AAC 并在本机播放。

**会话内常用操作**

- 导航：返回、主页、多任务。
- 电源、旋转、背光、音量。
- 剪贴板、通知栏、截图。
- 音频转接（会话内开关会重连，以便 server 重新握手）。
- 临时打开远端应用、摄像头镜像、单应用虚拟屏（管理菜单，仅本次连接）。

**Android 控制端额外**

- 全屏、悬浮小窗、迷你条三种窗口；可配置点外部自动最小化、异常挂起后复位。
- USB 插入后可作为有线设备连接。

**HarmonyOS 控制端额外**

- 会话始终全屏；折叠悬停为左控右画，展开宽屏为侧栏。
- 系统返回键可选择「发给被控端」或「退出控制页」。
- ADB 同步拉取远端文件（单文件 ≤ 32 MiB）到应用沙箱。
- 桌面可添加「设备列表」服务卡片，点按直达连接。
- 设置页可测试本机 H.264 / H.265 / Opus / AAC 硬件解码。

### 4. 连接预设

内置三类模板，可编辑、复制、设为默认；自定义预设可增删。

| 预设 | 用途 |
|---|---|
| 普通远程 | 整屏镜像 |
| 摄像头监控 | 被控端前后置相机（Android 12+） |
| 单应用 | 虚拟屏只镜像指定包名（Android 11+） |

- **默认预设**会填充并关联新建设备。
- 设备编辑页「应用预设」会写入并关联；管理页「应用预设」仅影响即将打开的这一次连接。
- 手动改动画面相关选项会解除关联（设备保留你改过的值）。修改预设时会询问是否同步已关联设备。

---

## 平台说明

### Android 控制端（`easycontrolnext/`）

Jetpack Compose + Material 3。主页在宽屏上为设备列表 + 详情；设置分为连接 / 通用 / 诊断 / 关于。

| 设置项 | 说明 |
|---|---|
| 连接预设 | 管理镜像配置 |
| 本机 IP | 查看并复制 IPv4 / IPv6 |
| 自定义 / 重置 ADB 密钥 | 查看或更换本机密钥对 |
| 连接探测超时 | 连接前 TCP 探测，超时立即失败 |
| 语言 | 中文 / English |
| 错误日志 | 筛选、复制、分享 |

设备级选项覆盖连接时、运行中、断开时：自定义分辨率、自适应分辨率、保持唤醒、关背光、锁定、自动重连、启动时连接等。**修改分辨率或熄屏超时可能影响车机、VR（如 Quest）等特殊设备**，见下方恢复命令。

### HarmonyOS 控制端（`harmonyos/`）

Stage 模型 ArkUI 应用。生产基线 **HarmonyOS 6.1.1 / API 24**。ADB 协议、配对 TLS、画面组帧与音频解码在 Rust 原生库 `libadb_core.so` 中实现，经 Node-API 供 ArkTS 调用。本机 ADB RSA 密钥一次生成，经 **HUKS AES-256-GCM** 封装存储。

当前相对 Android **不做**：

- USB ADB
- 悬浮窗 / 迷你条
- 后台音频（AVSession）；前台 Opus / AAC 转接已实现
- 把鸿蒙设备作为被控端

工程内开发约定与移植进度见 [`harmonyos/README.md`](harmonyos/README.md) 与 [`harmonyos/IMPLEMENTATION_PLAN.md`](harmonyos/IMPLEMENTATION_PLAN.md)。

---

## 注意事项

无线投屏会通过 ADB 调整被控端部分系统状态（唤醒超时、分辨率等）。在车机、VR 头显等设备上使用前请确认可恢复。

恢复屏幕分辨率：

```bash
adb shell wm size RESOLUTION_WIDTH x RESOLUTION_HEIGHT
```

恢复自动熄屏（示例：60 秒）：

```bash
adb shell settings put system screen_off_timeout 60000
```

Quest 3 出厂熄屏超时示例：

```bash
adb shell settings put system screen_off_timeout 86400000
```

连接建立后的媒体与控制流沿用现有 EasyControl **明文协议**，请仅在可信局域网使用。

---

## 仓库结构

```
EasyControlNext/
├── easycontrolnext/          # Android：控制端 App + 被控端 server
│   ├── app/                  # Compose 控制端
│   └── server/               # scrcpy 系 server → easycontrolnext_server.jar
├── harmonyos/                # HarmonyOS NEXT 控制端（独立工程）
│   ├── entry/                # ArkUI HAP
│   ├── native/               # Rust protocol / adb_client / adb_core
│   └── scripts/              # 宿主测试、.so 构建、拷贝 server JAR
├── LICENSE                   # GPLv3
└── README.md
```

---

## 构建

### Android

在 GNU/Linux 或 macOS：

```bash
cd easycontrolnext

# Debug
./gradlew assembleDebug -p server
./gradlew copyDebug -p server
./gradlew assembleDebug

# Release
./gradlew assembleRelease -p server
./gradlew copyRelease -p server
./gradlew assembleRelease
```

`copyDebug` / `copyRelease` 会把未签名的 server APK 复制为 App 资源 `app/src/main/res/raw/easycontrolnext_server.jar`。

### HarmonyOS

1. 安装 [DevEco Studio](https://developer.huawei.com/consumer/cn/deveco-studio/) 6.1.1（API 24）。
2. **File → Open** 选择 `harmonyos/`（含 `build-profile.json5`）。
3. 配置签名后运行到真机或模拟器。

本机还需 Rust（建议 1.88+）目标 `aarch64-unknown-linux-ohos`，以及 DevEco 自带 OHOS NDK：

```bash
cd harmonyos
export OHOS_NDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony

./scripts/run_host_tests.sh          # 协议 / ADB 客户端单元测试
./scripts/copy_server_jar.sh         # 从 Android Gradle 产物拷贝 server JAR
./scripts/build_native_ohos.sh       # 编译并暂存 libadb_core.so
./hvigorw assembleHap -p product=default
```

Assemble 会在打包前按需重编 native（`entry/hvigorfile.ts`）。若本机缺少 Rust/NDK 且已有暂存 `.so`：

```bash
SKIP_NATIVE_OHOS=1 ./hvigorw assembleHap
```

修改 Android `server` 后必须重新 `copy_server_jar.sh`，否则 HAP 仍使用旧 JAR。

---

## 控制端对 server 使用的 ADB 命令

应用通过 ADB 执行的操作包括：

- 保持唤醒：`settings put system screen_off_timeout 600000000`
- 修改分辨率：`wm size`
- 锁屏后状态：`dumpsys deviceidle`
- 显示器信息：`dumpsys display`

启动 server：

1. 删除已有 `/data/local/tmp/easycontrolnext_*`
2. 推送 `easycontrolnext_server.jar`
3. 以 `app_process` 启动，参数示例：

```
app_process -Djava.class.path=<server> / com.shiyunjin.easycontrolnext.server.Server
  serverPort=… listenClip=… isAudio=… maxSize=… maxFps=… maxVideoBit=…
  keepAwake=… supportH265=… supportOpus=… startApp=…
```

单应用模式额外使用：

```
monkey -p <package> -c android.intent.category.LAUNCHER 1
am display move-stack <appStackId> <displayId>
```

---

## 致谢

- [Scrcpy](https://github.com/Genymobile/scrcpy)
- [libadb-android](https://github.com/MuntashirAkon/libadb-android)
- [ADB protocol description](https://github.com/cstyan/adbDocumentation)（官方文档不易读，感谢 cstyan）
- 原作者 [mingzhixian/Easycontrol](https://github.com/mingzhixian/Easycontrol)、[daitj/Easycontrol](https://github.com/daitj/easycontrol)

## 许可

[GNU General Public License v3.0](LICENSE)
