#!/usr/bin/env python3
"""
Reduced-Town Stage 1 — Pure-Python PBR Texture, glTF 2.0 (.glb) Model, and WAV Audio Generator.

Generates realistic, mipmap-ready tileable PBR textures (Albedo, Normal, Roughness),
sculpted multi-part glTF 2.0 (.glb) 3D models (buildings, American sport sedan, wheels,
street props, landmark clock-fountain), and seamless WAV audio assets using only the
Python 3 standard library.
"""

import json
import math
import os
import random
import struct
import wave
import zlib

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
TEX_DIR = os.path.join(ROOT, "assets", "textures")
MOD_DIR = os.path.join(ROOT, "assets", "models")
AUD_DIR = os.path.join(ROOT, "assets", "audio")

os.makedirs(TEX_DIR, exist_ok=True)
os.makedirs(MOD_DIR, exist_ok=True)
os.makedirs(AUD_DIR, exist_ok=True)


# =============================================================================
# 1. PNG WRITER & PROCEDURAL TILEABLE NOISE
# =============================================================================

def write_png(path, width, height, pixels_rgba, is_rgba=False):
    """Write 8-bit RGB or RGBA PNG using stdlib zlib."""
    raw = bytearray()
    stride = 4 if is_rgba else 3
    for y in range(height):
        raw.append(0)  # Filter type 0 (None)
        row_start = y * width * stride
        raw.extend(pixels_rgba[row_start:row_start + width * stride])

    def chunk(tag, data):
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    color_type = 6 if is_rgba else 2
    ihdr = struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", ihdr)
    png += chunk(b"IDAT", zlib.compress(bytes(raw), level=6))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def hash2(ix, iy, seed):
    n = (ix * 374761393 + iy * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFFFF) / 16777215.0


def tile_value_noise(u, v, period, seed):
    x = (u % 1.0) * period
    y = (v % 1.0) * period
    x0 = int(math.floor(x))
    y0 = int(math.floor(y))
    fx = x - x0
    fy = y - y0
    fx = fx * fx * (3.0 - 2.0 * fx)
    fy = fy * fy * (3.0 - 2.0 * fy)
    x1 = (x0 + 1) % period
    y1 = (y0 + 1) % period
    x0 = x0 % period
    y0 = y0 % period
    v00 = hash2(x0, y0, seed)
    v10 = hash2(x1, y0, seed)
    v01 = hash2(x0, y1, seed)
    v11 = hash2(x1, y1, seed)
    a = v00 + (v10 - v00) * fx
    b = v01 + (v11 - v01) * fx
    return a + (b - a) * fy


def tile_fbm(u, v, base_period, octaves, seed):
    total = 0.0
    amp = 0.5
    norm = 0.0
    period = base_period
    for i in range(octaves):
        total += amp * tile_value_noise(u, v, period, seed + i * 31)
        norm += amp
        amp *= 0.5
        period *= 2
    return total / norm


def clamp_byte(val):
    if val < 0:
        return 0
    if val > 255:
        return 255
    return int(val)


def height_to_normal(height_map, w, h, strength=3.0):
    out = bytearray(w * h * 3)
    for y in range(h):
        ym = (y - 1) % h
        yp = (y + 1) % h
        for x in range(w):
            xm = (x - 1) % w
            xp = (x + 1) % w
            dx = (height_map[y * w + xp] - height_map[y * w + xm]) * strength
            dy = (height_map[yp * w + x] - height_map[ym * w + x]) * strength
            nx = -dx
            ny = -dy
            nz = 1.0
            inv_len = 1.0 / math.sqrt(nx * nx + ny * ny + nz * nz)
            idx = (y * w + x) * 3
            out[idx] = clamp_byte((nx * inv_len * 0.5 + 0.5) * 255.0)
            out[idx + 1] = clamp_byte((ny * inv_len * 0.5 + 0.5) * 255.0)
            out[idx + 2] = clamp_byte((nz * inv_len * 0.5 + 0.5) * 255.0)
    return out


