/**
 * AOSP wireless-debug QR payload — mirrors Android AdbQrPairing.kt
 * WIFI:T:ADB;S:<service-name>;P:<password>;;
 */

export class AdbQrCredentials {
  serviceName: string = '';
  password: string = '';

  constructor(serviceName: string, password: string) {
    this.serviceName = serviceName;
    this.password = password;
  }

  get payload(): string {
    return `WIFI:T:ADB;S:${this.serviceName};P:${this.password};;`;
  }
}

export class AdbQrPairing {
  static generate(): AdbQrCredentials {
    const n = Math.floor(Math.random() * 1000000);
    const serviceName = `easycontrol-${n.toString().padStart(6, '0')}`;
    let password = '';
    for (let i = 0; i < 6; i++) {
      password += `${Math.floor(Math.random() * 10)}`;
    }
    return new AdbQrCredentials(serviceName, password);
  }

  static parse(raw: string): AdbQrCredentials | undefined {
    const text = raw.trim();
    if (!text.toUpperCase().startsWith('WIFI:')) {
      return undefined;
    }
    let body = text.substring(5);
    if (body.startsWith('wifi:')) {
      body = body.substring(5);
    }
    const parts = body.split(';');
    let type: string = '';
    let service: string = '';
    let password: string = '';
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i].trim();
      if (part.length === 0) {
        continue;
      }
      const idx = part.indexOf(':');
      if (idx <= 0) {
        continue;
      }
      const key = part.substring(0, idx).toUpperCase();
      const value = part.substring(idx + 1);
      if (key === 'T') {
        type = value;
      } else if (key === 'S') {
        service = value;
      } else if (key === 'P') {
        password = value;
      }
    }
    if (type.toUpperCase() !== 'ADB') {
      return undefined;
    }
    if (service.length === 0 || password.length === 0) {
      return undefined;
    }
    return new AdbQrCredentials(service, password);
  }
}
