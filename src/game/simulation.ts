import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { GameAudioEngine } from './audioEngine';
import { buildCityWorld, OUTER_ROAD_EDGE, SIDEWALK_HEIGHT } from './cityScene';
import { PlayerRig } from './playerRig';
import type { ColliderBox, GameMode, HudSnapshot, TouchInputState } from './types';

// Exact Stage 1 Player & Vehicle Constants matching Godot scripts
const WALK_SPEED = 6.2;
const SPRINT_SPEED = 9.5;
const JUMP_VELOCITY = 6.5;
const GRAVITY = 18.5;
const CAR_MAX_FWD = 25.5;
const CAR_MAX_REV = 9.0;
const CAR_WHEEL_RADIUS = 0.35;
const ENTER_RADIUS = 3.5;

const _vecA = new THREE.Vector3();
const _vecB = new THREE.Vector3();
const _rayOrigin = new THREE.Vector3();
const _rayDir = new THREE.Vector3();

function detectSoftwareWebGL(): boolean {
  const probe = document.createElement('canvas');
  const gl = probe.getContext('webgl2') || probe.getContext('webgl');
  if (!gl) return true;
  const ext = gl.getExtension('WEBGL_debug_renderer_info');
  const param = ext ? ext.UNMASKED_RENDERER_WEBGL : gl.RENDERER;
  const gpu = String(gl.getParameter(param) || '');
  gl.getExtension('WEBGL_lose_context')?.loseContext();
  return /SwiftShader|llvmpipe|softpipe|Software|Basic Render/i.test(gpu);
}

function lerpAngle(a: number, b: number, t: number): number {
  let diff = ((b - a + Math.PI) % (Math.PI * 2)) - Math.PI;
  if (diff < -Math.PI) diff += Math.PI * 2;
  return a + diff * t;
}

export class ReducedTownSimulation {
  private readonly container: HTMLElement;
  private readonly onHudChange: (snap: HudSnapshot) => void;
  private readonly touchInput: TouchInputState;

  private renderer: THREE.WebGLRenderer | null = null;
  private scene = new THREE.Scene();
  private camera = new THREE.PerspectiveCamera(65, 16 / 9, 0.12, 260);
  private sunLight: THREE.DirectionalLight | null = null;
  private raycaster = new THREE.Raycaster();
  private audio = new GameAudioEngine();

  private isSoftwareGl = false;
  private disposed = false;
  private frameId = 0;
  private lastTimeMs = 0;

  private colliders: ColliderBox[] = [];
  private sidewalks: ColliderBox[] = [];
  private occluders: THREE.Object3D[] = [];

  // Player state
  private playerRig: PlayerRig | null = null;
  private playerPos = new THREE.Vector3(6.2, SIDEWALK_HEIGHT, 8.8);
  private playerVel = new THREE.Vector3();
  private playerYaw = -0.55;
  private playerOnFloor = true;

  // Vehicle state
  private carRoot = new THREE.Group();
  private carTiltPivot = new THREE.Group();
  private wheelSteerPivots: THREE.Group[] = [];
  private wheelSpinNodes: THREE.Group[] = [];
  private taillightMat: THREE.MeshStandardMaterial | null = null;
  private carPos = new THREE.Vector3(14.7, 0.35, 5.0);
  private carYaw = 0;
  private carSpeed = 0;
  private carSteerAngle = 0;
  private wheelSpinRad = 0;
  private carPitchVis = 0;
  private carRollVis = 0;
  private bumpCooldown = 0;

  // Camera & Game Mode
  private mode: GameMode = 'ON_FOOT';
  private camYaw = -0.55;
  private camPitch = -0.24;
  private camPos = new THREE.Vector3(8.5, 3.2, 13.0);
  private camArmLen = 4.6;
  private bobPhase = 0;
  private manualOrbitTimer = 0;
  private canEnterCar = false;

  // Input state
  private keys = new Set<string>();
  private draggingLook = false;
  private lookPointerId = -1;
  private lastPointerX = 0;
  private lastPointerY = 0;
  private hudEmitAccum = 0;
  private loading = true;
  private loadProgress = 0;

  constructor(
    container: HTMLElement,
    touchInput: TouchInputState,
    onHudChange: (snap: HudSnapshot) => void
  ) {
    this.container = container;
    this.touchInput = touchInput;
    this.onHudChange = onHudChange;
  }

