/**
 * HUKS AES-256-GCM wrap for the on-device ADB RSA private key.
 *
 * ADB AUTH still signs in Rust (PKCS#1 v1.5 / SHA-1). HUKS does not wrap that
 * signature path — it only encrypts the PKCS#8 PEM at rest.
 */

import { BusinessError } from '@kit.BasicServicesKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { huks } from '@kit.UniversalKeystoreKit';

const DOMAIN: number = 0xEC02;
const TAG: string = 'AdbHuks';
const KEY_ALIAS: string = 'easycontrol_adb_wrap';
const AAD_TEXT: string = 'easycontrol-adb-rsa';
const NONCE_LEN: number = 12;
const GCM_TAG_LEN: number = 16;

function stringToBytes(text: string): Uint8Array {
  const out = new Uint8Array(text.length);
  for (let i = 0; i < text.length; i++) {
    out[i] = text.charCodeAt(i) & 0xff;
  }
  return out;
}

function aadBytes(): Uint8Array {
  return stringToBytes(AAD_TEXT);
}

function wrapError(e: Object, fallback: string): string {
  if (e instanceof Error) {
    return e.message;
  }
  try {
    const be = e as BusinessError;
    if (typeof be.code === 'number') {
      return `huks ${be.code}: ${be.message}`;
    }
  } catch (_e) {
    // not BusinessError
  }
  return fallback;
}

function generateProperties(): huks.HuksParam[] {
  return [
    {
      tag: huks.HuksTag.HUKS_TAG_ALGORITHM,
      value: huks.HuksKeyAlg.HUKS_ALG_AES
    },
    {
      tag: huks.HuksTag.HUKS_TAG_KEY_SIZE,
      value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256
    },
    {
      tag: huks.HuksTag.HUKS_TAG_PURPOSE,
      value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT |
        huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
    }
  ];
}

function cipherProperties(purpose: huks.HuksKeyPurpose, nonce: Uint8Array): huks.HuksParam[] {
  return [
    {
      tag: huks.HuksTag.HUKS_TAG_ALGORITHM,
      value: huks.HuksKeyAlg.HUKS_ALG_AES
    },
    {
      tag: huks.HuksTag.HUKS_TAG_KEY_SIZE,
      value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256
    },
    {
      tag: huks.HuksTag.HUKS_TAG_PURPOSE,
      value: purpose
    },
    {
      tag: huks.HuksTag.HUKS_TAG_PADDING,
      value: huks.HuksKeyPadding.HUKS_PADDING_NONE
    },
    {
      tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE,
      value: huks.HuksCipherMode.HUKS_MODE_GCM
    },
    {
      tag: huks.HuksTag.HUKS_TAG_NONCE,
      value: nonce
    },
    {
      tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA,
      value: aadBytes()
    }
  ];
}

function decryptProperties(nonce: Uint8Array, cipherWithTag: Uint8Array): huks.HuksParam[] {
  const props = cipherProperties(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT, nonce);
  props.push({
    tag: huks.HuksTag.HUKS_TAG_AE_TAG,
    value: cipherWithTag.slice(cipherWithTag.length - GCM_TAG_LEN)
  });
  return props;
}

function randomNonce(): Uint8Array {
  const blob = cryptoFramework.createRandom().generateRandomSync(NONCE_LEN);
  return blob.data;
}

async function keyExists(): Promise<boolean> {
  const options: huks.HuksOptions = {
    properties: generateProperties()
  };
  try {
    return await huks.isKeyItemExist(KEY_ALIAS, options);
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'isKeyItemExist %{public}s', wrapError(e, 'exist-check failed'));
    return false;
  }
}

async function ensureWrapKey(): Promise<void> {
  if (await keyExists()) {
    return;
  }
  const options: huks.HuksOptions = {
    properties: generateProperties()
  };
  try {
    await huks.generateKeyItem(KEY_ALIAS, options);
    hilog.info(DOMAIN, TAG, '%{public}s', 'wrap key generated');
  } catch (e) {
    // Race: another caller created the alias.
    if (await keyExists()) {
      return;
    }
    throw new Error(wrapError(e, 'generate wrap key failed'));
  }
}

async function runSession(purpose: huks.HuksKeyPurpose, properties: huks.HuksParam[],
  inData: Uint8Array): Promise<Uint8Array> {
  const options: huks.HuksOptions = {
    properties: properties,
    inData: inData
  };
  let handle: number = -1;
  try {
    const session = await huks.initSession(KEY_ALIAS, options);
    handle = session.handle;
    const finished = await huks.finishSession(handle, options);
    const out = finished.outData;
    if (out === undefined || out === null) {
      throw new Error('huks finish returned empty');
    }
    return out;
  } catch (e) {
    if (handle >= 0) {
      try {
        await huks.abortSession(handle, options);
      } catch (_abort) {
        // already failed
      }
    }
    throw new Error(wrapError(e, purpose === huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT ?
      'huks encrypt failed' : 'huks decrypt failed'));
  }
}

export class AdbHuksWrap {
  /** Encrypt plaintext; returns nonce || ciphertext+tag. */
  static async wrap(plain: Uint8Array): Promise<Uint8Array> {
    await ensureWrapKey();
    const nonce = randomNonce();
    const cipher = await runSession(
      huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT,
      cipherProperties(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT, nonce),
      plain
    );
    const out = new Uint8Array(nonce.length + cipher.length);
    out.set(nonce, 0);
    out.set(cipher, nonce.length);
    return out;
  }

  static async unwrap(packed: Uint8Array): Promise<Uint8Array> {
    if (packed.length < NONCE_LEN + GCM_TAG_LEN + 1) {
      throw new Error('wrapped blob too short');
    }
    await ensureWrapKey();
    const nonce = packed.slice(0, NONCE_LEN);
    const cipherWithTag = packed.slice(NONCE_LEN);
    const body = cipherWithTag.slice(0, cipherWithTag.length - GCM_TAG_LEN);
    return await runSession(
      huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT,
      decryptProperties(nonce, cipherWithTag),
      body
    );
  }
}
