# ha-sonycam

A Home Assistant add-on that controls Sony cameras supported by the
[Sony Camera Remote SDK](https://support.d-imaging.sony.co.jp/app/sdk/en/index.html)
(FX30, FX3, a1, a7 IV/V, a9, ZV-E1, ...) over the network and exposes them as
Home Assistant entities via MQTT discovery:

- a **camera** entity streaming SDK live-view frames
- **select** entities for ISO and white-balance mode
- a **number** entity for color temperature (2500-9900 K)
- a **switch** to take/release the remote-control connection
- a **status** sensor

Built on the MIT-licensed [sonycam](https://github.com/talayolabs/sonycam)
CLI (currently pinned to a fork carrying an
[FX30 compatibility fix](https://github.com/talayolabs/sonycam/pull/3)).

## Bring your own SDK

Sony's Camera Remote SDK is free but **cannot be redistributed**, so this
add-on does not contain it. Apply for and download the **Linux 64-bit (x86)**
SDK package from [Sony's SDK page](https://support.d-imaging.sony.co.jp/app/sdk/en/index.html),
then either:

- copy the downloaded `CrSDK_*_Linux64PC.zip` to `/share/sonycam/` on your
  Home Assistant box, or
- set the `sdk_url` add-on option to a URL the add-on can download it from.

On first start the add-on compiles sonycam against your SDK (a few minutes);
subsequent starts are instant.

## Install

Settings -> Add-ons -> Add-on Store -> menu -> Repositories -> add
`https://github.com/davidanthoff/ha-sonycam`, then install "sonycam".
Requires the Mosquitto broker add-on (or another MQTT broker configured in HA).

## Camera setup

Enable network remote control on the camera (e.g. FX30: Network ->
Cnct./Remote Sht. -> Remote Shoot Function) and pair once. Only one remote
client can hold the camera at a time - use the connection switch entity to
take/release it.

---
Not affiliated with or endorsed by Sony. Maintained by David Anthoff with
Claude (Anthropic). Issues and PRs welcome, but this is primarily a personal
project.
