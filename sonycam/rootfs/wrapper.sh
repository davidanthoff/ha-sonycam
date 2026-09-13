#!/bin/bash
DEBUG_LOG_URL=$(python3 -c "import json;print(json.load(open('/data/options.json')).get('debug_log_url',''))" 2>/dev/null)
export DEBUG_LOG_URL
# Plain-bash wrapper: run the real entrypoint, then post its tail output to an
# HA sensor via the Supervisor core API - even if run.sh dies instantly.
# --- diagnostic: report token presence and supervisor API reachability ---
DIAG_TOK="tok_len=${#SUPERVISOR_TOKEN}"
DIAG_INFO=$(curl -s -m 5 -o /tmp/diag_info.json -w "%{http_code}"     -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" http://supervisor/addons/self/info)
DIAG_BODY=$(head -c 120 /tmp/diag_info.json)
if [ -n "${DEBUG_LOG_URL}" ]; then
    DPAYLOAD=$(python3 - "${DIAG_TOK} info_http=${DIAG_INFO} body=${DIAG_BODY}" << 'PYEOF2'
import json, sys
print(json.dumps({"msg": sys.argv[1][:250]}))
PYEOF2
)
    curl -s -m 5 -X POST -H "Content-Type: application/json" -d "${DPAYLOAD}" "${DEBUG_LOG_URL}" > /dev/null
fi

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
    http://${SUPERVISOR_HOST:-172.30.32.2}/core/api/states/sensor.sonycam_addon_log
if [ -n "${DEBUG_LOG_URL}" ]; then
    WPAYLOAD=$(python3 - "$CODE" "$TAIL" << 'PYEOF2'
import json, sys
print(json.dumps({"msg": ("exit " + sys.argv[1] + ": " + sys.argv[2])[:250]}))
PYEOF2
)
    curl -s -m 5 -X POST -H "Content-Type: application/json"         -d "${WPAYLOAD}" "${DEBUG_LOG_URL}" > /dev/null
fi
if [ ${CODE} -ne 0 ]; then
    sleep 20
    exit ${CODE}
fi
