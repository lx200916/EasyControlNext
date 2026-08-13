# Account, Push, Payment, Map, Location, Notification, Form

## Location Kit (geoLocationManager)

```ts
import { geoLocationManager } from '@kit.LocationKit'

// Permission required: ohos.permission.APPROXIMATELY_LOCATION (user_grant)
// module.json5: reason + usedScene required

const pos = await geoLocationManager.getCurrentLocation({
  priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
  scenario: geoLocationManager.LocationRequestScenario.UNSET,
  timeoutMs: 10000
})

const addresses = await geoLocationManager.getAddressesFromLocation({
  latitude: pos.latitude,
  longitude: pos.longitude,
  maxItems: 1
})

// Build readable location string from GeoAddress fields:
// administrativeArea (省) → subAdministrativeArea (市) → locality (区) → subLocality → placeName
```

## Weather Service Kit — weather data API

> Requires `ohos.permission.LOCATION` (or `APPROXIMATELY_LOCATION`) if using device location.

```ts
import { weatherService } from '@kit.WeatherServiceKit';

const weatherRequest: weatherService.WeatherRequest = {
  location: { latitude: 39.9042, longitude: 116.4074 },   // Beijing
  limitedDatasets: [
    weatherService.Dataset.CURRENT,    // current conditions
    weatherService.Dataset.DAILY,      // daily forecast
    weatherService.Dataset.HOURLY,     // hourly forecast
    weatherService.Dataset.ALERTS,     // severe weather alerts
    weatherService.Dataset.INDICES,    // life indices (UV, air quality...)
    weatherService.Dataset.TIDES,      // coastal tides
    weatherService.Dataset.MINUTE,     // minute-level precipitation
  ],
};

try {
  const weather = await weatherService.getWeather(weatherRequest);
  // weather.currentWeather.temperature, .humidity, .conditionCode, ...
  // weather.dailyForecast?.days[] (each: tempMax/tempMin/precipitation/sunrise/sunset)
  // weather.hourlyForecast?.hours[]
  // weather.weatherAlerts?.alerts[] (severity, summary)
} catch (err) {
  console.error('Weather fetch failed:', err);
}
```

## Notification Kit (notificationManager)

```ts
import { notificationManager } from '@kit.NotificationKit'

// 1. Create slot (call once at app init)
await notificationManager.addSlot(notificationManager.SlotType.SOCIAL_COMMUNICATION)

// 2. Check and request notification enable
const enabled = await notificationManager.isNotificationEnabled()
if (!enabled) await notificationManager.requestEnableNotification()  // deprecated but functional

// 3. Publish
const request: notificationManager.NotificationRequest = {
  id: 1001,
  // OMIT slotType — see API 21 type mismatch note above
  content: {
    notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
    normal: { title: '标题', text: '正文', additionalText: '副文本' }
  },
  deliveryTime: Date.now(),
  showDeliveryTime: true,
  tapDismissed: true
}
await notificationManager.publish(request)

// 4. Cancel
await notificationManager.cancel(1001)
```

## Form Kit — ArkTS service cards (服务卡片)

Service cards run in a sandboxed FormExtensionAbility process; they use a subset of ArkUI.

### FormExtensionAbility lifecycle

```ts
// entry/src/main/ets/formextensionability/EntryFormAbility.ets
import { FormExtensionAbility, formBindingData, FormInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want) {
    // Called when user adds card to home screen
    const formData = { title: 'Hello', count: 0 };
    return formBindingData.createFormBindingData(formData);
  }

  onCastToNormalForm(formId: string) { }

  onUpdateForm(formId: string) {
    // Periodic/requested update
    const data = formBindingData.createFormBindingData({ count: Date.now() });
    formProvider.updateForm(formId, data);
  }

  onRemoveForm(formId: string) { }

  onFormEvent(formId: string, message: string) {
    // Triggered by postCardAction in the card UI
    console.log('card event:', formId, message);
  }
}
```

### Card UI (`EntryFormAbility/pages/Card.ets`)

```ts
// Cards are ArkUI components but with restricted APIs (no @State mutation from events)
// Use postCardAction to route events back to FormExtensionAbility
@Entry
@Component
struct CardPage {
  @LocalStorageProp('title') title: string = '';
  @LocalStorageProp('count') count: number = 0;

  build() {
    Column({ space: 8 }) {
      Text(this.title).fontSize(16).fontWeight(FontWeight.Bold)
      Text(`Count: ${this.count}`).fontSize(14)
      Button('+1')
        .onClick(() => {
          postCardAction(this, {
            action: 'message',
            params: { event: 'increment' }
          });
        })
    }.padding(12)
  }
}
```

### `module.json5` — declare the form

```json5
{
  "extensionAbilities": [{
    "name": "EntryFormAbility",
    "srcEntry": "./ets/formextensionability/EntryFormAbility.ets",
    "type": "form",
    "metadata": [{
      "name": "ohos.extension.form",
      "resource": "$profile:form_config"
    }]
  }]
}
```

### `resources/base/profile/form_config.json`