  public async init(): Promise<void> {
    this.isSoftwareGl = detectSoftwareWebGL();
    try {
      this.renderer = new THREE.WebGLRenderer({
        antialias: !this.isSoftwareGl,
        powerPreference: 'high-performance',
        preserveDrawingBuffer: false,
      });
    } catch {
      this.emitHud('WebGL context unavailable in this browser.');
      return;
    }

    const r = this.renderer;
    r.outputColorSpace = THREE.SRGBColorSpace;
    r.toneMapping = THREE.ACESFilmicToneMapping;
    r.toneMappingExposure = 0.98;
    r.setPixelRatio(this.isSoftwareGl ? 1 : Math.min(window.devicePixelRatio, 2));
    r.shadowMap.enabled = !this.isSoftwareGl;
    r.shadowMap.type = THREE.PCFSoftShadowMap;
    r.setSize(this.container.clientWidth || window.innerWidth, this.container.clientHeight || window.innerHeight);

    const canvas = r.domElement;
    canvas.style.display = 'block';
    canvas.style.width = '100%';
    canvas.style.height = '100%';
    this.container.appendChild(canvas);

    canvas.addEventListener('webglcontextlost', this.handleContextLost, false);
    canvas.addEventListener('webglcontextrestored', this.handleContextRestored, false);

    // Studio RoomEnvironment IBL so car paint, chrome & glass reflect realistically
    const pmrem = new THREE.PMREMGenerator(r);
    this.scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
    pmrem.dispose();

    // Horizon-matched atmospheric fog
    this.scene.background = new THREE.Color(0xc4d8eb);
    this.scene.fog = new THREE.Fog(0xc4d8eb, 42, 162);

    // Warm angled afternoon key sun + cool sky/ground HemisphereLight fill
    const hemi = new THREE.HemisphereLight(0xaad0f5, 0x5c5247, 0.78);
    this.scene.add(hemi);

    const sun = new THREE.DirectionalLight(0xfff0d6, 1.85);
    sun.position.set(34, 40, 38);
    sun.castShadow = !this.isSoftwareGl;
    sun.shadow.mapSize.set(2048, 2048);
    sun.shadow.camera.near = 2;
    sun.shadow.camera.far = 140;
    const d = 46;
    sun.shadow.camera.left = -d;
    sun.shadow.camera.right = d;
    sun.shadow.camera.top = d;
    sun.shadow.camera.bottom = -d;
    sun.shadow.bias = -0.0005;
    sun.shadow.normalBias = 0.03;
    this.scene.add(sun);
    this.scene.add(sun.target);
    this.sunLight = sun;

    // Build 5x5 city world using the real Godot GLB models & PBR PNG textures
    const cityRes = await buildCityWorld(this.scene, r, !this.isSoftwareGl, (pct) => {
      this.loadProgress = pct;
      this.emitHud();
    });
    if (this.disposed) return;

    this.colliders = cityRes.colliders;
    this.sidewalks = cityRes.sidewalks;
    this.occluders = cityRes.occluders;

    // Player articulated PBR rig
    this.playerRig = new PlayerRig(cityRes.contactShadowMat, !this.isSoftwareGl);
    this.playerRig.root.position.copy(this.playerPos);
    this.playerRig.root.rotation.y = this.playerYaw;
    this.scene.add(this.playerRig.root);

    // Hero Crimson American Sport Sedan (car_body.glb + 4x car_wheel.glb + AO shadow)
    this.setupVehicle(cityRes.carBodyTemplate, cityRes.carWheelTemplate, cityRes.contactShadowMat, cityRes.applyPbrMaterials);

    // Bind listeners
    window.addEventListener('resize', this.handleResize);
    window.addEventListener('keydown', this.handleKeyDown);
    window.addEventListener('keyup', this.handleKeyUp);
    canvas.addEventListener('pointerdown', this.handlePointerDown);
    window.addEventListener('pointermove', this.handlePointerMove);
    window.addEventListener('pointerup', this.handlePointerUp);
    window.addEventListener('pointercancel', this.handlePointerUp);

    if (!this.isSoftwareGl) {
      r.compile(this.scene, this.camera);
    }

    this.loading = false;
    this.loadProgress = 100;
    this.emitHud();
    this.handleResize();

    this.lastTimeMs = performance.now();
    this.scheduleNextFrame();
  }