def generate_textures():
    print("Generating realistic PBR textures...")
    S = 256

    # 1. Asphalt Road (aggregate pebbles, subtle tire wear lanes, cracks, normal + roughness)
    alb = bytearray(S * S * 3)
    rgh = bytearray(S * S * 3)
    hmap = [0.0] * (S * S)
    for y in range(S):
        v = y / S
        for x in range(S):
            u = x / S
            coarse = tile_fbm(u, v, 8, 3, 11)
            fine = tile_value_noise(u, v, 64, 17)
            speck = hash2(x, y, 23)
            # subtle wheel track darkening near u=0.25 and u=0.75
            track = math.exp(-((u - 0.28) * 9.0) ** 2) + math.exp(-((u - 0.72) * 9.0) ** 2)
            base = 58.0 + (coarse - 0.5) * 22.0 + (fine - 0.5) * 16.0 + (speck - 0.5) * 18.0 - track * 9.0
            # subtle tar crack
            crack_n = abs(tile_fbm(u, v, 6, 3, 99) - 0.5)
            crack = 1.0 if crack_n < 0.012 else 0.0
            if crack:
                base -= 22.0
            idx = (y * S + x) * 3
            alb[idx] = clamp_byte(base * 0.99)
            alb[idx + 1] = clamp_byte(base * 1.00)
            alb[idx + 2] = clamp_byte(base * 1.04)
            rv = clamp_byte(215 - track * 25 + (fine - 0.5) * 35)
            rgh[idx] = rgh[idx + 1] = rgh[idx + 2] = rv
            hmap[y * S + x] = coarse * 0.4 + fine * 0.4 + speck * 0.2 - crack * 0.35
    write_png(os.path.join(TEX_DIR, "asphalt_albedo.png"), S, S, alb)
    write_png(os.path.join(TEX_DIR, "asphalt_roughness.png"), S, S, rgh)
    write_png(os.path.join(TEX_DIR, "asphalt_normal.png"), S, S, height_to_normal(hmap, S, S, 3.8))

    # 2. Road with Center Double-Yellow Line & Edge Lines
    road_lane = bytearray(alb)
    for y in range(S):
        for x in range(S):
            u = x / S
            idx = (y * S + x) * 3
            wear = tile_fbm(u, y / S, 16, 2, 41)
            # Double yellow center line
            if (0.478 <= u <= 0.493) or (0.507 <= u <= 0.522):
                blend = 0.85 * (0.75 + 0.25 * wear)
                road_lane[idx] = clamp_byte(road_lane[idx] * (1 - blend) + 232 * blend)
                road_lane[idx + 1] = clamp_byte(road_lane[idx + 1] * (1 - blend) + 184 * blend)
                road_lane[idx + 2] = clamp_byte(road_lane[idx + 2] * (1 - blend) + 46 * blend)
            # Crisp white curb-edge lines
            elif (0.045 <= u <= 0.062) or (0.938 <= u <= 0.955):
                blend = 0.82 * (0.72 + 0.28 * wear)
                road_lane[idx] = clamp_byte(road_lane[idx] * (1 - blend) + 230 * blend)
                road_lane[idx + 1] = clamp_byte(road_lane[idx + 1] * (1 - blend) + 232 * blend)
                road_lane[idx + 2] = clamp_byte(road_lane[idx + 2] * (1 - blend) + 235 * blend)
    write_png(os.path.join(TEX_DIR, "asphalt_lane_albedo.png"), S, S, road_lane)

    # 3. Crosswalk Asphalt
    xwalk = bytearray(alb)
    for y in range(S):
        v = y / S
        for x in range(S):
            u = x / S
            idx = (y * S + x) * 3
            stripe = int(u * 10) % 2 == 0
            if stripe and 0.14 <= v <= 0.86 and 0.06 <= u <= 0.94:
                wear = tile_fbm(u, v, 16, 2, 53)
                blend = 0.84 * (0.75 + 0.25 * wear)
                xwalk[idx] = clamp_byte(xwalk[idx] * (1 - blend) + 236 * blend)
                xwalk[idx + 1] = clamp_byte(xwalk[idx + 1] * (1 - blend) + 236 * blend)
                xwalk[idx + 2] = clamp_byte(xwalk[idx + 2] * (1 - blend) + 232 * blend)
    write_png(os.path.join(TEX_DIR, "road_crosswalk_albedo.png"), S, S, xwalk)

    # 4. Concrete Sidewalk Slabs (expansion joints + warm concrete variation)
    alb = bytearray(S * S * 3)
    rgh = bytearray(S * S * 3)
    hmap = [0.0] * (S * S)
    for y in range(S):
        v = y / S
        for x in range(S):
            u = x / S
            gx = (u * 4.0) % 1.0
            gy = (v * 4.0) % 1.0
            tile_id_x = int(u * 4.0)
            tile_id_y = int(v * 4.0)
            slab_var = (hash2(tile_id_x, tile_id_y, 71) - 0.5) * 14.0
            joint = 1.0 if (gx < 0.035 or gy < 0.035) else 0.0
            n1 = tile_fbm(u, v, 8, 3, 73)
            grain = hash2(x, y, 79)
            base = 178.0 + slab_var + (n1 - 0.5) * 22.0 + (grain - 0.5) * 10.0 - joint * 58.0
            idx = (y * S + x) * 3
            alb[idx] = clamp_byte(base * 1.01)
            alb[idx + 1] = clamp_byte(base * 0.99)
            alb[idx + 2] = clamp_byte(base * 0.94)
            rv = clamp_byte(210 + (n1 - 0.5) * 30 + joint * 30)
            rgh[idx] = rgh[idx + 1] = rgh[idx + 2] = rv
            hmap[y * S + x] = (0.75 + n1 * 0.2 + grain * 0.05) - joint * 0.55
    write_png(os.path.join(TEX_DIR, "sidewalk_albedo.png"), S, S, alb)
    write_png(os.path.join(TEX_DIR, "sidewalk_roughness.png"), S, S, rgh)
    write_png(os.path.join(TEX_DIR, "sidewalk_normal.png"), S, S, height_to_normal(hmap, S, S, 3.2))

    # 5. Plaza Interlocking Stone Pavers (for landmark square & intentional plazas)
    alb = bytearray(S * S * 3)
    rgh = bytearray(S * S * 3)
    hmap = [0.0] * (S * S)
    for y in range(S):
        v = y / S
        row = int(v * 8.0)
        for x in range(S):
            u = x / S
            u_off = (u * 8.0 + (0.5 if row % 2 else 0.0))
            col = int(u_off) % 8
            fx = u_off % 1.0
            fy = (v * 8.0) % 1.0
            joint = 1.0 if (fx < 0.07 or fy < 0.07) else 0.0
            pv = hash2(col, row, 101)
            n = tile_fbm(u, v, 12, 3, 107)
            r_c = 174 + (pv - 0.5) * 32 + (n - 0.5) * 18 - joint * 65
            g_c = 160 + (pv - 0.5) * 26 + (n - 0.5) * 16 - joint * 62
            b_c = 142 + (pv - 0.5) * 20 + (n - 0.5) * 14 - joint * 55
            idx = (y * S + x) * 3
            alb[idx] = clamp_byte(r_c)
            alb[idx + 1] = clamp_byte(g_c)
            alb[idx + 2] = clamp_byte(b_c)
            rv = clamp_byte(185 + (n - 0.5) * 35 + joint * 45)
            rgh[idx] = rgh[idx + 1] = rgh[idx + 2] = rv
            hmap[y * S + x] = 0.8 + n * 0.15 - joint * 0.55
    write_png(os.path.join(TEX_DIR, "plaza_paver_albedo.png"), S, S, alb)
    write_png(os.path.join(TEX_DIR, "plaza_paver_roughness.png"), S, S, rgh)
    write_png(os.path.join(TEX_DIR, "plaza_paver_normal.png"), S, S, height_to_normal(hmap, S, S, 3.6))

    # 6. Warm Sunlit Suburban Grass
    alb = bytearray(S * S * 3)
    hmap = [0.0] * (S * S)
    for y in range(S):
        v = y / S
        for x in range(S):
            u = x / S
            n1 = tile_fbm(u, v, 6, 3, 131)
            n2 = tile_value_noise(u, v, 48, 137)
            blade = hash2(x, y, 139)
            idx = (y * S + x) * 3
            alb[idx] = clamp_byte(86 + n1 * 34 + (blade - 0.5) * 22)
            alb[idx + 1] = clamp_byte(122 + n1 * 42 + (n2 - 0.5) * 24 + (blade - 0.5) * 18)
            alb[idx + 2] = clamp_byte(56 + n1 * 20 + (blade - 0.5) * 12)
            hmap[y * S + x] = n1 * 0.4 + n2 * 0.35 + blade * 0.25
    write_png(os.path.join(TEX_DIR, "grass_albedo.png"), S, S, alb)
    write_png(os.path.join(TEX_DIR, "grass_normal.png"), S, S, height_to_normal(hmap, S, S, 3.0))

    # 7. Running-Bond Brick (Red & Tan variants + Normal + Roughness)
    def make_brick(name, base_rgb, seed):
        alb_b = bytearray(S * S * 3)
        rgh_b = bytearray(S * S * 3)
        hm = [0.0] * (S * S)
        rows = 12
        cols = 6
        for y in range(S):
            v = y / S
            ry = v * rows
            r_idx = int(ry) % rows
            fy = ry % 1.0
            for x in range(S):
                u = x / S
                rx = u * cols + (0.5 if r_idx % 2 else 0.0)
                c_idx = int(rx) % cols
                fx = rx % 1.0
                mortar = 1.0 if (fx < 0.065 or fy < 0.11) else 0.0
                bv = hash2(c_idx, r_idx, seed)
                tex = tile_fbm(u, v, 16, 3, seed + 7)
                idx = (y * S + x) * 3
                if mortar:
                    mc = 186 + (tex - 0.5) * 24
                    alb_b[idx] = clamp_byte(mc)
                    alb_b[idx + 1] = clamp_byte(mc * 0.97)
                    alb_b[idx + 2] = clamp_byte(mc * 0.91)
                    rgh_b[idx] = rgh_b[idx + 1] = rgh_b[idx + 2] = 240
                    hm[y * S + x] = 0.2 + tex * 0.1
                else:
                    shade = 0.78 + bv * 0.42 + (tex - 0.5) * 0.18
                    alb_b[idx] = clamp_byte(base_rgb[0] * shade)
                    alb_b[idx + 1] = clamp_byte(base_rgb[1] * shade)
                    alb_b[idx + 2] = clamp_byte(base_rgb[2] * shade)
                    rv = clamp_byte(195 + (tex - 0.5) * 35)
                    rgh_b[idx] = rgh_b[idx + 1] = rgh_b[idx + 2] = rv
                    hm[y * S + x] = 0.78 + tex * 0.18
        write_png(os.path.join(TEX_DIR, f"{name}_albedo.png"), S, S, alb_b)
        if name == "brick_red":
            write_png(os.path.join(TEX_DIR, "brick_roughness.png"), S, S, rgh_b)
            write_png(os.path.join(TEX_DIR, "brick_normal.png"), S, S, height_to_normal(hm, S, S, 4.2))

    make_brick("brick_red", (152, 74, 58), 201)
    make_brick("brick_tan", (178, 146, 108), 223)

    # 8. Stucco / Painted Plaster Facades (4 district color palettes + shared Normal/Roughness)
    stucco_h = [0.0] * (S * S)
    stucco_r = bytearray(S * S * 3)
    for y in range(S):
        v = y / S
        for x in range(S):
            u = x / S
            n1 = tile_fbm(u, v, 8, 4, 307)
            n2 = hash2(x, y, 311)
            stucco_h[y * S + x] = n1 * 0.7 + n2 * 0.3
            rv = clamp_byte(208 + (n1 - 0.5) * 32)
            idx = (y * S + x) * 3
            stucco_r[idx] = stucco_r[idx + 1] = stucco_r[idx + 2] = rv
    write_png(os.path.join(TEX_DIR, "stucco_normal.png"), S, S, height_to_normal(stucco_h, S, S, 2.5))
    write_png(os.path.join(TEX_DIR, "stucco_roughness.png"), S, S, stucco_r)

    stucco_palettes = {
        "stucco_cream": (222, 208, 184),
        "stucco_terracotta": (206, 152, 122),
        "stucco_slate": (166, 178, 190),
        "stucco_sage": (176, 192, 172),
    }
    for sname, rgb in stucco_palettes.items():
        buf = bytearray(S * S * 3)
        for i in range(S * S):
            h = stucco_h[i]
            # Subtle vertical weathering gradient
            y_norm = (i // S) / S
            weath = 0.94 + 0.08 * math.sin(y_norm * math.pi)
            fac = (0.90 + h * 0.20) * weath
            buf[i * 3] = clamp_byte(rgb[0] * fac)
            buf[i * 3 + 1] = clamp_byte(rgb[1] * fac)
            buf[i * 3 + 2] = clamp_byte(rgb[2] * fac)
        write_png(os.path.join(TEX_DIR, f"{sname}_albedo.png"), S, S, buf)

    # 9. Architectural Commercial Glass Curtain Wall (mullions, interior blinds, sky reflection)
    alb = bytearray(S * S * 3)
    rgh = bytearray(S * S * 3)
    hmap = [0.0] * (S * S)
    for y in range(S):
        v = y / S
        for x in range(S):
            u = x / S
            gx = (u * 4.0) % 1.0
            gy = (v * 3.0) % 1.0
            wx = int(u * 4.0)
            wy = int(v * 3.0)
            frame = 1.0 if (gx < 0.09 or gx > 0.91 or gy < 0.11 or gy > 0.89) else 0.0
            idx = (y * S + x) * 3
            if frame:
                alb[idx] = 68
                alb[idx + 1] = 74
                alb[idx + 2] = 82
                rgh[idx] = rgh[idx + 1] = rgh[idx + 2] = 120
                hmap[y * S + x] = 0.9
            else:
                room_var = hash2(wx, wy, 409)
                sky_grad = (1.0 - gy) * 0.45 + 0.35
                blinds = 1.0 if (gy < 0.35 and room_var > 0.45) else 0.0
                r_c = 72 + sky_grad * 72 + blinds * 42 + room_var * 18
                g_c = 98 + sky_grad * 82 + blinds * 38 + room_var * 14
                b_c = 124 + sky_grad * 88 + blinds * 24 + room_var * 12
                alb[idx] = clamp_byte(r_c)
                alb[idx + 1] = clamp_byte(g_c)
                alb[idx + 2] = clamp_byte(b_c)
                rgh[idx] = rgh[idx + 1] = rgh[idx + 2] = 28
                hmap[y * S + x] = 0.25
    write_png(os.path.join(TEX_DIR, "commercial_glass_albedo.png"), S, S, alb)
    write_png(os.path.join(TEX_DIR, "commercial_glass_roughness.png"), S, S, rgh)
    write_png(os.path.join(TEX_DIR, "commercial_glass_normal.png"), S, S, height_to_normal(hmap, S, S, 3.0))

    # 10. Roof Gravel / Tar
    alb = bytearray(S * S * 3)
    hmap = [0.0] * (S * S)
    for y in range(S):
        v = y / S
        for x in range(S):
            u = x / S
            n = tile_fbm(u, v, 10, 4, 503)
            g = hash2(x, y, 509)
            base = 96 + (n - 0.5) * 32 + (g - 0.5) * 24
            idx = (y * S + x) * 3
            alb[idx] = clamp_byte(base * 1.02)
            alb[idx + 1] = clamp_byte(base)
            alb[idx + 2] = clamp_byte(base * 0.96)
            hmap[y * S + x] = n * 0.6 + g * 0.4
    write_png(os.path.join(TEX_DIR, "roof_gravel_albedo.png"), S, S, alb)
    write_png(os.path.join(TEX_DIR, "roof_gravel_normal.png"), S, S, height_to_normal(hmap, S, S, 3.5))

    # 11. Tree Bark & Sunlit Foliage
    alb = bytearray(S * S * 3)
    hmap = [0.0] * (S * S)
    for y in range(S):
        v = y / S
        for x in range(S):
            u = x / S
            ridge = tile_fbm(u * 2.5, v * 0.6, 8, 4, 601)
            fine = hash2(x, y, 607)
            idx = (y * S + x) * 3
            alb[idx] = clamp_byte(78 + ridge * 46 + (fine - 0.5) * 14)
            alb[idx + 1] = clamp_byte(58 + ridge * 34 + (fine - 0.5) * 10)
            alb[idx + 2] = clamp_byte(44 + ridge * 24 + (fine - 0.5) * 8)
            hmap[y * S + x] = ridge * 0.8 + fine * 0.2
    write_png(os.path.join(TEX_DIR, "bark_albedo.png"), S, S, alb)
    write_png(os.path.join(TEX_DIR, "bark_normal.png"), S, S, height_to_normal(hmap, S, S, 4.5))

    alb = bytearray(S * S * 3)
    hmap = [0.0] * (S * S)
    for y in range(S):
        v = y / S
        for x in range(S):
            u = x / S
            clump = tile_fbm(u, v, 10, 4, 641)
            leaf = tile_value_noise(u, v, 32, 647)
            idx = (y * S + x) * 3
            alb[idx] = clamp_byte(56 + clump * 48 + leaf * 18)
            alb[idx + 1] = clamp_byte(104 + clump * 64 + leaf * 24)
            alb[idx + 2] = clamp_byte(42 + clump * 30 + leaf * 12)
            hmap[y * S + x] = clump * 0.5 + leaf * 0.5
    write_png(os.path.join(TEX_DIR, "foliage_albedo.png"), S, S, alb)
    write_png(os.path.join(TEX_DIR, "foliage_normal.png"), S, S, height_to_normal(hmap, S, S, 3.2))

    # 12. Tire Tread & Wood Slat
    alb = bytearray(S * S * 3)
    hmap = [0.0] * (S * S)
    for y in range(S):
        v = y / S
        for x in range(S):
            u = x / S
            groove_u = 1.0 if (0.28 < u < 0.34 or 0.66 < u < 0.72) else 0.0
            chev = ((v * 16.0 + abs(u - 0.5) * 3.0) % 1.0) < 0.25
            tread = 0.0 if (groove_u or chev) else 1.0
            rub = 34 + tread * 18 + (hash2(x, y, 701) - 0.5) * 8
            idx = (y * S + x) * 3
            alb[idx] = alb[idx + 1] = alb[idx + 2] = clamp_byte(rub)
            hmap[y * S + x] = 0.25 + tread * 0.65
    write_png(os.path.join(TEX_DIR, "tire_tread_albedo.png"), S, S, alb)
    write_png(os.path.join(TEX_DIR, "tire_tread_normal.png"), S, S, height_to_normal(hmap, S, S, 4.0))

    # 13. Soft Radial Contact Shadow (RGBA) for AO Grounding on GL Compatibility
    CS = 128
    csha = bytearray(CS * CS * 4)
    for y in range(CS):
        dy = (y / (CS - 1)) * 2.0 - 1.0
        for x in range(CS):
            dx = (x / (CS - 1)) * 2.0 - 1.0
            # Soft rounded rectangle/ellipse falloff
            d = math.sqrt(dx * dx + dy * dy)
            alpha = max(0.0, 1.0 - d)
            alpha = alpha * alpha * (3.0 - 2.0 * alpha)
            idx = (y * CS + x) * 4
            csha[idx] = 10
            csha[idx + 1] = 12
            csha[idx + 2] = 18
            csha[idx + 3] = clamp_byte(alpha * 195.0)
    write_png(os.path.join(TEX_DIR, "contact_shadow.png"), CS, CS, csha, is_rgba=True)


# =============================================================================
# 2. MINIMAL PURE-PYTHON glTF 2.0 BINARY (.glb) BUILDER
# =============================================================================

class MeshPrimitiveBuilder:
    def __init__(self, material_name):
        self.material_name = material_name
        self.positions = []
        self.normals = []
        self.uvs = []
        self.indices = []

    def add_quad(self, p0, p1, p2, p3, uv_scale=(1.0, 1.0), normal=None):
        """Add counter-clockwise quad (p0, p1, p2, p3) with auto normal and UV."""
        if normal is None:
            ux, uy, uz = p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2]
            vx, vy, vz = p3[0] - p0[0], p3[1] - p0[1], p3[2] - p0[2]
            nx = uy * vz - uz * vy
            ny = uz * vx - ux * vz
            nz = ux * vy - uy * vx
            l = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
            normal = (nx / l, ny / l, nz / l)
        base = len(self.positions)
        w = math.dist(p0, p1) * uv_scale[0]
        h = math.dist(p0, p3) * uv_scale[1]
        self.positions.extend([p0, p1, p2, p3])
        self.normals.extend([normal, normal, normal, normal])
        self.uvs.extend([(0.0, h), (w, h), (w, 0.0), (0.0, 0.0)])
        self.indices.extend([base, base + 1, base + 2, base, base + 2, base + 3])

    def add_tri(self, p0, p1, p2, uv_scale=(1.0, 1.0), normal=None):
        if normal is None:
            ux, uy, uz = p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2]
            vx, vy, vz = p2[0] - p0[0], p2[1] - p0[1], p2[2] - p0[2]
            nx = uy * vz - uz * vy
            ny = uz * vx - ux * vz
            nz = ux * vy - uy * vx
            l = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
            normal = (nx / l, ny / l, nz / l)
        base = len(self.positions)
        self.positions.extend([p0, p1, p2])
        self.normals.extend([normal, normal, normal])
        self.uvs.extend([(0.0, 0.0), (uv_scale[0], 0.0), (uv_scale[0] * 0.5, uv_scale[1])])
        self.indices.extend([base, base + 1, base + 2])

    def add_box(self, cx, cy, cz, sx, sy, sz, uv_scale=(0.25, 0.25), skip_bottom=False):
        hx, hy, hz = sx * 0.5, sy * 0.5, sz * 0.5
        x0, x1 = cx - hx, cx + hx
        y0, y1 = cy - hy, cy + hy
        z0, z1 = cz - hz, cz + hz
        # +Z front
        self.add_quad((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1), uv_scale, (0, 0, 1))
        # -Z back
        self.add_quad((x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0), uv_scale, (0, 0, -1))
        # +X right
        self.add_quad((x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1), uv_scale, (1, 0, 0))
        # -X left
        self.add_quad((x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0), uv_scale, (-1, 0, 0))
        # +Y top
        self.add_quad((x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0), uv_scale, (0, 1, 0))
        # -Y bottom
        if not skip_bottom:
            self.add_quad((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1), uv_scale, (0, -1, 0))

    def add_cylinder(self, cx, cy, cz, r_bot, r_top, height, segs=12, axis="y", uv_scale=(1.0, 1.0)):
        """Add cylinder centered at (cx, cy, cz) along y or x axis."""
        half = height * 0.5
        ring0 = []
        ring1 = []
        for i in range(segs):
            a = (i / segs) * math.tau
            ca, sa = math.cos(a), math.sin(a)
            if axis == "y":
                ring0.append((cx + ca * r_bot, cy - half, cz + sa * r_bot, ca, 0.0, sa))
                ring1.append((cx + ca * r_top, cy + half, cz + sa * r_top, ca, 0.0, sa))
            else:  # wheel along x axis
                ring0.append((cx - half, cy + ca * r_bot, cz + sa * r_bot, 0.0, ca, sa))
                ring1.append((cx + half, cy + ca * r_top, cz + sa * r_top, 0.0, ca, sa))

        for i in range(segs):
            j = (i + 1) % segs
            p0 = ring0[i][:3]
            p1 = ring0[j][:3]
            p2 = ring1[j][:3]
            p3 = ring1[i][:3]
            if axis == "y":
                # Outward winding for Y cylinder (swap p1/p3 order for CCW outside)
                self.add_quad(p1, p0, p3, p2, uv_scale)
            else:
                self.add_quad(p0, p1, p2, p3, uv_scale)

        # Caps
        c0 = (cx, cy - half, cz) if axis == "y" else (cx - half, cy, cz)
        c1 = (cx, cy + half, cz) if axis == "y" else (cx + half, cy, cz)
        n0 = (0, -1, 0) if axis == "y" else (-1, 0, 0)
        n1 = (0, 1, 0) if axis == "y" else (1, 0, 0)
        for i in range(segs):
            j = (i + 1) % segs
            if axis == "y":
                self.add_tri(c1, ring1[j][:3], ring1[i][:3], uv_scale, n1)
                self.add_tri(c0, ring0[i][:3], ring0[j][:3], uv_scale, n0)
            else:
                self.add_tri(c1, ring1[i][:3], ring1[j][:3], uv_scale, n1)
                self.add_tri(c0, ring0[j][:3], ring0[i][:3], uv_scale, n0)

    def add_sphere_cluster(self, cx, cy, cz, rx, ry, rz, rings=6, segs=10):
        """Low-poly sculpted organic cluster (for realistic tree crowns)."""
        pts = []
        for r in range(rings + 1):
            phi = (r / rings) * math.pi
            sp, cp = math.sin(phi), math.cos(phi)
            row = []
            for s in range(segs):
                theta = (s / segs) * math.tau
                ct, st = math.cos(theta), math.sin(theta)
                # subtle organic bump
                bump = 1.0 + 0.08 * math.sin(theta * 3.0 + phi * 2.0)
                px = cx + ct * sp * rx * bump
                py = cy + cp * ry * bump
                pz = cz + st * sp * rz * bump
                row.append((px, py, pz))
            pts.append(row)
        for r in range(rings):
            for s in range(segs):
                sn = (s + 1) % segs
                p0 = pts[r][s]
                p1 = pts[r + 1][s]
                p2 = pts[r + 1][sn]
                p3 = pts[r][sn]
                if r == 0:
                    self.add_tri(p0, p2, p1, (0.5, 0.5))
                elif r == rings - 1:
                    self.add_tri(p0, p3, p1, (0.5, 0.5))
                else:
                    self.add_quad(p0, p3, p2, p1, (0.4, 0.4))


