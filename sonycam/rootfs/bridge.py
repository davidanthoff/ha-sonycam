"""MQTT bridge: expose a sonycam-controlled Sony camera as HA entities."""
import json
import os
import signal
import subprocess
import threading
import time

import paho.mqtt.client as mqtt

SONYCAM = os.environ["SONYCAM"]
LIVEVIEW_INTERVAL = int(os.environ.get("LIVEVIEW_INTERVAL", "2"))
POLL_INTERVAL = int(os.environ.get("POLL_INTERVAL", "5"))

BASE = "sonycam/fx30"
AVAIL = BASE + "/availability"
DISCOVERY_PREFIX = "homeassistant"
DEVICE = {
    "identifiers": ["sonycam_camera"],
    "name": "Sony Camera",
    "manufacturer": "Sony",
    "model": "via sonycam",
}

PROPS = ["iso", "white_balance", "color_temp"]


def run_sonycam(args, timeout=60, binary_output=False):
    try:
        cmd = [SONYCAM] + args if binary_output else [SONYCAM, "--json"] + args
        res = subprocess.run(cmd, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "timeout"}
    if binary_output:
        return {"ok": res.returncode == 0}
    try:
        return json.loads(res.stdout.decode("utf-8", "replace").strip())
    except Exception:
        err = res.stderr.decode("utf-8", "replace").strip()
        return {"ok": False, "error": err or "unparseable sonycam output"}