```json
{
  "forms": [{
    "name": "widget",
    "displayName": "$string:widget_display_name",
    "description": "$string:widget_desc",
    "src": "./ets/formextensionability/pages/Card.ets",
    "uiSyntax": "arkts",
    "window": { "designWidth": 720, "autoDesignWidth": true },
    "colorMode": "auto",
    "isDynamic": true,
    "updateEnabled": true,
    "scheduledUpdateTime": "10:30",
    "updateDuration": 1,
    "defaultDimension": "2*2",
    "supportDimensions": ["1*2", "2*2", "2*4"]
  }]
}
```

## Map Kit — MapComponent

```ts
import { mapCommon, map } from '@kit.MapKit';
import { AsyncCallback } from '@kit.BasicServicesKit';

@Entry
@Component
struct MapPage {
  private mapOptions: mapCommon.MapOptions = {
    position: {
      target: { latitude: 39.9042, longitude: 116.4074 },  // Beijing
      zoom: 12
    }
  };
  private mapController?: map.MapComponentController;

  build() {
    Column() {
      MapComponent({
        mapOptions: this.mapOptions,
        mapCallback: (err, controller) => {
          if (!err) {
            this.mapController = controller;
            this.addMarker();
          }
        }
      }).width('100%').layoutWeight(1)
    }
  }

  private addMarker() {
    this.mapController?.addMarker({
      position: { latitude: 39.9042, longitude: 116.4074 },
      title: 'Tiananmen',
      snippet: 'Beijing city center'
    });
  }
}
```

Required permissions in `module.json5`: `ohos.permission.LOCATION` and `ohos.permission.APPROXIMATELY_LOCATION`.

## Account Kit — Huawei ID login

### Configure Client ID in `module.json5`

```json5
{
  "module": {
    "name": "entry",
    "type": "entry",
    "metadata": [{
      "name": "client_id",
      "value": "YOUR_CLIENT_ID"  // from AGC console
    }]
  }
}
```

### One-click login (enterprise developers, non-game apps)

Retrieves phone number + UnionID in a single tap. Requires manual signing + AGC permission approval.

```ts
import { authentication } from '@kit.AccountKit';
import { util } from '@kit.ArkTS';

// Step 1: Get anonymous phone number (for display on login page)
const authRequest = new authentication.HuaweiIDProvider().createAuthorizationWithHuaweiIDRequest();
authRequest.scopes = ['quickLoginAnonymousPhone'];
authRequest.state = util.generateRandomUUID();
authRequest.forceAuthorization = false;  // must be false for one-click login

const controller = new authentication.AuthenticationController();
const response = await controller.executeRequest(authRequest);
const anonymousPhone = response.data?.extraInfo?.quickLoginAnonymousPhone as string;
// Display anonymousPhone on login page, e.g. "188****1234"
```

```ts
// Step 2: Show LoginWithHuaweiIDButton — user taps to get Authorization Code
import { loginComponentManager, LoginWithHuaweiIDButton } from '@kit.AccountKit';

LoginWithHuaweiIDButton({
  params: {
    style: loginComponentManager.Style.BUTTON_RED,
    borderRadius: 24,
    loginType: loginComponentManager.LoginType.QUICK_LOGIN,  // one-click login
    supportDarkMode: true
  },
  controller: this.controller  // LoginWithHuaweiIDButtonController
})

// In controller callback: response.authorizationCode → send to server
// Server calls /oauth2/v6/quickLogin/getPhoneNumber to get full phone + UnionID
```

**Obfuscation whitelist** — if property obfuscation is enabled, add to `obfuscation-rules.txt`:
```
-keep-property-name
quickLoginAnonymousPhone
```

### Huawei Account login (all developers)

Retrieves UnionID/OpenID via `LoginWithHuaweiIDButton` or API. Supports enterprise + individual developers.

```ts
// Using LoginWithHuaweiIDButton component (recommended)
LoginWithHuaweiIDButton({
  params: {
    style: loginComponentManager.Style.BUTTON_RED,
    borderRadius: 24,
    loginType: loginComponentManager.LoginType.ID,  // standard login
    supportDarkMode: true
  },
  controller: this.controller
})
// callback returns authorizationCode → server exchanges for UnionID/OpenID
```

```ts
// Using custom button with API
import { authentication } from '@kit.AccountKit';

const loginRequest = new authentication.HuaweiIDProvider().createLoginWithHuaweiIDRequest();
loginRequest.forceLogin = true;  // true = show login page if not logged in
loginRequest.state = util.generateRandomUUID();

const controller = new authentication.AuthenticationController(getContext(this));
const response = await controller.executeRequest(loginRequest);
const authCode = response.data?.authorizationCode;
// Send authCode to server → server gets UnionID/OpenID via Access Token
```

### Silent login

No user interaction — retrieves UnionID for returning users (reinstall, device switch).

```ts
const loginRequest = new authentication.HuaweiIDProvider().createLoginWithHuaweiIDRequest();
loginRequest.forceLogin = false;  // false = silent, no UI if not logged in
loginRequest.state = util.generateRandomUUID();

const controller = new authentication.AuthenticationController();
const response = await controller.executeRequest(loginRequest);
const authCode = response.data?.authorizationCode;
// If error.code === 1001502001 → user not logged in, show other login methods
```

