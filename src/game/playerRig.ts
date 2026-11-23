import * as THREE from 'three';

const WALK_STRIDE_LENGTH = 1.48;
const SPRINT_STRIDE_LENGTH = 2.05;

/**
 * Articulated third-person PBR humanoid rig mirroring scripts/player/PlayerAnimator.gd.
 * Gait phase advances strictly from actual horizontal ground velocity (zero foot sliding)
 * and emits foot-plant callbacks for synced asphalt footstep audio.
 */
export class PlayerRig {
  public readonly root = new THREE.Group();
  private readonly hips = new THREE.Group();
  private readonly torso = new THREE.Group();
  private readonly armL = new THREE.Group();
  private readonly armR = new THREE.Group();
  private readonly forearmL = new THREE.Group();
  private readonly forearmR = new THREE.Group();
  private readonly legL = new THREE.Group();
  private readonly legR = new THREE.Group();
  private readonly shinL = new THREE.Group();
  private readonly shinR = new THREE.Group();
  private readonly contactShadow: THREE.Mesh;

  private gaitPhase = 0;
  private prevStepHalf = 0;
  private idleTime = 0;

  constructor(contactShadowMat: THREE.MeshBasicMaterial, castShadow: boolean) {
    this.root.name = 'PlayerRig';

    const makeMat = (hex: number, roughness: number, metalness = 0.0) =>
      new THREE.MeshStandardMaterial({ color: hex, roughness, metalness });

    const matJacket = makeMat(0x3d4f47, 0.84);
    const matShirt = makeMat(0xdcd6cc, 0.86);
    const matJeans = makeMat(0x283857, 0.88);
    const matSkin = makeMat(0xd1a385, 0.65);
    const matHair = makeMat(0x241c17, 0.72);
    const matShoe = makeMat(0xe0e0dc, 0.58);
    const matSole = makeMat(0x242429, 0.82);
    const matPack = makeMat(0x333138, 0.78);

    const addPart = (parent: THREE.Group, geo: THREE.BufferGeometry, mat: THREE.Material, x: number, y: number, z: number) => {
      const m = new THREE.Mesh(geo, mat);
      m.position.set(x, y, z);
      m.castShadow = castShadow;
      m.receiveShadow = true;
      parent.add(m);
      return m;
    };

    // Soft radial AO contact shadow directly beneath feet
    this.contactShadow = new THREE.Mesh(new THREE.PlaneGeometry(0.95, 0.95), contactShadowMat);
    this.contactShadow.rotation.x = -Math.PI * 0.5;
    this.contactShadow.position.y = 0.025;
    this.root.add(this.contactShadow);

    // Pelvis / Hips
    this.hips.position.set(0, 0.94, 0);
    this.root.add(this.hips);
    addPart(this.hips, new THREE.BoxGeometry(0.32, 0.16, 0.21), matJeans, 0, 0, 0);

    // Torso & Jacket + Daypack
    this.torso.position.set(0, 0.08, 0);
    this.hips.add(this.torso);
    addPart(this.torso, new THREE.BoxGeometry(0.38, 0.44, 0.23), matJacket, 0, 0.24, 0);
    addPart(this.torso, new THREE.BoxGeometry(0.14, 0.42, 0.24), matShirt, 0, 0.23, -0.006);
    addPart(this.torso, new THREE.BoxGeometry(0.28, 0.34, 0.12), matPack, 0, 0.24, 0.16);

    // Head & Hair
    const head = new THREE.Group();
    head.position.set(0, 0.49, 0);
    this.torso.add(head);
    addPart(head, new THREE.CylinderGeometry(0.055, 0.06, 0.1, 10), matSkin, 0, 0.03, 0);
    addPart(head, new THREE.SphereGeometry(0.118, 14, 12), matSkin, 0, 0.16, 0);
    const hair = addPart(head, new THREE.SphereGeometry(0.124, 14, 10), matHair, 0, 0.205, 0.014);
    hair.scale.set(1, 0.72, 1.02);

    // Arms
    const upperArmGeo = new THREE.CapsuleGeometry(0.055, 0.2, 6, 10);
    const lowerArmGeo = new THREE.CapsuleGeometry(0.046, 0.19, 6, 10);
    const handGeo = new THREE.SphereGeometry(0.045, 8, 8);

    this.armL.position.set(-0.24, 0.42, 0);
    this.torso.add(this.armL);
    addPart(this.armL, upperArmGeo, matJacket, 0, -0.14, 0);
    this.forearmL.position.set(0, -0.28, 0);
    this.armL.add(this.forearmL);
    addPart(this.forearmL, lowerArmGeo, matJacket, 0, -0.13, 0);
    addPart(this.forearmL, handGeo, matSkin, 0, -0.27, 0);

    this.armR.position.set(0.24, 0.42, 0);
    this.torso.add(this.armR);
    addPart(this.armR, upperArmGeo, matJacket, 0, -0.14, 0);
    this.forearmR.position.set(0, -0.28, 0);
    this.armR.add(this.forearmR);
    addPart(this.forearmR, lowerArmGeo, matJacket, 0, -0.13, 0);
    addPart(this.forearmR, handGeo, matSkin, 0, -0.27, 0);

    // Legs & Sneakers
    const thighGeo = new THREE.CapsuleGeometry(0.075, 0.3, 6, 10);
    const shinGeo = new THREE.CapsuleGeometry(0.062, 0.3, 6, 10);
    const shoeGeo = new THREE.BoxGeometry(0.11, 0.09, 0.24);
    const soleGeo = new THREE.BoxGeometry(0.115, 0.03, 0.25);

    this.legL.position.set(-0.105, -0.05, 0);
    this.hips.add(this.legL);
    addPart(this.legL, thighGeo, matJeans, 0, -0.21, 0);
    this.shinL.position.set(0, -0.42, 0);
    this.legL.add(this.shinL);
    addPart(this.shinL, shinGeo, matJeans, 0, -0.2, 0);
    addPart(this.shinL, shoeGeo, matShoe, 0, -0.43, -0.04);
    addPart(this.shinL, soleGeo, matSole, 0, -0.47, -0.04);

    this.legR.position.set(0.105, -0.05, 0);
    this.hips.add(this.legR);
    addPart(this.legR, thighGeo, matJeans, 0, -0.21, 0);
    this.shinR.position.set(0, -0.42, 0);
    this.legR.add(this.shinR);
    addPart(this.shinR, shinGeo, matJeans, 0, -0.2, 0);
    addPart(this.shinR, shoeGeo, matShoe, 0, -0.43, -0.04);
    addPart(this.shinR, soleGeo, matSole, 0, -0.47, -0.04);
  }

