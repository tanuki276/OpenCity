import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import type { ColliderBox } from './types';

export const GRID_HALF = 2;
export const ROAD_WIDTH = 9.6;
export const BLOCK_SIZE = 15.2;
export const CELL_PITCH = 24.8;
export const SIDEWALK_HEIGHT = 0.14;
export const OUTER_ROAD_EDGE = 2.5 * CELL_PITCH + ROAD_WIDTH * 0.5; // 66.8m

export interface LoadedCityResources {
  colliders: ColliderBox[];
  sidewalks: ColliderBox[];
  occluders: THREE.Object3D[];
  contactShadowMat: THREE.MeshBasicMaterial;
  carBodyTemplate: THREE.Group;
  carWheelTemplate: THREE.Group;
  applyPbrMaterials: (root: THREE.Object3D, tintHex?: THREE.Color, castShadow?: boolean) => void;
}

class SeededRng {
  private s: number;
  constructor(seed: number) {
    this.s = seed >>> 0;
  }
  next(): number {
    this.s = (this.s * 1664525 + 1013904223) >>> 0;
    return this.s / 4294967296;
  }
  range(min: number, max: number): number {
    return min + this.next() * (max - min);
  }
  int(min: number, max: number): number {
    return Math.floor(this.range(min, max + 1));
  }
}

