# Network, ArkWeb, App Linking, and Share

### HTTP request example

```ts
import { http } from '@kit.NetworkKit';

async function fetchJson(url: string): Promise<string> {
  const req = http.createHttp();
  try {
    const res = await req.request(url, {
      method: http.RequestMethod.GET,
      header: { 'Content-Type': 'application/json' },
      connectTimeout: 5000, readTimeout: 10000
    });
    return res.result as string;
  } finally {
    req.destroy();
  }
}
```

### Network connectivity monitoring

```ts
import { connection } from '@kit.NetworkKit';

// Check current network state
const hasNet = connection.hasDefaultNetSync();

// Monitor network changes
const netCon = connection.createNetConnection();
netCon.on('netAvailable', () => { /* network restored */ });
netCon.on('netLost', () => { /* network lost */ });
netCon.on('netCapabilitiesChange', (info: connection.NetCapabilityInfo) => {
  const isWifi = info.netCap.bearerTypes.includes(connection.NetBearType.BEARER_WIFI);
  const isCellular = info.netCap.bearerTypes.includes(connection.NetBearType.BEARER_CELLULAR);
});
netCon.register(() => {});  // activate subscriptions

// Cleanup
netCon.unregister(() => {});
```

### WebSocket

```ts
import { webSocket } from '@kit.NetworkKit';

const ws = webSocket.createWebSocket();
ws.on('open', () => { ws.send('hello'); });
ws.on('message', (err, data: string | ArrayBuffer) => {
  console.info('received:', typeof data === 'string' ? data : 'binary');
});
ws.on('close', (err, { code, reason }) => { /* closed */ });
ws.on('error', (err) => { /* handle */ });

ws.connect('wss://example.com/ws', { header: { 'Authorization': 'Bearer xxx' } });

// Send
ws.send(JSON.stringify({ type: 'chat', text: 'hi' }));

// Close
ws.close();
```

### Launch app by type (startAbilityByType)

```ts
import { common } from '@kit.AbilityKit';

const context = getContext(this) as common.UIAbilityContext;

// Open navigation app with destination
context.startAbilityByType('navigation', {
  sceneType: 1,
  destinationLatitude: 39.9042,
  destinationLongitude: 116.4074,
  destinationName: 'Beijing',
} as Record<string, Object>);

// Open browser
context.startAbilityByType('browser', {
  uri: 'https://example.com',
} as Record<string, Object>);
```

Supported types: `navigation`, `browser`, `email`, `finance`, `transit`, etc.

## ArkWeb — Web component

Embed web content in ArkTS via the `Web` component from `@kit.ArkWeb`.

```ts
import { webview } from '@kit.ArkWeb';

@Entry
@Component
struct BrowserPage {
  controller: webview.WebviewController = new webview.WebviewController();

  build() {
    Column() {
      Web({ src: 'https://example.com', controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(true)
        .onPageBegin((event) => { console.log('loading:', event?.url); })
        .onPageEnd((event) => { console.log('loaded:', event?.url); })
        .onErrorReceive((event) => { console.error('web error:', event?.error.getErrorInfo()); })
        .darkMode(WebDarkMode.Auto)   // follow system dark mode
        .forceDarkAccess(true)
    }
  }
}
```

### JS ↔ ArkTS bridge (`javaScriptProxy`)

```ts
// Register ArkTS object callable from JS
Web({ src: 'https://example.com', controller: this.controller })
  .javaScriptProxy({
    object: {
      callNative: (msg: string) => {
        console.log('from JS:', msg);
        return 'ArkTS received: ' + msg;
      }
    },
    name: 'NativeBridge',
    methodList: ['callNative'],
    controller: this.controller
  })
// In the web page: window.NativeBridge.callNative('hello');

// Call JS from ArkTS
this.controller.runJavaScript('window.updateUI("data")', (err, result) => {
  console.log('JS result:', result);
});
```

### Custom User-Agent and cookies

```ts
// Append to default UA
webview.WebviewController.setCustomUserAgent(
  webview.WebviewController.getDefaultUserAgent() + ' MyApp/1.0'
);

// Manage cookies
import { webCookie } from '@kit.ArkWeb';
webCookie.setCookie('https://example.com', 'token=abc; path=/');
webCookie.saveCookieAsync();   // persist to disk
```

