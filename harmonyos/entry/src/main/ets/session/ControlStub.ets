/**
 * Touch / key / power / rotate / light → EasyControl control packets.
 * Packet layout matches ControlPacket.java (big-endian).
 * Session writes the buffer to the live main socket when streaming.
 */

import adbCore from 'libadb_core.so';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'ControlStub';

/** Android MotionEvent.ACTION_* subset used by EasyControl. */
export const MOTION_DOWN: number = 0;
export const MOTION_UP: number = 1;
export const MOTION_MOVE: number = 2;

/** Android KeyEvent keycodes used by nav / volume / hover keyboard. */
export const KEYCODE_HOME: number = 3;
export const KEYCODE_BACK: number = 4;
export const KEYCODE_0: number = 7;
export const KEYCODE_A: number = 29;
export const KEYCODE_VOLUME_UP: number = 24;
export const KEYCODE_VOLUME_DOWN: number = 25;
export const KEYCODE_SPACE: number = 62;
export const KEYCODE_ENTER: number = 66;
export const KEYCODE_DEL: number = 67;
export const KEYCODE_APP_SWITCH: number = 187;
/** KeyEvent.META_SHIFT_ON — uppercase letters on hover QWERTY. */
export const META_SHIFT_ON: number = 0x1;

/** Map a–z char to Android KEYCODE_* (29–54). */
export function keyCodeForLetter(ch: string): number {
  if (ch.length !== 1) {
    return -1;
  }
  const c = ch.toLowerCase().charCodeAt(0);
  if (c < 97 || c > 122) {
    return -1;
  }
  return KEYCODE_A + (c - 97);
}

/** Map digit 0–9 to Android KEYCODE_0..KEYCODE_9. */
export function keyCodeForDigit(ch: string): number {
  if (ch.length !== 1) {
    return -1;
  }
  const c = ch.charCodeAt(0);
  if (c < 48 || c > 57) {
    return -1;
  }
  return KEYCODE_0 + (c - 48);
}

/** Android Display.STATE_* for light events. */
export const DISPLAY_STATE_UNKNOWN: number = 0;
export const DISPLAY_STATE_OFF: number = 1;
export const DISPLAY_STATE_ON: number = 2;

const EVENT_KEY: number = 2;
const EVENT_ROTATE: number = 6;
const EVENT_LIGHT: number = 7;
const EVENT_POWER: number = 8;
const EVENT_RESOLUTION_WH: number = 9;

export interface EncodedTouch {
  ok: boolean;
  bytes: ArrayBuffer | null;
  detail: string;
}

export interface EncodedControl {
  ok: boolean;
  bytes: ArrayBuffer | null;
  detail: string;
}

function putI32Be(view: DataView, offset: number, value: number): void {
  view.setInt32(offset, value, false);
}

export function encodeTouchPacket(
  action: number,
  pointerId: number,
  xNorm: number,
  yNorm: number,
  offsetTimeMs: number
): EncodedTouch {
  try {
    const buf = adbCore.encodeControlTouch(
      action,
      pointerId,
      xNorm,
      yNorm,
      offsetTimeMs
    ) as ArrayBuffer;
    const detail = `touch encode ok len=${buf.byteLength} action=${action}`;
    return { ok: true, bytes: buf, detail: detail };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    hilog.error(DOMAIN, TAG, 'encode failed %{public}s', msg);
    return { ok: false, bytes: null, detail: msg };
  }
}

/** Key event: type(1) + key(i32 BE) + meta(i32 BE). */
export function encodeKeyPacket(keyCode: number, metaState: number = 0): EncodedControl {
  const buf = new ArrayBuffer(9);
  const view = new DataView(buf);
  view.setUint8(0, EVENT_KEY);
  putI32Be(view, 1, keyCode);
  putI32Be(view, 5, metaState);
  return { ok: true, bytes: buf, detail: `key ${keyCode}` };
}

/** Power event: type(1) + mode(i32 BE). mode -1 = toggle. */
export function encodePowerPacket(mode: number = -1): EncodedControl {
  const buf = new ArrayBuffer(5);
  const view = new DataView(buf);
  view.setUint8(0, EVENT_POWER);
  putI32Be(view, 1, mode);
  return { ok: true, bytes: buf, detail: `power ${mode}` };
}

/** Rotate event: single type byte. */
export function encodeRotatePacket(): EncodedControl {
  const buf = new ArrayBuffer(1);
  new DataView(buf).setUint8(0, EVENT_ROTATE);
  return { ok: true, bytes: buf, detail: 'rotate' };
}

/** Light event: type(1) + mode(u8). */
export function encodeLightPacket(mode: number): EncodedControl {
  const buf = new ArrayBuffer(2);
  const view = new DataView(buf);
  view.setUint8(0, EVENT_LIGHT);
  view.setUint8(1, mode & 0xff);
  return { ok: true, bytes: buf, detail: `light ${mode}` };
}

/** Clipboard event via native encoder (rejects empty / >5000 UTF-8 bytes). */
export function encodeClipboardPacket(text: string): EncodedControl {
  try {
    const buf = adbCore.encodeControlClipboard(text) as ArrayBuffer;
    return { ok: true, bytes: buf, detail: `clipboard len=${buf.byteLength}` };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    hilog.warn(DOMAIN, TAG, 'clipboard encode failed %{public}s', msg);
    return { ok: false, bytes: null, detail: msg };
  }
}

/** Fixed WxH resolution event (ControlPacket type 9). */
export function encodeChangeResolutionWh(width: number, height: number): EncodedControl {
  const buf = new ArrayBuffer(9);
  const view = new DataView(buf);
  view.setUint8(0, EVENT_RESOLUTION_WH);
  putI32Be(view, 1, width);
  putI32Be(view, 5, height);
  return { ok: true, bytes: buf, detail: `resolution ${width}x${height}` };
}
