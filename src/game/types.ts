export type GameMode = 'ON_FOOT' | 'DRIVING';

export interface ColliderBox {
  minX: number;
  maxX: number;
  minZ: number;
  maxZ: number;
  maxY: number;
  isSidewalk?: boolean;
}

export interface HudSnapshot {
  mode: GameMode;
  canEnterCar: boolean;
  speedKmh: number;
  audioUnlocked: boolean;
  muted: boolean;
  loading: boolean;
  loadProgress: number;
  webglError: string | null;
}

export interface TouchInputState {
  moveX: number;
  moveY: number;
  sprint: boolean;
  jumpQueued: boolean;
  gas: boolean;
  brake: boolean;
  steerX: number;
}
