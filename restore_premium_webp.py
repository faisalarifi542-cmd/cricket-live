#!/usr/bin/env python3
"""Restore premium background originals (archived PNG) as optimized active WebP.

For each large local-first background key, the active WebP in assets/images was a
heavily compressed (256-color, downscaled) Phase-4 fallback. The full-quality
originals live in archived/remote-assets-replaced/ as PNG. This converts each
original PNG -> optimized WebP (quality 85, longest side capped at 1600px) and
overwrites the active asset path. No PNG is shipped as a Flutter runtime asset.

Run:  python restore_premium_webp.py
"""
import os
from PIL import Image

SRC_ROOT = "archived/remote-assets-replaced"
DST_ROOT = "assets/images"
QUALITY = 85          # premium range 82-88 for large backgrounds
MAX_SIDE = 1600       # cap longest side; preserves aspect ratio

def main():
    rows = []
    for dirpath, _, files in os.walk(SRC_ROOT):
        for name in files:
            if not name.lower().endswith(".png"):
                continue
            src = os.path.join(dirpath, name).replace("\\", "/")
            rel = os.path.relpath(src, SRC_ROOT).replace("\\", "/")
            dst = os.path.join(DST_ROOT, os.path.splitext(rel)[0] + ".webp").replace("\\", "/")
            before = os.path.getsize(dst) if os.path.exists(dst) else 0
            im = Image.open(src)
            ow, oh = im.size
            # Real-alpha images keep RGBA; opaque -> RGB.
            if im.mode in ("RGBA", "LA", "P"):
                im = im.convert("RGBA")
                if not _has_alpha(im):
                    im = im.convert("RGB")
            else:
                im = im.convert("RGB")
            longest = max(im.size)
            if longest > MAX_SIDE:
                scale = MAX_SIDE / longest
                im = im.resize((round(im.size[0]*scale), round(im.size[1]*scale)), Image.LANCZOS)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            im.save(dst, "WEBP", quality=QUALITY, method=6)
            after = os.path.getsize(dst)
            rows.append((dst, ow, oh, im.size[0], im.size[1], before, after))

    print(f"{'active path':62} {'orig':>11} {'out':>11} {'before':>8} {'after':>8}")
    tb = ta = 0
    for dst, ow, oh, nw, nh, before, after in sorted(rows):
        tb += before; ta += after
        print(f"{dst:62} {ow}x{oh:>5} {nw}x{nh:>5} {before:8} {after:8}")
    print(f"\n{len(rows)} files. active webp total before={tb}  after={ta}  delta=+{ta-tb} bytes")

def _has_alpha(im):
    if im.mode != "RGBA":
        return False
    alpha = im.getchannel("A")
    return alpha.getextrema()[0] < 255

if __name__ == "__main__":
    main()
