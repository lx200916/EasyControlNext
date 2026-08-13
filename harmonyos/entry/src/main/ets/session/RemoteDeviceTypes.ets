/**
 * Lightweight remote-device DTOs shared by Home / Session / LiveMirror.
 * Kept free of libadb_core.so so Home cold-start can import types without dlopen.
 */

export interface InstalledAppRow {
  packageName: string;
  label: string;
}

export interface AdbOpResult {
  ok: boolean;
  detail: string;
}

export interface RemoteSystemProps {
  ok: boolean;
  model: string;
  release: string;
  sdk: string;
  detail: string;
}
