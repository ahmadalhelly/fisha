// These declarations must precede Arduino's auto-generated function prototypes.
struct Strip;
struct LinkDay;
void linkDrop(const String& mac);
void linkUp(const String& mac);
struct Note;
struct Known;
struct Sched;
struct Autom;
struct HubUser;
struct ELog; struct PeakLog; struct SseClient; struct PubMark;   // for the Arduino-generated prototypes
struct ApiRes;
struct OwnerDev;
struct PairReq;

/*
  Fisha Hub — ESP32 local controller + cloud relay for LG U+ MTTL-W01 smart strips
  Board: ESP32 Dev Module (ESP32-WROOM-32) | Core: esp32 by Espressif 3.x | Partition: Minimal SPIFFS (1.9MB APP with OTA)
  No external libraries.  By: @ahmadalhelly

  Strips  : TCP 10086 and 21197 (the strip dials the hub, plain-text "up:..." lines; strip fw 1.0.116+ uses 21197)
  HTTP    : 8080   GET /api/state · GET /api/health · GET /api/raw?cmd=up:... · POST /api/<action> (JSON body)
  Live    : 8081   GET /events  (Server-Sent Events: "state" on every change, "event" for alerts)
  MQTT    : mttl/<HUB_ID>/{status,info,state,event,cmd,cmd/ack}   cmd = {"id","path":"/api/...", ...same fields as HTTP}
  Storage : names, child lock, protected outlets, auto-off, schedules, automations, energy history -> NVS (survive reboots)
            countdown / power-cycle timers -> NVS (restored after hub restart)

  POST actions: onoff, refresh, label, lock, protect, autooff, timer, timer_cancel, provision,
                schedules, schedule_save, schedule_delete, automations, automation_save, automation_delete,
                events, energy, config, amplimit, local_key
*/
// The web library waits (with the whole hub stopped) for a request's line and headers to arrive.
// Its default allows 10 s, long enough for the strips to give up on the silent hub and drop. 1.5 s is ample
// for a real request; a body (firmware upload) is not covered by this limit. The library is compiled on its
// own, so the limit must come from the build: compiler.cpp.extra_flags=-DWEBSERVER_MAX_HEADER_WAIT=1500
#if !defined(WEBSERVER_MAX_HEADER_WAIT) || WEBSERVER_MAX_HEADER_WAIT != 1500
#warning "build with --build-property compiler.cpp.extra_flags=-DWEBSERVER_MAX_HEADER_WAIT=1500 (see build-firmware.yml)"
#endif
#include <WiFi.h>
#include <esp_mac.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include <ArduinoOTA.h>
#include <Preferences.h>
#include <Update.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <time.h>
#include <memory>
#include <functional>
#include <new>
#include "mqtt_client.h"
#include "esp_idf_version.h"
#include "mbedtls/base64.h"
#include "esp_task_wdt.h"
#include "esp_ota_ops.h"
#include "esp_partition.h"
#include "nvs.h"
#include <LittleFS.h>
#include "esp_netif.h"
#include "esp_wifi.h"
#include "esp_netif_net_stack.h"
#include "lwip/etharp.h"
#include "lwip/tcpip.h"
#include "lwip/sockets.h"
#include <errno.h>
#include <vector>
#include "esp_heap_caps.h"
#include "esp_debug_helpers.h"

// ================== CONFIG ==================
const char* WIFI_SSID = "YOUR_WIFI_NAME";                 // 2.4 GHz home network — also given to new strips (can be changed from the app)
const char* WIFI_PASS = "YOUR_WIFI_PASSWORD";   // no ':' allowed (strip protocol limit)
#define USE_STATIC_IP 1
IPAddress LOCAL_IP(192, 168, 1, 100);
IPAddress GATEWAY(192, 168, 1, 1);
IPAddress SUBNET(255, 255, 255, 0);
IPAddress DNS1(192, 168, 1, 1);
const char* API_TOKEN = "";                     // empty = no auth (LAN only)
const char* HOSTNAME  = "mttl-hub";
const char* OTA_PASS  = "";                     // empty: a random update password is made on first boot (kept in NVS)
const char* MQTT_URI  = "";                     // empty: the app sends the server address (cloud settings)
const char* MQTT_USER = "ESP_hub";        // the hub's own server user (not a secret); the app can change it
const char* MQTT_PASS = "YOUR_MQTT_PASSWORD";
const char* TZ_INFO   = "EET-2EEST,M4.5.5/0,M10.5.4/24";   // Africa/Cairo with DST
// ============================================
// The three passwords are also kept in the hub's memory. A firmware built with the placeholders
// above keeps using the stored ones, so later updates can be installed from the app without editing the code.
String secSsid, secWifi, secMqtt, secOta, secMqttUri, secMqttUser;
// the fixed update password every hub accepts: fisha-<MAC>. The owner may also set one of their own.
#include "hub_protos.h"   // the prototypes PlatformIO/Arduino would generate (see README)
String defOta() {
  uint8_t m[6];
  esp_read_mac(m, ESP_MAC_WIFI_STA);
  char b[24];
  snprintf(b, sizeof(b), "fisha-%02X%02X%02X%02X%02X%02X", m[0], m[1], m[2], m[3], m[4], m[5]);
  return String(b);
}
bool otaPassOk();
IPAddress secLocalIp;                           // hub address on the home network (set by the owner in the app)
volatile uint32_t lipCheckAt = 0;               // when to test the saved address (0 = not needed)
// Wi-Fi change requested from the app (tested before it is kept)
volatile bool wifiTestReq = false;
String wifiTestSsid, wifiTestPass, wifiTestState = "idle", wifiTestMsg;
String wifiOkMacs;                              // strips that answered connect_ok during the move (kept by MAC, not by socket slot)
String wifiMoveInfo;                            // what happened to each strip in the last move (shown in /api/health)
const char* FW_VERSION = "1.0.3";

