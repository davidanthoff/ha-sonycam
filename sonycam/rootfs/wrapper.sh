#!/bin/bash
# Plain-bash wrapper: run the real entrypoint, then post its tail output to an
# HA sensor via the Supervisor core API - even if run.sh dies instantly.
/run.sh > /tmp/addon.log 2>&1
CODE=$?
TAIL=$(tail -c 240 /tmp/addon.log)
PAYLOAD=$(python3 - "$CODE" "$TAIL" << 'PYEOF'
import json, sys
print(json.dumps({
    "state": ("exit " + sys.argv[1])[:250],
    "attributes": {"friendly_name": "sonycam add-on log",
                   "tail": sys.argv[2]},
}))
PYEOF
)
curl -s -X POST \
    -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${PAYLOAD}" \
    http://supervisor/core/api/states/sensor.sonycam_addon_log
if [ ${CODE} -ne 0 ]; then
    sleep 20
    exit ${CODE}
fi
