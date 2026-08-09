#!/usr/bin/env python3
"""Generate the DMG background image for TOM (660x400, @2x rendered then downscaled)."""

import math
import random
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SCALE = 3  # supersample for crisp text/lines
CANVAS_W, CANVAS_H = 660, 430  # extra 30px buffer below the original 400px design
DESIGN_H = 400  # all layout below is positioned relative to this, unchanged
W, H = CANVAS_W * SCALE, CANVAS_H * SCALE
DH = DESIGN_H * SCALE

BG_TOP = (100, 150, 205)
BG_BOTTOM = (70, 115, 170)
CRYSTAL_LIGHT = (110, 160, 210)
CRYSTAL_MID = (70, 120, 170)
CRYSTAL_DARK = (48, 88, 130)
LINE_COLOR = (150, 190, 225)
TEXT_COLOR = (255, 255, 255)
SUB_COLOR = (225, 235, 248)
ARROW_COLOR = (95, 105, 120)

random.seed(7)

img = Image.new("RGB", (W, H), BG_TOP)
draw = ImageDraw.Draw(img)

# Vertical gradient background
for y in range(H):
    t = y / H
    r = int(BG_TOP[0] + (BG_BOTTOM[0] - BG_TOP[0]) * t)
    g = int(BG_TOP[1] + (BG_BOTTOM[1] - BG_TOP[1]) * t)
    b = int(BG_TOP[2] + (BG_BOTTOM[2] - BG_TOP[2]) * t)
    draw.line([(0, y), (W, y)], fill=(r, g, b))

# Scattered angular crystal shards along the very bottom edge, echoing the
# app icon's faceted-gem look (individual jagged chunks, not a ridgeline).
def draw_shard(bdraw, cx, cy, size, rot_deg):
    """A faceted shard: an irregular hexagon-ish outline split into
    triangles fanning from a jittered core point, each shaded differently."""
    n = random.randint(5, 7)
    pts = []
    for i in range(n):
        ang = math.radians(rot_deg + i * (360 / n) + random.uniform(-12, 12))
        r = size * random.uniform(0.55, 1.0)
        pts.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
    core = (cx + random.uniform(-size * 0.15, size * 0.15),
            cy + random.uniform(-size * 0.15, size * 0.15))
    shades = [CRYSTAL_LIGHT, CRYSTAL_MID, CRYSTAL_DARK]
    for i in range(n):
        p1 = pts[i]
        p2 = pts[(i + 1) % n]
        shade = shades[(i + random.randint(0, 2)) % 3]
        bdraw.polygon([core, p1, p2], fill=shade + (255,))
        bdraw.line([core, p1], fill=LINE_COLOR + (110,), width=max(1, SCALE // 2))
    bdraw.polygon(pts, outline=LINE_COLOR + (140,), width=max(1, SCALE // 2))
    # tiny sparkle highlight near the top edge of the shard, only on some
    if random.random() < 0.25:
        hx, hy = cx + random.uniform(-size * 0.2, size * 0.2), cy - size * 0.55
        hs = max(1, SCALE // 3)
        hl = size * 0.18
        bdraw.line([(hx - hl, hy), (hx + hl, hy)], fill=(255, 255, 255, 140), width=hs)
        bdraw.line([(hx, hy - hl), (hx, hy + hl)], fill=(255, 255, 255, 140), width=hs)


def jagged_top(width, base_y, amplitude, seg_w):
    """A random jagged polyline used as the top edge of the crystal fill,
    so the band reads as a broken crystal edge rather than a straight cut."""
    pts = []
    x = -seg_w
    y = base_y
    while x < width + seg_w:
        y = max(0, min(base_y + amplitude, y + random.uniform(-amplitude, amplitude)))
        pts.append((x, y))
        x += seg_w
    return pts


def crystal_band(y_base, height, width, alpha_img):
    pad = 20 * SCALE
    total_h = height + pad
    band = Image.new("RGBA", (width, total_h), (0, 0, 0, 0))
    bdraw = ImageDraw.Draw(band)

    # opaque base fill with a finely jagged top edge so no background shows
    # through and the band doesn't read as a straight-cut rectangle; kept
    # solid (no isolated floating shards) so no dark gaps appear
    edge_y = 12 * SCALE
    amplitude = 7 * SCALE
    top_pts = jagged_top(width, edge_y, amplitude, 5 * SCALE)
    poly = top_pts + [(width + 20 * SCALE, total_h), (-20 * SCALE, total_h)]
    bdraw.polygon(poly, fill=CRYSTAL_DARK + (255,))

    # dense field of small shards, packed in rows with jitter for full
    # coverage; rows start within the solid fill (not above it) so no
    # isolated fragments float over transparent background
    row_h = 7 * SCALE
    y = max(0, edge_y - amplitude)
    while y < total_h:
        x = -10 * SCALE + random.uniform(-4, 4) * SCALE
        while x < width + 10 * SCALE:
            size = random.uniform(5, 9) * SCALE
            cy = y + random.uniform(-3, 3) * SCALE
            rot = random.uniform(0, 360)
            draw_shard(bdraw, x, cy, size, rot)
            x += random.uniform(6, 10) * SCALE
        y += row_h
    alpha_img.alpha_composite(band, (0, y_base - pad))

overlay = img.convert("RGBA")
band_h = 46 * SCALE
crystal_band(DH - band_h, band_h, W, overlay)
img = overlay.convert("RGB")
draw = ImageDraw.Draw(img)

# Title text, top-center
def load_font(size, bold=False):
    path = "/System/Library/Fonts/HelveticaNeue.ttc"
    idx = 1 if bold else 0
    try:
        return ImageFont.truetype(path, size, index=idx)
    except Exception:
        return ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size)

title_font = load_font(30 * SCALE, bold=True)
sub_font = load_font(14 * SCALE, bold=False)

title = "TOM"
subtitle = "Tuco on Meth"

def center_text(draw, text, font, cy, fill):
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    x = (W - tw) / 2 - bbox[0]
    y = cy - th / 2 - bbox[1]
    draw.text((x, y), text, font=font, fill=fill)
    return tw, th

center_text(draw, title, title_font, 58 * SCALE, TEXT_COLOR)
center_text(draw, subtitle, sub_font, 92 * SCALE, SUB_COLOR)

# small divider line under subtitle
line_y = 112 * SCALE
draw.line([(W / 2 - 40 * SCALE, line_y), (W / 2 + 40 * SCALE, line_y)], fill=(220, 232, 245), width=max(1, SCALE // 2))

# Downscale for crisp anti-aliasing
final = img.resize((CANVAS_W, CANVAS_H), Image.LANCZOS)
out_path = "/Users/chris/Documents/Claude Code Projects/TOM/scripts/dmg_background.png"
final.save(out_path)
print("saved", out_path)