  private setupVehicle(
    bodyTemplate: THREE.Group,
    wheelTemplate: THREE.Group,
    contactShadowMat: THREE.MeshBasicMaterial,
    applyPbr: (root: THREE.Object3D, tint?: THREE.Color, castShadow?: boolean) => void
  ): void {
    this.carRoot.position.copy(this.carPos);
    this.carRoot.rotation.y = this.carYaw;
    this.scene.add(this.carRoot);

    const shadowPlane = new THREE.Mesh(new THREE.PlaneGeometry(2.55, 5.05), contactShadowMat);
    shadowPlane.rotation.x = -Math.PI * 0.5;
    shadowPlane.position.y = -0.325;
    this.carRoot.add(shadowPlane);

    this.carTiltPivot.position.set(0, -0.03, 0);
    this.carRoot.add(this.carTiltPivot);

    const body = bodyTemplate.clone(true);
    applyPbr(body, undefined, !this.isSoftwareGl);
    body.traverse((obj) => {
      if (obj instanceof THREE.Mesh) {
        const m = obj.material as THREE.MeshStandardMaterial;
        if (m && m.name === 'mat_taillight') {
          const tl = m.clone();
          tl.emissive = new THREE.Color(0xf01810);
          tl.emissiveIntensity = 0.4;
          obj.material = tl;
          this.taillightMat = tl;
        }
      }
    });
    this.carTiltPivot.add(body);

    const wheelCoords: Array<[number, number, number]> = [
      [-0.86, 0.0, -1.34],
      [0.86, 0.0, -1.34],
      [-0.86, 0.0, 1.32],
      [0.86, 0.0, 1.32],
    ];
    for (const [wx, wy, wz] of wheelCoords) {
      const steerPivot = new THREE.Group();
      steerPivot.position.set(wx, wy, wz);
      this.carRoot.add(steerPivot);

      const spinNode = new THREE.Group();
      steerPivot.add(spinNode);

      const wMesh = wheelTemplate.clone(true);
      applyPbr(wMesh, undefined, !this.isSoftwareGl);
      spinNode.add(wMesh);

      this.wheelSteerPivots.push(steerPivot);
      this.wheelSpinNodes.push(spinNode);
    }
  }

  public toggleVehicleInteract(): void {
    this.audio.unlock();
    if (this.mode === 'ON_FOOT') {
      const dist = this.playerPos.distanceTo(this.carPos);
      if (dist <= ENTER_RADIUS) {
        this.mode = 'DRIVING';
        this.canEnterCar = false;
        if (this.playerRig) this.playerRig.root.visible = false;
        this.camYaw = this.carYaw;
        this.camPitch = -0.22;
        this.audio.setEngineRunning(true);
        this.emitHud();
      }
    } else {
      this.mode = 'ON_FOOT';
      const exitPos = this.findSafeExitPosition();
      this.playerPos.copy(exitPos);
      this.playerVel.set(0, 0, 0);
      if (this.playerRig) {
        this.playerRig.root.position.copy(this.playerPos);
        this.playerRig.root.visible = true;
      }
      this.audio.setEngineRunning(false);
      this.emitHud();
    }
  }

  public toggleMute(): void {
    this.audio.unlock();
    this.audio.setMuted(!this.audio.isMuted());
    this.emitHud();
  }

  public captureScreenshot(): void {
    if (!this.renderer) return;
    this.renderer.render(this.scene, this.camera);
    const dataUrl = this.renderer.domElement.toDataURL('image/png');
    const a = document.createElement('a');
    a.href = dataUrl;
    a.download = `reduced-town-street-${Date.now()}.png`;
    a.click();
  }

  private getGroundHeight(x: number, z: number): number {
    for (let i = 0; i < this.sidewalks.length; i++) {
      const s = this.sidewalks[i];
      if (x >= s.minX && x <= s.maxX && z >= s.minZ && z <= s.maxZ) {
        return s.maxY;
      }
    }
    return 0.0;
  }

