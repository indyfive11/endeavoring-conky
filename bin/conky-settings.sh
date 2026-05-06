#!/bin/bash
# conky-settings.sh — GUI for common Conky settings via kdialog
# Edits ~/.config/conky/JayBeeDe/default.conf and restarts Conky

CONF="$HOME/.config/conky/JayBeeDe/default.conf"
HELPER="$HOME/.config/conky/JayBeeDe/helper.lua"
GAUGE_GEN="$HOME/.config/conky/JayBeeDe/gauge_gen.py"
WEATHER_CONF="$HOME/.config/conky/weather/weather.conf"
WEATHER_CFG="$HOME/.config/conky/weather/config"
SYSTEM_CONF="$HOME/.config/conky/system/conky.conf"

# ── Coordinate system constants (empirically derived for this setup) ──────────
# Xwayland applies a 1.25× global HiDPI scale. Conky positions in logical coords.
# Physical position = logical × 1.25.
# For top_right: X11_left = (BASE_RIGHT - gap_x - LOGICAL_CONKY_W) × SCALE
#   Primary (Hisense) logical right = kscreen pos.x(768) + physical_w/scale(3072) = 3840.
# For top_left:  X11_left = PRIMARY_X + gap_x × SCALE
#   Primary left X11 = 960 (primary is at xrandr +960+0 due to monitors below-left).
# Conky logical width ≈ physical_width / SCALE ≈ 634 / 1.25 ≈ 507.
SCALE=1.25
BASE_RIGHT=3840        # primary monitor logical right edge (= X11 right / SCALE)
PRIMARY_X=960          # primary monitor X11 physical left edge (for top_left formula)
CONKY_W=691            # actual Conky window physical width (pixels)
LOGICAL_CONKY_W=553    # CONKY_W / SCALE
MARGIN_X=20            # physical pixels from horizontal monitor edge
MARGIN_Y=12            # physical pixels from vertical monitor edge

_wcfg_get() { grep -m1 "^$1=" "$WEATHER_CFG" 2>/dev/null | cut -d= -f2-; }
_wcfg_set() { sed -i "s|^$1=.*|$1=$2|" "$WEATHER_CFG"; }

if [[ ! -f "$CONF" ]]; then
    kdialog --error "Conky config not found at $CONF"
    exit 1
fi

# ── Parse monitor geometry from xrandr --listmonitors ────────────────────────
# Format: WW/mmxHH/mm+X+Y  OUTPUT  (e.g. 3840/1095x2160/616+960+0  DP-1)
# Returns: "W H X Y name" per connected monitor, space-separated, one per line.
_parse_monitors() {
    python3 - <<'PYEOF'
import re, subprocess, os, glob

lines = subprocess.check_output(
    ["xrandr", "--listmonitors"],
    env={**os.environ, "DISPLAY": ":1"},
    stderr=subprocess.DEVNULL
).decode().splitlines()[1:]  # skip header

for line in lines:
    m = re.search(r'(\d+)/\d+x(\d+)/\d+\+(\d+)\+(\d+)\s+(\S+)', line)
    if not m:
        continue
    w, h, x, y, output = m.group(1), m.group(2), m.group(3), m.group(4), m.group(5)
    # Read EDID monitor name from the monitor name descriptor (type 0xFC)
    name = output
    for edid_path in glob.glob(f"/sys/class/drm/card*/card*-{output}/edid"):
        try:
            edid = open(edid_path, "rb").read()
            for off in (54, 72, 90, 108):
                block = edid[off:off+18]
                if len(block) >= 18 and block[0] == 0 and block[1] == 0 and block[3] == 0xFC:
                    name = block[5:18].decode("ascii", errors="replace").strip().rstrip('\n')
                    break
        except Exception:
            pass
    print(w, h, x, y, output, name)
PYEOF
}

# ── Read current values ───────────────────────────────────────────────────────

cur_alpha=$(grep 'own_window_argb_value' "$CONF" | grep -oP '\d+' | head -1)
cur_align=$(grep 'alignment' "$CONF" | grep -oP "'[^']+'" | tr -d "'" | head -1)
cur_font_size=$(grep "font7.*GE Inspira:pixelsize=" "$CONF" | grep -oP "pixelsize=\K\d+" | head -1)
cur_interval=$(grep 'update_interval' "$CONF" | grep -oP '\d+' | head -1)
cur_gap_x=$(grep 'gap_x' "$CONF" | grep -oP '\d+' | head -1)
cur_gap_y=$(grep 'gap_y' "$CONF" | grep -oP '\d+' | head -1)
cur_gauge_size=$(grep -oP 'local GAUGE_SIZE\s*=\s*\K\d+' "$HELPER" | head -1)
cur_gauge_x=$(grep -oP 'local GAUGE_X_START\s*=\s*\K\d+' "$HELPER" | head -1)

# Reverse the coordinate formula to find which monitor Conky is on.
_current_monitor_label() {
    local phys_left phys_top
    if [[ "$cur_align" == *_left* ]]; then
        phys_left=$(python3 -c "print(round($PRIMARY_X + $cur_gap_x * $SCALE))")
    else
        phys_left=$(python3 -c "print(round(($BASE_RIGHT - $cur_gap_x - $LOGICAL_CONKY_W) * $SCALE))")
    fi
    phys_top=$(python3 -c "print(round($cur_gap_y * $SCALE))")
    while IFS=' ' read -r mw mh mx my output name; do
        local mr=$(( mx + mw ))
        local mb=$(( my + mh ))
        if (( phys_left >= mx && phys_left < mr && phys_top >= my && phys_top < mb )); then
            echo "$name"
            return
        fi
    done < <(_parse_monitors)
    echo "unknown"
}

cur_monitor=$(_current_monitor_label)

# Derive current margins (physical px from monitor edges) from live Conky position.
read cur_margin_x cur_margin_y < <(python3 - <<PYEOF
import re, subprocess, os
try:
    xdt = subprocess.check_output(
        ['xdotool', 'search', '--name', 'Conky', 'getwindowgeometry'],
        env={**os.environ, 'DISPLAY': ':1'}, stderr=subprocess.DEVNULL).decode()
    pm = re.search(r'Position: (\d+),(\d+)', xdt)
    gm = re.search(r'Geometry: (\d+)x(\d+)', xdt)
    wx = int(pm.group(1)) if pm else None
    wy = int(pm.group(2)) if pm else None
    ww = int(gm.group(1)) if gm else $CONKY_W
except Exception:
    wx = wy = None
    ww = $CONKY_W
if wx is None:
    print($MARGIN_X, $MARGIN_Y)
else:
    lines = subprocess.check_output(['xrandr', '--listmonitors'],
        env={**os.environ, 'DISPLAY': ':1'}, stderr=subprocess.DEVNULL).decode().splitlines()[1:]
    monitors = []
    for l in lines:
        m = re.search(r'(\d+)/\d+x(\d+)/\d+\+(\d+)\+(\d+)', l)
        if m: monitors.append(tuple(int(m.group(i)) for i in range(1,5)))
    mon = next((m for m in monitors if m[2]<=wx<m[2]+m[0] and m[3]<=wy<m[3]+m[1]), None)
    if not mon:
        print($MARGIN_X, $MARGIN_Y)
    else:
        mw,mh,mx,my = mon
        print(max(0,(mx+mw)-wx-ww), max(0,wy-my))
PYEOF
)
[[ -z "$cur_margin_x" ]] && cur_margin_x=$MARGIN_X
[[ -z "$cur_margin_y" ]] && cur_margin_y=$MARGIN_Y

