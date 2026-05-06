#!/usr/bin/env python3
# gauge_gen.py — generates arc gauge PNGs for Conky (Wayland-compatible via Imlib2 ${image})
# Args: cpu_pct mem_pct gpu_pct cpu_temp_pct gpu_temp_pct disk_pct down_pct up_pct
# pct:display format — arc uses pct, center shows display verbatim (caller appends ° for temps)
import sys, math, os
import cairo

OUTDIR = "/tmp/conky_gauges"
SIZE   = 90
NAMES  = ["cpu", "ram", "gpu", "cputemp", "gputemp", "disk", "netdown", "netup", "gpufan"]
LABELS = ["CPU", "RAM", "GPU", "CPU °C", "GPU °C", "Disk", "Net ↓", "Net ↑", "Fan"]
CRIT   = 85   # pct threshold for red
WARN   = 70   # pct threshold for orange

def draw_gauge(pct, label, path, center_text=None):
    pct = max(0.0, min(100.0, float(pct)))
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, SIZE, SIZE)
    cr = cairo.Context(surface)
    cx, cy = SIZE / 2, SIZE / 2
    r  = SIZE / 2 - 10
    lw = 7

    # 270° sweep: 7-o'clock (135°) to 5-o'clock (405°), gap at bottom
    a_start = math.radians(135)
    a_end   = math.radians(405)
    a_val   = math.radians(135 + 270 * pct / 100)

    cr.set_line_cap(cairo.LINE_CAP_ROUND)
    cr.set_line_width(lw)

    # Background arc (dark gray)
    cr.set_source_rgba(0.267, 0.267, 0.267, 0.85)
    cr.arc(cx, cy, r, a_start, a_end)
    cr.stroke()

    # Value arc (color based on level)
    if pct > 0:
        if pct >= CRIT:
            cr.set_source_rgba(1.0,  0.0,  0.0,  1.0)   # red
        elif pct >= WARN:
            cr.set_source_rgba(1.0,  0.67, 0.0,  1.0)   # orange
        else:
            cr.set_source_rgba(0.467, 0.392, 0.847, 1.0) # purple #7764D8
        cr.arc(cx, cy, r, a_start, a_val)
        cr.stroke()

    # Center: value (percentage or raw with degree symbol for temp gauges)
    cr.set_source_rgba(1.0, 1.0, 1.0, 0.92)
    cr.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    cr.set_font_size(14)
    txt = center_text if center_text is not None else f"{int(pct)}%"
    ext = cr.text_extents(txt)
    cr.move_to(cx - ext.width / 2 - ext.x_bearing,
               cy - ext.height / 2 - ext.y_bearing)
    cr.show_text(txt)

    # Label below center (purple, small)
    cr.set_source_rgba(0.467, 0.392, 0.847, 0.9)
    cr.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    cr.set_font_size(10)
    ext = cr.text_extents(label)
    cr.move_to(cx - ext.width / 2 - ext.x_bearing, cy + 16)
    cr.show_text(label)

    surface.write_to_png(path)

os.makedirs(OUTDIR, exist_ok=True)
values = sys.argv[1:]
for i, name in enumerate(NAMES):
    raw = values[i] if i < len(values) else "0"
    try:
        center_text = None
        if ":" in str(raw):
            pct_str, display_val = str(raw).split(":", 1)
            center_text = display_val
            raw = pct_str
        draw_gauge(raw, LABELS[i], f"{OUTDIR}/{name}.png", center_text)
    except Exception as e:
        print(f"gauge_gen: error on {name}: {e}", file=sys.stderr)