  private resolveCircleCollisions(pos: THREE.Vector3, radius: number, includeCar: boolean): boolean {
    let hit = false;
    const bound = OUTER_ROAD_EDGE - radius;
    if (pos.x < -bound) {
      pos.x = -bound;
      hit = true;
    } else if (pos.x > bound) {
      pos.x = bound;
      hit = true;
    }
    if (pos.z < -bound) {
      pos.z = -bound;
      hit = true;
    } else if (pos.z > bound) {
      pos.z = bound;
      hit = true;
    }

    for (let i = 0; i < this.colliders.length; i++) {
      const b = this.colliders[i];
      const closestX = Math.max(b.minX, Math.min(pos.x, b.maxX));
      const closestZ = Math.max(b.minZ, Math.min(pos.z, b.maxZ));
      const dx = pos.x - closestX;
      const dz = pos.z - closestZ;
      const distSq = dx * dx + dz * dz;
      if (distSq < radius * radius) {
        hit = true;
        if (distSq > 0.00001) {
          const dist = Math.sqrt(distSq);
          const push = radius - dist;
          pos.x += (dx / dist) * push;
          pos.z += (dz / dist) * push;
        } else {
          // Push out along nearest edge
          const penL = Math.abs(pos.x - b.minX);
          const penR = Math.abs(b.maxX - pos.x);
          const penT = Math.abs(pos.z - b.minZ);
          const penB = Math.abs(b.maxZ - pos.z);
          const m = Math.min(penL, penR, penT, penB);
          if (m === penL) pos.x = b.minX - radius;
          else if (m === penR) pos.x = b.maxX + radius;
          else if (m === penT) pos.z = b.minZ - radius;
          else pos.z = b.maxZ + radius;
        }
      }
    }

    if (includeCar) {
      // Solid pedestrian vs car collision in car local space
      const dx = pos.x - this.carPos.x;
      const dz = pos.z - this.carPos.z;
      const c = Math.cos(-this.carYaw);
      const s = Math.sin(-this.carYaw);
      const lx = dx * c - dz * s;
      const lz = dx * s + dz * c;
      const hx = 1.0 + radius;
      const hz = 2.22 + radius;
      if (Math.abs(lx) < hx && Math.abs(lz) < hz) {
        const penX = hx - Math.abs(lx);
        const penZ = hz - Math.abs(lz);
        let nlx = lx;
        let nlz = lz;
        if (penX < penZ) nlx = lx >= 0 ? hx : -hx;
        else nlz = lz >= 0 ? hz : -hz;
        const ic = Math.cos(this.carYaw);
        const is = Math.sin(this.carYaw);
        pos.x = this.carPos.x + nlx * ic - nlz * is;
        pos.z = this.carPos.z + nlx * is + nlz * ic;
        hit = true;
      }
    }
    return hit;
  }

  private isSpotClear(x: number, z: number, radius: number): boolean {
    if (Math.abs(x) > OUTER_ROAD_EDGE - 0.6 || Math.abs(z) > OUTER_ROAD_EDGE - 0.6) return false;
    for (let i = 0; i < this.colliders.length; i++) {
      const b = this.colliders[i];
      const cx = Math.max(b.minX, Math.min(x, b.maxX));
      const cz = Math.max(b.minZ, Math.min(z, b.maxZ));
      const dx = x - cx;
      const dz = z - cz;
      if (dx * dx + dz * dz < radius * radius) return false;
    }
    return true;
  }

  private findSafeExitPosition(): THREE.Vector3 {
    const candidates: Array<[number, number]> = [
      [-1.9, -0.15],
      [1.9, -0.15],
      [-2.5, 0.6],
      [0, 3.1],
      [0, -3.1],
    ];
    const c = Math.cos(this.carYaw);
    const s = Math.sin(this.carYaw);
    for (const [lx, lz] of candidates) {
      const wx = this.carPos.x + lx * c + lz * s;
      const wz = this.carPos.z - lx * s + lz * c;
      if (this.isSpotClear(wx, wz, 0.48)) {
        return new THREE.Vector3(wx, this.getGroundHeight(wx, wz), wz);
      }
    }
    return new THREE.Vector3(this.carPos.x, 1.9, this.carPos.z);
  }