class GLBModel:
    def __init__(self, name):
        self.name = name
        self.materials = {}  # mat_name -> dict(baseColorFactor, metallicFactor, roughnessFactor, emissiveFactor)
        self.builders = {}

    def mat(self, name, color=(0.8, 0.8, 0.8, 1.0), metallic=0.0, roughness=0.8, emissive=None):
        if name not in self.materials:
            m = {
                "name": name,
                "pbrMetallicRoughness": {
                    "baseColorFactor": list(color),
                    "metallicFactor": metallic,
                    "roughnessFactor": roughness,
                },
            }
            if emissive:
                m["emissiveFactor"] = list(emissive)
            self.materials[name] = m
            self.builders[name] = MeshPrimitiveBuilder(name)
        return self.builders[name]

    def save(self, path):
        mat_names = [m for m in self.materials.keys() if len(self.builders[m].indices) > 0]
        mat_list = [self.materials[m] for m in mat_names]

        bin_data = bytearray()
        buffer_views = []
        accessors = []
        primitives = []

        def align4():
            while len(bin_data) % 4 != 0:
                bin_data.append(0)

        def push_buffer(raw_bytes, target):
            align4()
            offset = len(bin_data)
            bin_data.extend(raw_bytes)
            bv_idx = len(buffer_views)
            bv = {"buffer": 0, "byteOffset": offset, "byteLength": len(raw_bytes)}
            if target is not None:
                bv["target"] = target
            buffer_views.append(bv)
            return bv_idx

        for mat_idx, mname in enumerate(mat_names):
            b = self.builders[mname]
            vcount = len(b.positions)
            icount = len(b.indices)

            pos_bytes = bytearray()
            min_p = [1e9, 1e9, 1e9]
            max_p = [-1e9, -1e9, -1e9]
            for x, y, z in b.positions:
                pos_bytes.extend(struct.pack("<fff", x, y, z))
                if x < min_p[0]: min_p[0] = x
                if y < min_p[1]: min_p[1] = y
                if z < min_p[2]: min_p[2] = z
                if x > max_p[0]: max_p[0] = x
                if y > max_p[1]: max_p[1] = y
                if z > max_p[2]: max_p[2] = z

            nrm_bytes = bytearray()
            for nx, ny, nz in b.normals:
                nrm_bytes.extend(struct.pack("<fff", nx, ny, nz))

            uv_bytes = bytearray()
            for u, v in b.uvs:
                uv_bytes.extend(struct.pack("<ff", u, v))

            idx_bytes = bytearray()
            for idx in b.indices:
                idx_bytes.extend(struct.pack("<I", idx))

            pos_bv = push_buffer(pos_bytes, 34962)
            nrm_bv = push_buffer(nrm_bytes, 34962)
            uv_bv = push_buffer(uv_bytes, 34962)
            idx_bv = push_buffer(idx_bytes, 34963)

            pos_acc = len(accessors)
            accessors.append({
                "bufferView": pos_bv, "componentType": 5126, "count": vcount,
                "type": "VEC3", "min": min_p, "max": max_p
            })
            nrm_acc = len(accessors)
            accessors.append({
                "bufferView": nrm_bv, "componentType": 5126, "count": vcount, "type": "VEC3"
            })
            uv_acc = len(accessors)
            accessors.append({
                "bufferView": uv_bv, "componentType": 5126, "count": vcount, "type": "VEC2"
            })
            idx_acc = len(accessors)
            accessors.append({
                "bufferView": idx_bv, "componentType": 5125, "count": icount, "type": "SCALAR"
            })

            primitives.append({
                "attributes": {"POSITION": pos_acc, "NORMAL": nrm_acc, "TEXCOORD_0": uv_acc},
                "indices": idx_acc,
                "material": mat_idx,
            })

        align4()
        gltf = {
            "asset": {"version": "2.0", "generator": "Reduced-Town PBR GLB Generator"},
            "scene": 0,
            "scenes": [{"nodes": [0]}],
            "nodes": [{"name": self.name, "mesh": 0}],
            "meshes": [{"name": self.name, "primitives": primitives}],
            "materials": mat_list,
            "buffers": [{"byteLength": len(bin_data)}],
            "bufferViews": buffer_views,
            "accessors": accessors,
        }
        json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
        while len(json_bytes) % 4 != 0:
            json_bytes += b" "

        total_len = 12 + 8 + len(json_bytes) + 8 + len(bin_data)
        with open(path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, total_len))
            f.write(struct.pack("<II", len(json_bytes), 0x4E4F534A))
            f.write(json_bytes)
            f.write(struct.pack("<II", len(bin_data), 0x004E4942))
            f.write(bin_data)


