#!/usr/bin/env bash
# Post a status line directly to an HA sensor via the Supervisor core API.
# Independent of MQTT so it works even when the broker connection is broken.
MSG="${1:0:250}"
PAYLOAD=$(python3 - "$MSG" << 'PYEOF'
import json, sys
print(json.dumps({
    "state": sys.argv[1],
    "attributes": {"friendly_name": "sonycam add-on log",
                   "icon": "mdi:text-box-outline"},
}))
PYEOF
)
curl -s -X POST \
    -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${PAYLOAD}" \
    http://supervisor/core/api/states/sensor.sonycam_addon_log > /dev/null || true