  private stepSimulation(dt: number): void {
    this.bumpCooldown = Math.max(0, this.bumpCooldown - dt);
    this.manualOrbitTimer = Math.max(0, this.manualOrbitTimer - dt);

    // --- Player Update (ON_FOOT) ---
    if (this.mode === 'ON_FOOT') {
      let mx = (this.keys.has('KeyD') || this.keys.has('ArrowRight') ? 1 : 0) -
        (this.keys.has('KeyA') || this.keys.has('ArrowLeft') ? 1 : 0) +
        this.touchInput.moveX;
      let my = (this.keys.has('KeyS') || this.keys.has('ArrowDown') ? 1 : 0) -
        (this.keys.has('KeyW') || this.keys.has('ArrowUp') ? 1 : 0) +
        this.touchInput.moveY;
      const mag = Math.hypot(mx, my);
      if (mag > 1) {
        mx /= mag;
        my /= mag;
      }

      const sinY = Math.sin(this.camYaw);
      const cosY = Math.cos(this.camYaw);
      // Camera forward is (-sinY, -cosY), right is (cosY, -sinY)
      const wishX = mx * cosY + my * sinY;
      const wishZ = -mx * sinY + my * cosY;

      const sprinting =
        (this.keys.has('ShiftLeft') || this.keys.has('ShiftRight') || this.touchInput.sprint || mag > 0.88) &&
        mag > 0.45;
      const targetSpd = (sprinting ? SPRINT_SPEED : WALK_SPEED) * Math.min(1, mag);
      const accel = this.playerOnFloor ? (mag > 0.05 ? 26 : 22) : 8.5;

      const tx = mag > 0.05 ? (wishX / Math.max(0.001, Math.hypot(wishX, wishZ))) * targetSpd : 0;
      const tz = mag > 0.05 ? (wishZ / Math.max(0.001, Math.hypot(wishX, wishZ))) * targetSpd : 0;

      const stepAcc = accel * dt;
      this.playerVel.x += Math.max(-stepAcc, Math.min(stepAcc, tx - this.playerVel.x));
      this.playerVel.z += Math.max(-stepAcc, Math.min(stepAcc, tz - this.playerVel.z));

      // Jump
      const jumpPressed = this.keys.has('Space') || this.touchInput.jumpQueued;
      this.touchInput.jumpQueued = false;
      if (jumpPressed && this.playerOnFloor) {
        this.playerVel.y = JUMP_VELOCITY;
        this.playerOnFloor = false;
      }

      this.playerVel.y -= GRAVITY * dt;
      this.playerPos.x += this.playerVel.x * dt;
      this.playerPos.z += this.playerVel.z * dt;
      this.playerPos.y += this.playerVel.y * dt;

      this.resolveCircleCollisions(this.playerPos, 0.38, true);

      const groundY = this.getGroundHeight(this.playerPos.x, this.playerPos.z);
      if (this.playerPos.y <= groundY) {
        this.playerPos.y = groundY;
        this.playerVel.y = 0;
        this.playerOnFloor = true;
      } else if (this.playerPos.y - groundY < 0.16 && this.playerVel.y <= 0) {
        this.playerPos.y = groundY;
        this.playerVel.y = 0;
        this.playerOnFloor = true;
      }

      const hSpeed = Math.hypot(this.playerVel.x, this.playerVel.z);
      if (hSpeed > 0.25) {
        const targetYaw = Math.atan2(-this.playerVel.x, -this.playerVel.z);
        this.playerYaw = lerpAngle(this.playerYaw, targetYaw, Math.min(1, dt * 12));
      }

      if (this.playerRig) {
        this.playerRig.root.position.copy(this.playerPos);
        this.playerRig.root.rotation.y = this.playerYaw;
        this.playerRig.update(dt, hSpeed, this.playerOnFloor, this.playerVel.y, (sb) => {
          this.audio.playFootstep(sb);
        });
      }

      const near = this.playerPos.distanceTo(this.carPos) <= ENTER_RADIUS;
      if (near !== this.canEnterCar) {
        this.canEnterCar = near;
        this.emitHud();
      }
    }

    // --- Vehicle Update (Always steps so car coasts to stop when exited) ---
    let throttle = 0;
    let brake = 0;
    let steerIn = 0;
    if (this.mode === 'DRIVING') {
      throttle = this.keys.has('KeyW') || this.keys.has('ArrowUp') || this.touchInput.gas ? 1 : 0;
      brake = this.keys.has('KeyS') || this.keys.has('ArrowDown') || this.keys.has('Space') || this.touchInput.brake ? 1 : 0;
      const kbSteer =
        (this.keys.has('KeyA') || this.keys.has('ArrowLeft') ? 1 : 0) -
        (this.keys.has('KeyD') || this.keys.has('ArrowRight') ? 1 : 0);
      steerIn = Math.max(-1, Math.min(1, kbSteer - this.touchInput.steerX));
    }

    const prevSpd = this.carSpeed;
    let brakeLightOn = false;
    if (this.mode === 'DRIVING') {
      if (throttle > 0.05) {
        if (this.carSpeed < -0.5) {
          this.carSpeed = Math.min(0, this.carSpeed + 22 * dt);
          brakeLightOn = true;
        } else {
          const taper = Math.max(0.25, 1 - (this.carSpeed / CAR_MAX_FWD) * 0.62);
          this.carSpeed = Math.min(CAR_MAX_FWD, this.carSpeed + 13.8 * taper * dt);
        }
      } else if (brake > 0.05) {
        brakeLightOn = true;
        if (this.carSpeed > 0.5) {
          this.carSpeed = Math.max(0, this.carSpeed - 22.5 * dt);
        } else {
          this.carSpeed = Math.max(-CAR_MAX_REV, this.carSpeed - 8.5 * dt);
        }
      } else {
        const drag = 4.6 * dt;
        if (Math.abs(this.carSpeed) <= drag) this.carSpeed = 0;
        else this.carSpeed -= Math.sign(this.carSpeed) * drag;
      }
    } else {
      const parkBrake = 16.0 * dt;
      if (Math.abs(this.carSpeed) <= parkBrake) this.carSpeed = 0;
      else this.carSpeed -= Math.sign(this.carSpeed) * parkBrake;
    }

    const spdRatio = Math.min(1, Math.abs(this.carSpeed) / CAR_MAX_FWD);
    const maxSteer = THREE.MathUtils.degToRad(THREE.MathUtils.lerp(32, 15, spdRatio * 0.85));
    const targetSteer = steerIn * maxSteer;
    this.carSteerAngle = THREE.MathUtils.damp(this.carSteerAngle, targetSteer, 11, dt);

    // Cornering yaw rate
    const turnFactor = Math.min(1, Math.abs(this.carSpeed) / 3.0);
    if (turnFactor > 0.02) {
      const dirSign = this.carSpeed >= 0 ? 1 : -1;
      const yawRate = (this.carSteerAngle / THREE.MathUtils.degToRad(32)) * dirSign * turnFactor * THREE.MathUtils.lerp(2.25, 1.45, spdRatio);
      this.carYaw += yawRate * dt;
    }

    // Move along car forward (-sin(yaw), -cos(yaw))
    const fwdX = -Math.sin(this.carYaw);
    const fwdZ = -Math.cos(this.carYaw);
    this.carPos.x += fwdX * this.carSpeed * dt;
    this.carPos.z += fwdZ * this.carSpeed * dt;

    // Multi-sphere chassis collision against buildings & props (zero wall clipping!)
    const hitCenter = this.resolveCircleCollisions(this.carPos, 1.25, false);
    // Also check nose & tail offset points
    _vecA.set(this.carPos.x + fwdX * 1.15, 0, this.carPos.z + fwdZ * 1.15);
    const hitNose = this.resolveCircleCollisions(_vecA, 0.96, false);
    if (hitNose) {
      this.carPos.x = _vecA.x - fwdX * 1.15;
      this.carPos.z = _vecA.z - fwdZ * 1.15;
    }
    _vecB.set(this.carPos.x - fwdX * 1.15, 0, this.carPos.z - fwdZ * 1.15);
    const hitTail = this.resolveCircleCollisions(_vecB, 0.96, false);
    if (hitTail) {
      this.carPos.x = _vecB.x + fwdX * 1.15;
      this.carPos.z = _vecB.z + fwdZ * 1.15;
    }

    if (hitCenter || hitNose || hitTail) {
      if (Math.abs(this.carSpeed) > 2.2 && this.bumpCooldown <= 0) {
        this.audio.playBump(Math.abs(this.carSpeed) / 16);
        this.bumpCooldown = 0.35;
      }
      this.carSpeed *= -0.18;
    }

    // Smooth sidewalk curb ride height
    const roadY = this.getGroundHeight(this.carPos.x, this.carPos.z);
    this.carPos.y = THREE.MathUtils.damp(this.carPos.y, roadY + CAR_WHEEL_RADIUS, 16, dt);
    this.carRoot.position.copy(this.carPos);
    this.carRoot.rotation.y = this.carYaw;

    // Spin wheels & steer front wheels
    this.wheelSpinRad -= (this.carSpeed / CAR_WHEEL_RADIUS) * dt;
    for (let i = 0; i < this.wheelSteerPivots.length; i++) {
      if (i < 2) this.wheelSteerPivots[i].rotation.y = this.carSteerAngle;
      this.wheelSpinNodes[i].rotation.x = this.wheelSpinRad;
    }

    // Expressive chassis pitch (squat/dive) & cornering roll
    const longAccelG = Math.max(-1.2, Math.min(1.2, (this.carSpeed - prevSpd) / Math.max(0.001, dt) / 9.81));
    const targetPitch = longAccelG * 0.048;
    const targetRoll = THREE.MathUtils.clamp(
      this.carSteerAngle * Math.max(-1, Math.min(1, this.carSpeed / 13)) * 0.16,
      -0.075,
      0.075
    );
    this.carPitchVis = THREE.MathUtils.damp(this.carPitchVis, targetPitch, 9, dt);
    this.carRollVis = THREE.MathUtils.damp(this.carRollVis, targetRoll, 9, dt);
    this.carTiltPivot.rotation.x = this.carPitchVis;
    this.carTiltPivot.rotation.z = this.carRollVis;

    if (this.taillightMat) {
      const targetGlow = brakeLightOn ? 2.4 : this.mode === 'DRIVING' ? 0.65 : 0.18;
      this.taillightMat.emissiveIntensity = THREE.MathUtils.damp(this.taillightMat.emissiveIntensity, targetGlow, 14, dt);
    }

    if (this.mode === 'DRIVING') {
      this.audio.updateEngineRpm(spdRatio, throttle);
    }

    // --- Spring-Arm Chase Camera ---
    this.updateCamera(dt);

    // Keep shadow frustum centered around active actor for crisp shadows everywhere in the 5x5 city
    if (this.sunLight) {
      const focus = this.mode === 'DRIVING' ? this.carPos : this.playerPos;
      this.sunLight.position.set(focus.x + 34, 42, focus.z + 36);
      this.sunLight.target.position.set(focus.x, 0, focus.z);
    }

    this.hudEmitAccum += dt;
    if (this.mode === 'DRIVING' && this.hudEmitAccum >= 0.08) {
      this.hudEmitAccum = 0;
      this.emitHud();
    }
  }

