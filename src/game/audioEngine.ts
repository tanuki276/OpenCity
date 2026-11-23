/**
 * Web Audio engine playing the exact WAV audio assets generated for Reduced-Town Stage 1:
 * - Continuous afternoon urban ambience loop (no silence)
 * - 3 velocity-synced asphalt footstep clips
 * - Harmonic engine loop with live RPM pitch & throttle gain modulation
 * - Car door latch/thud and building collision bump SFX
 */
export class GameAudioEngine {
  private ctx: AudioContext | null = null;
  private masterGain: GainNode | null = null;
  private buffers: Map<string, AudioBuffer> = new Map();
  private ambientSource: AudioBufferSourceNode | null = null;
  private engineSource: AudioBufferSourceNode | null = null;
  private engineGain: GainNode | null = null;
  private muted = false;
  private unlocked = false;
  private loadingPromise: Promise<void> | null = null;
  private engineRunning = false;

  public isUnlocked(): boolean {
    return this.unlocked;
  }

  public isMuted(): boolean {
    return this.muted;
  }

  public setMuted(mute: boolean): void {
    this.muted = mute;
    if (this.masterGain && this.ctx) {
      this.masterGain.gain.setTargetAtTime(mute ? 0 : 0.85, this.ctx.currentTime, 0.04);
    }
  }

  public unlock(): void {
    if (this.unlocked && this.ctx) {
      if (this.ctx.state === 'suspended') {
        void this.ctx.resume();
      }
      return;
    }
    const AudioCtx = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
    if (!AudioCtx) return;

    if (!this.ctx) {
      this.ctx = new AudioCtx();
      this.masterGain = this.ctx.createGain();
      this.masterGain.gain.value = this.muted ? 0 : 0.85;
      this.masterGain.connect(this.ctx.destination);
    }

    if (this.ctx.state === 'suspended') {
      void this.ctx.resume();
    }
    this.unlocked = true;

    if (!this.loadingPromise) {
      this.loadingPromise = this.preloadAll().then(() => {
        this.startAmbience();
        if (this.engineRunning) {
          this.startEngineLoop();
        }
      });
    }
  }

  private async preloadAll(): Promise<void> {
    if (!this.ctx) return;
    const files: Array<[string, string]> = [
      ['ambient', '/game-assets/audio/ambient_city_afternoon.wav'],
      ['step1', '/game-assets/audio/footstep_asphalt_01.wav'],
      ['step2', '/game-assets/audio/footstep_asphalt_02.wav'],
      ['step3', '/game-assets/audio/footstep_asphalt_03.wav'],
      ['engine', '/game-assets/audio/engine_loop.wav'],
      ['door', '/game-assets/audio/car_door.wav'],
      ['bump', '/game-assets/audio/car_bump.wav'],
    ];
    await Promise.all(
      files.map(async ([key, url]) => {
        try {
          const res = await fetch(url);
          if (!res.ok) return;
          const arr = await res.arrayBuffer();
          if (this.ctx) {
            const decoded = await this.ctx.decodeAudioData(arr);
            this.buffers.set(key, decoded);
          }
        } catch {
          // Graceful audio fallback if browser blocks decode
        }
      })
    );
  }

  private startAmbience(): void {
    if (!this.ctx || !this.masterGain || this.ambientSource) return;
    const buf = this.buffers.get('ambient');
    if (!buf) return;
    const src = this.ctx.createBufferSource();
    src.buffer = buf;
    src.loop = true;
    const g = this.ctx.createGain();
    g.gain.value = 0.24;
    src.connect(g);
    g.connect(this.masterGain);
    src.start(0);
    this.ambientSource = src;
  }

  public setEngineRunning(running: boolean): void {
    this.engineRunning = running;
    this.playOneShot('door', 0.55, 1.0);
    if (running) {
      this.startEngineLoop();
    } else {
      this.stopEngineLoop();
    }
  }

  private startEngineLoop(): void {
    if (!this.ctx || !this.masterGain || this.engineSource) return;
    const buf = this.buffers.get('engine');
    if (!buf) return;
    const src = this.ctx.createBufferSource();
    src.buffer = buf;
    src.loop = true;
    src.playbackRate.value = 0.82;
    const g = this.ctx.createGain();
    g.gain.value = 0.16;
    src.connect(g);
    g.connect(this.masterGain);
    src.start(0);
    this.engineSource = src;
    this.engineGain = g;
  }

  private stopEngineLoop(): void {
    if (this.engineSource) {
      try {
        this.engineSource.stop();
      } catch {
        // already stopped
      }
      this.engineSource.disconnect();
      this.engineSource = null;
    }
    if (this.engineGain) {
      this.engineGain.disconnect();
      this.engineGain = null;
    }
  }

  public updateEngineRpm(speedNorm: number, throttle: number): void {
    if (!this.ctx || !this.engineSource || !this.engineGain || !this.engineRunning) return;
    const gearSaw = (speedNorm * 2.6) % 1.0;
    const rpm = Math.min(1.15, Math.max(0.12, 0.18 + speedNorm * 0.55 + gearSaw * 0.25 + throttle * 0.28));
    const targetPitch = 0.76 + rpm * 1.48;
    const targetGain = 0.14 + Math.min(1, rpm * 0.75 + throttle * 0.25) * 0.28;
    const now = this.ctx.currentTime;
    this.engineSource.playbackRate.setTargetAtTime(targetPitch, now, 0.08);
    this.engineGain.gain.setTargetAtTime(targetGain, now, 0.08);
  }

  public playFootstep(sprintBlend: number): void {
    const idx = 1 + Math.floor(Math.random() * 3);
    const pitch = 0.92 + Math.random() * 0.16 + sprintBlend * 0.08;
    const vol = 0.26 + sprintBlend * 0.18;
    this.playOneShot(`step${idx}`, vol, pitch);
  }

  public playBump(intensity: number): void {
    const clamped = Math.max(0.25, Math.min(1.0, intensity));
    this.playOneShot('bump', 0.28 + clamped * 0.48, 0.86 + clamped * 0.26);
  }

  private playOneShot(key: string, volume: number, rate: number): void {
    if (!this.ctx || !this.masterGain || this.muted) return;
    const buf = this.buffers.get(key);
    if (!buf) return;
    const src = this.ctx.createBufferSource();
    src.buffer = buf;
    src.playbackRate.value = rate;
    const g = this.ctx.createGain();
    g.gain.value = volume;
    src.connect(g);
    g.connect(this.masterGain);
    src.start(0);
  }

  public dispose(): void {
    this.stopEngineLoop();
    if (this.ambientSource) {
      try {
        this.ambientSource.stop();
      } catch {
        // noop
      }
      this.ambientSource.disconnect();
      this.ambientSource = null;
    }
    if (this.ctx) {
      void this.ctx.close();
      this.ctx = null;
    }
  }
}
