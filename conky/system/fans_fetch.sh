#!/bin/bash
# Fetch fan/temp data from CoolerControl REST API and cache to /tmp/conky_system/fans.json
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
CONFIG="$SCRIPT_DIR/config"
[[ -f "$CONFIG" ]] && source "$CONFIG"

CC_HOST="${CC_HOST:-localhost}"
CC_PORT="${CC_PORT:-11987}"
CC_URL="https://${CC_HOST}:${CC_PORT}"

CACHE_DIR=/tmp/conky_system
CACHE_FILE=$CACHE_DIR/fans.json
MAX_AGE=5
COOKIE=$CACHE_DIR/cc_session.txt

mkdir -p "$CACHE_DIR"
if [[ -f "$CACHE_FILE" ]]; then
    age=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE") ))
    [[ $age -lt $MAX_AGE ]] && exit 0
fi

# Login (renews cookie if expired). Skip if no password configured.
if [[ -n "$CC_PASS" ]]; then
    curl -sk -X POST "$CC_URL/login" \
        -H "Authorization: Basic $(printf '%s:%s' "$CC_USER" "$CC_PASS" | base64 -w0)" \
        -c "$COOKIE" -o /dev/null
fi

RAW=$CACHE_DIR/status_raw.json
curl -sk -b "$COOKIE" "$CC_URL/status" -o "$RAW"

COMMANDER_UID="${COMMANDER_UID:-}" GPU_DEV_UID="${GPU_DEV_UID:-}" python3 - <<'PYEOF'
import json, os, time

CACHE_DIR = '/tmp/conky_system'
COMMANDER = os.environ.get('COMMANDER_UID', '')
GPU_DEV   = os.environ.get('GPU_DEV_UID', '')

out = {
    'water_temp':     None,
    'gpu_temp':       None,
    'commander_fans': [],
    'gpu_fan_rpm':    None,
    'gpu_fan_duty':   None,
    'fetched':        time.time(),
}

try:
    with open(CACHE_DIR + '/status_raw.json') as f:
        data = json.load(f)

    for dev in data.get('devices', []):
        uid = dev.get('uid', '')
        h   = (dev.get('status_history') or [{}])[-1]

        if COMMANDER and uid.startswith(COMMANDER):
            for t in h.get('temps', []):
                if t.get('name') == 'water':
                    out['water_temp'] = t.get('temp')
            for c in h.get('channels', []):
                n = c.get('name', '')
                if n.startswith('fan') or n == 'pump':
                    out['commander_fans'].append({'name': n, 'rpm': c.get('rpm') or 0})

        elif GPU_DEV and uid.startswith(GPU_DEV):
            temps = {t.get('name'): t.get('temp') for t in h.get('temps', [])}
            # temp3 = junction/edge (hottest, most relevant)
            out['gpu_temp'] = temps.get('temp3') or temps.get('temp1')
            for c in h.get('channels', []):
                if c.get('name') == 'fan1':
                    out['gpu_fan_rpm']  = c.get('rpm')
                    out['gpu_fan_duty'] = c.get('duty')

except Exception as e:
    out['error'] = str(e)

with open(CACHE_DIR + '/fans.json', 'w') as f:
    json.dump(out, f)
PYEOF