  private updateCamera(dt: number): void {
    const isDriving = this.mode === 'DRIVING';
    const focus = isDriving ? this.carPos : this.playerPos;
    const heightOff = isDriving ? 1.72 : 1.56;

    // Smooth auto-align behind moving vehicle when user isn't orbiting
    if (isDriving && this.manualOrbitTimer <= 0 && Math.abs(this.carSpeed) > 1.2) {
      const desiredYaw = this.carSpeed < -1.5 ? this.carYaw + Math.PI : this.carYaw;
      this.camYaw = lerpAngle(this.camYaw, desiredYaw, Math.min(1, dt * 3.4));
    }

    // Gentle speed-synced walk head-bob (never nausea-inducing)
    let bobY = 0;
    if (!isDriving && this.playerOnFloor) {
      const hSpd = Math.hypot(this.playerVel.x, this.playerVel.z);
      if (hSpd > 0.35) {
        this.bobPhase += dt * Math.max(6, Math.min(13.5, hSpd * 1.55));
        const amp = THREE.MathUtils.lerp(0.022, 0.044, Math.max(0, Math.min(1, (hSpd - 6.2) / 3.3)));
        bobY = Math.sin(this.bobPhase) * amp;
      } else {
        this.bobPhase = 0;
      }
    }

    _rayOrigin.set(focus.x, focus.y + heightOff + bobY, focus.z);

    const targetArm = isDriving ? 6.4 + Math.min(1, Math.abs(this.carSpeed) / CAR_MAX_FWD) * 1.2 : 4.55;
    this.camArmLen = THREE.MathUtils.damp(this.camArmLen, targetArm, 5.5, dt);

    const cosP = Math.cos(this.camPitch);
    const sinP = Math.sin(this.camPitch);
    _rayDir.set(Math.sin(this.camYaw) * cosP, -sinP, Math.cos(this.camYaw) * cosP).normalize();

    // SpringArm occlusion check against buildings so camera never clips inside walls
    let safeDist = this.camArmLen;
    if (this.occluders.length > 0) {
      this.raycaster.set(_rayOrigin, _rayDir);
      this.raycaster.far = this.camArmLen;
      const hits = this.raycaster.intersectObjects(this.occluders, true);
      if (hits.length > 0) {
        safeDist = Math.max(1.2, hits[0].distance - 0.35);
      }
    }

    _vecA.copy(_rayOrigin).addScaledVector(_rayDir, safeDist);
    if (_vecA.y < 0.45) _vecA.y = 0.45;

    const rate = isDriving ? 11 : 13;
    this.camPos.x = THREE.MathUtils.damp(this.camPos.x, _vecA.x, rate, dt);
    this.camPos.y = THREE.MathUtils.damp(this.camPos.y, _vecA.y, rate, dt);
    this.camPos.z = THREE.MathUtils.damp(this.camPos.z, _vecA.z, rate, dt);

    this.camera.position.copy(this.camPos);
    this.camera.lookAt(_rayOrigin);

    const targetFov = isDriving
      ? 66 + Math.min(1, Math.abs(this.carSpeed) / CAR_MAX_FWD) * 11
      : this.playerOnFloor && Math.hypot(this.playerVel.x, this.playerVel.z) > 7.5
      ? 69
      : 65;
    if (Math.abs(this.camera.fov - targetFov) > 0.05) {
      this.camera.fov = THREE.MathUtils.damp(this.camera.fov, targetFov, 5.5, dt);
      this.camera.updateProjectionMatrix();
    }
  }

