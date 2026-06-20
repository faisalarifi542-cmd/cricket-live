#!/usr/bin/env python3
"""Phase 4 fallback compressor.

Reads a manifest of "SRC|DST" lines. SRC is the archived ORIGINAL (full size),
DST is the in-bundle path where a small fallback must live. Produces a visually
acceptable, lightweight PNG at DST (same .png extension -> no code/pubspec change).

Approach (per image):
  1. Downscale so the longest side <= MAX_DIM (keeps aspect).
  2. If the image is opaque, drop alpha (RGB) and quantize to an adaptive palette,
     stepping colors down until the file is <= TARGET_BYTES (floor MIN_COLORS).
  3. If the image has real transparency, keep RGBA and rely on downscale + optimize
     (no lossy palette on alpha -> correctness preserved).
  4. If still over target after the smallest palette, also shrink the longest side.

These are decorative background/panel fills rendered behind UI with opacity/tint,
so palette banding is not user-visible. Critical assets are never passed in here.
"""
import sys
from io import BytesIO
from PIL import Image

MAX_DIM = 1080
TARGET_BYTES = 300 * 1024
MIN_COLORS = 48
WIDTH_STEPS = [1080, 900, 720, 600]


def has_real_alpha(im):
    if im.mode not in ("RGBA", "LA", "P"):
        return False
    if im.mode == "P":
        if "transparency" not in im.info:
            return False
        im = im.convert("RGBA")
    alpha = im.getchannel("A")
    lo, hi = alpha.getextrema()
    return lo < 255  # any non-opaque pixel


def encode_png(im):
    buf = BytesIO()
    im.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def fit(im, longest):
    w, h = im.size
    scale = min(1.0, longest / max(w, h))
    if scale < 1.0:
        im = im.resize((max(1, round(w * scale)), max(1, round(h * scale))),
                       Image.LANCZOS)
    return im


def compress_opaque(src_im):
    best = None
    for width in WIDTH_STEPS:
        base = fit(src_im.convert("RGB"), width)
        for colors in (256, 224, 192, 160, 128, 96, 64, MIN_COLORS):
            q = base.quantize(colors=colors, method=Image.FASTOCTREE)
            data = encode_png(q)
            if best is None or len(data) < best[1]:
                best = (data, len(data))
            if len(data) <= TARGET_BYTES:
                return data, q.size, colors, width
    return best[0], src_im.size, MIN_COLORS, WIDTH_STEPS[-1]


def compress_alpha(src_im):
    best = None
    for width in WIDTH_STEPS:
        im = fit(src_im.convert("RGBA"), width)
        data = encode_png(im)
        if best is None or len(data) < best[1]:
            best = (data, len(data), im.size, width)
        if len(data) <= TARGET_BYTES:
            return data, im.size, "rgba", width
    return best[0], best[2], "rgba", best[3]


def process(src, dst):
    with Image.open(src) as im:
        im.load()
        alpha = has_real_alpha(im)
        if alpha:
            data, size, colors, width = compress_alpha(im)
        else:
            data, size, colors, width = compress_opaque(im)
    with open(dst, "wb") as f:
        f.write(data)
    return size, colors, len(data)


def main():
    manifest = sys.argv[1]
    rows = []
    with open(manifest, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            src, dst = line.split("|", 1)
            rows.append((src, dst))
    total_out = 0
    for src, dst in rows:
        size, colors, nbytes = process(src, dst)
        total_out += nbytes
        print(f"OK  {dst}  ->  {size[0]}x{size[1]}  colors={colors}  {nbytes/1024:.0f}KB")
    print(f"TOTAL fallback bytes: {total_out/1024:.0f}KB")


if __name__ == "__main__":
    main()
