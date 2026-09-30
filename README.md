# MTTL Hub

Local-first controller for LG U+ **MTTL-W01** smart power strips.

```
strip ──TCP 10086──► ESP32 hub ──MQTT/TLS──► cloud broker ◄── app (remote)
                        └── REST :8080 ◄── app (same Wi-Fi)
```

| Folder | What |
|---|---|
| `firmware/mttl_hub` | ESP32 hub firmware (Arduino-ESP32 3.x) |
| `app` | Flutter app (Android). Built by GitHub Actions on every push to `main` |
| `docs` | Protocol notes |

**Get the app:** Releases → latest → `app-release.apk`.

Build logs of the last CI run are on the `ci-logs` branch.