class Bridge:
    def __init__(self):
        self.wb_point = {"x": 0.5, "y": 0.5}
        self.desired_connected = False
        self.connected = False
        self.model = ""
        self.choices = {}
        self.lock = threading.Lock()
        self.running = True

        self.client = mqtt.Client(client_id="sonycam-bridge")
        self.client.username_pw_set(os.environ["MQTT_USER"],
                                    os.environ["MQTT_PASSWORD"])
        self.client.will_set(AVAIL, "offline", retain=True)
        self.client.on_connect = self.on_mqtt_connect
        self.client.on_message = self.on_mqtt_message
        self.client.connect(os.environ.get("MQTT_HOST", "127.0.0.1"),
                            int(os.environ.get("MQTT_PORT", "1883")))
        self.client.loop_start()

    def on_mqtt_connect(self, client, userdata, flags, rc):
        client.subscribe(BASE + "/+/set")
        client.publish(AVAIL, "online", retain=True)
        self.publish_static_discovery()

    def on_mqtt_message(self, client, userdata, msg):
        payload = msg.payload.decode("utf-8", "replace").strip()
        entity = msg.topic.split("/")[-2]
        threading.Thread(target=self.handle_command,
                         args=(entity, payload), daemon=True).start()

    def disc(self, component, object_id, extra):
        cfg = {
            "availability_topic": AVAIL,
            "device": DEVICE,
            "unique_id": "sonycam_" + object_id,
        }
        cfg.update(extra)
        topic = DISCOVERY_PREFIX + "/" + component + "/sonycam/" + object_id + "/config"
        self.client.publish(topic, json.dumps(cfg), retain=True)

    def publish_static_discovery(self):
        self.disc("switch", "connection", {
            "name": "Camera connection",
            "command_topic": BASE + "/connection/set",
            "state_topic": BASE + "/connection/state",
            "icon": "mdi:camera-wireless",
        })
        self.disc("camera", "liveview", {
            "name": "Live view",
            "topic": BASE + "/liveview",
        })
        self.disc("sensor", "status", {
            "name": "Status",
            "state_topic": BASE + "/status/state",
            "json_attributes_topic": BASE + "/status/attributes",
        })
        self.disc("button", "wb_capture", {
            "name": "Capture custom WB",
            "command_topic": BASE + "/wb_capture/set",
            "icon": "mdi:eyedropper",
        })
        for axis in ("x", "y"):
            self.disc("number", "wb_point_" + axis, {
                "name": "WB capture point " + axis.upper(),
                "command_topic": BASE + "/wb_point_" + axis + "/set",
                "state_topic": BASE + "/wb_point_" + axis + "/state",
                "min": 0, "max": 1, "step": 0.01,
                "mode": "box",
                "entity_category": "config",
                "icon": "mdi:crosshairs",
            })
            self.client.publish(BASE + "/wb_point_" + axis + "/state",
                                "0.5", retain=True)
        self.disc("number", "color_temp", {
            "name": "Color temperature",
            "command_topic": BASE + "/color_temp/set",
            "state_topic": BASE + "/color_temp/state",
            "min": 2500, "max": 9900, "step": 100,
            "unit_of_measurement": "K",
            "mode": "box",
            "icon": "mdi:thermometer",
        })

    def publish_select_discovery(self, prop, options):
        self.disc("select", prop, {
            "name": prop.replace("_", " ").title(),
            "command_topic": BASE + "/" + prop + "/set",
            "state_topic": BASE + "/" + prop + "/state",
            "options": options,
        })

    def handle_command(self, entity, payload):
        with self.lock:
            if entity == "connection":
                self.desired_connected = payload.upper() == "ON"
                if self.desired_connected:
                    self.ensure_connected()
                else:
                    run_sonycam(["disconnect"], timeout=30)
                    self.connected = False
                self.publish_connection()
            elif entity == "color_temp":
                value = payload.split(".")[0] + "K"
                run_sonycam(["set", "color_temp", value])
                self.publish_props()
            elif entity in ("wb_point_x", "wb_point_y"):
                axis = entity[-1]
                try:
                    self.wb_point[axis] = min(1.0, max(0.0, float(payload)))
                except ValueError:
                    pass
                self.client.publish(BASE + "/" + entity + "/state",
                                    str(self.wb_point[axis]), retain=True)
            elif entity == "wb_capture":
                res = run_sonycam(["wb", "capture",
                                   str(self.wb_point["x"]),
                                   str(self.wb_point["y"])], timeout=60)
                msg = "custom WB captured" if res.get("ok") else                     "WB capture failed: " + str(res.get("error", ""))[:150]
                self.client.publish("sonycam/fx30/log/state", msg, retain=True)
                self.publish_props()
            elif entity in ("iso", "white_balance"):
                run_sonycam(["set", entity, payload])
                self.publish_props()

    def ensure_connected(self):
        res = run_sonycam(["connect"], timeout=120)
        self.connected = bool(res.get("ok"))
        if not self.connected:
            self.client.publish(BASE + "/status/state", "error", retain=True)
            attrs = {"error": res.get("error", "connect failed")}
            self.client.publish(BASE + "/status/attributes",
                                json.dumps(attrs), retain=True)
        return self.connected

    def publish_connection(self):
        state = "ON" if self.connected else "OFF"
        self.client.publish(BASE + "/connection/state", state, retain=True)

    def publish_props(self):
        res = run_sonycam(["props"])
        if not res.get("ok"):
            return
        for p in res.get("result", []):
            name = p.get("name")
            if name not in PROPS:
                continue
            value = str(p.get("value", ""))
            if name == "color_temp":
                value = value.rstrip("K")
            self.client.publish(BASE + "/" + name + "/state", value,
                                retain=True)
            choices = p.get("choices")
            has_select = name in ("iso", "white_balance")
            if has_select and choices and self.choices.get(name) != choices:
                self.choices[name] = choices
                self.publish_select_discovery(name, choices)

    def publish_status(self):
        res = run_sonycam(["status"], timeout=30)
        r = res.get("result", {}) if res.get("ok") else {}
        self.connected = bool(r.get("connected"))
        self.model = r.get("model", "")
        state = "connected" if self.connected else "disconnected"
        self.client.publish(BASE + "/status/state", state, retain=True)
        self.client.publish(BASE + "/status/attributes", json.dumps(r),
                            retain=True)
        self.publish_connection()

    def publish_liveview(self):
        path = "/tmp/liveview.jpg"
        res = run_sonycam(["liveview", path], timeout=30, binary_output=True)
        if res.get("ok") and os.path.exists(path):
            with open(path, "rb") as f:
                self.client.publish(BASE + "/liveview", f.read())

    def loop(self):
        last_poll = 0.0
        last_lv = 0.0
        while self.running:
            with self.lock:
                if self.desired_connected and not self.connected:
                    self.ensure_connected()
                now = time.time()
                if now - last_poll >= POLL_INTERVAL:
                    self.publish_status()
                    if self.connected:
                        self.publish_props()
                    last_poll = now
                if self.connected and now - last_lv >= LIVEVIEW_INTERVAL:
                    self.publish_liveview()
                    last_lv = now
            time.sleep(0.5)

    def shutdown(self, *_):
        self.running = False
        with self.lock:
            if self.connected:
                run_sonycam(["disconnect"], timeout=30)
        self.client.publish(AVAIL, "offline", retain=True)
        self.client.loop_stop()
        os._exit(0)


def main():
    bridge = Bridge()
    signal.signal(signal.SIGTERM, bridge.shutdown)
    signal.signal(signal.SIGINT, bridge.shutdown)
    bridge.loop()


if __name__ == "__main__":
    main()