export async function buildCityWorld(
  scene: THREE.Scene,
  renderer: THREE.WebGLRenderer,
  castShadows: boolean,
  onProgress?: (pct: number) => void
): Promise<LoadedCityResources> {
  const maxAniso = Math.min(8, renderer.capabilities.getMaxAnisotropy());
  const texLoader = new THREE.TextureLoader();
  const gltfLoader = new GLTFLoader();

  const texCache = new Map<string, THREE.Texture>();
  const loadTex = (file: string, isColor: boolean, repeatX = 1, repeatY = 1): THREE.Texture => {
    const key = `${file}:${repeatX.toFixed(2)}:${repeatY.toFixed(2)}`;
    const existing = texCache.get(key);
    if (existing) return existing;

    const baseKey = `${file}:1.00:1.00`;
    let tex: THREE.Texture;
    if (texCache.has(baseKey) && (repeatX !== 1 || repeatY !== 1)) {
      tex = texCache.get(baseKey)!.clone();
      tex.needsUpdate = true;
    } else {
      tex = texLoader.load(`/game-assets/textures/${file}`);
      tex.colorSpace = isColor ? THREE.SRGBColorSpace : THREE.NoColorSpace;
      tex.wrapS = THREE.RepeatWrapping;
      tex.wrapT = THREE.RepeatWrapping;
      tex.minFilter = THREE.LinearMipmapLinearFilter;
      tex.magFilter = THREE.LinearFilter;
      tex.anisotropy = maxAniso;
    }
    tex.repeat.set(repeatX, repeatY);
    texCache.set(key, tex);
    return tex;
  };

  // Preload all 16 sculpted GLB models concurrently
  const modelFiles = [
    'bldg_downtown_tower',
    'bldg_brick_midrise',
    'bldg_corner_shop',
    'bldg_suburban_house',
    'bldg_diner_market',
    'car_body',
    'car_wheel',
    'prop_streetlight',
    'prop_traffic_light',
    'prop_bench',
    'prop_tree',
    'prop_hydrant',
    'prop_vending',
    'prop_trashbin',
    'prop_utility_pole',
    'landmark_clock_fountain',
  ];

  const models = new Map<string, THREE.Group>();
  let loadedCount = 0;

  await Promise.all(
    modelFiles.map(async (name) => {
      const gltf = await gltfLoader.loadAsync(`/game-assets/models/${name}.glb`);
      models.set(name, gltf.scene);
      loadedCount += 1;
      onProgress?.(Math.round((loadedCount / modelFiles.length) * 100));
    })
  );

  // Material slot upgrades matching scripts/core/MaterialLibrary.gd
  const slotMatCache = new Map<string, THREE.MeshStandardMaterial>();
  const getSlotMaterial = (slotName: string): THREE.MeshStandardMaterial | null => {
    if (slotMatCache.has(slotName)) return slotMatCache.get(slotName)!;
    let mat: THREE.MeshStandardMaterial | null = null;

    const makeSlot = (
      albedo: string,
      normal?: string,
      rough?: string,
      roughVal = 0.86,
      metalVal = 0.0,
      tint = 0xffffff
    ) => {
      const m = new THREE.MeshStandardMaterial({
        color: tint,
        map: loadTex(albedo, true),
        roughness: rough ? 1.0 : roughVal,
        metalness: metalVal,
      });
      if (normal) {
        m.normalMap = loadTex(normal, false);
        m.normalScale.set(0.85, 0.85);
      }
      if (rough) {
        m.roughnessMap = loadTex(rough, false);
      }
      return m;
    };

    switch (slotName) {
      case 'mat_concrete':
        mat = makeSlot('sidewalk_albedo.png', 'sidewalk_normal.png', 'sidewalk_roughness.png', 0.86, 0.0);
        break;
      case 'mat_brick_red':
        mat = makeSlot('brick_red_albedo.png', 'brick_normal.png', 'brick_roughness.png', 0.88, 0.0);
        break;
      case 'mat_brick_tan':
        mat = makeSlot('brick_tan_albedo.png', 'brick_normal.png', 'brick_roughness.png', 0.88, 0.0);
        break;
      case 'mat_stucco_cream':
        mat = makeSlot('stucco_cream_albedo.png', 'stucco_normal.png', 'stucco_roughness.png', 0.84, 0.0);
        break;
      case 'mat_stucco_terracotta':
        mat = makeSlot('stucco_terracotta_albedo.png', 'stucco_normal.png', 'stucco_roughness.png', 0.84, 0.0);
        break;
      case 'mat_stucco_slate':
        mat = makeSlot('stucco_slate_albedo.png', 'stucco_normal.png', 'stucco_roughness.png', 0.80, 0.0);
        break;
      case 'mat_stucco_sage':
        mat = makeSlot('stucco_sage_albedo.png', 'stucco_normal.png', 'stucco_roughness.png', 0.84, 0.0);
        break;
      case 'mat_commercial_glass':
        mat = makeSlot('commercial_glass_albedo.png', 'commercial_glass_normal.png', 'commercial_glass_roughness.png', 0.14, 0.2);
        break;
      case 'mat_roof_gravel':
        mat = makeSlot('roof_gravel_albedo.png', 'roof_gravel_normal.png', undefined, 0.92, 0.0, 0xc2beb8);
        break;
      case 'mat_roof_shingle':
        mat = makeSlot('roof_gravel_albedo.png', 'roof_gravel_normal.png', undefined, 0.90, 0.0, 0x746258);
        break;
      case 'mat_bark':
        mat = makeSlot('bark_albedo.png', 'bark_normal.png', undefined, 0.92, 0.0);
        break;
      case 'mat_foliage':
        mat = makeSlot('foliage_albedo.png', 'foliage_normal.png', undefined, 0.85, 0.0);
        break;
      case 'mat_tire':
        mat = makeSlot('tire_tread_albedo.png', 'tire_tread_normal.png', undefined, 0.85, 0.05);
        break;
      default:
        return null;
    }
    slotMatCache.set(slotName, mat);
    return mat;
  };

  const applyPbrMaterials = (root: THREE.Object3D, tintColor?: THREE.Color, shouldCast = castShadows) => {
    root.traverse((obj) => {
      if (!(obj instanceof THREE.Mesh)) return;
      obj.castShadow = shouldCast;
      obj.receiveShadow = true;

      const orig = obj.material as THREE.MeshStandardMaterial | undefined;
      if (!orig) return;
      const upgraded = getSlotMaterial(orig.name);
      if (upgraded) {
        if (tintColor) {
          const cloned = upgraded.clone();
          cloned.color.multiply(tintColor);
          obj.material = cloned;
        } else {
          obj.material = upgraded;
        }
      } else if (tintColor && orig instanceof THREE.MeshStandardMaterial) {
        const cloned = orig.clone();
        cloned.color.multiply(tintColor);
        obj.material = cloned;
      }
    });
  };

  // Soft radial AO contact shadow material
  const contactShadowTex = loadTex('contact_shadow.png', true);
  contactShadowTex.wrapS = THREE.ClampToEdgeWrapping;
  contactShadowTex.wrapT = THREE.ClampToEdgeWrapping;
  const contactShadowMat = new THREE.MeshBasicMaterial({
    map: contactShadowTex,
    transparent: true,
    opacity: 0.72,
    depthWrite: false,
    polygonOffset: true,
    polygonOffsetFactor: -2,
    polygonOffsetUnits: -2,
  });

  // --- Bright American Afternoon Sky Dome (blue zenith -> warm sunlit horizon) ---
  const skyGeo = new THREE.SphereGeometry(230, 32, 18);
  const skyMat = new THREE.ShaderMaterial({
    side: THREE.BackSide,
    depthWrite: false,
    uniforms: {
      topColor: { value: new THREE.Color(0x367bd6) },
      horizonColor: { value: new THREE.Color(0xc4d8eb) },
      groundColor: { value: new THREE.Color(0x9fb0ba) },
      sunDir: { value: new THREE.Vector3(0.52, 0.62, 0.58).normalize() },
    },
    vertexShader: `
      varying vec3 vWorldPos;
      void main() {
        vec4 wp = modelMatrix * vec4(position, 1.0);
        vWorldPos = wp.xyz;
        gl_Position = projectionMatrix * viewMatrix * wp;
      }
    `,
    fragmentShader: `
      uniform vec3 topColor;
      uniform vec3 horizonColor;
      uniform vec3 groundColor;
      uniform vec3 sunDir;
      varying vec3 vWorldPos;
      void main() {
        vec3 dir = normalize(vWorldPos);
        float h = dir.y;
        vec3 col = h >= 0.0
          ? mix(horizonColor, topColor, pow(clamp(h, 0.0, 1.0), 0.52))
          : mix(horizonColor, groundColor, clamp(-h * 3.0, 0.0, 1.0));
        float sunAmt = max(dot(dir, sunDir), 0.0);
        col += vec3(1.0, 0.92, 0.76) * pow(sunAmt, 42.0) * 0.55;
        col += vec3(1.0, 0.96, 0.86) * pow(sunAmt, 420.0) * 1.1;
        gl_FragColor = vec4(col, 1.0);
      }
    `,
  });
  scene.add(new THREE.Mesh(skyGeo, skyMat));

  const cityGroup = new THREE.Group();
  cityGroup.name = 'ReducedTownCity';
  scene.add(cityGroup);

  const colliders: ColliderBox[] = [];
  const sidewalks: ColliderBox[] = [];
  const occluders: THREE.Object3D[] = [];
  const rng = new SeededRng(20261122);

  // --- Ground & Road Network ---
  const totalSpan = (GRID_HALF * 2 + 1) * CELL_PITCH + ROAD_WIDTH + 32;
  const plainAsphaltMat = new THREE.MeshStandardMaterial({
    map: loadTex('asphalt_albedo.png', true, totalSpan / 8, totalSpan / 8),
    normalMap: loadTex('asphalt_normal.png', false, totalSpan / 8, totalSpan / 8),
    roughnessMap: loadTex('asphalt_roughness.png', false, totalSpan / 8, totalSpan / 8),
    roughness: 1.0,
    metalness: 0.0,
  });
  const baseRoad = new THREE.Mesh(new THREE.PlaneGeometry(totalSpan, totalSpan), plainAsphaltMat);
  baseRoad.rotation.x = -Math.PI * 0.5;
  baseRoad.receiveShadow = true;
  cityGroup.add(baseRoad);

  const laneMat = new THREE.MeshStandardMaterial({
    map: loadTex('asphalt_lane_albedo.png', true, 1, BLOCK_SIZE / 6),
    normalMap: loadTex('asphalt_normal.png', false, 1, BLOCK_SIZE / 6),
    roughnessMap: loadTex('asphalt_roughness.png', false, 1, BLOCK_SIZE / 6),
    roughness: 1.0,
    polygonOffset: true,
    polygonOffsetFactor: -1,
    polygonOffsetUnits: -1,
  });
  const xwalkMat = new THREE.MeshStandardMaterial({
    map: loadTex('road_crosswalk_albedo.png', true, 1, 1),
    normalMap: loadTex('asphalt_normal.png', false, 1, 1),
    roughness: 0.88,
    polygonOffset: true,
    polygonOffsetFactor: -2,
    polygonOffsetUnits: -2,
  });
  const sidewalkMat = new THREE.MeshStandardMaterial({
    map: loadTex('sidewalk_albedo.png', true, 5, 5),
    normalMap: loadTex('sidewalk_normal.png', false, 5, 5),
    roughnessMap: loadTex('sidewalk_roughness.png', false, 5, 5),
    roughness: 1.0,
  });
  const plazaMat = new THREE.MeshStandardMaterial({
    map: loadTex('plaza_paver_albedo.png', true, 4.5, 4.5),
    normalMap: loadTex('plaza_paver_normal.png', false, 4.5, 4.5),
    roughnessMap: loadTex('plaza_paver_roughness.png', false, 4.5, 4.5),
    roughness: 1.0,
  });
  const grassMat = new THREE.MeshStandardMaterial({
    map: loadTex('grass_albedo.png', true, 3.5, 3.5),
    normalMap: loadTex('grass_normal.png', false, 3.5, 3.5),
    roughness: 0.92,
  });

  const laneGeo = new THREE.PlaneGeometry(ROAD_WIDTH, BLOCK_SIZE);
  const xwalkGeo = new THREE.PlaneGeometry(ROAD_WIDTH - 0.6, 2.4);

  const addRoadStrip = (x: number, y: number, z: number, geo: THREE.BufferGeometry, yaw: number, mat: THREE.Material) => {
    const m = new THREE.Mesh(geo, mat);
    m.rotation.order = 'YXZ';
    m.rotation.x = -Math.PI * 0.5;
    m.rotation.y = yaw;
    m.position.set(x, y, z);
    m.receiveShadow = true;
    cityGroup.add(m);
  };

  for (let i = 0; i < 6; i++) {
    const rx = (i - 2.5) * CELL_PITCH;
    for (let bz = -GRID_HALF; bz <= GRID_HALF; bz++) {
      const cz = bz * CELL_PITCH;
      addRoadStrip(rx, 0.012, cz, laneGeo, 0, laneMat);
      addRoadStrip(rx, 0.02, cz - BLOCK_SIZE * 0.5 + 1.3, xwalkGeo, 0, xwalkMat);
      addRoadStrip(rx, 0.02, cz + BLOCK_SIZE * 0.5 - 1.3, xwalkGeo, 0, xwalkMat);
    }
  }
  for (let j = 0; j < 6; j++) {
    const rz = (j - 2.5) * CELL_PITCH;
    for (let bx = -GRID_HALF; bx <= GRID_HALF; bx++) {
      const cx = bx * CELL_PITCH;
      addRoadStrip(cx, 0.015, rz, laneGeo, Math.PI * 0.5, laneMat);
      addRoadStrip(cx - BLOCK_SIZE * 0.5 + 1.3, 0.022, rz, xwalkGeo, Math.PI * 0.5, xwalkMat);
      addRoadStrip(cx + BLOCK_SIZE * 0.5 - 1.3, 0.022, rz, xwalkGeo, Math.PI * 0.5, xwalkMat);
    }
  }

  const addContactShadow = (x: number, y: number, z: number, w: number, d: number, yaw = 0) => {
    const q = new THREE.Mesh(new THREE.PlaneGeometry(w, d), contactShadowMat);
    q.rotation.order = 'YXZ';
    q.rotation.x = -Math.PI * 0.5;
    q.rotation.y = yaw;
    q.position.set(x, y + 0.025, z);
    cityGroup.add(q);
  };

  const addCollider = (cx: number, cz: number, sx: number, sz: number, maxY: number) => {
    colliders.push({
      minX: cx - sx * 0.5,
      maxX: cx + sx * 0.5,
      minZ: cz - sz * 0.5,
      maxZ: cz + sz * 0.5,
      maxY,
    });
  };

  const addRaisedSlab = (
    cx: number,
    baseY: number,
    cz: number,
    w: number,
    h: number,
    d: number,
    mat: THREE.Material,
    registerSidewalk: boolean
  ) => {
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
    mesh.position.set(cx, baseY + h * 0.5, cz);
    mesh.castShadow = castShadows;
    mesh.receiveShadow = true;
    cityGroup.add(mesh);
    if (registerSidewalk) {
      sidewalks.push({
        minX: cx - w * 0.5,
        maxX: cx + w * 0.5,
        minZ: cz - d * 0.5,
        maxZ: cz + d * 0.5,
        maxY: baseY + h,
        isSidewalk: true,
      });
    }
  };

  const placeProp = (
    modelKey: string,
    x: number,
    y: number,
    z: number,
    baseYaw: number,
    withShadow: boolean,
    sw: number,
    sd: number,
    colW: number,
    colD: number,
    colH: number
  ) => {
    const template = models.get(modelKey);
    if (!template) return;
    const inst = template.clone(true);
    const scaleVar = rng.range(0.9, 1.1);
    const jitter = modelKey === 'prop_tree' || modelKey === 'prop_trashbin' ? 0.14 : 0.04;
    const yaw = baseYaw + rng.range(-jitter, jitter);
    inst.position.set(x, y, z);
    inst.rotation.y = yaw;
    inst.scale.setScalar(scaleVar);
    const tint = new THREE.Color(rng.range(0.95, 1.05), rng.range(0.95, 1.05), rng.range(0.95, 1.05));
    applyPbrMaterials(inst, tint, castShadows);
    cityGroup.add(inst);

    if (withShadow) {
      addContactShadow(x, y, z, sw * scaleVar, sd * scaleVar, yaw);
    }
    if (colW > 0 && colD > 0) {
      addCollider(x, z, colW * scaleVar, colD * scaleVar, y + colH * scaleVar);
    }
  };

  const placeBuilding = (
    modelKey: string,
    x: number,
    y: number,
    z: number,
    yaw: number,
    tintHex: number,
    colX: number,
    colY: number,
    colZ: number,
    mirrorX: boolean
  ) => {
    const template = models.get(modelKey);
    if (!template) return;
    const inst = template.clone(true);
    inst.position.set(x, y, z);
    inst.rotation.y = yaw;
    inst.scale.set(mirrorX ? -1 : 1, rng.range(0.95, 1.07), 1);
    applyPbrMaterials(inst, new THREE.Color(tintHex), castShadows);
    cityGroup.add(inst);
    occluders.push(inst);

    const rot90 = Math.abs(Math.round(yaw / (Math.PI * 0.5))) % 2 === 1;
    const fx = rot90 ? colZ : colX;
    const fz = rot90 ? colX : colZ;
    addCollider(x, z, fx, fz, y + colY);
  };

  const populateSidewalkProps = (bx: number, bz: number, cx: number, cz: number, district: string) => {
    const edge = BLOCK_SIZE * 0.5 - 0.85;
    const lights: Array<[number, number, number]> =
      (bx + bz) % 2 === 0
        ? [
            [-edge, edge, 0],
            [edge, -edge, Math.PI],
          ]
        : [
            [edge, edge, Math.PI * 0.5],
            [-edge, -edge, -Math.PI * 0.5],
          ];
    for (const [lx, lz, lyaw] of lights) {
      placeProp('prop_streetlight', cx + lx, SIDEWALK_HEIGHT, cz + lz, lyaw, false, 0.8, 0.8, 0.42, 0.42, 6.0);
    }

    if (district === 'downtown') {
      placeProp('prop_vending', cx + 5.8, SIDEWALK_HEIGHT, cz - 1.8, Math.PI * 0.5, true, 1.5, 1.15, 1.1, 0.85, 2.0);
      placeProp('prop_trashbin', cx + edge, SIDEWALK_HEIGHT, cz + 2.6, 0, true, 0.95, 0.95, 0.62, 0.62, 1.1);
      placeProp('prop_hydrant', cx - edge, SIDEWALK_HEIGHT, cz - 3.4, rng.range(0, Math.PI * 2), true, 0.75, 0.75, 0.45, 0.45, 0.9);
      if ((bx + bz) % 2 !== 0) {
        placeProp('prop_bench', cx - 2.4, SIDEWALK_HEIGHT, cz + edge - 0.35, 0, true, 2.0, 1.0, 1.8, 0.7, 0.9);
      }
    } else if (district === 'commercial') {
      placeProp('prop_utility_pole', cx - edge, SIDEWALK_HEIGHT, cz + 4.2, Math.PI * 0.5, false, 0.8, 0.8, 0.45, 0.45, 7.2);
      placeProp('prop_trashbin', cx + edge, SIDEWALK_HEIGHT, cz - 2.5, 0, true, 0.95, 0.95, 0.62, 0.62, 1.1);
      if ((bx * 3 + bz) % 2 === 0) {
        placeProp('prop_vending', cx - 5.8, SIDEWALK_HEIGHT, cz + 1.6, -Math.PI * 0.5, true, 1.5, 1.15, 1.1, 0.85, 2.0);
      } else {
        placeProp('prop_hydrant', cx + edge, SIDEWALK_HEIGHT, cz + 3.6, rng.range(0, Math.PI * 2), true, 0.75, 0.75, 0.45, 0.45, 0.9);
      }
    } else if (district === 'suburban') {
      placeProp('prop_utility_pole', cx + edge, SIDEWALK_HEIGHT, cz - 4.4, 0, false, 0.8, 0.8, 0.45, 0.45, 7.2);
      placeProp('prop_tree', cx - edge + 0.3, SIDEWALK_HEIGHT, cz + 3.2, rng.range(0, Math.PI * 2), true, 2.2, 2.2, 0.65, 0.65, 3.4);
      if ((bx + bz) % 2 === 0) {
        placeProp('prop_hydrant', cx + edge, SIDEWALK_HEIGHT, cz + 4.8, rng.range(0, Math.PI * 2), true, 0.75, 0.75, 0.45, 0.45, 0.9);
      }
    }
  };

  // --- Build 5x5 Blocks ---
  const houseTints = [0xfffaf0, 0xebf9ed, 0xf0f5ff, 0xffede0];
  const urbanTints = [0xffffff, 0xf2f7ff, 0xfff6eb, 0xf0eef5, 0xfffef0];

  for (let bx = -GRID_HALF; bx <= GRID_HALF; bx++) {
    for (let bz = -GRID_HALF; bz <= GRID_HALF; bz++) {
      const cx = bx * CELL_PITCH;
      const cz = bz * CELL_PITCH;
      addRaisedSlab(cx, 0, cz, BLOCK_SIZE, SIDEWALK_HEIGHT, BLOCK_SIZE, sidewalkMat, true);

      // Central Landmark Clock-Fountain Plaza (0, 0)
      if (bx === 0 && bz === 0) {
        const pTop = new THREE.Mesh(new THREE.PlaneGeometry(BLOCK_SIZE - 1.6, BLOCK_SIZE - 1.6), plazaMat);
        pTop.rotation.x = -Math.PI * 0.5;
        pTop.position.set(cx, SIDEWALK_HEIGHT + 0.012, cz);
        pTop.receiveShadow = true;
        cityGroup.add(pTop);

        const landmark = models.get('landmark_clock_fountain')!.clone(true);
        landmark.position.set(cx, SIDEWALK_HEIGHT, cz);
        applyPbrMaterials(landmark, undefined, castShadows);
        cityGroup.add(landmark);
        occluders.push(landmark);
        addCollider(cx, cz, 6.2, 6.2, SIDEWALK_HEIGHT + 4.0);
        addContactShadow(cx, SIDEWALK_HEIGHT, cz, 7.6, 7.6, 0);

        const benches: Array<[number, number, number]> = [
          [0, 4.8, Math.PI],
          [0, -4.8, 0],
          [4.8, 0, -Math.PI * 0.5],
          [-4.8, 0, Math.PI * 0.5],
        ];
        for (const [ox, oz, oyaw] of benches) {
          placeProp('prop_bench', cx + ox, SIDEWALK_HEIGHT, cz + oz, oyaw, true, 2.1, 1.1, 1.8, 0.7, 0.9);
        }
        for (const sx of [-1, 1]) {
          for (const sz of [-1, 1]) {
            placeProp('prop_tree', cx + sx * 5.2, SIDEWALK_HEIGHT, cz + sz * 5.2, rng.range(0, Math.PI * 2), true, 2.4, 2.4, 0.7, 0.7, 3.5);
          }
        }
        continue;
      }

      const distCenter = Math.max(Math.abs(bx), Math.abs(bz));
      const isPocketPlaza = (bx === -2 && bz === 0) || (bx === 2 && bz === -1);
      const isSuburban = distCenter === 2 && !isPocketPlaza && (bz <= -1 || bx <= -1);
      const isDowntown = distCenter === 1;

      if (isPocketPlaza) {
        const pave = new THREE.Mesh(new THREE.PlaneGeometry(BLOCK_SIZE - 1.6, BLOCK_SIZE - 1.6), plazaMat);
        pave.rotation.x = -Math.PI * 0.5;
        pave.position.set(cx, SIDEWALK_HEIGHT + 0.014, cz);
        pave.receiveShadow = true;
        cityGroup.add(pave);
        addRaisedSlab(cx, SIDEWALK_HEIGHT, cz, 4.6, 0.42, 4.6, sidewalkMat, false);
        addCollider(cx, cz, 4.6, 4.6, SIDEWALK_HEIGHT + 0.6);
        const gt = new THREE.Mesh(new THREE.PlaneGeometry(4.1, 4.1), grassMat);
        gt.rotation.x = -Math.PI * 0.5;
        gt.position.set(cx, SIDEWALK_HEIGHT + 0.435, cz);
        cityGroup.add(gt);
        placeProp('prop_tree', cx, SIDEWALK_HEIGHT + 0.42, cz, rng.range(0, Math.PI * 2), true, 2.5, 2.5, 0.7, 0.7, 3.5);
        placeProp('prop_bench', cx, SIDEWALK_HEIGHT, cz + 3.8, Math.PI, true, 2.0, 1.0, 1.8, 0.7, 0.9);
        placeProp('prop_bench', cx, SIDEWALK_HEIGHT, cz - 3.8, 0, true, 2.0, 1.0, 1.8, 0.7, 0.9);
        placeProp('prop_vending', cx - 4.6, SIDEWALK_HEIGHT, cz - 2.5, Math.PI * 0.5, true, 1.5, 1.2, 1.1, 0.85, 2.0);
        placeProp('prop_trashbin', cx - 4.6, SIDEWALK_HEIGHT, cz - 0.9, 0, true, 0.95, 0.95, 0.6, 0.6, 1.1);
        populateSidewalkProps(bx, bz, cx, cz, 'plaza');
        continue;
      }

      if (isSuburban) {
        const yard = new THREE.Mesh(new THREE.PlaneGeometry(BLOCK_SIZE - 2.6, BLOCK_SIZE - 2.6), grassMat);
        yard.rotation.x = -Math.PI * 0.5;
        yard.position.set(cx, SIDEWALK_HEIGHT + 0.012, cz);
        yard.receiveShadow = true;
        cityGroup.add(yard);

        const yaw = rng.int(0, 3) * Math.PI * 0.5;
        const tint = houseTints[Math.abs(bx * 7 + bz * 13) % houseTints.length];
        placeBuilding('bldg_suburban_house', cx, SIDEWALK_HEIGHT, cz, yaw, tint, 9.0, 6.5, 8.6, false);
        placeProp('prop_tree', cx - 4.6, SIDEWALK_HEIGHT, cz - 4.4, rng.range(0, Math.PI * 2), true, 2.2, 2.2, 0.7, 0.7, 3.5);
        if ((bx + bz) % 2 === 0) {
          placeProp('prop_tree', cx + 4.7, SIDEWALK_HEIGHT, cz - 4.2, rng.range(0, Math.PI * 2), true, 2.1, 2.1, 0.7, 0.7, 3.5);
        }
        populateSidewalkProps(bx, bz, cx, cz, 'suburban');
        continue;
      }

      // Downtown / Commercial Avenue
      const apron = new THREE.Mesh(new THREE.PlaneGeometry(BLOCK_SIZE - 2.2, BLOCK_SIZE - 2.2), plazaMat);
      apron.rotation.x = -Math.PI * 0.5;
      apron.position.set(cx, SIDEWALK_HEIGHT + 0.012, cz);
      apron.receiveShadow = true;
      cityGroup.add(apron);

      const pat = Math.abs(bx * 5 + bz * 3 + 11) % 4;
      let modelKey = 'bldg_brick_midrise';
      let colX = 9.9;
      let colY = 10.4;
      let colZ = 9.3;
      if (isDowntown) {
        if (pat === 0 || (pat === 3 && (bx + bz) % 2 === 0)) {
          modelKey = 'bldg_downtown_tower';
          colX = 10.6;
          colY = 15.0;
          colZ = 10.6;
        } else if (pat === 2) {
          modelKey = 'bldg_corner_shop';
          colX = 9.5;
          colY = 6.6;
          colZ = 8.9;
        }
      } else {
        if (pat === 0 || pat === 2) {
          modelKey = 'bldg_diner_market';
          colX = 10.4;
          colY = 5.2;
          colZ = 7.6;
        } else if (pat === 1) {
          modelKey = 'bldg_corner_shop';
          colX = 9.5;
          colY = 6.6;
          colZ = 8.9;
        }
      }

      const bYaw = (Math.abs(bx * 3 + bz * 5) % 4) * Math.PI * 0.5;
      const tint = urbanTints[Math.abs(bx * 11 + bz * 17) % urbanTints.length];
      placeBuilding(modelKey, cx, SIDEWALK_HEIGHT, cz, bYaw, tint, colX, colY, colZ, (bx + bz) % 3 === 0);
      populateSidewalkProps(bx, bz, cx, cz, isDowntown ? 'downtown' : 'commercial');
    }
  }

  // --- Central Intersection Traffic Lights ---
  const cornerOff = ROAD_WIDTH * 0.5 + 0.75;
  for (const sx of [-1, 1]) {
    for (const sz of [-1, 1]) {
      const ix = sx * CELL_PITCH * 0.5;
      const iz = sz * CELL_PITCH * 0.5;
      placeProp('prop_traffic_light', ix - cornerOff, SIDEWALK_HEIGHT, iz - cornerOff, Math.PI * 0.5, false, 0.9, 0.9, 0.45, 0.45, 5.5);
      placeProp('prop_traffic_light', ix + cornerOff, SIDEWALK_HEIGHT, iz + cornerOff, -Math.PI * 0.5, false, 0.9, 0.9, 0.45, 0.45, 5.5);
    }
  }

  // --- Outer Tree-Lined Suburban Boulevard Perimeter ---
  const stripW = 14.0;
  const span = OUTER_ROAD_EDGE * 2 + stripW * 2;
  const perimGrassMat = new THREE.MeshStandardMaterial({
    map: loadTex('grass_albedo.png', true, 24, 3),
    normalMap: loadTex('grass_normal.png', false, 24, 3),
    roughness: 0.92,
  });
  addRaisedSlab(0, 0, -(OUTER_ROAD_EDGE + stripW * 0.5), span, 0.22, stripW, perimGrassMat, false);
  addRaisedSlab(0, 0, OUTER_ROAD_EDGE + stripW * 0.5, span, 0.22, stripW, perimGrassMat, false);
  addRaisedSlab(-(OUTER_ROAD_EDGE + stripW * 0.5), 0, 0, stripW, 0.22, span, perimGrassMat, false);
  addRaisedSlab(OUTER_ROAD_EDGE + stripW * 0.5, 0, 0, stripW, 0.22, span, perimGrassMat, false);

  for (let k = -5; k <= 5; k++) {
    const off = k * 12.5 + rng.range(-1.6, 1.6);
    placeProp('prop_tree', off, 0.22, -(OUTER_ROAD_EDGE + 4.4), rng.range(0, Math.PI * 2), false, 2.4, 2.4, 0, 0, 0);
    placeProp('prop_tree', off, 0.22, OUTER_ROAD_EDGE + 4.4, rng.range(0, Math.PI * 2), false, 2.4, 2.4, 0, 0, 0);
    placeProp('prop_tree', -(OUTER_ROAD_EDGE + 4.4), 0.22, off, rng.range(0, Math.PI * 2), false, 2.4, 2.4, 0, 0, 0);
    placeProp('prop_tree', OUTER_ROAD_EDGE + 4.4, 0.22, off, rng.range(0, Math.PI * 2), false, 2.4, 2.4, 0, 0, 0);
  }

  return {
    colliders,
    sidewalks,
    occluders,
    contactShadowMat,
    carBodyTemplate: models.get('car_body')!,
    carWheelTemplate: models.get('car_wheel')!,
    applyPbrMaterials,
  };
}