  public update(
    dt: number,
    speed: number,
    onFloor: boolean,
    velY: number,
    onFootstep: (sprintBlend: number) => void
  ): void {
    this.idleTime += dt;
    const smooth = Math.min(1, dt * 14);
    this.contactShadow.visible = onFloor;

    if (!onFloor) {
      const jt = Math.max(-1, Math.min(1, velY / 6.5));
      this.hips.position.y = THREE.MathUtils.lerp(this.hips.position.y, 0.96, smooth);
      this.torso.rotation.x = THREE.MathUtils.lerp(this.torso.rotation.x, -0.1, smooth);
      this.legL.rotation.x = THREE.MathUtils.lerp(this.legL.rotation.x, 0.45 * jt + 0.25, smooth);
      this.legR.rotation.x = THREE.MathUtils.lerp(this.legR.rotation.x, -0.35, smooth);
      this.shinL.rotation.x = THREE.MathUtils.lerp(this.shinL.rotation.x, -0.55, smooth);
      this.shinR.rotation.x = THREE.MathUtils.lerp(this.shinR.rotation.x, -0.35, smooth);
      this.armL.rotation.x = THREE.MathUtils.lerp(this.armL.rotation.x, -0.55, smooth);
      this.armR.rotation.x = THREE.MathUtils.lerp(this.armR.rotation.x, 0.35, smooth);
      this.forearmL.rotation.x = THREE.MathUtils.lerp(this.forearmL.rotation.x, 0.45, smooth);
      this.forearmR.rotation.x = THREE.MathUtils.lerp(this.forearmR.rotation.x, 0.45, smooth);
      return;
    }

    if (speed < 0.12) {
      const breath = Math.sin(this.idleTime * 2.1);
      this.hips.position.y = THREE.MathUtils.lerp(this.hips.position.y, 0.94 + breath * 0.008, smooth);
      this.torso.rotation.x = THREE.MathUtils.lerp(this.torso.rotation.x, 0.02 + breath * 0.015, smooth);
      this.torso.rotation.y = THREE.MathUtils.lerp(this.torso.rotation.y, 0, smooth);
      this.legL.rotation.x = THREE.MathUtils.lerp(this.legL.rotation.x, 0, smooth);
      this.legR.rotation.x = THREE.MathUtils.lerp(this.legR.rotation.x, 0, smooth);
      this.shinL.rotation.x = THREE.MathUtils.lerp(this.shinL.rotation.x, 0, smooth);
      this.shinR.rotation.x = THREE.MathUtils.lerp(this.shinR.rotation.x, 0, smooth);
      this.armL.rotation.x = THREE.MathUtils.lerp(this.armL.rotation.x, 0.05, smooth);
      this.armR.rotation.x = THREE.MathUtils.lerp(this.armR.rotation.x, 0.05, smooth);
      this.forearmL.rotation.x = THREE.MathUtils.lerp(this.forearmL.rotation.x, 0.14, smooth);
      this.forearmR.rotation.x = THREE.MathUtils.lerp(this.forearmR.rotation.x, 0.14, smooth);
      return;
    }

    const sprintBlend = Math.max(0, Math.min(1, (speed - 6.2) / (9.5 - 6.2)));
    const strideLen = THREE.MathUtils.lerp(WALK_STRIDE_LENGTH, SPRINT_STRIDE_LENGTH, sprintBlend);
    this.gaitPhase += (speed / strideLen) * Math.PI * 2 * dt;

    const curHalf = Math.floor(this.gaitPhase / Math.PI);
    if (curHalf !== this.prevStepHalf) {
      this.prevStepHalf = curHalf;
      onFootstep(sprintBlend);
    }

    const s = Math.sin(this.gaitPhase);
    const c = Math.cos(this.gaitPhase);
    const amp = Math.max(0.25, Math.min(1, speed / 6.2)) * THREE.MathUtils.lerp(0.62, 0.96, sprintBlend);
    const bob = Math.abs(c) * THREE.MathUtils.lerp(0.042, 0.082, sprintBlend);

    this.hips.position.y = THREE.MathUtils.lerp(this.hips.position.y, 0.93 - bob, smooth);
    this.torso.rotation.x = THREE.MathUtils.lerp(this.torso.rotation.x, THREE.MathUtils.lerp(-0.06, -0.22, sprintBlend), smooth);
    this.torso.rotation.y = s * THREE.MathUtils.lerp(0.09, 0.18, sprintBlend);

    this.legL.rotation.x = s * amp;
    this.legR.rotation.x = -s * amp;
    this.shinL.rotation.x = -Math.max(0, -c) * THREE.MathUtils.lerp(0.65, 1.15, sprintBlend) - Math.max(0, -s) * 0.25;
    this.shinR.rotation.x = -Math.max(0, c) * THREE.MathUtils.lerp(0.65, 1.15, sprintBlend) - Math.max(0, s) * 0.25;

    const armAmp = amp * THREE.MathUtils.lerp(0.75, 1.05, sprintBlend);
    this.armL.rotation.x = -s * armAmp;
    this.armR.rotation.x = s * armAmp;
    const elbowBase = THREE.MathUtils.lerp(0.26, 0.95, sprintBlend);
    this.forearmL.rotation.x = elbowBase + Math.max(0, -s) * 0.35;
    this.forearmR.rotation.x = elbowBase + Math.max(0, s) * 0.35;
  }
}
