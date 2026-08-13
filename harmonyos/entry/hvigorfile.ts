import { hapTasks } from '@ohos/hvigor-ohos-plugin';
import { hvigor } from '@ohos/hvigor';
import { execFileSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';

/**
 * libadb_core.so is a Rust cdylib (ohos-rs / cargo), NOT built by CMake/externalNativeOptions.
 * hvigor only packages entry/libs/arm64-v8a/*.so in default@ProcessLibs.
 * Without this hook, Assemble silently ships a stale prebuilt .so.
 *
 * Escape hatches (keep a previously staged .so):
 *   SKIP_NATIVE_OHOS=1
 *   hvigorw assembleHap -p skipNativeOhos=true
 */
function isSkipNativeOhos(): boolean {
  const env = process.env.SKIP_NATIVE_OHOS;
  if (env === '1' || env === 'true') {
    return true;
  }
  try {
    const ext = hvigor.getParameter().getExtParam('skipNativeOhos');
    return ext === '1' || ext === 'true' || ext === true;
  } catch (_e) {
    return false;
  }
}

function resolveOhosNdkHome(): string | undefined {
  if (process.env.OHOS_NDK_HOME && fs.existsSync(process.env.OHOS_NDK_HOME)) {
    return process.env.OHOS_NDK_HOME;
  }
  const candidates: string[] = [
    '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony',
  ];
  if (process.env.DEVECO_SDK_HOME) {
    candidates.push(path.join(process.env.DEVECO_SDK_HOME, 'default', 'openharmony'));
  }
  for (let i = 0; i < candidates.length; i++) {
    const c = candidates[i];
    if (c && fs.existsSync(path.join(c, 'native'))) {
      return c;
    }
  }
  return undefined;
}

function buildNativeOhosPlugin() {
  return {
    pluginId: 'easycontrol-build-native-ohos',
    apply(pluginContext) {
      pluginContext.registerTask({
        name: 'buildNativeOhos',
        run(taskContext) {
          const modulePath: string = taskContext.modulePath;
          const script = path.resolve(modulePath, '..', 'scripts', 'build_native_ohos.sh');
          if (!fs.existsSync(script)) {
            throw new Error(`buildNativeOhos: missing ${script}`);
          }

          const staged = path.resolve(modulePath, 'libs', 'arm64-v8a', 'libadb_core.so');
          if (isSkipNativeOhos()) {
            console.warn('[buildNativeOhos] skipped via SKIP_NATIVE_OHOS / -p skipNativeOhos=true');
            if (!fs.existsSync(staged)) {
              throw new Error(`[buildNativeOhos] skip requested but ${staged} is missing`);
            }
            return;
          }

          const env: NodeJS.ProcessEnv = { ...process.env };
          const ndk = resolveOhosNdkHome();
          if (ndk) {
            env.OHOS_NDK_HOME = ndk;
          }

          console.info(`[buildNativeOhos] running ${script} --if-needed`);
          execFileSync('/bin/bash', [script, '--if-needed'], {
            cwd: path.resolve(modulePath, '..'),
            env,
            stdio: 'inherit',
          });
        },
        // Must refresh entry/libs BEFORE ProcessLibs copies into intermediates.
        postDependencies: ['default@ProcessLibs'],
      });
    },
  };
}

export default {
  system: hapTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: [buildNativeOhosPlugin()],
};
