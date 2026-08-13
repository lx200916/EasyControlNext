# Permissions Reference

Use this reference for HarmonyOS permission declaration and user authorization flows.

## Defaults

- Mention static declaration and runtime request when user authorization is required.
- Prefer HarmonyOS permission names, for example camera permission constants from Ability Kit.
- Include module configuration notes when code requires permissions.

## Answering pattern

1. Identify the required permission.
2. Add or verify the declaration in module configuration.
3. Request authorization at runtime when required.
4. Handle denied authorization gracefully.
5. Explain SDK-version-specific behavior when relevant.

## Review checklist

- Permission names are HarmonyOS permissions.
- Runtime request uses ability context correctly.
- Denial path is handled.
- API 26 permission behavior changes are not applied to API 24 production answers unless requested.

---

## Detailed reference

### Permissions

Declare in `module.json5` → `requestPermissions`. For user-granted permissions, request at runtime via `abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, [...])`.

## Security coding rules (from official best practices)

1. Set `exported: false` for non-interactive abilities
2. Validate all parameters crossing trust boundaries (Want intents, rpc.RemoteObject)
3. Use parameterized queries — never string concat for SQL
4. Replace HTTP with HTTPS; validate SSL certificates
5. Never store personal data in clipboard
6. Use `Asset Store Kit` for sensitive short data (passwords, tokens)
7. Avoid passing personal data through implicit intents
8. Use code obfuscation for production builds
9. Use precise `InputType` (`.USER_NAME`, `.Password`) for system-level protection
10. Never use debug signatures for production releases

**Permission check + request pattern:**
```ts
import { abilityAccessCtrl, bundleManager } from '@kit.AbilityKit';

// Check
const atManager = abilityAccessCtrl.createAtManager();
const bundleInfo = await bundleManager.getBundleInfoForSelf(
  bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
const status = await atManager.checkAccessToken(
  bundleInfo.appInfo.accessTokenId, 'ohos.permission.CAMERA');

// Step 1 — Request from user
const result = await atManager.requestPermissionsFromUser(context,
  ['ohos.permission.CAMERA', 'ohos.permission.MICROPHONE']);
if (result.authResults[0] === 0) {
  // Granted
} else if (result.dialogShownResults?.[0]) {
  // User saw dialog but denied — show in-app guidance, don't re-pop
} else {
  // Step 2 — Fallback: open settings dialog (user previously denied permanently)
  atManager.requestPermissionOnSetting(context,
    ['ohos.permission.CAMERA']).then((statuses) => {
    // statuses[0]: 0 = granted, -1 = denied
  });
}
```

**Data encryption levels:** EL1 (device-level) → EL2 (user-level, default) → EL3 (accessible while locked) → EL4 (inaccessible when locked)

**Network security config** — HTTPS/certificate pinning for production apps:

Create `src/main/resources/base/profile/network_config.json`:
```json
{
  "network-security-config": {
    "domain-config": [{
      "domains": [{ "include-subdomains": true, "name": "api.example.com" }],
      "trust-anchors": [{ "certificates": "/data/storage/el1/bundle/entry/resources/resfile/ca_cert.pem" }]
    }]
  }
}
```
Reference in `module.json5`: `"metadata": [{ "name": "NetworkSecurityConfig", "resource": "$profile:network_config" }]`.
