/**
 * Connection preset mirror of Android `ConnectionPreset`.
 * Stored in preferences in Phase 6.
 */
export class ConnectionPreset {
  id: string = '';
  name: string = '';
  maxSize: number = 1600;
  maxFps: number = 60;
  maxVideoBit: number = 4;
  useH265: boolean = false;
  isAudio: boolean = false;

  constructor(id?: string, name?: string) {
    if (id !== undefined) {
      this.id = id;
    }
    if (name !== undefined) {
      this.name = name;
    }
  }
}
