# Fisha on the web (iPhone home-screen app)

The same Flutter code also builds as a web app (`flutter build web`), served over https from GitHub Pages
and installed on an iPhone with Safari → Share → **Add to Home Screen**. The Android app is unchanged: every
web difference sits behind `kIsWeb` (a compile-time `false` on Android) or a conditional import.

## Cloud only

An https page may not call plain `http://` addresses (mixed content), so the web app cannot reach the hub's
LAN API (`http://<hub>:8080`) or its live feed (SSE on port 8081). On the web the app therefore:

- never starts local polling or SSE (`AppState.restart`, `_pollLocal`, `_runSse`, `refresh`), so the mode is always
  **cloud** or **offline**;
- talks to the hub only through MQTT over secure WebSockets: `wss://<brokerHost>:8084/mqtt`
  (subprotocol `mqtt`). The host is the usual `brokerHost` setting; the TLS port setting (8883) is not used.
  See `lib/services/mqtt_factory_web.dart`.

The cloud details (username and password, or an invite code) must be set for the web app to work at all.

## Disabled or hidden on the web

| Feature | Why |
| --- | --- |
| Home address field, MQTT/local port fields, local and live status rows (Connection) | no local link from an https page |
| Handing the hub its server password after saving (Connection) | needs the local link |
| Add strip button (Home) | pairing runs through the hub on the home network |
| Wi-Fi network page (Settings) | changing the hub's Wi-Fi is a home-network action |
| Firmware update page (Settings) | uploads to the hub's plain-http `/update` page; `uploadFirmwareBytes` returns `net` on the web |
| Instant phone notifications (background service) | `flutter_foreground_task` and `flutter_local_notifications` are Android-only; `NotifyService` is a no-op stub. The ntfy route still works |
| Biometric confirmation for protected outlets | `local_auth` has no web version; `authenticateBio` returns `true` (treated as passed) |
| Google sign-in and Drive sync | `google_sign_in` on the web needs a separate web OAuth client id; the Google options are hidden |
| Android home-screen widget | Android-only; widget updates are skipped |
| Saving a backup to a chosen path | the browser downloads the file instead; importing uses the picked file's bytes |

## How it is wired

Conditional imports (`export 'x_io.dart' if (dart.library.js_interop) 'x_web.dart';`) keep each platform's
libraries out of the other build:

- `lib/services/mqtt_factory.dart`: `MqttServerClient` (TLS socket, dart:io) / `MqttBrowserClient` (wss)
- `lib/services/notify_service.dart`: foreground service + local notifications / no-op
- `lib/services/bio_auth.dart`: `local_auth` / always passes
- `lib/services/firmware_upload.dart`: dart:io `HttpClient` upload / not available
- `lib/services/file_io.dart`: dart:io `File` / not available

## Build

CI (`.github/workflows/build-web.yml`) runs `flutter create --platforms=web`, copies `web_overrides/` over
`web/` (PWA manifest and an `index.html` with the iPhone home-screen meta tags), runs `tool/configure_web.py`
(brand assets and the PWA icons), then `flutter build web --base-href /<repo>/`.

## Two ways to open it (hub fw 2.14.2+)

- `https://ahmadalhelly.github.io/fisha-web/`: anywhere, cloud only (an https page can't call the hub's plain-http API).
- `http://<hub ip>:8080/app`: on the home Wi-Fi. The hub serves a tiny launcher that loads the app from the site above
  (`window.FISHA_BASE` in `web_overrides/flutter_bootstrap.js`), so the page's origin is the hub: local REST polling
  works (`kLocalCapable` in app_state.dart) and the cloud too. SSE stays off on the web; the 2 s poll covers it.
- Built by `.github/workflows/build-web.yml` into the `fisha-web` artifact; with the `FISHA_WEB_TOKEN` secret it is
  pushed to the public `fisha-web` repo (Pages from `main`).
