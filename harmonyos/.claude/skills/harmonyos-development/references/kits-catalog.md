# HarmonyOS Kits Catalog and Samples

## HarmonyOS Kits (common imports)

```ts
import { UIAbility, Want, common, abilityAccessCtrl } from '@kit.AbilityKit';
import { window, display, promptAction } from '@kit.ArkUI';
import { http, webSocket, connection } from '@kit.NetworkKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';   // photo/video picker
import { fileIo as fs } from '@kit.CoreFileKit';
import { geoLocationManager } from '@kit.LocationKit';
import { relationalStore, preferences, distributedKVStore } from '@kit.ArkData';
import { notificationManager } from '@kit.NotificationKit';
import { speechRecognizer } from '@kit.CoreSpeechKit';       // ASR / TTS
import { hilog } from '@kit.PerformanceAnalysisKit';
```

### Full Kit catalog — official SDK categories (developer.huawei.com/consumer/cn/sdk/)

**应用框架 Application Framework**

| Kit | Import key | Purpose |
|---|---|---|
| Ability Kit | `AbilityKit` | UIAbility, ExtensionAbility, Want, context, routing |
| Accessibility Kit | `AccessibilityKit` | Screen reader, universal design, a11y services |
| ArkData | `ArkData` | relationalStore, preferences, distributedKVStore |
| ArkTS | — | Language spec & Ark compiler tooling |
| ArkUI | `ArkUI` | window, display, promptAction, Navigation, components |
| ArkWeb | `ArkWeb` | WebView / Web component embedding |
| Background Tasks Kit | `BackgroundTasksKit` | Deferred/scheduled background work, transient tasks |
| Core File Kit | `CoreFileKit` | fileIo, picker, sandbox paths |
| Form Kit | `FormKit` | FormExtensionAbility, home-screen service cards/widgets |
| IME Kit | `IMEKit` | Input method engine development |
| IPC Kit | `IPCKit` | Inter-process communication (Parcel, RemoteObject) |
| Localization Kit | `LocalizationKit` | i18n, l10n, RTL, pseudo-localization |

**应用服务 Application Services**

| Kit | Import key | Purpose |
|---|---|---|
| Account Kit | `AccountKit` | One-click Huawei ID login, OAuth 2.0 |
| Ads Kit | `AdsKit` | Advertising SDK (banner, native, interstitial) |
| App Linking Kit | `AppLinkingKit` | Deep links, deferred deep links |
| Calendar Kit | `CalendarKit` | Calendar events, reminders |
| Contacts Kit | `ContactsKit` | Contact read/write/search |
| Content Embed Kit | `ContentEmbedKit` | Cross-app document embedding and collaborative editing |
| IAP Kit | `IAPKit` | In-app purchases (consumable, non-consumable, subscription) |
| Live View Kit | `LiveViewKit` | Live activities on lock screen / notification center |
| Location Kit | `LocationKit` | geoLocationManager, geofencing, geocoding |
| Map Kit | `MapKit` | Huawei Maps SDK, routing, place search |
| Notification Kit | `NotificationKit` | Local + push notifications, badges |
| Payment Kit | `PaymentKit` | Huawei Pay transaction processing |
| Push Kit | `PushKit` | Push notification delivery service |
| Scan Kit | `ScanKit` | QR/barcode scanning |
| Share Kit | `ShareKit` | Cross-app content sharing |
| Call Service Kit | `CallServiceKit` | Enterprise call identification and service lookup |
| Weather Service Kit | `WeatherServiceKit` | Weather data (current/daily/hourly/alerts/indices/tides) |
| Pen Kit | `Penkit` | Stylus / handwriting component (M-Pencil devices) |
| Wear Engine | `WearEngine` | Phone↔watch communication, device discovery |
| Health Service Kit | `HealthServiceKit` | Health data services |

**系统 System**

| Kit | Import key | Purpose |
|---|---|---|
| Asset Store Kit | `AssetStoreKit` | Secure credential/secret storage |
| Basic Services Kit | `BasicServicesKit` | Battery, vibration, thermal, brightness, clipboard |
| Connectivity Kit | `ConnectivityKit` | Bluetooth, Wi-Fi, NFC, USB, hotspot |
| Crypto Architecture Kit | `CryptoArchitectureKit` | Encryption, key management, certificates |
| Device Security Kit | `DeviceSecurityKit` | Code-signature queries, digital shield, security events |
| Distributed Service Kit | `DistributedServiceKit` | deviceManager, cross-device discovery |
| Enterprise Threat Protection Kit | `EnterpriseThreatProtectionKit` | Enterprise file threat scan, isolation, restore, delete |
| MDM Kit | `MDMKit` | Enterprise device, app, and settings management |
| Network Boost Kit | `NetworkBoostKit` | Network transfer optimization and low-power transfer mode |
| NearLink Kit | `NearLinkKit` | NearLink device capability and partner device management |
| Screen Time Guard Kit | `ScreenTimeGuardKit` | Screen-time authorization and app-control policy |

**媒体 Media**

