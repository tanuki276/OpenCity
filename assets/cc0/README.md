# CC0 Asset Packs Directory

Place or automatically fetch external CC0 3D packs into this directory using:

```bash
./tools/fetch_cc0_assets.sh
```

`scripts/core/AssetResolver.gd` automatically scans the following subdirectories and priority-loads real CC0 `.gltf`/`.glb` scenes when present, seamlessly falling back to the bundled PBR `.glb` models in `res://assets/models/`:

- `assets/cc0/kaykit_city_builder/` — KayKit City Builder Bits 1.0 (CC0)
- `assets/cc0/kenney_city_commercial/` — Kenney City Kit Commercial (CC0)
- `assets/cc0/kenney_city_suburban/` — Kenney City Kit Suburban (CC0)
- `assets/cc0/kenney_city_roads/` — Kenney City Kit Roads (CC0)
- `assets/cc0/kenney_car_kit/` — Kenney Car Kit (CC0)

All pack attributions and licenses are recorded in `THIRD_PARTY_ASSETS.md`.