# ── Ask what to change ────────────────────────────────────────────────────────

choice=$(kdialog --title "Conky Settings" --menu "What would you like to change?" \
    "1" "Transparency  (current: $cur_alpha / 255)" \
    "2" "Corner        (monitor: $cur_monitor)" \
    "3" "Section font  (current: ${cur_font_size}px, affects data rows only)" \
    "4" "Update interval (current: ${cur_interval}s)" \
    "5" "Edge gap      (current: right=${cur_margin_x}px  top=${cur_margin_y}px)" \
    "6" "Monitor       (current: $cur_monitor)" \
    "7" "Gauge size    (current: ${cur_gauge_size}px)" \
    "8" "Gauge position" \
    "11" "Weather settings" \
    "14" "System panel settings" \
    "12" "Restart Conky (no changes)" \
    "13" "Kill Conky")

[[ -z "$choice" ]] && exit 0

case "$choice" in
    1)  # Transparency
        val=$(kdialog --title "Transparency" \
            --inputbox "Enter transparency (0 = fully transparent, 255 = opaque):" "$cur_alpha")
        [[ -z "$val" ]] && exit 0
        if ! [[ "$val" =~ ^[0-9]+$ ]] || [[ "$val" -gt 255 ]]; then
            kdialog --error "Must be a number 0–255"
            exit 1
        fi
        sed -i "s/own_window_argb_value = [0-9]*/own_window_argb_value = $val/" "$CONF"
        ;;

    2)  # Corner picker — moves Conky to selected position on current monitor
        corner=$(kdialog --title "Screen Position" \
            --menu "Move Conky to which position on the current monitor?" \
            "top_right"     "Top-right corner" \
            "top_left"      "Top-left corner" \
            "top_center"    "Top center" \
            "bottom_right"  "Bottom-right corner" \
            "bottom_left"   "Bottom-left corner" \
            "bottom_center" "Bottom center")
        [[ -z "$corner" ]] && exit 0

        _xdt_geom=$(DISPLAY=:1 xdotool search --name 'Conky' getwindowgeometry 2>/dev/null)
        _cur_cw=$CONKY_W; _cur_ch=800
        if [[ "$_xdt_geom" =~ Geometry:\ ([0-9]+)x([0-9]+) ]]; then
            _cur_cw="${BASH_REMATCH[1]}"; _cur_ch="${BASH_REMATCH[2]}"
        fi
        _cur_lw=$(python3 -c "print(round($_cur_cw / $SCALE))")

        read new_align new_gx new_gy < <(python3 - <<PYEOF
import re, subprocess, os
try:
    xdt = subprocess.check_output(
        ['xdotool', 'search', '--name', 'Conky', 'getwindowgeometry'],
        env={**os.environ, 'DISPLAY': ':1'}, stderr=subprocess.DEVNULL).decode()
    pm = re.search(r'Position: (\d+),(\d+)', xdt)
    wx = int(pm.group(1)) if pm else None
    wy = int(pm.group(2)) if pm else None
except Exception:
    wx = wy = None
if wx is None:
    raise SystemExit(1)
lines = subprocess.check_output(['xrandr', '--listmonitors'],
    env={**os.environ, 'DISPLAY': ':1'}, stderr=subprocess.DEVNULL).decode().splitlines()[1:]
monitors = []
for l in lines:
    m = re.search(r'(\d+)/\d+x(\d+)/\d+\+(\d+)\+(\d+)', l)
    if m: monitors.append(tuple(int(m.group(i)) for i in range(1,5)))
mon = next((m for m in monitors if m[2]<=wx<m[2]+m[0] and m[3]<=wy<m[3]+m[1]), None)
if not mon:
    raise SystemExit(1)
mw, mh, mx, my = mon
SCALE=$SCALE; BASE_RIGHT=$BASE_RIGHT; MARGIN_X=$MARGIN_X; MARGIN_Y=$MARGIN_Y
CONKY_W=$_cur_cw; CONKY_H=$_cur_ch; PRIMARY_X=$PRIMARY_X
lw = round(CONKY_W / SCALE)
corner = '$corner'
if corner in ('bottom_right', 'bottom_left', 'bottom_center'):
    gap_y = round((my + mh - MARGIN_Y - CONKY_H) / SCALE)
else:
    gap_y = round((my + MARGIN_Y) / SCALE)
if corner in ('top_center', 'bottom_center'):
    panel_left = mx + (mw - CONKY_W) // 2
    print('top_left', round((panel_left - PRIMARY_X + 6) / SCALE), gap_y)
elif corner in ('top_right', 'bottom_right'):
    target_left = (mx + mw) - MARGIN_X - CONKY_W
    gx_tr = round(BASE_RIGHT - lw - target_left / SCALE)
    if gx_tr >= 0:
        print('top_right', gx_tr, gap_y)
    else:
        print('top_left', round((target_left - PRIMARY_X + 6) / SCALE), gap_y)
else:
    target_left = mx + MARGIN_X
    print('top_left', round((target_left - PRIMARY_X + 6) / SCALE), gap_y)
PYEOF
        )
        if [[ -z "$new_align" ]]; then
            kdialog --error "Could not compute position — is Conky running?"
            exit 1
        fi
        sed -i "s/alignment = '[^']*'/alignment = '$new_align'/" "$CONF"
        sed -i "s/gap_x = [0-9]*/gap_x = $new_gx/" "$CONF"
        sed -i "s/gap_y = [0-9]*/gap_y = $new_gy/" "$CONF"
        ;;

    3)  # Font size
        val=$(kdialog --title "Section Font Size" \
            --inputbox "Enter font size in pixels for data rows (e.g. 12, 14, 18, 20):" "$cur_font_size")
        [[ -z "$val" ]] && exit 0
        if ! [[ "$val" =~ ^[0-9]+$ ]]; then
            kdialog --error "Must be a whole number"
            exit 1
        fi
        sed -i "/font[6-9]/s/pixelsize=[0-9]*/pixelsize=$val/g" "$CONF"
        ;;

    4)  # Update interval
        val=$(kdialog --title "Update Interval" \
            --inputbox "Seconds between refreshes (e.g. 1, 2, 5):" "$cur_interval")
        [[ -z "$val" ]] && exit 0
        if ! [[ "$val" =~ ^[0-9]+$ ]]; then
            kdialog --error "Must be a whole number"
            exit 1
        fi
        sed -i "s/update_interval = [0-9]*/update_interval = $val/" "$CONF"
        ;;

    5)  # Edge gap — entered as physical pixels from monitor's right/top edges
        gx=$(kdialog --title "Right margin" \
            --inputbox "Physical pixels from the right edge of the current monitor:" "$cur_margin_x")
        [[ -z "$gx" ]] && exit 0
        gy=$(kdialog --title "Top margin" \
            --inputbox "Physical pixels from the top edge of the current monitor:" "$cur_margin_y")
        [[ -z "$gy" ]] && exit 0
        if ! [[ "$gx" =~ ^[0-9]+$ ]] || ! [[ "$gy" =~ ^[0-9]+$ ]]; then
            kdialog --error "Must be non-negative integers"
            exit 1
        fi
        # Convert margins to gap values using live position to derive empirical offsets.
        # For top_left, X11 = gap_x * SCALE + C (C ≠ 0); for top_right, use the
        # standard formula. C is derived from the running window's actual position.
        read new_gx new_gy < <(python3 - <<PYEOF
import re, subprocess, os
try:
    xdt = subprocess.check_output(
        ['xdotool', 'search', '--name', 'Conky', 'getwindowgeometry'],
        env={**os.environ, 'DISPLAY': ':1'}, stderr=subprocess.DEVNULL).decode()
    pm = re.search(r'Position: (\d+),(\d+)', xdt)
    gm = re.search(r'Geometry: (\d+)x(\d+)', xdt)
    wx = int(pm.group(1)) if pm else None
    wy = int(pm.group(2)) if pm else None
    ww = int(gm.group(1)) if gm else $CONKY_W
except Exception:
    wx = wy = ww = None
if wx is None:
    raise SystemExit(1)
SCALE=$SCALE; CW=ww; BR=$BASE_RIGHT; LW=$LOGICAL_CONKY_W
lines = subprocess.check_output(['xrandr', '--listmonitors'],
    env={**os.environ, 'DISPLAY': ':1'}, stderr=subprocess.DEVNULL).decode().splitlines()[1:]
monitors = []
for l in lines:
    m = re.search(r'(\d+)/\d+x(\d+)/\d+\+(\d+)\+(\d+)', l)
    if m: monitors.append(tuple(int(m.group(i)) for i in range(1,5)))
mon = next((m for m in monitors if m[2]<=wx<m[2]+m[0] and m[3]<=wy<m[3]+m[1]), None)
if not mon:
    raise SystemExit(1)
mw,mh,mx,my = mon
target_x = (mx+mw) - CW - $gx
target_y = my + $gy
new_gy = round(target_y / SCALE)
if 'left' in '$cur_align':
    new_gx = round((target_x - $PRIMARY_X + 6) / SCALE)
else:
    new_gx = round(BR - LW - target_x / SCALE)
print(new_gx, new_gy)
PYEOF
        )
        if [[ -z "$new_gx" ]]; then
            kdialog --error "Could not compute gap values — is Conky running?"
            exit 1
        fi
        sed -i "s/gap_x = [0-9]*/gap_x = $new_gx/" "$CONF"
        sed -i "s/gap_y = [0-9]*/gap_y = $new_gy/" "$CONF"
        ;;

    6)  # Monitor picker
        menu_args=()
        while IFS=' ' read -r mw mh mx my output name; do
            label="${name} (${mw}×${mh} at +${mx}+${my})"
            menu_args+=("$output" "$label")
        done < <(_parse_monitors)

        if [[ ${#menu_args[@]} -eq 0 ]]; then
            kdialog --error "No monitors detected."
            exit 1
        fi

        chosen_output=$(kdialog --title "Choose Monitor" \
            --menu "Select the monitor to display Conky on:" "${menu_args[@]}")
        [[ -z "$chosen_output" ]] && exit 0

        # Get geometry for chosen monitor and compute alignment + gap values.
        # Prefer top_right (anchored to primary right edge); fall back to top_left
        # for monitors beyond the primary's right edge (X11 x > BASE_RIGHT*SCALE).
        _xdt_geom=$(DISPLAY=:1 xdotool search --name 'Conky' getwindowgeometry 2>/dev/null)
        [[ "$_xdt_geom" =~ Geometry:\ ([0-9]+) ]] && _cur_cw="${BASH_REMATCH[1]}" || _cur_cw=$CONKY_W
        _cur_lw=$(python3 -c "print(round($_cur_cw / $SCALE))")
        read new_align new_gx new_gy < <(
            _parse_monitors | awk -v out="$chosen_output" '$5==out {print $1,$2,$3,$4}' \
            | python3 -c "
import sys
line = sys.stdin.read().split()
mw, mh, mx, my = int(line[0]), int(line[1]), int(line[2]), int(line[3])
SCALE=$SCALE; BASE_RIGHT=$BASE_RIGHT; LOGICAL_CONKY_W=$_cur_lw
MARGIN_X=$MARGIN_X; MARGIN_Y=$MARGIN_Y; CONKY_W=$_cur_cw; PRIMARY_X=$PRIMARY_X
right = mx + mw
target_left = right - MARGIN_X - CONKY_W
gap_x_tr = round(BASE_RIGHT - LOGICAL_CONKY_W - target_left / SCALE)
gap_y = round((my + MARGIN_Y) / SCALE)
if gap_x_tr >= 0:
    print('top_right', gap_x_tr, gap_y)
else:
    gap_x_tl = round((target_left - PRIMARY_X + 6) / SCALE)
    print('top_left', gap_x_tl, gap_y)
")

        if [[ -z "$new_align" ]]; then
            kdialog --error "Could not compute position for that monitor."
            exit 1
        fi
        sed -i "s/alignment = '[^']*'/alignment = '$new_align'/" "$CONF"
        sed -i "s/gap_x = [0-9]*/gap_x = $new_gx/" "$CONF"
        sed -i "s/gap_y = [0-9]*/gap_y = $new_gy/" "$CONF"
        ;;

    7)  # Gauge size
        val=$(kdialog --title "Gauge Size" \
            --inputbox "PNG size in pixels (40-160):" "$cur_gauge_size")
        [[ -z "$val" ]] && exit 0
        if ! [[ "$val" =~ ^[0-9]+$ ]] || (( val < 40 || val > 160 )); then
            kdialog --error "Must be a whole number between 40 and 160"
            exit 1
        fi
        python3 - <<PYEOF
import re
for path, pattern, repl in [
    ("$HELPER",    r'(local GAUGE_SIZE\s*=\s*)\d+', r'\g<1>$val'),
    ("$GAUGE_GEN", r'^(SIZE\s*=\s*)\d+',            r'\g<1>$val'),
]:
    content = open(path).read()
    content = re.sub(pattern, repl, content, flags=re.MULTILINE)
    open(path, 'w').write(content)
PYEOF
        python3 "$GAUGE_GEN" 0 0 0 0 0 0 0 0
        ;;

    8)  # Gauge position
        d_hw=$(grep -oP 'Hardware\s*=\s*\K[-\d]+' "$HELPER" | head -1)
        d_gpu=$(grep -oP 'GPU\s*=\s*\K[-\d]+' "$HELPER" | head -1)
        d_st=$(grep -oP 'Storage\s*=\s*\K[-\d]+' "$HELPER" | head -1)
        d_nip=$(grep -oP '"Network IPs"\]\s*=\s*\K[-\d]+' "$HELPER" | head -1)
        d_nrt=$(grep -oP '"Network Routes"\]\s*=\s*\K[-\d]+' "$HELPER" | head -1)
        cur_start=$(grep -oP 'conky_init_gauge_y\s+\K\d+' "$CONF" | head -1)

        section=$(kdialog --title "Gauge Position" --menu "Choose section to adjust:" \
            "all" "Shift ALL gauges up/down  (start Y: $cur_start)" \
            "hw"  "Hardware                  (drift: $d_hw)" \
            "gpu" "GPU                       (drift: $d_gpu)" \
            "st"  "Storage                   (drift: $d_st)" \
            "nip" "Network IPs               (drift: $d_nip)" \
            "nrt" "Network Routes            (drift: $d_nrt)")
        [[ -z "$section" ]] && exit 0

        if [[ "$section" == "all" ]]; then
            val=$(kdialog --title "Shift All Gauges" \
                --inputbox "Initial gauge Y (positive = down from top of panel):" "$cur_start")
            [[ -z "$val" ]] && exit 0
            [[ ! "$val" =~ ^[0-9]+$ ]] && { kdialog --error "Must be a positive integer"; exit 1; }
            sed -i "s/conky_init_gauge_y [0-9]*/conky_init_gauge_y $val/" "$CONF"
        else
            case "$section" in
                hw)  label="Hardware";       cur="$d_hw";  pkey="hw"  ;;
                gpu) label="GPU";            cur="$d_gpu"; pkey="gpu" ;;
                st)  label="Storage";        cur="$d_st";  pkey="st"  ;;
                nip) label="Network IPs";    cur="$d_nip"; pkey="nip" ;;
                nrt) label="Network Routes"; cur="$d_nrt"; pkey="nrt" ;;
                *)   kdialog --error "Unexpected section value: [$section]"; exit 1 ;;
            esac
            val=$(kdialog --title "Drift for $label" \
                --inputbox "Pixel offset (positive = down, negative = up):" -- "$cur")
            [[ -z "$val" ]] && exit 0
            [[ ! "$val" =~ ^-?[0-9]+$ ]] && { kdialog --error "Must be an integer"; exit 1; }
            python3 - <<PYEOF