  private afterDraw(cb: () => void): void {
    if (!this.renderer || this.disposed) return;
    const gl = this.renderer.getContext() as WebGL2RenderingContext;
    if (typeof gl.fenceSync === 'function') {
      const sync = gl.fenceSync(gl.SYNC_GPU_COMMANDS_COMPLETE, 0);
      gl.flush();
      const poll = () => {
        if (this.disposed) {
          if (sync) gl.deleteSync(sync);
          return;
        }
        const state = sync && gl.getSyncParameter(sync, gl.SYNC_STATUS);
        if (state === gl.UNSIGNALED) {
          this.frameId = window.setTimeout(poll, 5);
        } else {
          if (sync) gl.deleteSync(sync);
          this.frameId = window.setTimeout(cb, 80);
        }
      };
      this.frameId = window.setTimeout(poll, 5);
    } else {
      this.frameId = window.setTimeout(cb, 80);
    }
  }

  private scheduleNextFrame(): void {
    if (this.disposed) return;
    const tick = () => {
      if (this.disposed || !this.renderer) return;
      const now = performance.now();
      const dt = Math.min(0.05, Math.max(0.001, (now - this.lastTimeMs) / 1000));
      this.lastTimeMs = now;

      this.stepSimulation(dt);
      this.renderer.render(this.scene, this.camera);

      if (this.isSoftwareGl) {
        this.afterDraw(tick);
      } else {
        this.frameId = requestAnimationFrame(tick);
      }
    };
    if (this.isSoftwareGl) {
      this.frameId = window.setTimeout(tick, 16);
    } else {
      this.frameId = requestAnimationFrame(tick);
    }
  }

