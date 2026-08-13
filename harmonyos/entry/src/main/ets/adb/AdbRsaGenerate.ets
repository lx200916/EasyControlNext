/**
 * Software RSA-2048 PKCS#8 PEM for ADB AUTH. Signing stays in Rust (SHA-1).
 * Generated once, then HUKS-wrapped to filesDir — never the bundled Gate C rawfile.
 */

import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

const PEM_BEGIN: string = '-----BEGIN PRIVATE KEY-----';
const PEM_END: string = '-----END PRIVATE KEY-----';
const PEM_LINE: number = 64;

function derToPkcs8Pem(der: Uint8Array): string {
  const helper = new util.Base64Helper();
  const b64 = helper.encodeToStringSync(der);
  const lines: string[] = [PEM_BEGIN];
  let i = 0;
  while (i < b64.length) {
    const end = i + PEM_LINE < b64.length ? i + PEM_LINE : b64.length;
    lines.push(b64.substring(i, end));
    i = end;
  }
  lines.push(PEM_END);
  return `${lines.join('\n')}\n`;
}

export async function generateAdbRsaPkcs8Pem(): Promise<string> {
  const generator = cryptoFramework.createAsyKeyGenerator('RSA2048');
  const keyPair = await generator.generateKeyPair();
  const encoded = keyPair.priKey.getEncoded();
  if (encoded.data.length < 64) {
    throw new Error('rsa encode too short');
  }
  return derToPkcs8Pem(encoded.data);
}