import re
content = open("$HELPER").read()
patterns = {
    'hw':  r'(Hardware\s*=\s*)[-\d]+',
    'gpu': r'(GPU\s*=\s*)[-\d]+',
    'st':  r'(Storage\s*=\s*)[-\d]+',
    'nip': r'(\["Network IPs"\]\s*=\s*)[-\d]+',
    'nrt': r'(\["Network Routes"\]\s*=\s*)[-\d]+',
}
content = re.sub(patterns['$pkey'], r'\g<1>$val', content)
open("$HELPER", 'w').write(content)
PYEOF
        fi
        ;;

    11)  # Weather settings
        _wloc=$(_wcfg_get LOCATION_MODE); _wcity=$(_wcfg_get CITY)
        _wunits=$(_wcfg_get UNITS_MODE); _wtfmt=$(_wcfg_get TIME_FORMAT)
        _wics=$(_wcfg_get ICON_SIZE_CURRENT); _wifs=$(_wcfg_get ICON_SIZE_FORECAST)
        _walpha=$(grep 'own_window_argb_value' "$WEATHER_CONF" | grep -oP '\d+' | head -1)
        _walign=$(grep 'alignment' "$WEATHER_CONF" | grep -oP "'[^']+'" | tr -d "'" | head -1)
        _loc_label="${_wcity:-auto}"
        [[ "$_wloc" == "auto" ]] && _loc_label="auto (${_wcity:-detecting...})"

        wchoice=$(kdialog --title "Weather Settings" --menu "Weather panel settings:" \
            "1" "Location      (current: ${_loc_label})" \
            "2" "Units         (current: ${_wunits:-auto})" \
            "3" "Time format   (current: ${_wtfmt:-12h})" \
            "4" "Position      (current: ${_walign:-top_left})" \
            "5" "Monitor       (move to different monitor)" \
            "6" "Icon size     (current: ${_wics:-96}px current / ${_wifs:-64}px forecast)" \
            "10" "Transparency  (current: ${_walpha:-180} / 255)" \
            "9" "Edge gap      (margin from panel to monitor edge)" \
            "7" "Restart weather panel" \
            "8" "Kill weather panel")
        [[ -z "$wchoice" ]] && exit 0

        case "$wchoice" in
            1)  # Location
                lmode=$(kdialog --title "Location" --menu "Location source:" \
                    "auto"   "Auto-detect from IP" \
                    "manual" "Enter city name")
                [[ -z "$lmode" ]] && exit 0
                if [[ "$lmode" == "auto" ]]; then
                    _wcfg_set LOCATION_MODE auto
                    _wcfg_set LATITUDE ""
                    _wcfg_set LONGITUDE ""
                    _wcfg_set CITY ""
                else
                    cityq=$(kdialog --title "City Search" --inputbox "Enter city name:" "")
                    [[ -z "$cityq" ]] && exit 0
                    export WEATHER_CITY_QUERY="$cityq"
                    read -r picked_name picked_lat picked_lon < <(python3 - <<'PYEOF'
import urllib.request, urllib.parse, json, subprocess, sys, os
cityq = os.environ.get('WEATHER_CITY_QUERY', '')
try:
    url = ("https://geocoding-api.open-meteo.com/v1/search?name="
           + urllib.parse.quote(cityq) + "&count=10&language=en&format=json")
    with urllib.request.urlopen(url, timeout=10) as r:
        data = json.loads(r.read())
    results = data.get("results", [])
    if not results:
        sys.exit(0)
    args = ["kdialog", "--title", "Select City", "--menu", "Choose your city:"]
    for i, entry in enumerate(results[:10]):
        label = f"{entry['name']}, {entry.get('admin1','')}, {entry.get('country','')}"
        args += [str(i), label]
    idx = subprocess.run(args, capture_output=True, text=True).stdout.strip()
    if not idx:
        sys.exit(0)
    chosen = results[int(idx)]
    print(chosen['name'], chosen['latitude'], chosen['longitude'])
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
                    )
                    [[ -z "$picked_name" ]] && exit 0
                    _wcfg_set LOCATION_MODE manual
                    _wcfg_set CITY "$picked_name"
                    _wcfg_set LATITUDE "$picked_lat"
                    _wcfg_set LONGITUDE "$picked_lon"
                fi
                ;;
            2)  # Units
                umode=$(kdialog --title "Units" --menu "Temperature and wind units:" \
                    "auto"     "Auto-detect from location" \
                    "metric"   "Metric (°C, km/h)" \
                    "imperial" "Imperial (°F, mph)")
                [[ -z "$umode" ]] && exit 0
                _wcfg_set UNITS_MODE "$umode"
                if [[ "$umode" == "metric" ]]; then
                    _wcfg_set TEMPERATURE_UNIT celsius
                    _wcfg_set WIND_UNIT kmh
                elif [[ "$umode" == "imperial" ]]; then
                    _wcfg_set TEMPERATURE_UNIT fahrenheit
                    _wcfg_set WIND_UNIT mph
                else
                    _wcfg_set TEMPERATURE_UNIT ""
                    _wcfg_set WIND_UNIT ""
                fi
                ;;
            3)  # Time format
                tfmt=$(kdialog --title "Time Format" --menu "Clock display format:" \
                    "12h" "12-hour (AM/PM)" \
                    "24h" "24-hour")
                [[ -z "$tfmt" ]] && exit 0
                _wcfg_set TIME_FORMAT "$tfmt"
                ;;
            4)  # Corner — weather window geometry via xdotool
                corner=$(kdialog --title "Screen Position" \
                    --menu "Move weather panel to which position?" \
                    "top_right"     "Top-right corner" \
                    "top_left"      "Top-left corner" \
                    "top_center"    "Top center" \
                    "bottom_right"  "Bottom-right corner" \
                    "bottom_left"   "Bottom-left corner" \
                    "bottom_center" "Bottom center")
                [[ -z "$corner" ]] && exit 0
                export WEATHER_CORNER="$corner"
                read new_align new_gx new_gy < <(python3 - <<PYEOF
import re, subprocess, os
corner = os.environ.get('WEATHER_CORNER', 'top_left')
try:
    xdt = subprocess.check_output(
        ['xdotool', 'search', '--name', 'Conky Weather', 'getwindowgeometry'],
        env={**os.environ, 'DISPLAY': ':1'}, stderr=subprocess.DEVNULL).decode()
    pm = re.search(r'Position: (\d+),(\d+)', xdt)
    gm = re.search(r'Geometry: (\d+)x(\d+)', xdt)
    wx = int(pm.group(1)) if pm else None
    wy = int(pm.group(2)) if pm else None
    cw = int(gm.group(1)) if gm else $CONKY_W
    ch = int(gm.group(2)) if gm else 400
except Exception:
    wx = wy = None; cw = $CONKY_W; ch = 400
if wx is None:
    try:
        xdt2 = subprocess.check_output(
            ['xdotool', 'search', '--name', 'Conky', 'getwindowgeometry'],
            env={**os.environ, 'DISPLAY': ':1'}, stderr=subprocess.DEVNULL).decode()
        pm = re.search(r'Position: (\d+),(\d+)', xdt2)
        wx = int(pm.group(1)) if pm else 0
        wy = int(pm.group(2)) if pm else 0
    except Exception:
        wx, wy = 0, 0
lines = subprocess.check_output(['xrandr', '--listmonitors'],
    env={**os.environ, 'DISPLAY': ':1'}, stderr=subprocess.DEVNULL).decode().splitlines()[1:]
monitors = []
for l in lines:
    m = re.search(r'(\d+)/\d+x(\d+)/\d+\+(\d+)\+(\d+)', l)
    if m: monitors.append(tuple(int(m.group(i)) for i in range(1,5)))
mon = next((m for m in monitors if m[2]<=wx<m[2]+m[0] and m[3]<=wy<m[3]+m[1]), None)
if not mon: mon = monitors[0] if monitors else (1920,1080,0,0)
mw, mh, mx, my = mon
SCALE=$SCALE; BASE_RIGHT=$BASE_RIGHT; MARGIN_X=$MARGIN_X; MARGIN_Y=$MARGIN_Y; PRIMARY_X=$PRIMARY_X
lw = round(cw / SCALE)
if corner in ('bottom_right', 'bottom_left', 'bottom_center'):
    gap_y = round((my + mh - MARGIN_Y - ch) / SCALE)
else:
    gap_y = round((my + MARGIN_Y) / SCALE)
if corner in ('top_center', 'bottom_center'):
    panel_left = mx + (mw - cw) // 2
    print('top_left', round((panel_left - PRIMARY_X + 6) / SCALE), gap_y)
elif corner in ('top_right', 'bottom_right'):
    tl = (mx + mw) - MARGIN_X - cw
    gx = round(BASE_RIGHT - lw - tl / SCALE)
    print('top_right' if gx >= 0 else 'top_left',
          gx if gx >= 0 else round((tl - PRIMARY_X + 6) / SCALE), gap_y)
else:
    print('top_left', round((mx + MARGIN_X - PRIMARY_X + 6) / SCALE), gap_y)
PYEOF
                )
                if [[ -z "$new_align" ]]; then
                    kdialog --error "Could not compute position — is the weather panel running?"
                    exit 1
                fi
                sed -i "s/alignment = '[^']*'/alignment = '$new_align'/" "$WEATHER_CONF"
                sed -i "s/gap_x = [0-9]*/gap_x = $new_gx/" "$WEATHER_CONF"
                sed -i "s/gap_y = [0-9]*/gap_y = $new_gy/" "$WEATHER_CONF"
                systemctl --user restart conky-weather.service
                exit 0
                ;;
            5)  # Monitor
                menu_args=()
                while IFS=' ' read -r mw mh mx my output name; do
                    label="${name} (${mw}×${mh} at +${mx}+${my})"
                    menu_args+=("$output" "$label")
                done < <(_parse_monitors)
                [[ ${#menu_args[@]} -eq 0 ]] && { kdialog --error "No monitors detected."; exit 1; }
                chosen_output=$(kdialog --title "Choose Monitor" \
                    --menu "Select monitor for weather panel:" "${menu_args[@]}")
                [[ -z "$chosen_output" ]] && exit 0
                read new_align new_gx new_gy < <(
                    _parse_monitors | awk -v out="$chosen_output" '$5==out {print $1,$2,$3,$4}' \
                    | python3 -c "
import sys
line = sys.stdin.read().split()
mw, mh, mx, my = int(line[0]), int(line[1]), int(line[2]), int(line[3])
import subprocess, os, re
try:
    xdt = subprocess.check_output(['xdotool','search','--name','Conky Weather','getwindowgeometry'],
        env={**os.environ,'DISPLAY':':1'}, stderr=subprocess.DEVNULL).decode()
    gm = re.search(r'Geometry: (\d+)x', xdt)
    cw = int(gm.group(1)) if gm else $CONKY_W
except Exception:
    cw = $CONKY_W
SCALE=$SCALE; BASE_RIGHT=$BASE_RIGHT; MARGIN_X=$MARGIN_X; MARGIN_Y=$MARGIN_Y; PRIMARY_X=$PRIMARY_X
lw = round(cw / SCALE)
tl = (mx + mw) - MARGIN_X - cw
gx = round(BASE_RIGHT - lw - tl / SCALE)
gy = round((my + MARGIN_Y) / SCALE)
if gx >= 0:
    print('top_right', gx, gy)
else:
    print('top_left', round((tl - PRIMARY_X + 6) / SCALE), gy)
")
                [[ -z "$new_align" ]] && { kdialog --error "Could not compute position for that monitor."; exit 1; }
                sed -i "s/alignment = '[^']*'/alignment = '$new_align'/" "$WEATHER_CONF"
                sed -i "s/gap_x = [0-9]*/gap_x = $new_gx/" "$WEATHER_CONF"
                sed -i "s/gap_y = [0-9]*/gap_y = $new_gy/" "$WEATHER_CONF"
                systemctl --user restart conky-weather.service
                exit 0
                ;;
            6)  # Icon size
                val=$(kdialog --title "Icon Size" \
                    --inputbox "Current-conditions icon size in px (32-160). Forecast will be ⅔ of this:" "${_wics:-96}")
                [[ -z "$val" ]] && exit 0
                if ! [[ "$val" =~ ^[0-9]+$ ]] || (( val < 32 || val > 160 )); then
                    kdialog --error "Must be a whole number between 32 and 160"
                    exit 1
                fi
                _fcast=$(python3 -c "print(round($val * 2/3 / 8) * 8)")
                _wcfg_set ICON_SIZE_CURRENT "$val"
                _wcfg_set ICON_SIZE_FORECAST "$_fcast"
                ;;
            7)  # Restart weather panel
                systemctl --user restart conky-weather.service
                sleep 2
                if systemctl --user is-active --quiet conky-weather.service; then
                    kdialog --passivepopup "Weather panel restarted." 3
                else
                    kdialog --error "Weather panel failed to restart.\n\n$(systemctl --user status conky-weather.service --no-pager 2>&1 | tail -10)"
                fi
                exit 0
                ;;
            8)  # Kill weather panel
                systemctl --user stop conky-weather.service
                kdialog --msgbox "Weather panel stopped."
                exit 0
                ;;
            10) # Transparency
                val=$(kdialog --title "Transparency" \
                    --inputbox "Enter transparency (0 = fully transparent, 255 = opaque):" "${_walpha:-180}")
                [[ -z "$val" ]] && exit 0
                if ! [[ "$val" =~ ^[0-9]+$ ]] || [[ "$val" -gt 255 ]]; then
                    kdialog --error "Must be a number 0–255"
                    exit 1
                fi
                sed -i "s/own_window_argb_value *= *[0-9]*/own_window_argb_value  = $val/" "$WEATHER_CONF"
                systemctl --user restart conky-weather.service
                exit 0
                ;;
            9)  # Edge gap — margin from panel edges to monitor edges
                # Detect current position: which horizontal side (left/right/center) and vertical side (top/bottom)
                read _wpanel_h _wpanel_v _wcur_mx _wcur_my < <(python3 - <<PYEOF
import re, subprocess, os
try:
    xdt = subprocess.check_output(
        ['xdotool', 'search', '--name', 'Conky Weather', 'getwindowgeometry'],
        env={**os.environ, 'DISPLAY': ':1'}, stderr=subprocess.DEVNULL).decode()
    pm = re.search(r'Position: (\d+),(\d+)', xdt)
    gm = re.search(r'Geometry: (\d+)x(\d+)', xdt)
    wx = int(pm.group(1)) if pm else None
    wy = int(pm.group(2)) if pm else None
    cw = int(gm.group(1)) if gm else $CONKY_W
    ch = int(gm.group(2)) if gm else 400
except Exception:
    wx = wy = None; cw = $CONKY_W; ch = 400
if wx is None:
    print('right top $MARGIN_X $MARGIN_Y')
else:
    lines = subprocess.check_output(['xrandr', '--listmonitors'],
        env={**os.environ, 'DISPLAY': ':1'}, stderr=subprocess.DEVNULL).decode().splitlines()[1:]
    monitors = []
    for l in lines:
        m = re.search(r'(\d+)/\d+x(\d+)/\d+\+(\d+)\+(\d+)', l)
        if m: monitors.append(tuple(int(m.group(i)) for i in range(1,5)))
    mon = next((m for m in monitors if m[2]<=wx<m[2]+m[0] and m[3]<=wy<m[3]+m[1]), None)
    if not mon: mon = monitors[0] if monitors else (1920,1080,0,0)
    mw, mh, mx, my = mon
    dist_left   = wx - mx
    dist_right  = (mx + mw) - (wx + cw)
    dist_top    = wy - my
    dist_bottom = (my + mh) - (wy + ch)
    if abs(dist_left - dist_right) <= max(10, mw * 0.05):
        h_mode = 'center'; h_margin = 0
    elif dist_left <= dist_right:
        h_mode = 'left';   h_margin = dist_left
    else:
        h_mode = 'right';  h_margin = dist_right
    v_mode   = 'top' if dist_top <= dist_bottom else 'bottom'
    v_margin = dist_top if v_mode == 'top' else dist_bottom
    print(h_mode, v_mode, max(0, h_margin), max(0, v_margin))
PYEOF
                )
                [[ -z "$_wpanel_h" ]] && { kdialog --error "Could not read weather panel position — is it running?"; exit 1; }

                if [[ "$_wpanel_h" != "center" ]]; then
                    _wmx=$(kdialog --title "Horizontal Margin" \
                        --inputbox "Pixels from the ${_wpanel_h} edge of the monitor:" "$_wcur_mx")
                    [[ -z "$_wmx" ]] && exit 0
                    if ! [[ "$_wmx" =~ ^[0-9]+$ ]]; then
                        kdialog --error "Must be a non-negative integer"; exit 1
                    fi
                else
                    _wmx=0
                fi
                _wmy=$(kdialog --title "Vertical Margin" \
                    --inputbox "Pixels from the ${_wpanel_v} edge of the monitor:" "$_wcur_my")
                [[ -z "$_wmy" ]] && exit 0
                if ! [[ "$_wmy" =~ ^[0-9]+$ ]]; then
                    kdialog --error "Must be a non-negative integer"; exit 1
                fi

                export _WPANEL_H="$_wpanel_h" _WPANEL_V="$_wpanel_v" _WMARG_X="$_wmx" _WMARG_Y="$_wmy"
                read new_align new_gx new_gy < <(python3 - <<PYEOF
import re, subprocess, os
h_mode   = os.environ['_WPANEL_H']
v_mode   = os.environ['_WPANEL_V']
margin_x = int(os.environ['_WMARG_X'])
margin_y = int(os.environ['_WMARG_Y'])
try:
    xdt = subprocess.check_output(
        ['xdotool', 'search', '--name', 'Conky Weather', 'getwindowgeometry'],
        env={**os.environ, 'DISPLAY': ':1'}, stderr=subprocess.DEVNULL).decode()
    pm = re.search(r'Position: (\d+),(\d+)', xdt)
    gm = re.search(r'Geometry: (\d+)x(\d+)', xdt)
    wx = int(pm.group(1)) if pm else None
    wy = int(pm.group(2)) if pm else None
    cw = int(gm.group(1)) if gm else $CONKY_W
    ch = int(gm.group(2)) if gm else 400
except Exception:
    wx = wy = None; cw = $CONKY_W; ch = 400
lines = subprocess.check_output(['xrandr', '--listmonitors'],
    env={**os.environ, 'DISPLAY': ':1'}, stderr=subprocess.DEVNULL).decode().splitlines()[1:]
monitors = []
for l in lines:
    m = re.search(r'(\d+)/\d+x(\d+)/\d+\+(\d+)\+(\d+)', l)
    if m: monitors.append(tuple(int(m.group(i)) for i in range(1,5)))
if wx is not None:
    mon = next((m for m in monitors if m[2]<=wx<m[2]+m[0] and m[3]<=wy<m[3]+m[1]), None)
else:
    mon = None
if not mon: mon = monitors[0] if monitors else (1920,1080,0,0)
mw, mh, mx, my = mon
SCALE=$SCALE; BASE_RIGHT=$BASE_RIGHT; PRIMARY_X=$PRIMARY_X
lw = round(cw / SCALE)
if h_mode == 'center':
    panel_left = mx + (mw - cw) // 2
    gx = round((panel_left - PRIMARY_X + 6) / SCALE)
    align = 'top_left'
elif h_mode == 'left':
    panel_left = mx + margin_x
    gx = round((panel_left - PRIMARY_X + 6) / SCALE)
    align = 'top_left'
else:
    panel_left = (mx + mw) - margin_x - cw
    gx_tr = round(BASE_RIGHT - lw - panel_left / SCALE)
    if gx_tr >= 0:
        gx = gx_tr; align = 'top_right'
    else:
        gx = round((panel_left - PRIMARY_X + 6) / SCALE); align = 'top_left'
if v_mode == 'top':
    gy = round((my + margin_y) / SCALE)
else:
    gy = round((my + mh - margin_y - ch) / SCALE)
print(align, gx, gy)
PYEOF
                )
                [[ -z "$new_align" ]] && { kdialog --error "Could not compute gap values."; exit 1; }
                sed -i "s/alignment = '[^']*'/alignment = '$new_align'/" "$WEATHER_CONF"
                sed -i "s/gap_x = [0-9]*/gap_x = $new_gx/" "$WEATHER_CONF"
                sed -i "s/gap_y = [0-9]*/gap_y = $new_gy/" "$WEATHER_CONF"
                systemctl --user restart conky-weather.service
                exit 0
                ;;
        esac

        # Force re-fetch and restart weather panel
        rm -f /tmp/conky_weather/data.json
        systemctl --user restart conky-weather.service
        sleep 2
        if systemctl --user is-active --quiet conky-weather.service; then
            kdialog --passivepopup "Weather panel updated." 3
        else
            kdialog --error "Weather panel failed to restart.\n\n$(systemctl --user status conky-weather.service --no-pager 2>&1 | tail -10)"
        fi
        exit 0
        ;;

    14)  # System panel settings
        _salpha=$(grep 'own_window_argb_value' "$SYSTEM_CONF" | grep -oP '\d+' | head -1)
        _salign=$(grep 'alignment' "$SYSTEM_CONF" | grep -oP "'[^']+'" | tr -d "'" | head -1)

        schoice=$(kdialog --title "System Panel Settings" --menu "System panel settings:" \
            "1" "Position      (current: ${_salign:-top_right})" \
            "2" "Monitor       (move to different monitor)" \
            "3" "Transparency  (current: ${_salpha:-180} / 255)" \
            "4" "Edge gap      (margin from panel to monitor edge)" \
            "5" "Restart system panel" \
            "6" "Kill system panel")
        [[ -z "$schoice" ]] && exit 0

        case "$schoice" in
            1)  # Position — corner picker
                corner=$(kdialog --title "Screen Position" \
                    --menu "Move system panel to which position?" \
                    "top_right"     "Top-right corner" \
                    "top_left"      "Top-left corner" \
                    "top_center"    "Top center" \
                    "bottom_right"  "Bottom-right corner" \
                    "bottom_left"   "Bottom-left corner" \
                    "bottom_center" "Bottom center")
                [[ -z "$corner" ]] && exit 0
                _sxdt=$(DISPLAY=:1 xdotool search --name 'Conky System' getwindowgeometry 2>/dev/null)
                _scw=$(echo "$_sxdt" | grep -oP 'Geometry: \K\d+' || echo 380)
                _sch=$(echo "$_sxdt" | grep -oP 'Geometry: \d+x\K\d+' || echo 400)
                read new_align new_gx new_gy < <(python3 - <<PYEOF
import re, subprocess, os
corner = '$corner'
try:
    xdt = subprocess.check_output(
        ['xdotool', 'search', '--name', 'Conky System', 'getwindowgeometry'],
        env={**os.environ, 'DISPLAY': ':1'}, stderr=subprocess.DEVNULL).decode()
    pm = re.search(r'Position: (\d+),(\d+)', xdt)
    gm = re.search(r'Geometry: (\d+)x(\d+)', xdt)
    wx = int(pm.group(1)) if pm else 0
    wy = int(pm.group(2)) if pm else 0
    cw = int(gm.group(1)) if gm else 380
    ch = int(gm.group(2)) if gm else 400
except Exception:
    wx, wy, cw, ch = 0, 0, 380, 400
lines = subprocess.check_output(['xrandr', '--listmonitors'],
    env={**os.environ, 'DISPLAY': ':1'}, stderr=subprocess.DEVNULL).decode().splitlines()[1:]
monitors = []
for l in lines:
    m = re.search(r'(\d+)/\d+x(\d+)/\d+\+(\d+)\+(\d+)', l)
    if m: monitors.append(tuple(int(m.group(i)) for i in range(1,5)))
mon = next((m for m in monitors if m[2]<=wx<m[2]+m[0] and m[3]<=wy<m[3]+m[1]), None)
if not mon: mon = monitors[0] if monitors else (1920,1080,0,0)
mw, mh, mx, my = mon
SCALE=$SCALE; BASE_RIGHT=$BASE_RIGHT; MARGIN_X=$MARGIN_X; MARGIN_Y=$MARGIN_Y; PRIMARY_X=$PRIMARY_X
lw = round(cw / SCALE)
if corner in ('bottom_right', 'bottom_left', 'bottom_center'):
    gap_y = round((my + mh - MARGIN_Y - ch) / SCALE)
else:
    gap_y = round((my + MARGIN_Y) / SCALE)
if corner in ('top_center', 'bottom_center'):
    panel_left = mx + (mw - cw) // 2
    print('top_left', round((panel_left - PRIMARY_X + 6) / SCALE), gap_y)
elif corner in ('top_right', 'bottom_right'):
    tl = (mx + mw) - MARGIN_X - cw
    gx = round(BASE_RIGHT - lw - tl / SCALE)
    print('top_right' if gx >= 0 else 'top_left',
          gx if gx >= 0 else round((tl - PRIMARY_X + 6) / SCALE), gap_y)
else:
    print('top_left', round((mx + MARGIN_X - PRIMARY_X + 6) / SCALE), gap_y)
PYEOF
                )
                if [[ -z "$new_align" ]]; then
                    kdialog --error "Could not compute position — is the system panel running?"
                    exit 1
                fi
                sed -i "s/alignment = '[^']*'/alignment = '$new_align'/" "$SYSTEM_CONF"
                sed -i "s/gap_x = [0-9]*/gap_x = $new_gx/" "$SYSTEM_CONF"
                sed -i "s/gap_y = [0-9]*/gap_y = $new_gy/" "$SYSTEM_CONF"
                systemctl --user restart conky-system.service
                exit 0
                ;;
            2)  # Monitor
                menu_args=()
                while IFS=' ' read -r mw mh mx my output name; do
                    label="${name} (${mw}×${mh} at +${mx}+${my})"
                    menu_args+=("$output" "$label")
                done < <(_parse_monitors)
                [[ ${#menu_args[@]} -eq 0 ]] && { kdialog --error "No monitors detected."; exit 1; }
                chosen_output=$(kdialog --title "Choose Monitor" \
                    --menu "Select monitor for system panel:" "${menu_args[@]}")
                [[ -z "$chosen_output" ]] && exit 0
                read new_align new_gx new_gy < <(
                    _parse_monitors | awk -v out="$chosen_output" '$5==out {print $1,$2,$3,$4}' \
                    | python3 -c "
import sys
line = sys.stdin.read().split()
mw, mh, mx, my = int(line[0]), int(line[1]), int(line[2]), int(line[3])
import subprocess, os, re
try:
    xdt = subprocess.check_output(['xdotool','search','--name','Conky System','getwindowgeometry'],
        env={**os.environ,'DISPLAY':':1'}, stderr=subprocess.DEVNULL).decode()
    gm = re.search(r'Geometry: (\d+)x', xdt)
    cw = int(gm.group(1)) if gm else 380
except Exception:
    cw = 380
SCALE=$SCALE; BASE_RIGHT=$BASE_RIGHT; MARGIN_X=$MARGIN_X; MARGIN_Y=$MARGIN_Y; PRIMARY_X=$PRIMARY_X
lw = round(cw / SCALE)
tl = (mx + mw) - MARGIN_X - cw
gx = round(BASE_RIGHT - lw - tl / SCALE)
gy = round((my + MARGIN_Y) / SCALE)
if gx >= 0:
    print('top_right', gx, gy)
else:
    print('top_left', round((tl - PRIMARY_X + 6) / SCALE), gy)
")
                [[ -z "$new_align" ]] && { kdialog --error "Could not compute position for that monitor."; exit 1; }
                sed -i "s/alignment = '[^']*'/alignment = '$new_align'/" "$SYSTEM_CONF"
                sed -i "s/gap_x = [0-9]*/gap_x = $new_gx/" "$SYSTEM_CONF"
                sed -i "s/gap_y = [0-9]*/gap_y = $new_gy/" "$SYSTEM_CONF"
                systemctl --user restart conky-system.service
                exit 0
                ;;
            3)  # Transparency
                val=$(kdialog --title "Transparency" \
                    --inputbox "Enter transparency (0 = fully transparent, 255 = opaque):" "${_salpha:-180}")
                [[ -z "$val" ]] && exit 0
                if ! [[ "$val" =~ ^[0-9]+$ ]] || [[ "$val" -gt 255 ]]; then
                    kdialog --error "Must be a number 0–255"
                    exit 1
                fi
                sed -i "s/own_window_argb_value  = [0-9]*/own_window_argb_value  = $val/" "$SYSTEM_CONF"
                systemctl --user restart conky-system.service
                exit 0
                ;;
            4)  # Edge gap
                read _spanel_h _spanel_v _scur_mx _scur_my < <(python3 - <<PYEOF
import re, subprocess, os
try:
    xdt = subprocess.check_output(
        ['xdotool', 'search', '--name', 'Conky System', 'getwindowgeometry'],
        env={**os.environ, 'DISPLAY': ':1'}, stderr=subprocess.DEVNULL).decode()
    pm = re.search(r'Position: (\d+),(\d+)', xdt)
    gm = re.search(r'Geometry: (\d+)x(\d+)', xdt)
    wx = int(pm.group(1)) if pm else None
    wy = int(pm.group(2)) if pm else None
    cw = int(gm.group(1)) if gm else 380
    ch = int(gm.group(2)) if gm else 400
except Exception:
    wx = wy = None; cw = 380; ch = 400
if wx is None:
    print('right top $MARGIN_X $MARGIN_Y')
else:
    lines = subprocess.check_output(['xrandr', '--listmonitors'],
        env={**os.environ, 'DISPLAY': ':1'}, stderr=subprocess.DEVNULL).decode().splitlines()[1:]
    monitors = []
    for l in lines:
        m = re.search(r'(\d+)/\d+x(\d+)/\d+\+(\d+)\+(\d+)', l)
        if m: monitors.append(tuple(int(m.group(i)) for i in range(1,5)))
    mon = next((m for m in monitors if m[2]<=wx<m[2]+m[0] and m[3]<=wy<m[3]+m[1]), None)
    if not mon: mon = monitors[0] if monitors else (1920,1080,0,0)
    mw, mh, mx, my = mon
    dist_left   = wx - mx
    dist_right  = (mx + mw) - (wx + cw)
    dist_top    = wy - my
    dist_bottom = (my + mh) - (wy + ch)
    if abs(dist_left - dist_right) <= max(10, mw * 0.05):
        h_mode = 'center'; h_margin = 0
    elif dist_left <= dist_right:
        h_mode = 'left';   h_margin = dist_left
    else:
        h_mode = 'right';  h_margin = dist_right
    v_mode   = 'top' if dist_top <= dist_bottom else 'bottom'
    v_margin = dist_top if v_mode == 'top' else dist_bottom
    print(h_mode, v_mode, max(0, h_margin), max(0, v_margin))
PYEOF
                )
                [[ -z "$_spanel_h" ]] && { kdialog --error "Could not read system panel position — is it running?"; exit 1; }

                if [[ "$_spanel_h" != "center" ]]; then
                    _smx=$(kdialog --title "Horizontal Margin" \
                        --inputbox "Pixels from the ${_spanel_h} edge of the monitor:" "$_scur_mx")
                    [[ -z "$_smx" ]] && exit 0
                    if ! [[ "$_smx" =~ ^[0-9]+$ ]]; then
                        kdialog --error "Must be a non-negative integer"; exit 1
                    fi
                else
                    _smx=0
                fi
                _smy=$(kdialog --title "Vertical Margin" \
                    --inputbox "Pixels from the ${_spanel_v} edge of the monitor:" "$_scur_my")
                [[ -z "$_smy" ]] && exit 0
                if ! [[ "$_smy" =~ ^[0-9]+$ ]]; then
                    kdialog --error "Must be a non-negative integer"; exit 1
                fi

                export _SPANEL_H="$_spanel_h" _SPANEL_V="$_spanel_v" _SMARG_X="$_smx" _SMARG_Y="$_smy"
                read new_align new_gx new_gy < <(python3 - <<PYEOF
import re, subprocess, os
h_mode   = os.environ['_SPANEL_H']
v_mode   = os.environ['_SPANEL_V']
margin_x = int(os.environ['_SMARG_X'])
margin_y = int(os.environ['_SMARG_Y'])
try:
    xdt = subprocess.check_output(
        ['xdotool', 'search', '--name', 'Conky System', 'getwindowgeometry'],
        env={**os.environ, 'DISPLAY': ':1'}, stderr=subprocess.DEVNULL).decode()
    pm = re.search(r'Position: (\d+),(\d+)', xdt)
    gm = re.search(r'Geometry: (\d+)x(\d+)', xdt)
    wx = int(pm.group(1)) if pm else 0
    wy = int(pm.group(2)) if pm else 0
    cw = int(gm.group(1)) if gm else 380
    ch = int(gm.group(2)) if gm else 400
except Exception:
    wx, wy, cw, ch = 0, 0, 380, 400
lines = subprocess.check_output(['xrandr', '--listmonitors'],
    env={**os.environ, 'DISPLAY': ':1'}, stderr=subprocess.DEVNULL).decode().splitlines()[1:]
monitors = []
for l in lines:
    m = re.search(r'(\d+)/\d+x(\d+)/\d+\+(\d+)\+(\d+)', l)
    if m: monitors.append(tuple(int(m.group(i)) for i in range(1,5)))
mon = next((m for m in monitors if m[2]<=wx<m[2]+m[0] and m[3]<=wy<m[3]+m[1]), None)
if not mon: mon = monitors[0] if monitors else (1920,1080,0,0)
mw, mh, mx, my = mon
SCALE=$SCALE; BASE_RIGHT=$BASE_RIGHT; MARGIN_X=$MARGIN_X; MARGIN_Y=$MARGIN_Y; PRIMARY_X=$PRIMARY_X
lw = round(cw / SCALE)
if h_mode == 'center':
    panel_left = mx + (mw - cw) // 2
    gx = round((panel_left - PRIMARY_X + 6) / SCALE)
    align = 'top_left'
elif h_mode == 'left':
    panel_left = mx + margin_x
    gx = round((panel_left - PRIMARY_X + 6) / SCALE)
    align = 'top_left'
else:
    panel_left = (mx + mw) - margin_x - cw
    gx_tr = round(BASE_RIGHT - lw - panel_left / SCALE)
    if gx_tr >= 0:
        gx = gx_tr; align = 'top_right'
    else:
        gx = round((panel_left - PRIMARY_X + 6) / SCALE); align = 'top_left'
if v_mode == 'top':
    gy = round((my + margin_y) / SCALE)
else:
    gy = round((my + mh - margin_y - ch) / SCALE)
print(align, gx, gy)
PYEOF
                )
                [[ -z "$new_align" ]] && { kdialog --error "Could not compute gap values."; exit 1; }
                sed -i "s/alignment = '[^']*'/alignment = '$new_align'/" "$SYSTEM_CONF"
                sed -i "s/gap_x = [0-9]*/gap_x = $new_gx/" "$SYSTEM_CONF"
                sed -i "s/gap_y = [0-9]*/gap_y = $new_gy/" "$SYSTEM_CONF"
                systemctl --user restart conky-system.service
                exit 0
                ;;
            5)  # Restart system panel
                systemctl --user restart conky-system.service
                sleep 2
                if systemctl --user is-active --quiet conky-system.service; then
                    kdialog --passivepopup "System panel restarted." 3
                else
                    kdialog --error "System panel failed to restart.\n\n$(systemctl --user status conky-system.service --no-pager 2>&1 | tail -10)"
                fi
                exit 0
                ;;
            6)  # Kill system panel
                systemctl --user stop conky-system.service
                kdialog --msgbox "System panel stopped."
                exit 0
                ;;
        esac
        exit 0
        ;;

    12)  # Restart only
        ;;

    13)  # Kill
        systemctl --user stop conky.service && kdialog --msgbox "Conky stopped."
        exit 0
        ;;
esac

# ── Restart Conky via systemd ─────────────────────────────────────────────────
systemctl --user restart conky.service
sleep 2

if systemctl --user is-active --quiet conky.service; then
    kdialog --passivepopup "Conky restarted with new settings." 3
else
    kdialog --error "Conky failed to restart.\n\n$(systemctl --user status conky.service --no-pager 2>&1 | tail -10)"
fi