# =============================================================================
# 3. ARCHITECTURAL BUILDINGS, AMERICAN SEDAN, AND STREET PROPS (.glb)
# =============================================================================

def generate_models():
    print("Generating sculpted glTF 2.0 (.glb) models...")

    # --- A. Downtown Commercial Mid-Rise Tower (11m x 14m x 11m) ---
    m = GLBModel("bldg_downtown_tower")
    plinth = m.mat("mat_concrete", (0.76, 0.75, 0.72, 1.0), 0.0, 0.85)
    facade = m.mat("mat_stucco_slate", (0.68, 0.73, 0.78, 1.0), 0.0, 0.78)
    glass = m.mat("mat_commercial_glass", (0.45, 0.62, 0.76, 1.0), 0.15, 0.12)
    roof = m.mat("mat_roof_gravel", (0.40, 0.39, 0.38, 1.0), 0.0, 0.92)
    metal = m.mat("mat_metal_dark", (0.24, 0.26, 0.30, 1.0), 0.65, 0.38)
    awning = m.mat("mat_awning_accent", (0.78, 0.28, 0.18, 1.0), 0.0, 0.75)

    # Ground-floor lobby stone base
    plinth.add_box(0, 1.8, 0, 10.6, 3.6, 10.6, (0.25, 0.25), skip_bottom=True)
    # Recessed lobby glass storefronts on all 4 sides
    glass.add_box(0, 1.65, 5.33, 8.6, 2.7, 0.08, (0.35, 0.35))
    glass.add_box(0, 1.65, -5.33, 8.6, 2.7, 0.08, (0.35, 0.35))
    glass.add_box(5.33, 1.65, 0, 0.08, 2.7, 8.6, (0.35, 0.35))
    glass.add_box(-5.33, 1.65, 0, 0.08, 2.7, 8.6, (0.35, 0.35))
    # Entrance canopy
    metal.add_box(0, 3.15, 5.85, 5.2, 0.22, 1.2, (0.5, 0.5))
    awning.add_box(0, 3.26, 5.85, 5.0, 0.08, 1.0, (0.5, 0.5))
    # Upper stepped tower body
    facade.add_box(0, 8.6, 0, 9.8, 10.0, 9.8, (0.22, 0.22))
    # Horizontal floor slab cornices
    for fy in (3.65, 6.8, 10.0, 13.55):
        plinth.add_box(0, fy, 0, 10.4, 0.32, 10.4, (0.3, 0.3))
    # Upper curtain-wall window bands
    for fy in (5.2, 8.4, 11.7):
        glass.add_box(0, fy, 4.94, 8.2, 2.1, 0.08, (0.35, 0.45))
        glass.add_box(0, fy, -4.94, 8.2, 2.1, 0.08, (0.35, 0.45))
        glass.add_box(4.94, fy, 0, 0.08, 2.1, 8.2, (0.35, 0.45))
        glass.add_box(-4.94, fy, 0, 0.08, 2.1, 8.2, (0.35, 0.45))
    # Parapet wall & rooftop mechanical penthouse + HVAC units
    roof.add_box(0, 13.72, 0, 9.5, 0.14, 9.5, (0.25, 0.25))
    plinth.add_box(0, 14.1, 4.8, 10.2, 0.75, 0.4, (0.3, 0.3))
    plinth.add_box(0, 14.1, -4.8, 10.2, 0.75, 0.4, (0.3, 0.3))
    plinth.add_box(4.8, 14.1, 0, 0.4, 0.75, 9.4, (0.3, 0.3))
    plinth.add_box(-4.8, 14.1, 0, 0.4, 0.75, 9.4, (0.3, 0.3))
    facade.add_box(-1.6, 14.8, -1.4, 3.6, 2.1, 3.4, (0.3, 0.3))
    metal.add_box(2.2, 14.25, 1.6, 2.0, 1.0, 1.5, (0.5, 0.5))
    metal.add_box(2.2, 14.25, -1.8, 1.6, 0.9, 1.6, (0.5, 0.5))
    m.save(os.path.join(MOD_DIR, "bldg_downtown_tower.glb"))

    # --- B. Brick Urban Mid-Rise Apartments / Lofts (10m x 10.5m x 9.5m) ---
    m = GLBModel("bldg_brick_midrise")
    brick = m.mat("mat_brick_red", (0.68, 0.36, 0.28, 1.0), 0.0, 0.88)
    trim = m.mat("mat_concrete", (0.80, 0.77, 0.71, 1.0), 0.0, 0.85)
    glass = m.mat("mat_commercial_glass", (0.38, 0.50, 0.62, 1.0), 0.15, 0.14)
    metal = m.mat("mat_metal_dark", (0.20, 0.22, 0.24, 1.0), 0.6, 0.4)
    roof = m.mat("mat_roof_gravel", (0.38, 0.37, 0.36, 1.0), 0.0, 0.92)
    awning = m.mat("mat_awning_accent", (0.16, 0.44, 0.34, 1.0), 0.0, 0.8)

    trim.add_box(0, 1.6, 0, 9.8, 3.2, 9.2, (0.28, 0.28), skip_bottom=True)
    brick.add_box(0, 6.4, 0, 9.6, 6.6, 9.0, (0.30, 0.30))
    # Stone lintel & decorative top cornice
    trim.add_box(0, 3.25, 0, 10.1, 0.3, 9.5, (0.3, 0.3))
    trim.add_box(0, 9.85, 0, 10.2, 0.45, 9.6, (0.3, 0.3))
    roof.add_box(0, 10.05, 0, 9.2, 0.15, 8.6, (0.25, 0.25))
    # Ground shop windows & striped awning
    glass.add_box(-2.4, 1.5, 4.64, 3.4, 2.2, 0.08, (0.4, 0.4))
    glass.add_box(2.4, 1.5, 4.64, 3.4, 2.2, 0.08, (0.4, 0.4))
    awning.add_box(-2.4, 2.75, 5.15, 3.6, 0.4, 1.1, (0.5, 0.5))
    awning.add_box(2.4, 2.75, 5.15, 3.6, 0.4, 1.1, (0.5, 0.5))
    # Upper apartment windows with stone sills on front & back
    for fy in (5.0, 7.8):
        for fx in (-3.0, 0.0, 3.0):
            glass.add_box(fx, fy, 4.54, 1.5, 1.8, 0.08, (0.5, 0.5))
            trim.add_box(fx, fy - 0.96, 4.62, 1.75, 0.16, 0.24, (0.5, 0.5))
            glass.add_box(fx, fy, -4.54, 1.5, 1.8, 0.08, (0.5, 0.5))
            trim.add_box(fx, fy - 0.96, -4.62, 1.75, 0.16, 0.24, (0.5, 0.5))
    # Side windows
    for fy in (5.0, 7.8):
        for fz in (-2.2, 2.2):
            glass.add_box(4.84, fy, fz, 0.08, 1.8, 1.5, (0.5, 0.5))
            glass.add_box(-4.84, fy, fz, 0.08, 1.8, 1.5, (0.5, 0.5))
    # Roof skylight & AC
    metal.add_box(-1.5, 10.45, 0.5, 2.2, 0.7, 1.6, (0.5, 0.5))
    metal.add_box(2.0, 10.35, -1.5, 1.4, 0.5, 1.4, (0.5, 0.5))
    m.save(os.path.join(MOD_DIR, "bldg_brick_midrise.glb"))

    # --- C. American Corner Shop / Cafe (9.5m x 6.4m x 9.0m) ---
    m = GLBModel("bldg_corner_shop")
    stucco = m.mat("mat_stucco_cream", (0.86, 0.81, 0.72, 1.0), 0.0, 0.82)
    brick = m.mat("mat_brick_tan", (0.72, 0.59, 0.44, 1.0), 0.0, 0.86)
    glass = m.mat("mat_commercial_glass", (0.40, 0.58, 0.72, 1.0), 0.15, 0.12)
    awning = m.mat("mat_awning_accent", (0.84, 0.45, 0.14, 1.0), 0.0, 0.76)
    metal = m.mat("mat_metal_dark", (0.24, 0.25, 0.27, 1.0), 0.55, 0.42)
    roof = m.mat("mat_roof_gravel", (0.42, 0.40, 0.38, 1.0), 0.0, 0.92)

    brick.add_box(0, 0.65, 0, 9.4, 1.3, 8.8, (0.3, 0.3), skip_bottom=True)
    stucco.add_box(0, 3.65, 0, 9.2, 4.8, 8.6, (0.25, 0.25))
    brick.add_box(0, 6.2, 0, 9.6, 0.5, 9.0, (0.3, 0.3))
    roof.add_box(0, 6.42, 0, 8.8, 0.15, 8.2, (0.25, 0.25))
    # Wrap-around storefront windows & corner awning
    glass.add_box(0, 2.2, 4.35, 7.6, 2.6, 0.1, (0.4, 0.4))
    glass.add_box(4.65, 2.2, 0, 0.1, 2.6, 6.8, (0.4, 0.4))
    awning.add_box(0, 3.65, 4.95, 8.2, 0.45, 1.3, (0.5, 0.5))
    awning.add_box(5.2, 3.65, 0, 1.3, 0.45, 7.6, (0.5, 0.5))
    # Rooftop sign fascia & HVAC
    metal.add_box(0, 6.95, 4.2, 5.2, 1.1, 0.28, (0.5, 0.5))
    metal.add_box(-2.0, 6.8, -1.6, 1.8, 0.75, 1.4, (0.5, 0.5))
    m.save(os.path.join(MOD_DIR, "bldg_corner_shop.glb"))

    # --- D. American Suburban Craftsman House (9.0m x 6.8m x 8.4m) ---
    m = GLBModel("bldg_suburban_house")
    wall = m.mat("mat_stucco_sage", (0.72, 0.78, 0.71, 1.0), 0.0, 0.84)
    stone = m.mat("mat_brick_tan", (0.68, 0.58, 0.48, 1.0), 0.0, 0.88)
    trim = m.mat("mat_concrete", (0.92, 0.90, 0.86, 1.0), 0.0, 0.78)
    roof_mat = m.mat("mat_roof_shingle", (0.32, 0.27, 0.25, 1.0), 0.0, 0.90)
    glass = m.mat("mat_commercial_glass", (0.36, 0.48, 0.60, 1.0), 0.15, 0.15)
    wood = m.mat("mat_wood_door", (0.46, 0.28, 0.16, 1.0), 0.0, 0.72)

    # Foundation & main two-story volume
    stone.add_box(0, 0.35, 0, 8.6, 0.7, 7.6, (0.3, 0.3), skip_bottom=True)
    wall.add_box(0, 2.8, 0, 8.4, 4.3, 7.4, (0.28, 0.28))
    # Front porch deck, columns & porch roof
    stone.add_box(-0.9, 0.3, 4.5, 5.2, 0.6, 1.8, (0.3, 0.3), skip_bottom=True)
    trim.add_box(-3.2, 1.75, 5.2, 0.26, 2.5, 0.26, (0.5, 0.5))
    trim.add_box(-0.9, 1.75, 5.2, 0.26, 2.5, 0.26, (0.5, 0.5))
    trim.add_box(1.4, 1.75, 5.2, 0.26, 2.5, 0.26, (0.5, 0.5))
    roof_mat.add_box(-0.9, 3.15, 4.55, 5.6, 0.32, 2.1, (0.35, 0.35))
    # Front door & garage door
    wood.add_box(-0.9, 1.65, 3.74, 1.15, 2.2, 0.1, (0.5, 0.5))
    trim.add_box(2.55, 1.55, 3.74, 2.7, 2.35, 0.12, (0.4, 0.4))
    # Windows with crisp white frames
    for wx, wy, wz in [(-2.6, 1.85, 3.74), (-2.4, 3.85, 3.74), (0.0, 3.85, 3.74), (2.4, 3.85, 3.74)]:
        trim.add_box(wx, wy, wz, 1.32, 1.32, 0.1, (0.5, 0.5))
        glass.add_box(wx, wy, wz + 0.04, 1.12, 1.12, 0.06, (0.5, 0.5))
    for wz in (-1.6, 1.6):
        trim.add_box(4.24, 2.2, wz, 0.1, 1.3, 1.3, (0.5, 0.5))
        glass.add_box(4.28, 2.2, wz, 0.06, 1.1, 1.1, (0.5, 0.5))
        trim.add_box(-4.24, 2.2, wz, 0.1, 1.3, 1.3, (0.5, 0.5))
        glass.add_box(-4.28, 2.2, wz, 0.06, 1.1, 1.1, (0.5, 0.5))
    # Pitched gabled roof (sculpted triangular prism with eaves overhang)
    eave_y = 4.95
    ridge_y = 7.15
    rx, rz = 4.75, 4.15
    # Two sloped roof planes
    roof_mat.add_quad((-rx, eave_y, rz), (rx, eave_y, rz), (rx, ridge_y, 0), (-rx, ridge_y, 0), (0.35, 0.35))
    roof_mat.add_quad((rx, eave_y, -rz), (-rx, eave_y, -rz), (-rx, ridge_y, 0), (rx, ridge_y, 0), (0.35, 0.35))
    # Gable walls (+X / -X)
    wall.add_tri((4.2, eave_y, 3.7), (4.2, eave_y, -3.7), (4.2, ridge_y - 0.08, 0.0), (0.3, 0.3), (1, 0, 0))
    wall.add_tri((-4.2, eave_y, -3.7), (-4.2, eave_y, 3.7), (-4.2, ridge_y - 0.08, 0.0), (0.3, 0.3), (-1, 0, 0))
    # Brick chimney
    stone.add_box(-2.8, 6.2, -1.6, 0.95, 2.6, 0.95, (0.4, 0.4))
    m.save(os.path.join(MOD_DIR, "bldg_suburban_house.glb"))

    # --- E. Diner / Convenience Market (10.5m x 5.2m x 7.5m) ---
    m = GLBModel("bldg_diner_market")
    stucco = m.mat("mat_stucco_terracotta", (0.82, 0.62, 0.48, 1.0), 0.0, 0.80)
    trim = m.mat("mat_concrete", (0.88, 0.86, 0.82, 1.0), 0.0, 0.75)
    glass = m.mat("mat_commercial_glass", (0.42, 0.62, 0.74, 1.0), 0.15, 0.10)
    chrome = m.mat("mat_chrome", (0.82, 0.84, 0.88, 1.0), 0.85, 0.22)
    accent = m.mat("mat_awning_accent", (0.86, 0.22, 0.18, 1.0), 0.0, 0.65)
    roof = m.mat("mat_roof_gravel", (0.38, 0.37, 0.36, 1.0), 0.0, 0.92)

    stucco.add_box(0, 2.3, 0, 10.2, 4.6, 7.2, (0.28, 0.28), skip_bottom=True)
    accent.add_box(0, 4.2, 0, 10.6, 0.65, 7.6, (0.3, 0.3))
    chrome.add_box(0, 4.62, 0, 10.75, 0.22, 7.75, (0.4, 0.4))
    roof.add_box(0, 4.75, 0, 9.8, 0.14, 6.8, (0.25, 0.25))
    # Wide front diner windows & cantilevered canopy
    glass.add_box(0, 1.95, 3.64, 8.6, 2.3, 0.08, (0.4, 0.4))
    trim.add_box(0, 3.45, 4.5, 9.4, 0.28, 1.9, (0.4, 0.4))
    chrome.add_box(-4.2, 1.65, 5.2, 0.18, 3.3, 0.18, (0.5, 0.5))
    chrome.add_box(4.2, 1.65, 5.2, 0.18, 3.3, 0.18, (0.5, 0.5))
    m.save(os.path.join(MOD_DIR, "bldg_diner_market.glb"))

    # --- F. Hero Drivable American Sport Sedan Body (1.92m wide x 1.38m tall x 4.42m long, facing -Z) ---
    m = GLBModel("car_body")
    paint = m.mat("mat_car_paint", (0.76, 0.14, 0.14, 1.0), 0.45, 0.22)  # Deep metallic crimson
    glass = m.mat("mat_car_glass", (0.12, 0.18, 0.24, 1.0), 0.2, 0.08)
    trim = m.mat("mat_car_trim", (0.12, 0.13, 0.15, 1.0), 0.25, 0.55)
    chrome = m.mat("mat_chrome", (0.86, 0.88, 0.92, 1.0), 0.90, 0.18)
    headlight = m.mat("mat_headlight", (0.98, 0.96, 0.86, 1.0), 0.1, 0.1, emissive=(0.95, 0.92, 0.78))
    taillight = m.mat("mat_taillight", (0.88, 0.10, 0.08, 1.0), 0.1, 0.15, emissive=(0.45, 0.04, 0.03))

    # Note: Model origin is at chassis center; bottom of sills at y = 0.0 (positioned above wheel hubs in Vehicle.tscn)
    # Lower rocker skirts & chassis tub
    trim.add_box(0, 0.10, 0.0, 1.82, 0.20, 4.10, (0.5, 0.5))
    # Main sculpted lower body
    paint.add_box(0, 0.44, 0.02, 1.90, 0.54, 4.28, (0.5, 0.5))
    # Front hood (sloped slightly forward toward -Z)
    paint.add_quad((-0.88, 0.71, -0.78), (0.88, 0.71, -0.78), (0.84, 0.62, -2.14), (-0.84, 0.62, -2.14), (0.5, 0.5))
    # Sculpted rear trunk deck
    paint.add_box(0, 0.74, 1.56, 1.82, 0.14, 1.12, (0.5, 0.5))
    # Rear subtle lip spoiler
    trim.add_box(0, 0.84, 2.08, 1.72, 0.08, 0.18, (0.5, 0.5))

    # Tapered Greenhouse Cabin (sloped windshield + rear fastback glass)
    # Roof panel
    paint.add_quad((-0.72, 1.24, 0.82), (0.72, 1.24, 0.82), (0.72, 1.24, -0.34), (-0.72, 1.24, -0.34), (0.5, 0.5))
    # Front windshield (-Z)
    glass.add_quad((-0.82, 0.71, -0.84), (0.82, 0.71, -0.84), (0.71, 1.24, -0.34), (-0.71, 1.24, -0.34), (0.5, 0.5))
    # Rear window (+Z)
    glass.add_quad((0.80, 0.78, 1.38), (-0.80, 0.78, 1.38), (-0.71, 1.24, 0.82), (0.71, 1.24, 0.82), (0.5, 0.5))
    # Left & right cabin side windows
    glass.add_quad((-0.82, 0.71, 1.32), (-0.82, 0.71, -0.80), (-0.72, 1.24, -0.34), (-0.72, 1.24, 0.82), (0.5, 0.5))
    glass.add_quad((0.82, 0.71, -0.80), (0.82, 0.71, 1.32), (0.72, 1.24, 0.82), (0.72, 1.24, -0.34), (0.5, 0.5))
    # B-pillars and side mirrors
    trim.add_box(-0.79, 0.96, 0.24, 0.07, 0.52, 0.14, (0.5, 0.5))
    trim.add_box(0.79, 0.96, 0.24, 0.07, 0.52, 0.14, (0.5, 0.5))
    paint.add_box(-1.02, 0.78, -0.60, 0.22, 0.12, 0.16, (0.5, 0.5))
    paint.add_box(1.02, 0.78, -0.60, 0.22, 0.12, 0.16, (0.5, 0.5))

    # Front bumper, intake grille, chrome strip, headlights (-Z front)
    trim.add_box(0, 0.24, -2.16, 1.90, 0.28, 0.18, (0.5, 0.5))
    trim.add_box(0, 0.48, -2.15, 1.12, 0.22, 0.10, (0.5, 0.5))
    chrome.add_box(0, 0.48, -2.19, 1.06, 0.05, 0.06, (0.5, 0.5))
    headlight.add_box(-0.68, 0.52, -2.14, 0.40, 0.16, 0.10, (0.5, 0.5))
    headlight.add_box(0.68, 0.52, -2.14, 0.40, 0.16, 0.10, (0.5, 0.5))

    # Rear bumper, twin exhaust tips, taillights, license plate (+Z rear)
    trim.add_box(0, 0.24, 2.18, 1.90, 0.28, 0.18, (0.5, 0.5))
    chrome.add_cylinder(-0.56, 0.14, 2.24, 0.055, 0.055, 0.14, 8, axis="y")
    chrome.add_cylinder(0.56, 0.14, 2.24, 0.055, 0.055, 0.14, 8, axis="y")
    taillight.add_box(-0.66, 0.56, 2.17, 0.46, 0.15, 0.08, (0.5, 0.5))
    taillight.add_box(0.66, 0.56, 2.17, 0.46, 0.15, 0.08, (0.5, 0.5))
    chrome.add_box(0, 0.48, 2.18, 0.36, 0.16, 0.04, (0.5, 0.5))

    # Wheel well arches (dark recessed inner wells)
    for wx in (-0.82, 0.82):
        for wz in (-1.34, 1.32):
            trim.add_box(wx, 0.28, wz, 0.28, 0.44, 0.78, (0.5, 0.5))
    m.save(os.path.join(MOD_DIR, "car_body.glb"))

    # --- G. Detailed Car Wheel (Radius 0.35m, Width 0.26m, X-aligned axle) ---
    m = GLBModel("car_wheel")
    tire = m.mat("mat_tire", (0.13, 0.13, 0.14, 1.0), 0.05, 0.82)
    rim = m.mat("mat_alloy_rim", (0.78, 0.80, 0.84, 1.0), 0.85, 0.24)
    hub = m.mat("mat_brake_disc", (0.28, 0.29, 0.31, 1.0), 0.7, 0.45)

    tire.add_cylinder(0, 0, 0, 0.35, 0.35, 0.25, segs=18, axis="x", uv_scale=(1.0, 1.0))
    rim.add_cylinder(0, 0, 0, 0.23, 0.23, 0.265, segs=16, axis="x")
    hub.add_cylinder(0, 0, 0, 0.08, 0.08, 0.28, segs=10, axis="x")
    # 5 alloy spokes (visible rotation cues!)
    for i in range(5):
        ang = (i / 5.0) * math.tau
        sy = math.cos(ang) * 0.14
        sz = math.sin(ang) * 0.14
        rim.add_box(0, sy, sz, 0.275, 0.055, 0.055, (1.0, 1.0))
    m.save(os.path.join(MOD_DIR, "car_wheel.glb"))

    # --- H. Streetlight (Cobra-head American pole, 6.2m tall) ---
    m = GLBModel("prop_streetlight")
    pole = m.mat("mat_metal_dark", (0.24, 0.27, 0.30, 1.0), 0.65, 0.40)
    lamp = m.mat("mat_headlight", (0.96, 0.92, 0.80, 1.0), 0.1, 0.2, emissive=(0.45, 0.42, 0.32))
    pole.add_cylinder(0, 0.22, 0, 0.18, 0.14, 0.44, segs=8)
    pole.add_cylinder(0, 3.2, 0, 0.10, 0.075, 5.9, segs=8)
    pole.add_box(0, 6.05, 0.78, 0.10, 0.10, 1.65, (1, 1))
    pole.add_box(0, 6.04, 1.62, 0.28, 0.12, 0.52, (1, 1))
    lamp.add_box(0, 5.96, 1.62, 0.22, 0.05, 0.40, (1, 1))
    m.save(os.path.join(MOD_DIR, "prop_streetlight.glb"))

    # --- I. Traffic Signal Pole (American cantilevered gantry) ---
    m = GLBModel("prop_traffic_light")
    pole = m.mat("mat_metal_dark", (0.20, 0.22, 0.24, 1.0), 0.65, 0.42)
    housing = m.mat("mat_signal_yellow", (0.86, 0.64, 0.14, 1.0), 0.15, 0.45)
    red_l = m.mat("mat_sig_red", (0.85, 0.12, 0.10, 1.0), 0.1, 0.2, emissive=(0.7, 0.08, 0.06))
    amb_l = m.mat("mat_sig_amb", (0.88, 0.62, 0.10, 1.0), 0.1, 0.2, emissive=(0.18, 0.12, 0.02))
    grn_l = m.mat("mat_sig_grn", (0.14, 0.82, 0.34, 1.0), 0.1, 0.2, emissive=(0.15, 0.75, 0.28))

    pole.add_cylinder(0, 0.25, 0, 0.20, 0.16, 0.5, segs=8)
    pole.add_cylinder(0, 3.0, 0, 0.12, 0.09, 5.6, segs=8)
    pole.add_box(0, 5.55, 1.45, 0.12, 0.12, 3.0, (1, 1))
    for z_pos in (1.4, 2.7):
        housing.add_box(0, 5.15, z_pos, 0.30, 0.86, 0.34, (1, 1))
        red_l.add_box(0.16, 5.40, z_pos, 0.04, 0.18, 0.18, (1, 1))
        amb_l.add_box(0.16, 5.15, z_pos, 0.04, 0.18, 0.18, (1, 1))
        grn_l.add_box(0.16, 4.90, z_pos, 0.04, 0.18, 0.18, (1, 1))
    m.save(os.path.join(MOD_DIR, "prop_traffic_light.glb"))

    # --- J. Park / Sidewalk Bench ---
    m = GLBModel("prop_bench")
    wood = m.mat("mat_wood_door", (0.56, 0.36, 0.20, 1.0), 0.0, 0.76)
    iron = m.mat("mat_metal_dark", (0.18, 0.20, 0.22, 1.0), 0.65, 0.44)
    for lx in (-0.76, 0.76):
        iron.add_box(lx, 0.24, 0.18, 0.08, 0.48, 0.08, (1, 1))
        iron.add_box(lx, 0.44, -0.22, 0.08, 0.88, 0.08, (1, 1))
        iron.add_box(lx, 0.46, 0.0, 0.08, 0.06, 0.48, (1, 1))
    for sz in (-0.12, 0.04, 0.20):
        wood.add_box(0, 0.48, sz, 1.76, 0.06, 0.13, (1, 1))
    for sy in (0.68, 0.84):
        wood.add_box(0, sy, -0.22, 1.76, 0.12, 0.05, (1, 1))
    m.save(os.path.join(MOD_DIR, "prop_bench.glb"))

    # --- K. Street Tree (Tapered bark trunk + multi-lobed organic foliage crown) ---
    m = GLBModel("prop_tree")
    bark = m.mat("mat_bark", (0.42, 0.30, 0.22, 1.0), 0.0, 0.92)
    foliage = m.mat("mat_foliage", (0.30, 0.56, 0.24, 1.0), 0.0, 0.85)
    bark.add_cylinder(0, 1.4, 0, 0.24, 0.15, 2.8, segs=8, uv_scale=(1.0, 0.6))
    # Main limbs
    bark.add_box(0.32, 2.6, 0.18, 0.14, 0.9, 0.14, (1, 1))
    bark.add_box(-0.28, 2.7, -0.20, 0.14, 0.8, 0.14, (1, 1))
    # Sculpted multi-lobe crown
    foliage.add_sphere_cluster(0.0, 4.15, 0.0, 1.65, 1.35, 1.60, rings=6, segs=10)
    foliage.add_sphere_cluster(0.95, 3.65, 0.55, 1.15, 0.95, 1.10, rings=5, segs=8)
    foliage.add_sphere_cluster(-0.90, 3.75, -0.45, 1.20, 1.00, 1.15, rings=5, segs=8)
    foliage.add_sphere_cluster(-0.35, 4.85, 0.40, 1.05, 0.85, 1.00, rings=5, segs=8)
    m.save(os.path.join(MOD_DIR, "prop_tree.glb"))

    # --- L. American Fire Hydrant ---
    m = GLBModel("prop_hydrant")
    red = m.mat("mat_hydrant_red", (0.78, 0.16, 0.14, 1.0), 0.25, 0.42)
    cap = m.mat("mat_chrome", (0.76, 0.78, 0.80, 1.0), 0.75, 0.30)
    red.add_cylinder(0, 0.06, 0, 0.20, 0.18, 0.12, segs=10)
    red.add_cylinder(0, 0.40, 0, 0.14, 0.13, 0.60, segs=10)
    red.add_cylinder(0, 0.74, 0, 0.17, 0.11, 0.14, segs=10)
    cap.add_cylinder(0, 0.85, 0, 0.06, 0.05, 0.10, segs=6)
    cap.add_cylinder(0, 0.54, 0, 0.065, 0.065, 0.42, segs=8, axis="x")
    m.save(os.path.join(MOD_DIR, "prop_hydrant.glb"))

    # --- M. Street Vending Machine ---
    m = GLBModel("prop_vending")
    body = m.mat("mat_vending_body", (0.18, 0.42, 0.72, 1.0), 0.35, 0.38)
    front = m.mat("mat_vending_front", (0.90, 0.94, 0.98, 1.0), 0.1, 0.2, emissive=(0.16, 0.20, 0.24))
    dark = m.mat("mat_metal_dark", (0.14, 0.15, 0.17, 1.0), 0.5, 0.5)
    body.add_box(0, 0.98, 0, 1.08, 1.96, 0.76, (0.5, 0.5), skip_bottom=True)
    front.add_box(-0.10, 1.24, 0.39, 0.72, 1.04, 0.04, (1, 1))
    dark.add_box(0.36, 1.18, 0.39, 0.18, 0.46, 0.05, (1, 1))
    dark.add_box(-0.08, 0.38, 0.39, 0.76, 0.34, 0.05, (1, 1))
    m.save(os.path.join(MOD_DIR, "prop_vending.glb"))

    # --- N. Hooded Sidewalk Trash Bin ---
    m = GLBModel("prop_trashbin")
    bin_mat = m.mat("mat_metal_dark", (0.22, 0.28, 0.25, 1.0), 0.45, 0.50)
    trim = m.mat("mat_chrome", (0.65, 0.68, 0.70, 1.0), 0.7, 0.35)
    bin_mat.add_box(0, 0.44, 0, 0.56, 0.88, 0.56, (1, 1), skip_bottom=True)
    bin_mat.add_box(0, 1.04, 0, 0.60, 0.16, 0.60, (1, 1))
    trim.add_box(-0.26, 0.94, -0.26, 0.06, 0.24, 0.06, (1, 1))
    trim.add_box(0.26, 0.94, -0.26, 0.06, 0.24, 0.06, (1, 1))
    trim.add_box(-0.26, 0.94, 0.26, 0.06, 0.24, 0.06, (1, 1))
    trim.add_box(0.26, 0.94, 0.26, 0.06, 0.24, 0.06, (1, 1))
    m.save(os.path.join(MOD_DIR, "prop_trashbin.glb"))

    # --- O. Wooden Utility Pole with Cross-Arm & Transformer ---
    m = GLBModel("prop_utility_pole")
    wood = m.mat("mat_bark", (0.38, 0.29, 0.22, 1.0), 0.0, 0.90)
    metal = m.mat("mat_metal_dark", (0.36, 0.38, 0.40, 1.0), 0.55, 0.45)
    wood.add_cylinder(0, 3.7, 0, 0.16, 0.11, 7.4, segs=8)
    wood.add_box(0, 6.75, 0, 2.2, 0.14, 0.14, (1, 1))
    wood.add_box(0, 6.20, 0, 1.7, 0.12, 0.12, (1, 1))
    metal.add_cylinder(0.28, 5.4, 0, 0.24, 0.24, 0.82, segs=10)
    m.save(os.path.join(MOD_DIR, "prop_utility_pole.glb"))

    # --- P. Central Landmark Clock-Tower & Tiered Fountain Monument ---
    m = GLBModel("landmark_clock_fountain")
    stone = m.mat("mat_concrete", (0.82, 0.79, 0.73, 1.0), 0.0, 0.78)
    bronze = m.mat("mat_bronze", (0.34, 0.28, 0.20, 1.0), 0.72, 0.36)
    water = m.mat("mat_water", (0.20, 0.56, 0.74, 1.0), 0.1, 0.08)
    dial = m.mat("mat_clock_dial", (0.96, 0.94, 0.88, 1.0), 0.05, 0.3, emissive=(0.25, 0.24, 0.20))

    # Octagonal fountain basin + shimmering water
    stone.add_cylinder(0, 0.32, 0, 3.2, 3.3, 0.64, segs=12)
    water.add_cylinder(0, 0.56, 0, 2.85, 2.85, 0.22, segs=12)
    # Central stone obelisk / clock pedestal
    stone.add_box(0, 1.35, 0, 1.9, 1.9, 1.9, (0.4, 0.4))
    stone.add_box(0, 3.9, 0, 1.35, 3.4, 1.35, (0.4, 0.4))
    bronze.add_box(0, 5.75, 0, 1.55, 0.24, 1.55, (0.5, 0.5))
    stone.add_box(0, 6.6, 0, 1.45, 1.5, 1.45, (0.5, 0.5))
    # 4 Clock Faces
    dial.add_box(0, 6.6, 0.75, 1.02, 1.02, 0.06, (1, 1))
    dial.add_box(0, 6.6, -0.75, 1.02, 1.02, 0.06, (1, 1))
    dial.add_box(0.75, 6.6, 0, 0.06, 1.02, 1.02, (1, 1))
    dial.add_box(-0.75, 6.6, 0, 0.06, 1.02, 1.02, (1, 1))
    # Clock hands
    bronze.add_box(0.08, 6.72, 0.80, 0.06, 0.34, 0.04, (1, 1))
    bronze.add_box(0.18, 6.60, 0.80, 0.28, 0.06, 0.04, (1, 1))
    # Stepped bronze spire roof
    bronze.add_cylinder(0, 7.95, 0, 1.15, 0.14, 1.25, segs=4)
    bronze.add_cylinder(0, 8.85, 0, 0.06, 0.02, 0.7, segs=6)
    m.save(os.path.join(MOD_DIR, "landmark_clock_fountain.glb"))