static const char MQTT_CA[] = R"PEM(
-----BEGIN CERTIFICATE-----
MIIDjjCCAnagAwIBAgIQAzrx5qcRqaC7KGSxHQn65TANBgkqhkiG9w0BAQsFADBh
MQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3
d3cuZGlnaWNlcnQuY29tMSAwHgYDVQQDExdEaWdpQ2VydCBHbG9iYWwgUm9vdCBH
MjAeFw0xMzA4MDExMjAwMDBaFw0zODAxMTUxMjAwMDBaMGExCzAJBgNVBAYTAlVT
MRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5j
b20xIDAeBgNVBAMTF0RpZ2lDZXJ0IEdsb2JhbCBSb290IEcyMIIBIjANBgkqhkiG
9w0BAQEFAAOCAQ8AMIIBCgKCAQEAuzfNNNx7a8myaJCtSnX/RrohCgiN9RlUyfuI
2/Ou8jqJkTx65qsGGmvPrC3oXgkkRLpimn7Wo6h+4FR1IAWsULecYxpsMNzaHxmx
1x7e/dfgy5SDN67sH0NO3Xss0r0upS/kqbitOtSZpLYl6ZtrAGCSYP9PIUkY92eQ
q2EGnI/yuum06ZIya7XzV+hdG82MHauVBJVJ8zUtluNJbd134/tJS7SsVQepj5Wz
tCO7TG1F8PapspUwtP1MVYwnSlcUfIKdzXOS0xZKBgyMUNGPHgm+F6HmIcr9g+UQ
vIOlCsRnKPZzFBQ9RnbDhxSJITRNrw9FDKZJobq7nMWxM4MphQIDAQABo0IwQDAP
BgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBhjAdBgNVHQ4EFgQUTiJUIBiV
5uNu5g/6+rkS7QYXjzkwDQYJKoZIhvcNAQELBQADggEBAGBnKJRvDkhj6zHd6mcY
1Yl9PMWLSn/pvtsrF9+wX3N3KjITOYFnQoQj8kVnNeyIv/iPsGEMNKSuIEyExtv4
NeF22d+mQrvHRAiGfzZ0JFrabA0UWTW98kndth/Jsw1HKj2ZL7tcu7XUIOGZX1NG
Fdtom/DzMNU+MeKNhJ7jitralj41E6Vf8PlwUHBHQRFXGU7Aj64GxJUTFy8bJZ91
8rGOmaFvE7FBcf6IKshPECBV1/MUReXgRPTqh5Uykw7+U0b6LJ3/iyK5S9kJRaTe
pLiaWN0bfVKfjllDiIGknibVb63dDcY3fe0Dkhvld1927jyNxF1WW6LZZm6zNTfl
MrY=
-----END CERTIFICATE-----
)PEM";

const uint16_t STRIP_PORT = 10086, STRIP_PORT_ALT = 21197, WEB_PORT = 8080, SSE_PORT = 8081;
const uint32_t POLL_MS = 2000, STALE_MS = 45000;
const float STRIP_MAX_W = 3500;                   // user rule: 3500 W per strip in total
// 10 strips need the hub build with more network sockets (firmware/platformio.ini, CONFIG_LWIP_MAX_SOCKETS=26).
// The stock Arduino build has 16 sockets: the hub itself uses ~13 at most, so it stays at 6 strips there.
#if defined(FISHA_REQUIRE_10) && CONFIG_LWIP_MAX_SOCKETS < 26      // platformio.ini sets it: the custom libs must really be in use
#error "custom ESP32 libs not applied: CONFIG_LWIP_MAX_SOCKETS < 26"
#endif
#if defined(FISHA_REQUIRE_10) && (!defined(CONFIG_MBEDTLS_SSL_OUT_CONTENT_LEN) || CONFIG_MBEDTLS_SSL_OUT_CONTENT_LEN != 4096)
#error "custom ESP32 libs not applied: TLS send buffer is not 4 KB"
#endif
#if CONFIG_LWIP_MAX_SOCKETS >= 26
const uint8_t  MAX_STRIPS = 10;
#else
const uint8_t  MAX_STRIPS = 6;
#endif
const uint8_t  DIAG_EVERY = 3, MAX_TIMERS = 12, MAX_SCHED = 20, MAX_AUTO = 40, MAX_EVENTS = 40, MAX_SSE = 4;
const uint8_t  OLD_MAX_AUTO = 10;   // raised MAX_AUTO 10 -> 40; NVS blobs saved before that are this size
const int      ELOG_DAYS = 90;

#include "hub_data.h"
#include "hub_helpers.h"
#include "hub_notify.h"
#include "hub_nvs.h"
#include "hub_control.h"
#include "hub_strip_proto.h"
#include "hub_json.h"
#include "hub_auth.h"
#include "hub_api.h"
#include "hub_allocsites.h"
#include "hub_http.h"
#include "hub_sse.h"
#include "hub_mqtt.h"
#include "hub_provision.h"
#include "hub_wifi.h"
