/**
 * Persist desktop form IDs + dimension so the UIAbility can push device-list updates.
 */

import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0xEC03;
const TAG: string = 'FormIds';
const STORE_NAME: string = 'form_store';
const KEY_IDS: string = 'form_ids_json';

export class FormIdEntry {
  id: string = '';
  dimension: string = '2*2';
}

async function openStore(context: common.Context): Promise<preferences.Preferences> {
  return await preferences.getPreferences(context, STORE_NAME);
}

function parseEntries(raw: string): FormIdEntry[] {
  if (raw.length === 0) {
    return [];
  }
  try {
    const parsed: Object = JSON.parse(raw) as Object;
    if (!Array.isArray(parsed)) {
      return [];
    }
    const list: Object[] = parsed as Object[];
    const out: FormIdEntry[] = [];
    for (let i = 0; i < list.length; i++) {
      const item = list[i];
      if (typeof item === 'string' && item.length > 0) {
        const e = new FormIdEntry();
        e.id = item;
        out.push(e);
        continue;
      }
      if (item === null || typeof item !== 'object') {
        continue;
      }
      const rec = item as Record<string, Object>;
      const id = typeof rec['id'] === 'string' ? rec['id'] as string : '';
      if (id.length === 0) {
        continue;
      }
      const e = new FormIdEntry();
      e.id = id;
      e.dimension = typeof rec['dimension'] === 'string' && (rec['dimension'] as string).length > 0 ?
        rec['dimension'] as string : '2*2';
      out.push(e);
    }
    return out;
  } catch (_e) {
    return [];
  }
}

function serializeEntries(entries: FormIdEntry[]): string {
  const parts: string[] = [];
  for (let i = 0; i < entries.length; i++) {
    const idJson = JSON.stringify(entries[i].id);
    const dimJson = JSON.stringify(entries[i].dimension);
    parts.push(`{"id":${idJson},"dimension":${dimJson}}`);
  }
  return `[${parts.join(',')}]`;
}

export class FormIds {
  static async all(context: common.Context): Promise<FormIdEntry[]> {
    const store = await openStore(context);
    const raw = (await store.get(KEY_IDS, '')) as string;
    return parseEntries(raw);
  }

  static async add(context: common.Context, formId: string, dimension: string): Promise<void> {
    if (formId.length === 0) {
      return;
    }
    const store = await openStore(context);
    const ids = parseEntries((await store.get(KEY_IDS, '')) as string);
    const dim = dimension.length > 0 ? dimension : '2*2';
    for (let i = 0; i < ids.length; i++) {
      if (ids[i].id === formId) {
        ids[i].dimension = dim;
        await store.put(KEY_IDS, serializeEntries(ids));
        await store.flush();
        return;
      }
    }
    const e = new FormIdEntry();
    e.id = formId;
    e.dimension = dim;
    ids.push(e);
    await store.put(KEY_IDS, serializeEntries(ids));
    await store.flush();
    hilog.info(DOMAIN, TAG, 'add form %{public}s dim=%{public}s count=%{public}d', formId, dim, ids.length);
  }

  static async remove(context: common.Context, formId: string): Promise<void> {
    const store = await openStore(context);
    const ids = parseEntries((await store.get(KEY_IDS, '')) as string);
    const next: FormIdEntry[] = [];
    for (let i = 0; i < ids.length; i++) {
      if (ids[i].id !== formId) {
        next.push(ids[i]);
      }
    }
    await store.put(KEY_IDS, serializeEntries(next));
    await store.flush();
  }
}