| Kit | Import key | Purpose |
|---|---|---|
| Audio Kit | `AudioKit` | Audio playback, recording, routing, focus |
| AVCodec Kit | `AVCodecKit` | Hardware-accelerated encode/decode (H.264, H.265, AAC…) |
| Camera Kit | `CameraKit` | Camera preview, photo capture, video recording |
| Image Kit | `ImageKit` | Image decoding, transformation, EXIF |
| Media Kit | `MediaKit` | AVPlayer, AVRecorder (unified playback/recording) |
| Media Library Kit | `MediaLibraryKit` | photoAccessHelper, media library CRUD |
| Scan Kit | `ScanKit` | QR/barcode scanning |

**图形 Graphics**

| Kit | Import key | Purpose |
|---|---|---|
| ArkGraphics 2D | `ArkGraphics2D` | 2D Canvas drawing, effects, blur, shadow |
| ArkGraphics 3D | `ArkGraphics3D` | 3D scene graph, glTF rendering |
| UI Design Kit | `UIDesignKit` | `hdsDrawable` icon processing, `HdsNavigation` component |
| XComponent | (ArkUI built-in) | Native OpenGL ES / Vulkan surface via NAPI |

**AI**

| Kit | Import key | Purpose |
|---|---|---|
| Core Speech Kit | `CoreSpeechKit` | On-device ASR / TTS engine |
| Core Vision Kit | `CoreVisionKit` | OCR, face detection, image segmentation, super-resolution |
| CANN Kit | `CANNKit` | AI compute acceleration; API 24 adds PC LLM inference support |
| FAST Kit | `FASTKit` | Concurrent hash tables, vector operations, filters |
| Intents Kit | `IntentsKit` | Intent recognition (30+ domains, 60+ built-in intents) |
| MindSpore Lite | `MindSporeLiteKit` | Edge model inference (Caffe/TF/ONNX/MindIR) |
| Natural Language Kit | `NaturalLanguageKit` | Word segmentation, NER, keyword extraction |

**Performance & DevTools**

| Kit | Import key | Purpose |
|---|---|---|
| Performance Analysis Kit | `PerformanceAnalysisKit` | hilog, HiAppEvent, crash analysis |

## Official sample projects (GitCode)

430+ open-source HarmonyOS samples at `https://gitcode.com/HarmonyOS_Samples/<name>`. Key projects by category:

### Audio & Video
- **AVCodecVideo** — Video playback/recording via AVCodec (H.264/H.265, AudioVivid)
- **AdaptiveVideo** — Short video immersive & rotation playback
- **AudioCast** — Audio casting to external devices
- **AudioToVideoSync** — Audio-video synchronization
- **DecodePlayControl** — Surface-mode video playback control
- **PlayShortVideosBasedOnVideoComponent** — Short video player (progress bar, fullscreen, speed, autoplay)
- **SmoothSwitchShortVideos** — Smooth short video switching with preloading
- **MusicHome** — Adaptive music album app (one-time dev, multi-device)
- **MusicCard** — Music service widget via Form Kit
- **NetAdaptiveVideoStream** — Adaptive bitrate video streaming
- **HMOS_LiveStream** — Live streaming (broadcaster + viewer)
- **UseAVTranscoderVideo** — Video transcoding
- **SwipePlayer** — Swipe-to-switch video player
- **VideoCast** — Video casting to external devices

### Camera & Image
- **CustomCamera** — Camera Kit: preview, flash, focus, exposure, front/back switch
- **ImageGetAndSave** — Image acquisition and saving
- **PicturePreview** — Image preview with zoom and swipe
- **PixelMapImageEdit** — Image editing via PixelMap encode/decode
- **SmartPhotoPicker** — Photo recommendation via PhotoPicker
- **MultiPictureBeautification** — Multi-device image beautification
- **LongSnapshotPractice** — Long screenshot implementation
- **MultipleImage** — Multi-image carousel with Swiper
- **ImageToVideo** — Compositing images into video
- **CoreVisionKitOCR** — OCR-based text auto-fill

### UI Components & Layout
- **CommonListFlows** — Common list scenarios with List component
- **ListScrollComponent** — Scrollable list with lazy loading
- **GridScrollComponent** — Grid scroll with performance optimization
- **WaterFlowScrollComponent** — Waterfall flow layout
- **SwiperPerformance** — Swiper performance optimization
- **ComponentEncapsulation** — Component encapsulation patterns
- **CommentReply** — Comment reply with RichEditor (text, emoji, @mention)
- **DialogHub** — Universal dialog library
- **CustomizeKeyboard** — Custom keyboard implementation
- **DragFramework** — Drag-and-drop for images, rich text, lists
- **TextExpand** — Expandable/collapsible text
- **PureTabs** — Tab-based navigation UI
- **FoldedHover** — Foldable device hover mode
- **CardInfoRefresh** — Service widget creation, interaction & refresh (Form Kit)
- **PageFlip** — Page turning effects
- **ResponsiveLayout** — Responsive layout for multiple device types
- **Immersive** — Immersive full-screen UI

