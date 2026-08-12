/**
 * Built-in presets lite (Android PresetStore subset). No custom CRUD yet.
 */

import { ConnectionPreset, createBuiltInPresets } from './ConnectionPreset';

export class PresetStore {
  private static cache: ConnectionPreset[] | null = null;

  static all(): ConnectionPreset[] {
    if (PresetStore.cache === null) {
      PresetStore.cache = createBuiltInPresets();
    }
    const out: ConnectionPreset[] = [];
    for (let i = 0; i < PresetStore.cache.length; i++) {
      out.push(PresetStore.cache[i]);
    }
    return out;
  }

  static get(id: string): ConnectionPreset | undefined {
    const list = PresetStore.all();
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === id) {
        return list[i];
      }
    }
    return undefined;
  }

  static summaryLine(preset: ConnectionPreset): string {
    const src = preset.videoSource === 'camera' ? '摄像头' : '屏幕';
    return `${src} · ${preset.maxSize}p · ${preset.maxFps} fps`;
  }
}
