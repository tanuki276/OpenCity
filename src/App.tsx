import { useEffect, useRef, useState } from 'react';
import { VirtualStick } from './components/VirtualStick';
import { ReducedTownSimulation } from './game/simulation';
import type { HudSnapshot, TouchInputState } from './game/types';

const INITIAL_HUD: HudSnapshot = {
  mode: 'ON_FOOT',
  canEnterCar: false,
  speedKmh: 0,
  audioUnlocked: false,
  muted: false,
  loading: true,
  loadProgress: 0,
  webglError: null,
};

export default function App() {
  const canvasHostRef = useRef<HTMLDivElement>(null);
  const simRef = useRef<ReducedTownSimulation | null>(null);
  const touchStateRef = useRef<TouchInputState>({
    moveX: 0,
    moveY: 0,
    sprint: false,
    jumpQueued: false,
    gas: false,
    brake: false,
    steerX: 0,
  });

  const [hud, setHud] = useState<HudSnapshot>(INITIAL_HUD);
  const [touchUi, setTouchUi] = useState<boolean>(() =>
    typeof window !== 'undefined' && ('ontouchstart' in window || navigator.maxTouchPoints > 0)
  );
  const [dockOpen, setDockOpen] = useState<boolean>(true);
  const [toast, setToast] = useState<string | null>(null);

  useEffect(() => {
    const host = canvasHostRef.current;
    if (!host) return;
    const sim = new ReducedTownSimulation(host, touchStateRef.current, (snap) => {
      setHud(snap);
    });
    simRef.current = sim;
    void sim.init();

    const onKey = (e: KeyboardEvent) => {
      if (e.repeat) return;
      if (e.code === 'KeyT') {
        setTouchUi((v) => !v);
      } else if (e.code === 'KeyH') {
        setDockOpen((v) => !v);
      }
    };
    window.addEventListener('keydown', onKey);

    return () => {
      window.removeEventListener('keydown', onKey);
      sim.dispose();
      simRef.current = null;
    };
  }, []);

  const triggerToast = (msg: string) => {
    setToast(msg);
    window.setTimeout(() => {
      setToast((cur) => (cur === msg ? null : cur));
    }, 1800);
  };

  const handleScreenshot = () => {
    simRef.current?.captureScreenshot();
    triggerToast('Screenshot saved');
  };

  const isDriving = hud.mode === 'DRIVING';

  return (
    <div className="relative h-screen w-screen overflow-hidden bg-[#101620]">
      {/* Isolated WebGL canvas mount */}
      <div ref={canvasHostRef} className="absolute inset-0 h-full w-full cursor-grab active:cursor-grabbing" />

      {/* Loading veil until GLB models & PBR textures finish */}
      {hud.loading && !hud.webglError && (
        <div className="absolute inset-0 z-30 flex flex-col items-center justify-center bg-[#101620] text-slate-100">
          <div className="text-lg font-semibold tracking-tight">Reduced-Town</div>
          <div className="mt-2 text-xs text-slate-400">Loading 5×5 city models and PBR textures</div>
          <div className="mt-5 h-1.5 w-52 overflow-hidden rounded-full bg-slate-800">
            <div
              className="h-full bg-amber-500 transition-transform duration-150 origin-left"
              style={{ transform: `scaleX(${Math.max(0.06, hud.loadProgress / 100)})` }}
            />
          </div>
        </div>
      )}

      {/* WebGL fallback state */}
      {hud.webglError && (
        <div className="absolute inset-0 z-30 flex items-center justify-center bg-[#101620] p-6">
          <div className="max-w-md rounded-xl border border-white/15 bg-[#161e2b] p-6 text-center">
            <h1 className="text-lg font-semibold text-white">Reduced-Town — Stage 1</h1>
            <p className="mt-2 text-sm text-slate-300">{hud.webglError}</p>
            <p className="mt-3 text-xs text-slate-400">
              Open <code className="text-amber-400">project.godot</code> in Godot 4.7 or run GitHub Actions to build the Android arm64 APK.
            </p>
          </div>
        </div>
      )}

      {/* Top-Left: Quiet Title or Compact Driving Speedometer */}
      {!hud.loading && !hud.webglError && (
        <div className="pointer-events-none absolute left-5 top-5 z-10 flex items-center gap-4">
          {isDriving ? (
            <div className="flex items-baseline gap-2.5 rounded-xl border border-white/20 bg-[#11161f]/85 px-4 py-2.5">
              <img
                src="/game-assets/icons/ic_steering_wheel.svg"
                alt=""
                className="h-5 w-5 self-center opacity-90"
              />
              <span className="font-display-num text-3xl font-bold leading-none text-white">
                {hud.speedKmh}
              </span>
              <span className="text-xs font-semibold tracking-wider text-slate-300">KM/H</span>
            </div>
          ) : (
            <div className="rounded-lg border border-white/15 bg-[#11161f]/80 px-3.5 py-2">
              <div className="text-sm font-semibold tracking-tight text-white">Reduced-Town</div>
              <div className="text-[11px] text-slate-300">Stage 1 · Godot 4.7 + WebGL Preview</div>
            </div>
          )}
        </div>
      )}

      {/* Center-Top Toast */}
      {toast && (
        <div className="pointer-events-none absolute left-1/2 top-5 z-20 -translate-x-1/2 rounded-lg border border-amber-400/50 bg-[#11161f]/90 px-4 py-2 text-xs font-semibold text-white">
          {toast}
        </div>
      )}

      {/* Center-Bottom Contextual Drive Prompt (appears when near vehicle on foot) */}
      {!hud.loading && !isDriving && hud.canEnterCar && (
        <div className="absolute bottom-28 left-1/2 z-20 -translate-x-1/2">
          <button
            type="button"
            onClick={() => simRef.current?.toggleVehicleInteract()}
            className="flex items-center gap-2.5 rounded-xl border border-amber-200/60 bg-amber-600 px-5 py-3 text-sm font-semibold text-white shadow-lg transition-transform duration-150 hover:bg-amber-500 active:scale-95 whitespace-nowrap"
          >
            <img src="/game-assets/icons/ic_enter_car.svg" alt="" className="h-5 w-5" />
            <span>{touchUi ? 'Drive' : 'Drive [F]'}</span>
          </button>
        </div>
      )}

      {/* Android / Touch Controls Layer */}
      {!hud.loading && touchUi && !isDriving && (
        <>
          <div className="absolute bottom-8 left-6 z-20">
            <VirtualStick
              onChange={(x, y) => {
                touchStateRef.current.moveX = x;
                touchStateRef.current.moveY = y;
              }}
            />
          </div>
          <div className="absolute bottom-10 right-6 z-20 flex items-center gap-3.5">
            <button
              type="button"
              onPointerDown={(e) => {
                e.stopPropagation();
                touchStateRef.current.sprint = true;
              }}
              onPointerUp={() => {
                touchStateRef.current.sprint = false;
              }}
              onPointerCancel={() => {
                touchStateRef.current.sprint = false;
              }}
              className="flex h-16 w-16 flex-col items-center justify-center gap-1 rounded-full border border-white/25 bg-[#11161f]/80 text-[11px] font-semibold text-white active:scale-95"
            >
              <img src="/game-assets/icons/ic_sprint.svg" alt="" className="h-5 w-5" />
              <span>Run</span>
            </button>
            <button
              type="button"
              onPointerDown={(e) => {
                e.stopPropagation();
                touchStateRef.current.jumpQueued = true;
              }}
              className="flex h-16 w-16 flex-col items-center justify-center gap-1 rounded-full border border-white/25 bg-[#11161f]/80 text-[11px] font-semibold text-white active:scale-95"
            >
              <img src="/game-assets/icons/ic_jump.svg" alt="" className="h-5 w-5" />
              <span>Jump</span>
            </button>
          </div>
        </>
      )}

      {!hud.loading && touchUi && isDriving && (
        <>
          <div className="absolute bottom-9 left-6 z-20">
            <VirtualStick
              horizontalOnly
              maxRadius={62}
              onChange={(x) => {
                touchStateRef.current.steerX = x;
              }}
            />
          </div>
          <div className="absolute bottom-9 right-6 z-20 flex items-end gap-3.5">
            <button
              type="button"
              onPointerDown={(e) => {
                e.stopPropagation();
                touchStateRef.current.brake = true;
              }}
              onPointerUp={() => {
                touchStateRef.current.brake = false;
              }}
              onPointerCancel={() => {
                touchStateRef.current.brake = false;
              }}
              className="flex h-20 w-18 flex-col items-center justify-center gap-1 rounded-xl border border-white/25 bg-[#11161f]/85 text-[11px] font-semibold text-white active:scale-95"
            >
              <img src="/game-assets/icons/ic_brake.svg" alt="" className="h-5 w-5" />
              <span>Brake</span>
            </button>
            <button
              type="button"
              onPointerDown={(e) => {
                e.stopPropagation();
                touchStateRef.current.gas = true;
              }}
              onPointerUp={() => {
                touchStateRef.current.gas = false;
              }}
              onPointerCancel={() => {
                touchStateRef.current.gas = false;
              }}
              className="flex h-24 w-20 flex-col items-center justify-center gap-1 rounded-xl border border-amber-200/50 bg-amber-600/95 text-[11px] font-semibold text-white active:scale-95"
            >
              <img src="/game-assets/icons/ic_gas.svg" alt="" className="h-6 w-6" />
              <span>Gas</span>
            </button>
          </div>
        </>
      )}

      {/* Unified Collapsible Bottom Dock (Zero Viewport Occlusion) */}
      {!hud.loading && !hud.webglError && (
        <div className="pointer-events-none fixed bottom-4 left-1/2 z-20 flex max-w-[94vw] -translate-x-1/2 flex-col items-center">
          <button
            type="button"
            onClick={() => setDockOpen((v) => !v)}
            className="pointer-events-auto mb-1.5 rounded-md border border-white/15 bg-[#11161f]/80 px-3 py-1 text-[11px] font-medium text-slate-200 transition-colors hover:bg-[#1a2230] whitespace-nowrap"
          >
            {dockOpen ? 'Hide Controls' : 'Show Controls'}
          </button>

          <div
            className={`pointer-events-auto flex flex-wrap items-center justify-center gap-2.5 rounded-xl border border-white/15 bg-[#11161f]/85 px-4 py-2.5 text-xs text-slate-200 transition-all duration-200 ${
              dockOpen ? 'translate-y-0 opacity-100' : 'pointer-events-none translate-y-4 opacity-0 hidden'
            }`}
          >
            {isDriving && (
              <button
                type="button"
                onClick={() => simRef.current?.toggleVehicleInteract()}
                className="flex items-center gap-1.5 rounded-lg bg-amber-600 px-3 py-1.5 font-semibold text-white hover:bg-amber-500 active:scale-95 whitespace-nowrap"
              >
                <img src="/game-assets/icons/ic_exit_car.svg" alt="" className="h-4 w-4" />
                <span>{touchUi ? 'Exit Car' : 'Exit [F]'}</span>
              </button>
            )}

            {!touchUi && (
              <span className="text-slate-300 whitespace-nowrap">
                {isDriving
                  ? 'WASD Drive · Space Brake · Drag Look · F Exit'
                  : 'WASD Walk · Shift Sprint · Space Jump · Drag Look · F Drive'}
              </span>
            )}

            <button
              type="button"
              onClick={() => setTouchUi((v) => !v)}
              className={`rounded-lg border px-2.5 py-1.5 font-medium transition-colors whitespace-nowrap ${
                touchUi
                  ? 'border-amber-400/60 bg-amber-500/20 text-amber-200'
                  : 'border-white/15 bg-white/5 text-slate-200 hover:bg-white/10'
              }`}
            >
              {touchUi ? 'Touch UI On' : 'Touch UI Off'}
            </button>

            <button
              type="button"
              onClick={() => simRef.current?.toggleMute()}
              className="rounded-lg border border-white/15 bg-white/5 px-2.5 py-1.5 font-medium text-slate-200 hover:bg-white/10 whitespace-nowrap"
            >
              {hud.muted ? 'Sound Off' : 'Sound On'}
            </button>

            <button
              type="button"
              onClick={handleScreenshot}
              className="flex items-center gap-1.5 rounded-lg border border-white/15 bg-white/5 px-2.5 py-1.5 font-medium text-slate-200 hover:bg-white/10 whitespace-nowrap"
              title="Capture street-level screenshot (F12)"
            >
              <img src="/game-assets/icons/ic_screenshot.svg" alt="" className="h-4 w-4" />
              <span>Shot</span>
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
