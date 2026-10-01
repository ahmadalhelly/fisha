# Fisha · فيشة

Local-first controller for LG U+ MTTL-W01 smart power strips: an ESP32 hub talks to the strips on your Wi-Fi and relays to the cloud over MQTT; the Android app works on the home network (live push) and from anywhere.

- `firmware/mttl_hub/` — ESP32 hub v2.0 (Arduino core 3.x, partition "Minimal SPIFFS"). Fill WIFI_PASS, MQTT_PASS, OTA_PASS.
- `app/` — Flutter app v1.0. CI builds a signed APK into Releases on every push.
- `docs/protocol.md` — strip protocol + hub API.

By: ahmadalhelly
