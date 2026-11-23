#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CC0_DIR="${ROOT_DIR}/assets/cc0"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${CC0_DIR}"

echo "[Reduced-Town] Fetching CC0 asset packs into ${CC0_DIR}..."

# 1. KayKit: City Builder Bits 1.0 (Official GitHub CC0 Release)
KAYKIT_DIR="${CC0_DIR}/kaykit_city_builder"
if [ ! -d "${KAYKIT_DIR}/Assets" ]; then
  echo " -> Downloading KayKit City Builder Bits 1.0 (CC0)..."
  if curl -fSL --connect-timeout 15 --max-time 120 \
    -o "${TMP_DIR}/kaykit_city_builder.zip" \
    "https://github.com/KayKit-Game-Assets/KayKit-City-Builder-Bits-1.0/archive/refs/heads/main.zip"; then
    unzip -q -o "${TMP_DIR}/kaykit_city_builder.zip" -d "${TMP_DIR}/kaykit"
    mkdir -p "${KAYKIT_DIR}"
    SRC_SUBDIR="$(find "${TMP_DIR}/kaykit" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    cp -r "${SRC_SUBDIR}/"* "${KAYKIT_DIR}/"
    echo "    OK: KayKit City Builder Bits extracted to ${KAYKIT_DIR}"
  else
    echo "    WARN: Could not download KayKit City Builder Bits (offline or network blocked)."
  fi
else
  echo " -> KayKit City Builder Bits already present."
fi

# 2. Kenney CC0 Packs (Commercial, Suburban, Roads, Car Kit)
# Kenney direct download URLs occasionally rotate version numbers on kenney.nl;
# attempt official direct zip links and also extract any manually placed zips in assets/cc0/.
fetch_kenney_pack() {
  local slug="$1"
  local target_dir="${CC0_DIR}/$2"
  local url="$3"

  if [ -d "${target_dir}" ] && [ -n "$(find "${target_dir}" -name '*.glb' -o -name '*.gltf' 2>/dev/null | head -n 1)" ]; then
    echo " -> ${2} already present."
    return 0
  fi

  local local_zip="${CC0_DIR}/${slug}.zip"
  if [ -f "${local_zip}" ]; then
    echo " -> Extracting local archive ${local_zip}..."
    mkdir -p "${target_dir}"
    unzip -q -o "${local_zip}" -d "${target_dir}"
    return 0
  fi

  echo " -> Attempting download for ${2} from kenney.nl..."
  if curl -fSL --connect-timeout 15 --max-time 90 -o "${TMP_DIR}/${slug}.zip" "${url}" 2>/dev/null; then
    mkdir -p "${target_dir}"
    unzip -q -o "${TMP_DIR}/${slug}.zip" -d "${target_dir}"
    echo "    OK: ${2} extracted."
  else
    echo "    NOTE: Direct URL unavailable for ${2}. Download CC0 zip from https://kenney.nl/assets/${slug} and place as assets/cc0/${slug}.zip, then re-run."
  fi
}

fetch_kenney_pack "city-kit-commercial" "kenney_city_commercial" "https://kenney.nl/media/pages/assets/city-kit-commercial/c0d28587b1-1713433772/kenney_city-kit-commercial_2.1.zip"
fetch_kenney_pack "city-kit-suburban" "kenney_city_suburban" "https://kenney.nl/media/pages/assets/city-kit-suburban/c259b5c34d-1713433818/kenney_city-kit-suburban_2.0.zip"
fetch_kenney_pack "city-kit-roads" "kenney_city_roads" "https://kenney.nl/media/pages/assets/city-kit-roads/c72c598e33-1713433804/kenney_city-kit-roads_2.2.zip"
fetch_kenney_pack "car-kit" "kenney_car_kit" "https://kenney.nl/media/pages/assets/car-kit/86f8368f88-1713433757/kenney_car-kit_2.2.zip"

echo "[Reduced-Town] CC0 asset sync finished. Bundled PBR GLB assets in assets/models/ remain ready as immediate defaults."
