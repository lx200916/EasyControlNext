/**
 * Push device-list snapshots to every installed desktop service card.
 */

import { common } from '@kit.AbilityKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DevicePrefs } from '../data/DevicePrefs';
import { Device } from '../model/Device';
import { buildDeviceFormSnapshot, snapshotToBinding } from './DeviceFormSnapshot';
import { FormIds } from './FormIds';

const DOMAIN: number = 0xEC03;
const TAG: string = 'FormSync';

export async function pushDeviceForms(context: common.Context, devices?: Device[]): Promise<void> {
  let list: Device[] = [];
  if (devices !== undefined) {
    list = devices;
  } else {
    try {
      await DevicePrefs.open(context);
      list = await DevicePrefs.readAll();
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'prefs';
      hilog.warn(DOMAIN, TAG, 'read devices failed %{public}s', msg);
      return;
    }
  }
  const ids = await FormIds.all(context);
  if (ids.length === 0) {
    return;
  }
  for (let i = 0; i < ids.length; i++) {
    const binding = formBindingData.createFormBindingData(
      snapshotToBinding(buildDeviceFormSnapshot(list, ids[i].dimension))
    );
    try {
      await formProvider.updateForm(ids[i].id, binding);
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'updateForm';
      hilog.warn(DOMAIN, TAG, 'update %{public}s failed %{public}s', ids[i].id, msg);
    }
  }
}
