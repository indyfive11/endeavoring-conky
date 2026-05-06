#!/bin/bash
# Check service health and cache results to /tmp/conky_system/services.json (ordered array)
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
CONFIG="$SCRIPT_DIR/config"
[[ -f "$CONFIG" ]] && source "$CONFIG"

CACHE_DIR=/tmp/conky_system
CACHE_FILE=$CACHE_DIR/services.json
MAX_AGE=30

mkdir -p "$CACHE_DIR"
if [[ -f "$CACHE_FILE" ]]; then
    age=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE") ))
    [[ $age -lt $MAX_AGE ]] && exit 0
fi

probe_port() { ncat -zw 2 "$1" "$2" &>/dev/null && echo up || echo down; }

entries=()
for svc in "${SERVICES[@]}"; do
    label="${svc%:*}"
    port="${svc##*:}"
    status=$(probe_port localhost "$port")
    entries+=("{\"label\":\"$label\",\"status\":\"$status\",\"kind\":\"port\"}")
done

if [[ -n "$NFS_MOUNT" ]]; then
    mountpoint -q "$NFS_MOUNT" 2>/dev/null && status=up || status=down
    entries+=("{\"label\":\"$NFS_LABEL\",\"status\":\"$status\",\"kind\":\"nfs\"}")
fi

if [[ -n "$REMOTE_HOST" && -n "$REMOTE_PORT" ]]; then
    status=$(probe_port "$REMOTE_HOST" "$REMOTE_PORT")
    entries+=("{\"label\":\"$REMOTE_LABEL\",\"status\":\"$status\",\"kind\":\"port\"}")
fi

(IFS=,; echo "[${entries[*]}]") > "$CACHE_FILE"