### Intercept resource requests

```ts
Web({ src: '...', controller: this.controller })
  .onInterceptRequest((event) => {
    if (event?.request.getRequestUrl().includes('/api/')) {
      // Return custom response
      const resp = new WebResourceResponse();
      resp.setResponseData('{"intercepted":true}');
      resp.setResponseMimeType('application/json');
      resp.setResponseEncoding('utf-8');
      resp.setResponseCode(200);
      resp.setReasonMessage('OK');
      return resp;
    }
    return null;  // null = load normally
  })
```

## App Linking — deep links & app-to-app navigation

### Configure deep link in module.json5

```json5
{
  "module": {
    "abilities": [{
      "name": "EntryAbility",
      "skills": [{
        "entities": ["entity.system.home", "entity.system.browsable"],
        "actions": ["ohos.want.action.home", "ohos.want.action.viewData"],
        "uris": [{ "scheme": "https", "host": "example.com", "path": "/detail" }],
        "domainVerify": true       // enable App Linking verification
      }]
    }]
  }
}
```

### Handle incoming link — cold start (onCreate)

```ts
import { url } from '@kit.ArkTS';

export default class EntryAbility extends UIAbility {
  private targetPage: string = '';
  private linkParams: Record<string, string> = {};

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.parseUri(want);
  }

  private parseUri(want: Want): void {
    if (want?.uri) {
      const urlObj = url.URL.parseURL(want.uri);
      this.linkParams = Object.fromEntries(urlObj.params.entries());
      this.targetPage = urlObj.pathname;        // e.g. "/detail"
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    const page = this.targetPage === '/detail' ? 'pages/Detail' : 'pages/Index';
    if (this.linkParams['id']) {
      AppStorage.setOrCreate('linkId', this.linkParams['id']);
    }
    windowStage.loadContent(page);
  }
}
```

### Handle link — app already running (onNewWant)

```ts
onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
  this.parseUri(want);
  if (this.linkParams['id']) {
    AppStorage.setOrCreate('linkId', this.linkParams['id']);
    AppStorage.setOrCreate('newWantFlag', true);   // notify UI to navigate
  }
}
```

Page listens for `newWantFlag` via `@StorageLink` + `@Watch` and navigates accordingly.

## Share Kit — cross-app content sharing

```ts
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';

// Share a hyperlink
const shareData = new systemShare.SharedData({
  utd: uniformTypeDescriptor.UniformDataType.HYPERLINK,
  content: 'https://example.com/article/123',
  title: 'Article Title',
  description: 'Article preview text',
});
const controller = new systemShare.ShareController(shareData);
controller.show(this.context, {
  previewMode: systemShare.SharePreviewMode.DEFAULT,
  selectionMode: systemShare.SelectionMode.SINGLE,
});
```

Supported UTD types: `HYPERLINK`, `PLAIN_TEXT`, `HTML`, `IMAGE` (pass `uri` from file), `FILE`.

## Background upload & download (request.agent)

```ts
import { request } from '@kit.BasicServicesKit';
```

### Background upload (supports pause/resume)

```ts
const config: request.agent.Config = {
  action: request.agent.Action.UPLOAD,
  url: 'https://example.com/upload',
  mode: request.agent.Mode.BACKGROUND,
  method: 'POST',
  data: formItems,                       // Array of FormItem
};
const task = await request.agent.create(context, config);
task.on('progress', (progress) => { /* track */ });
task.on('completed', (progress) => { /* done */ });
await task.start();
await task.pause();    // pause
await task.resume();   // resume with breakpoint
```

### Background download (auto breakpoint resume)

```ts
const config: request.agent.Config = {
  action: request.agent.Action.DOWNLOAD,
  url: 'https://example.com/file.zip',
  mode: request.agent.Mode.BACKGROUND,
  saveas: `./downloads/file.zip`,
  overwrite: true,
  gauge: true,
};
const task = await request.agent.create(context, config);
task.on('progress', (progress) => { /* track */ });
await task.start();
```