### App Architecture & Navigation
- **AppLifecycleManagement** — App lifecycle state management
- **AppStartUp** — Startup task initialization (AppStartup)
- **StageModelContext** — Stage model context usage
- **HMRouter** — HMRouter-based page navigation
- **NavigationSettings** — Settings app with Navigation (small/large window)
- **JumpBetweenApps** — App-to-app jumping via App Linking
- **CrossModuleReference** — Native HAR/HSP module cross-reference
- **CrossModuleResourceAccess** — Cross-module resource access ($r, resourceManager)
- **DynamicComponent** — Dynamic component creation
- **DesktopShortcut** — Desktop shortcut entry via module.json5
- **EmebedAbility** — Embedded atomic service via FullScreenLaunchComponent

### Data & Storage
- **KVStore** — Key-value database read/write
- **DatabaseReadWrite** — Relational database via C-API
- **DataCache** — Cold start acceleration with data caching
- **BackupRestore** — Data migration via backup/restore framework
- **GenerateSandboxFile** — Sandbox file generation
- **NativeFileIO** — Native-side file read/write
- **NativeFileAccess** — Native-side file access
- **TurboTransJSON** — High-performance JSON serialization (turbo_trans)

### Network & Communication
- **NetworkReconnection** — App network reconnection
- **NetBoost** — Multi-network concurrency for acceleration
- **RcpFileTransfer** — File upload/download via Remote Communication Kit
- **RemoteCommunicationPlatform** — RCP network requests (forms, certificates, DNS)
- **WebCrossDomain** — Web cross-domain via ArkWeb interceptor & cookies
- **MultiWeb** — Responsive multi-Web layout
- **OnlineEditorCollaboration** — Online document editing with cross-device collaboration

### Security & Auth
- **UserAuth** — Face/fingerprint auth + password vault auto-fill
- **PermissionApplication** — Permission request flow
- **AntiPeep** — Sensitive information anti-peep protection
- **UniversalKeystoreCollection** — HUKS key management (encrypt/decrypt, sign/verify)
- **DigitalShield** — Biometric authentication for transactions
- **DeviceSecurityKit_sampleCode_SafetyDetectDemo_ArkTS** — Device environment & URL safety detection

### AI & ML
- **MindSporeLiteArkTS** — On-device image classification (MindSpore Lite ArkTS API)
- **MindSporeLiteCpp** — On-device image classification (MindSpore Lite C++ API)
- **MSLiteHumanSegmentation** — On-device human segmentation
- **MSLiteSceneRecognition** — On-device scene detection
- **MSLiteStyleTransform** — On-device image style transfer
- **RAG_QA** — RAG-based Q&A with on-device knowledge processing

### Multi-Device & Wearable
- **MultiDeviceCamera** — Camera on phone, foldable, tablet with preview rotation
- **MultiDeviceCommunication** — One-time dev, multi-device IM app
- **Phone_Connection** — Phone-watch communication & heart rate monitoring
- **SmartWatchCarControl** — Watch car control app
- **SmartWatchMap** — Watch map app
- **SmartWatchTakeTaxi** — Watch taxi app
- **WearableBus** — Watch bus transit app
- **WearableMusic** — Watch music app
- **APILevelAdapt** — Multi-API version compatibility (ArkTS + Native)

### Concurrency & Performance
- **UseTaskPool** — Multi-threaded tasks via TaskPool
- **UseSendable** — Sendable cross-thread communication & UI refresh
- **MultiThreadIO** — Database & file I/O with TaskPool + @Sendable
- **NativeSubMainThreadCommunication** — Native sub-thread to UI main-thread communication
- **FunctionFlowRuntimeKit-SampleCode-ConcurrentQueue** — FFRT concurrent queue
- **FunctionFlowRuntimeKit-SampleCode-TaskGraph** — FFRT task graph dependencies
- **UtilizeHWCEfficiently** — Low-power HWC composition

### System & Platform
- **BackTaskImplement** — Background tasks for app continuity
- **LiveViewLockScreen** — Lock screen live view
- **IntentsKitGameRevisit** — Intent-based game revisit recommendations
- **ContinuePublish** — Cross-device content publishing (app continuation)
- **HiTraceMeterPrefTag** — Performance tracing with HiTraceMeter
- **ObtainingDeviceID** — Device identifier retrieval
- **BluetoothLowEnergy** — BLE device connection & communication
- **NFCTag** — NFC-based app launch
- **QueryAppPackageInfo** — App package info query
- **SystemEnvVarSubscriber** — System environment variable subscription
- **DesktopExtensionKit-samplecode** — Status bar integration via Desktop Extension Kit

### Graphics & 3D
- **Graphics3D** — 3D engine API usage
- **DocsSample_XComponent** — XComponent self-rendering & AI analysis
- **DocsSample_Graphics** — Graphics subsystem samples

### Web & Hybrid
- **H5Launch** — H5 cold start acceleration
- **ExecutingJSWithJSVM** — JSVM-API: create engines, execute JS, destroy
- **DocsSample_ArkWeb** — ArkWeb component samples
- **SmallWindowScene** — Small window (floating) scenario

> Full catalog: `https://gitcode.com/HarmonyOS_Samples` — clone any sample with `git clone https://gitcode.com/HarmonyOS_Samples/<name>.git`
