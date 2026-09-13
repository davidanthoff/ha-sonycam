## Setup

1. Download the Sony Camera Remote SDK (Linux 64-bit x86) from Sony and copy
   the zip to `/share/sonycam/`, or set `sdk_url` to a reachable URL.
2. Start the add-on; the first start compiles sonycam (watch the log).
3. Entities appear under the MQTT integration as device "Sony Camera".
4. Turn on the connection switch to take control of the camera. Only one
   remote client at a time: disconnect other apps (e.g. Monitor & Control).

## Options

- `liveview_interval`: seconds between live-view frames while connected.
- `poll_interval`: seconds between property refreshes while connected.
- `sdk_url`: optional http(s) URL of the SDK zip if not using /share.
