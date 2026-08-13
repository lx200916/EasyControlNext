/**
 * Desktop service card (FormExtensionAbility) — device list, tap opens EntryAbility.
 * Isolated process: read DevicePrefs, do not import libadb_core.so.
 */

import { Want } from '@kit.AbilityKit';
import {
  FormExtensionAbility,
  formBindingData,
  formInfo,
  formProvider,
} from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DevicePrefs } from '../data/DevicePrefs';
import {
  buildDeviceFormSnapshot,
  DeviceFormSnapshot,
  snapshotToBinding,
} from './DeviceFormSnapshot';
import { FormIds } from './FormIds';

const DOMAIN: number = 0xEC03;
const TAG: string = 'EntryForm';

function formIdOf(want: Want): string {
  if (want.parameters === undefined) {
    return '';
  }
  const raw = want.parameters[formInfo.FormParam.IDENTITY_KEY];
  return raw !== undefined ? `${raw}` : '';
}

function dimensionOf(want: Want): string {
  if (want.parameters === undefined) {
    return '2*2';
  }
  const raw = want.parameters[formInfo.FormParam.DIMENSION_KEY];
  const value = raw !== undefined ? `${raw}` : '2*2';
  return value.length > 0 ? value : '2*2';
}

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = formIdOf(want);
    const dimension = dimensionOf(want);
    if (formId.length > 0) {
      void this.fillForm(formId, dimension);
    }
    return formBindingData.createFormBindingData(
      snapshotToBinding(new DeviceFormSnapshot())
    );
  }

  onUpdateForm(formId: string): void {
    void this.fillForm(formId, '');
  }

  onFormEvent(formId: string, _message: string): void {
    void this.fillForm(formId, '');
  }

  onRemoveForm(formId: string): void {
    void FormIds.remove(this.context, formId);
  }

  onCastToNormalForm(_formId: string): void {
  }

  private async fillForm(formId: string, dimension: string): Promise<void> {
    try {
      let dim = dimension;
      if (dim.length === 0) {
        const existing = await FormIds.all(this.context);
        for (let i = 0; i < existing.length; i++) {
          if (existing[i].id === formId) {
            dim = existing[i].dimension;
            break;
          }
        }
      }
      if (dim.length === 0) {
        dim = '2*2';
      }
      await FormIds.add(this.context, formId, dim);
      await DevicePrefs.open(this.context);
      const devices = await DevicePrefs.readAll();
      const snap = buildDeviceFormSnapshot(devices, dim);
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(snapshotToBinding(snap)));
      hilog.info(DOMAIN, TAG, 'filled %{public}s count=%{public}d dim=%{public}s', formId, snap.count, dim);
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'fill failed';
      hilog.warn(DOMAIN, TAG, 'fillForm %{public}s', msg);
    }
  }
}
