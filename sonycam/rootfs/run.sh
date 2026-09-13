#!/usr/bin/env bashio
set -e

SRC=/opt/sonycam-src
SDK_ROOT=/data/sdk
BUILD_DIR=/data/build
SHARE_DIR=/share/sonycam

bash /ha_log.sh "add-on starting (version 0.1.2)" || true

SDK_URL=$(bashio::config 'sdk_url')

# ---- MQTT credentials from the Supervisor services API -----------------------
if bashio::services.available "mqtt"; then
    export MQTT_HOST=127.0.0.1        # host_network: broker reachable on host
    export MQTT_PORT=$(bashio::services mqtt "port")
    export MQTT_USER=$(bashio::services mqtt "username")
    export MQTT_PASSWORD=$(bashio::services mqtt "password")
else
    bashio::log.error "No MQTT service available - install/start the Mosquitto broker add-on"
    bash /ha_log.sh "ERROR: no MQTT service available from Supervisor" || true
    exit 1
fi

report() {
    bashio::log.info "$1"
    bash /ha_log.sh "$1" || true
    python3 /mqtt_log.py "$1" || true
}

fatal() {
    bashio::log.error "$1"
    bash /ha_log.sh "ERROR: $1" || true
    python3 /mqtt_log.py "ERROR: $1" || true
    exit 1
}


# ---- locate the Sony SDK zip -------------------------------------------------
SDK_ZIP=""
if compgen -G "${SHARE_DIR}/CrSDK*Linux64PC*.zip" > /dev/null; then
    SDK_ZIP=$(ls -t ${SHARE_DIR}/CrSDK*Linux64PC*.zip | head -1)
elif compgen -G "${SHARE_DIR}/*.zip" > /dev/null; then
    SDK_ZIP=$(ls -t ${SHARE_DIR}/*.zip | head -1)
elif [ -n "${SDK_URL}" ]; then
    bashio::log.info "Downloading Sony SDK from ${SDK_URL}"
    mkdir -p /data/download
    curl -fL --retry 3 -o /data/download/crsdk.zip "${SDK_URL}"
    SDK_ZIP=/data/download/crsdk.zip
fi
if [ -z "${SDK_ZIP}" ]; then
    fatal "No Sony SDK found. Copy the CrSDK Linux64PC zip to /share/sonycam/ or set the sdk_url option. See the add-on documentation."
fi
report "Using Sony SDK: ${SDK_ZIP}"

# ---- build sonycam if SDK or source changed ----------------------------------
STAMP_NEW="$(md5sum "${SDK_ZIP}" | cut -d' ' -f1)-$(cat /opt/sonycam-src.rev)"
STAMP_OLD=""
[ -f /data/build.stamp ] && STAMP_OLD=$(cat /data/build.stamp)

if [ "${STAMP_NEW}" != "${STAMP_OLD}" ] || [ ! -x "${BUILD_DIR}/sonycam" ]; then
    report "Building sonycam (first run or SDK/source changed) ..."
    rm -rf "${SDK_ROOT}" "${BUILD_DIR}"
    mkdir -p "${SDK_ROOT}"
    unzip -q -o "${SDK_ZIP}" -d "${SDK_ROOT}/zip"
    RCLI_ZIP=$(find "${SDK_ROOT}/zip" -name "RemoteCli.zip" | head -1)
    if [ -z "${RCLI_ZIP}" ]; then
        fatal "RemoteCli.zip not found inside the SDK zip - is this the Camera Remote SDK Linux 64-bit PC package?"
    fi
    unzip -q -o "${RCLI_ZIP}" -d "${SDK_ROOT}/remotecli"
    # Sony sometimes nests a single top-level dir inside RemoteCli.zip
    SDK_DIR="${SDK_ROOT}/remotecli"
    if [ ! -d "${SDK_DIR}/app/CRSDK" ]; then
        INNER=$(find "${SDK_ROOT}/remotecli" -maxdepth 2 -type d -name CRSDK | head -1)
        [ -n "${INNER}" ] && SDK_DIR=$(dirname "$(dirname "${INNER}")")
    fi
    bashio::log.info "SDK dir: ${SDK_DIR}"
    cmake -B "${BUILD_DIR}" -S "${SRC}" -DSONY_SDK_DIR="${SDK_DIR}" > /data/cmake.log 2>&1 \
        || { tail -40 /data/cmake.log; fatal "sonycam build failed - see add-on log"; }
    cmake --build "${BUILD_DIR}" -j "$(nproc)" >> /data/cmake.log 2>&1 \
        || { tail -40 /data/cmake.log; fatal "sonycam build failed - see add-on log"; }
    echo "${STAMP_NEW}" > /data/build.stamp
    report "sonycam built successfully"
else
    bashio::log.info "sonycam build is up to date"
fi

export SONYCAM="${BUILD_DIR}/sonycam"
export LIVEVIEW_INTERVAL=$(bashio::config 'liveview_interval')
export POLL_INTERVAL=$(bashio::config 'poll_interval')

report "Starting MQTT bridge"
exec python3 /bridge.py
