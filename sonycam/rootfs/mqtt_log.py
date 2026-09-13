"""Publish an add-on status line to MQTT (retained) + a discovery config
for a 'Log' sensor, so startup problems are visible in HA without
Supervisor log access."""
import json
import os
import sys

import paho.mqtt.client as mqtt

msg = " ".join(sys.argv[1:])[:255]
client = mqtt.Client(client_id="sonycam-log")
client.username_pw_set(os.environ["MQTT_USER"], os.environ["MQTT_PASSWORD"])
client.connect(os.environ.get("MQTT_HOST", "127.0.0.1"),
               int(os.environ.get("MQTT_PORT", "1883")))
client.loop_start()
disc = {
    "name": "Log",
    "state_topic": "sonycam/fx30/log/state",
    "icon": "mdi:text-box-outline",
    "entity_category": "diagnostic",
    "device": {
        "identifiers": ["sonycam_camera"],
        "name": "Sony Camera",
        "manufacturer": "Sony",
        "model": "via sonycam",
    },
    "unique_id": "sonycam_log",
}
client.publish("homeassistant/sensor/sonycam/log/config",
               json.dumps(disc), retain=True).wait_for_publish(5)
client.publish("sonycam/fx30/log/state", msg, retain=True).wait_for_publish(5)
client.loop_stop()