  private handleResize = (): void => {
    if (!this.renderer) return;
    const w = this.container.clientWidth || window.innerWidth;
    const h = this.container.clientHeight || window.innerHeight;
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(w, h);
  };

  private handleKeyDown = (e: KeyboardEvent): void => {
    this.audio.unlock();
    if (['Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.code)) {
      e.preventDefault();
    }
    this.keys.add(e.code);
    if (!e.repeat && e.code === 'KeyF') {
      this.toggleVehicleInteract();
    } else if (!e.repeat && e.code === 'F12') {
      e.preventDefault();
      this.captureScreenshot();
    }
  };

  private handleKeyUp = (e: KeyboardEvent): void => {
    this.keys.delete(e.code);
  };

  private handlePointerDown = (e: PointerEvent): void => {
    this.audio.unlock();
    if (this.draggingLook) return;
    this.draggingLook = true;
    this.lookPointerId = e.pointerId;
    this.lastPointerX = e.clientX;
    this.lastPointerY = e.clientY;
  };

  private handlePointerMove = (e: PointerEvent): void => {
    if (!this.draggingLook || e.pointerId !== this.lookPointerId) return;
    const dx = e.clientX - this.lastPointerX;
    const dy = e.clientY - this.lastPointerY;
    this.lastPointerX = e.clientX;
    this.lastPointerY = e.clientY;

    const sens = e.pointerType === 'touch' ? 0.0052 : 0.0042;
    this.camYaw -= dx * sens;
    this.camPitch = THREE.MathUtils.clamp(this.camPitch - dy * sens, THREE.MathUtils.degToRad(-52), THREE.MathUtils.degToRad(26));
    this.manualOrbitTimer = 1.8;
  };

  private handlePointerUp = (e: PointerEvent): void => {
    if (e.pointerId === this.lookPointerId) {
      this.draggingLook = false;
      this.lookPointerId = -1;
    }
  };

  private handleContextLost = (e: Event): void => {
    e.preventDefault();
    cancelAnimationFrame(this.frameId);
    clearTimeout(this.frameId);
  };

  private handleContextRestored = (): void => {
    this.lastTimeMs = performance.now();
    this.scheduleNextFrame();
  };

  private emitHud(webglError: string | null = null): void {
    this.onHudChange({
      mode: this.mode,
      canEnterCar: this.canEnterCar,
      speedKmh: Math.round(Math.abs(this.carSpeed) * 3.6),
      audioUnlocked: this.audio.isUnlocked(),
      muted: this.audio.isMuted(),
      loading: this.loading,
      loadProgress: this.loadProgress,
      webglError,
    });
  }

  public dispose(): void {
    this.disposed = true;
    cancelAnimationFrame(this.frameId);
    clearTimeout(this.frameId);
    window.removeEventListener('resize', this.handleResize);
    window.removeEventListener('keydown', this.handleKeyDown);
    window.removeEventListener('keyup', this.handleKeyUp);
    window.removeEventListener('pointermove', this.handlePointerMove);
    window.removeEventListener('pointerup', this.handlePointerUp);
    window.removeEventListener('pointercancel', this.handlePointerUp);
    this.audio.dispose();

    if (this.renderer) {
      const c = this.renderer.domElement;
      c.removeEventListener('pointerdown', this.handlePointerDown);
      c.removeEventListener('webglcontextlost', this.handleContextLost);
      c.removeEventListener('webglcontextrestored', this.handleContextRestored);
      this.renderer.dispose();
      c.remove();
      this.renderer = null;
    }
  }
}
