/**
 * AppStorage key for desktop service-card router → Navigation.
 * Values: '' | 'home' | 'session:<uuid>'
 */

export const PENDING_FORM_NAV_KEY: string = 'pendingFormNav';

export function formNavHome(): string {
  return 'home';
}

export function formNavSession(uuid: string): string {
  return `session:${uuid}`;
}

export function isFormNavSession(value: string): boolean {
  return value.indexOf('session:') === 0 && value.length > 8;
}

export function formNavSessionUuid(value: string): string {
  if (!isFormNavSession(value)) {
    return '';
  }
  return value.substring(8);
}
