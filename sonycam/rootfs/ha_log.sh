#!/usr/bin/env bash
# Post a status line to HA: via the Supervisor core API and, if configured,
# to a webhook (debug_log_url) which needs no authentication.
MSG="${1:0:250}"
PAYLOAD=$(python3 - "$MSG" << 'PYEOF2'
import json, sys
print(json.dumps({
    "state": sys.argv[1],
    "attributes": {"friendly_name": "sonycam add-on log",
                   "icon": "mdi:text-box-outline"},
}))
PYEOF2
)
curl -s -m 5 -X POST     -H "Authorization: Bearer ${SUPERVISOR_TOKEN}"     -H "Content-Type: application/json"     -d "${PAYLOAD}"     http://supervisor/core/api/states/sensor.sonycam_addon_log > /dev/null
if [ -n "${DEBUG_LOG_URL}" ]; then
    WPAYLOAD=$(python3 - "$MSG" << 'PYEOF2'
import json, sys
print(json.dumps({"msg": sys.argv[1]}))
PYEOF2
)
    curl -s -m 5 -X POST -H "Content-Type: application/json"         -d "${WPAYLOAD}" "${DEBUG_LOG_URL}" > /dev/null
fi
exit 0