### Common error codes

| Code | Meaning | Action |
|---|---|---|
| `1001502001` | Huawei Account not logged in | Show other login methods |
| `1001502005` | Network error | Retry or show other methods |
| `1001502012` | User cancelled | No action needed |
| `1001500001` | Certificate fingerprint check failed | Check signing config |
| `1001502014` | Missing scopes/permissions | Check AGC permission approval |
| `1005300001` | User did not agree to protocol | Show agreement dialog |

### Key concepts

| ID type | Scope | Use case |
|---|---|---|
| **OpenID** | Per-app unique | Identify user within one app |
| **UnionID** | Per-developer unique | Identify user across multiple apps by same developer |
| **GroupUnionID** | Per-account-group unique | Identify user across affiliated developers |

For cross-platform user data continuity, prefer **UnionID** over OpenID.

## App continuation (应用接续) — cross-device migration

Enable cross-device task handoff: migrate UIAbility state from device A to device B.

### Enable continuation in `module.json5`

```json5
{
  "module": {
    "abilities": [{
      "name": "EntryAbility",
      "continuable": true   // enable cross-device migration
    }]
  }
}
```

### Source device — save migration data

```ts
// In UIAbility
onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
  // Save data to migrate (keep under 100KB, use distributed data object for larger data)
  wantParam['currentPage'] = 'DetailPage';
  wantParam['articleId'] = this.articleId;

  // Check target app version compatibility
  const targetVersion = wantParam['version'] as number;
  if (targetVersion < 2) {
    return AbilityConstant.OnContinueResult.MISMATCH;
  }

  return AbilityConstant.OnContinueResult.AGREE;
}
```

### Target device — restore data

```ts
// Cold start
onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
  if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
    // Restore migrated data
    this.articleId = want.parameters?.['articleId'] as number;
    // Restore page stack
    this.context.restoreWindowStage(this.storage);
  }
}

// Hot start (single-instance)
onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam) {
  if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
    this.articleId = want.parameters?.['articleId'] as number;
    this.context.restoreWindowStage(this.storage);
  }
}
```

### Dynamic migration control

```ts
// Disable migration on certain pages
this.context.setMissionContinueState(AbilityConstant.ContinueState.INACTIVE);

// Re-enable when on a migrateable page
this.context.setMissionContinueState(AbilityConstant.ContinueState.ACTIVE);
```

### Cross-device migration with different Ability names

Use `continueType` in `module.json5` to link different Abilities across devices:

```json5
// Device A
{ "name": "PhoneAbility", "continueType": ["myApp_main"] }

// Device B
{ "name": "TabletAbility", "continueType": ["myApp_main"] }
```

### Prerequisites

- Both devices logged into same Huawei Account
- Wi-Fi + Bluetooth enabled (or "Multi-device Collaboration Enhanced" enabled)
- "Settings → Multi-device Collaboration → Continuation" enabled
- App installed on both devices

## Push Kit — push notifications

### Get Push Token

Call in `onCreate()` of your UIAbility. Token identifies device+app for push messages.

```ts
import { pushService } from '@kit.PushKit';

// In EntryAbility.onCreate()
pushService.getToken().then((token: string) => {
  console.info('Push token:', token);
  // Upload token to your app server for sending push messages
}).catch((err: BusinessError) => {
  console.error('Failed to get push token:', err.code, err.message);
});
```

**Prerequisites**: Enable Push Service in AGC console first, otherwise `getToken()` returns error 1000900010.

Token changes on: app reinstall, factory reset, `deleteToken()` + re-`getToken()`. Always call `getToken()` on each app launch to keep server-side token fresh.

### Receive push messages (module.json5)

Configure a UIAbility with `action.ohos.push.listener` to receive token updates and push data:

```json5
"skills": [{ "actions": ["action.ohos.push.listener"] }]
```

Push Kit supports: notification messages, voice broadcast, card refresh, background messages, live view, in-app call messages.

## Payment Kit — Huawei Pay (physical goods & services)

For physical goods/services only (hotels, rides, bills). Virtual goods use IAP Kit instead.

```ts
import { paymentService } from '@kit.PaymentKit';
import { common } from '@kit.AbilityKit';

// orderStr is built by your server after calling Huawei Pay pre-order API
// Contains: app_id, merc_no, prepay_id, timestamp, noncestr, sign
const orderStr = '{"app_id":"...","merc_no":"...","prepay_id":"...","timestamp":"...","noncestr":"...","sign":"..."}';

const context = getContext(this) as common.UIAbilityContext;
paymentService.requestPayment(context, orderStr)
  .then(() => { console.info('Payment succeeded'); })
  .catch((err: BusinessError) => { console.error('Payment failed:', err.code, err.message); });
```

Server flow: your server calls `/api/v2/aggr/preorder/create/app` → gets `prepayId` → builds signed `orderStr` → returns to client.

Supports: Phone, Tablet, PC/2in1. China mainland only.