# =============================================================================
# 4. SYNTHESIZED REALISTIC WAV AUDIO ASSETS (ZERO SILENCE)
# =============================================================================

def write_wav(path, samples, sample_rate=22050):
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        data = bytearray()
        for s in samples:
            s = max(-0.98, min(0.98, s))
            data.extend(struct.pack("<h", int(s * 32767.0)))
        wf.writeframes(bytes(data))


def generate_audio():
    print("Synthesizing WAV audio assets...")
    SR = 22050
    rng = random.Random(42)

    # 1. Seamless Urban Afternoon Ambience Loop (8.0s: soft breeze + warm distant city hum)
    dur = 8.0
    n = int(SR * dur)
    raw = [0.0] * n
    lp1 = 0.0
    lp2 = 0.0
    # Generate slightly longer then crossfade ends for click-free loop
    ext = n + int(SR * 0.5)
    buf = [0.0] * ext
    for i in range(ext):
        t = i / SR
        w = rng.uniform(-1.0, 1.0)
        lp1 = lp1 * 0.985 + w * 0.015  # deep distant traffic rumble
        lp2 = lp2 * 0.935 + w * 0.065  # mid-low afternoon air / breeze
        swell = 0.70 + 0.30 * math.sin(math.tau * t / dur)
        breeze = 0.75 + 0.25 * math.sin(math.tau * t * 2.0 / dur + 1.1)
        city_bed = (lp1 * 2.4 * swell) + (lp2 * 0.85 * breeze)
        # subtle warm tonal air bed (very soft 82Hz / 123Hz urban hum)
        hum = 0.014 * math.sin(math.tau * 82.0 * t) + 0.009 * math.sin(math.tau * 123.0 * t)
        buf[i] = (city_bed + hum) * 0.55
    xfade = int(SR * 0.5)
    for i in range(n):
        if i < xfade:
            a = i / xfade
            raw[i] = buf[i] * a + buf[n + i] * (1.0 - a)
        else:
            raw[i] = buf[i]
    write_wav(os.path.join(AUD_DIR, "ambient_city_afternoon.wav"), raw, SR)

    # 2. Asphalt Footstep Variations (3 crisp heel-toe sneaker impacts)
    for idx_step in range(1, 4):
        sr_f = SR
        nf = int(sr_f * 0.16)
        samples = [0.0] * nf
        bp = 0.0
        hp = 0.0
        freq_thud = 112.0 + idx_step * 14.0
        for i in range(nf):
            t = i / sr_f
            # Heel strike + subtle grit scuff
            env_thud = math.exp(-t * 42.0)
            env_grit = math.exp(-t * 28.0) * min(1.0, t * 180.0)
            thud = math.sin(math.tau * freq_thud * t * (1.0 - t * 2.5)) * env_thud * 0.52
            w = rng.uniform(-1.0, 1.0)
            bp = bp * 0.72 + w * 0.28
            hp = w - bp
            grit = (bp * 0.55 + hp * 0.22) * env_grit * 0.65
            samples[i] = (thud + grit) * 0.85
        write_wav(os.path.join(AUD_DIR, f"footstep_asphalt_0{idx_step}.wav"), samples, sr_f)

    # 3. Seamless Engine Loop (2.0s harmonic V6/sport-sedan idle-cruising loop)
    # Exact integer cycles in 2.0s so loop boundary is mathematically phase-continuous!
    dur_e = 2.0
    ne = int(SR * dur_e)
    base_hz = 46.0  # 92 cycles in 2.0s -> phase continuous!
    eng = [0.0] * ne
    lp = 0.0
    for i in range(ne):
        t = i / SR
        p = math.tau * base_hz * t
        # Rich combustion harmonics + subtle firing flutter
        flutter = 1.0 + 0.08 * math.sin(math.tau * 7.0 * t)
        sig = (
            0.42 * math.sin(p)
            + 0.30 * math.sin(p * 2.0 + 0.3)
            + 0.18 * math.sin(p * 3.0 + 0.9)
            + 0.10 * math.sin(p * 4.0 + 1.4)
            + 0.06 * math.sin(p * 6.0 + 0.2)
            + 0.04 * math.sin(p * 0.5)
        ) * flutter
        # Soft mechanical exhaust grit
        w = rng.uniform(-1.0, 1.0)
        lp = lp * 0.86 + w * 0.14
        eng[i] = math.tanh((sig * 0.55 + lp * 0.18) * 1.15) * 0.62
    write_wav(os.path.join(AUD_DIR, "engine_loop.wav"), eng, SR)

    # 4. Car Door Latch & Cabin Thud (0.28s)
    nd = int(SR * 0.28)
    door = [0.0] * nd
    lp = 0.0
    for i in range(nd):
        t = i / SR
        latch = math.sin(math.tau * 920.0 * t) * math.exp(-t * 95.0) * 0.35
        thud = math.sin(math.tau * 74.0 * t) * math.exp(-t * 22.0) * 0.72
        w = rng.uniform(-1.0, 1.0)
        lp = lp * 0.85 + w * 0.15
        air = lp * math.exp(-t * 30.0) * 0.45
        door[i] = math.tanh((latch + thud + air) * 1.1) * 0.82
    write_wav(os.path.join(AUD_DIR, "car_door.wav"), door, SR)

    # 5. Vehicle Impact / Bump (0.34s)
    nb = int(SR * 0.34)
    bump = [0.0] * nb
    lp = 0.0
    for i in range(nb):
        t = i / SR
        w = rng.uniform(-1.0, 1.0)
        lp = lp * 0.82 + w * 0.18
        body = math.sin(math.tau * (68.0 - t * 40.0) * t) * math.exp(-t * 16.0) * 0.75
        crunch = lp * math.exp(-t * 18.0) * 0.65
        bump[i] = math.tanh((body + crunch) * 1.25) * 0.85
    write_wav(os.path.join(AUD_DIR, "car_bump.wav"), bump, SR)


if __name__ == "__main__":
    generate_textures()
    generate_models()
    generate_audio()
    print("All PBR textures, glTF 2.0 (.glb) models, and WAV audio assets generated successfully.")
