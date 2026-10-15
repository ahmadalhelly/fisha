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
struct ApiRes;
struct OwnerDev;
struct PairReq;

/*
  Fisha Hub v2.13.2 — ESP32 local controller + cloud relay for LG U+ MTTL-W01 smart strips
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
                events, energy, config, amplimit (v2.11), local_key (v2.11, shared users)

  v2.11: the loop never blocks on a phone/strip that stopped reading (asleep, out of range, unplugged):
         every socket write is non-blocking and a stuck peer is dropped instead of freezing the hub for
         10 s per write. Phone notifications (ntfy) run in their own task. Wi-Fi loss no longer reboots
         the hub after 60 s. Under-voltage limit, per-outlet current limit, near-limit warnings,
         current (A) automations, and shared users can talk to the hub directly on the home Wi-Fi.
  v2.13.1: also listens on TCP 21197 (strips after the Oct 2026 OTA), default IP 192.168.1.100.
  v2.13.2: no passwords in the source (placeholders; the hub keeps the stored ones, the app pushes the
           server password), SSE matches shared users by exact u=/t= before treating a client as owner.
  v2.14.0: over-voltage protection is always on and cuts the whole strip, protected outlets included;
           the protection switch now only turns the under-voltage cut on/off (limit 170..260 V).
  v2.14.1: the "strip offline" event keeps why it dropped (disconnected / stale); schedules and automations
           are only saved for a strip the hub knows, with thresholds kept in a sane range.
  v2.14.13: strip firmware flashing from the hub (/stripfw): the .fwr is kept in the spare OTA slot, the hub joins
            the strip's setup network, sends up:ota:192.168.1.2 and serves GET /ota.bin on port 80 itself
            (a Windows PC with Bitdefender dropped the strip's inbound connection).
  v2.14.14: /stripfw only auto-refreshes while a flash runs (it cleared the chosen file).
  v2.15.0: automations are armed as soon as they are saved and after every reboot (a load already past the
           limit never tripped before); the hub reports a storage id ("nvs") that changes when its saved data
           is erased, so the app can put family members, schedules and rules back; family members can be
           exported and restored with their own passwords (users_export / user_restore, owner only).
  v2.15.4: events made while the cloud link is down are kept (newest 12) and sent when it is back, so phone
           notifications are no longer lost on a Wi-Fi blip or an MQTT reconnect.
  v2.15.3: diagnostics only: each loss of the home Wi-Fi is logged as a "wifi" event (ESP-IDF reason code and
           seconds offline); /api/health adds wifi_drops and wifi_reason. Nothing else changes.
  v2.15.8: strips can be updated over their normal hub connection (stock 1.0.66 accepts up:ota there): pick strips
           (or all) on /stripfw or POST /api/stripfw/start; the hub serves the stored .fwr on :80, one strip at a
           time, waits for it to come back and checks the version in bootinfo, and stops at the first failure.
           An uploaded .fwr is checked (16-byte header, load address 0x10006000, length, checksum) and refused if bad.
           The watchdog is armed at the very start of boot (a hang while booting needed the reset button).
           A loop step that blocks 5 s or more is logged as a "stall" event (step name + seconds); /api/health adds
           stall_max_ms / stall_where. Every home Wi-Fi drop is logged even when the hub reconnects between two loop
           passes (counted from the Wi-Fi driver, not from the loop). A failed NVS save is logged ("save_fail").
  v2.15.7: energy and peak history moved from NVS to files (LittleFS on the unused SPIFFS partition); old data is
           moved over on first boot and its NVS entries freed. NVS was 500/630 full and saves had started to fail.
  v2.15.6: Wi-Fi settings are kept in RAM, not NVS (with NVS full the strip join failed: ESP_ERR_NVS_NOT_ENOUGH_SPACE);
           the strip's setup network is also recognised by its BSSID; /api/health adds nvs_used/nvs_free/nvs_total.
  v2.15.5: the strip flasher listens on port 80 before sending up:ota (the strip dials it ~0.1 s after ota_ok).
  v2.15.2: a strip is no longer dropped when one send is slow for a moment: unsent bytes wait (same bytes, same
           order, no protocol change) and the strip is dropped only after 3 s stuck; that drop is now logged as an
           "offline" event too ("socket stuck"). Live push (SSE) sends the state without extra copies and without
           blocking. Saving or deleting a schedule/automation pushes the state at once (outlet badges were stale).
           /api/health adds heap_min and sse (connected live clients).
  v2.15.1: a schedule can skip just its next run (schedule_skip, kept under its own NVS key so saved
           schedules keep their layout); a skipped run is logged as a "skipped" event.
           The strip protocol (ports 10086/21197, setup AP flow) is unchanged.
*/
// v2.15.23: a master "all on/off" no longer touches a child-locked outlet at all (lockSkip) - it used to race
// with the lock's own enforcement resend and could keep the OTHER outlets from responding to the master switch too.
// v2.15.23: the hub scans for a known strip's own setup network (TONLY_TAP_...) every 90 s while any known strip
// is offline, and re-links it automatically once seen — no "Add strip" tap needed after a router change. See
// autoResyncScan(). Logged as a "resync" event.
// v2.15.22: automations go from 10 to 40 (MAX_AUTO); NVS blobs saved under the old cap migrate on first boot.
// v2.15.22: the hub can fetch a strip .fwr itself over HTTP(S) (POST /api/stripfw/fetch {"url":...}) and flash it
// the same way as an uploaded file — the bytes never pass through the phone. Manual upload still works unchanged.
// v2.15.20: the owner sets the hub address in the app (cloud settings "lip"; stored in NVS, the hub restarts to use it).
// If the router does not answer on that address within a minute of boot, the hub goes back to the default address.
// The hub server user defaults to ESP_hub.
// v2.15.19: no secrets in the firmware. Update password is random per hub (NVS). Server address and user come from the app
// (cloud settings). The first owner claim needs no password; later phones pair. The setup Wi-Fi network is open. BETA.
// v2.15.18: the web library waits (with the whole hub stopped) for a request's line and headers to arrive.
// Its default allows 10 s, long enough for the strips to give up on the silent hub and drop. 1.5 s is ample
// for a real request; a body (firmware upload) is not covered by this limit. The library is compiled on its
// own, so the limit must come from the build: compiler.cpp.extra_flags=-DWEBSERVER_MAX_HEADER_WAIT=1500
#if !defined(WEBSERVER_MAX_HEADER_WAIT) || WEBSERVER_MAX_HEADER_WAIT != 1500
#warning "build with --build-property compiler.cpp.extra_flags=-DWEBSERVER_MAX_HEADER_WAIT=1500 (see build-firmware.yml)"
#endif
#include <WiFi.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include <ArduinoOTA.h>
#include <Preferences.h>
#include <Update.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <time.h>
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
// From v2.3 the three passwords are also kept in the hub's memory. A firmware built with the placeholders
// above keeps using the stored ones, so later updates can be installed from the app without editing the code.
String secSsid, secWifi, secMqtt, secOta, secMqttUri, secMqttUser;
IPAddress secLocalIp;                           // hub address on the home network (set by the owner in the app)
volatile uint32_t lipCheckAt = 0;               // when to test the saved address (0 = not needed)
// Wi-Fi change requested from the app (tested before it is kept)
volatile bool wifiTestReq = false;
String wifiTestSsid, wifiTestPass, wifiTestState = "idle", wifiTestMsg;
const char* FW_VERSION = "2.15.23";

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
const float STRIP_MAX_W = 3500;                   // v2.15.9 user rule: 3500 W per strip in total
const uint8_t  DIAG_EVERY = 3, MAX_STRIPS = 6, MAX_TIMERS = 12, MAX_SCHED = 20, MAX_AUTO = 40, MAX_EVENTS = 40, MAX_SSE = 4;
const uint8_t  OLD_MAX_AUTO = 10;   // v2.15.22 raised MAX_AUTO 10 -> 40; NVS blobs saved before that are this size
const int      ELOG_DAYS = 90;

// ---------- data ----------
struct Outlet { bool on = false; float powerW = 0; uint32_t energyWh = 0; int tempC = 0; };

struct ELog {                                    // per-strip daily energy history (Wh)
  uint32_t magic = 0;
  int32_t day = 0;                               // local day number of the running bucket
  uint32_t base[4] = {0, 0, 0, 0};               // counters at the start of that day
  uint32_t wh[ELOG_DAYS][4];
  int32_t dayOf[ELOG_DAYS];
};

struct PeakLog {                                 // per-strip daily highest total load (W)
  uint32_t magic = 0;
  int32_t day = 0;
  uint16_t today = 0;
  uint16_t pk[ELOG_DAYS];
  int32_t dayOf[ELOG_DAYS];
};

struct Strip {
  WiFiClient c;
  bool used = false, identified = false, hasRssi = false, gotInfo = false, poked = false;
  String mac, model, fw, ip, rx, pendingInfo, lastLine;
  String label, olabel[4];
  uint8_t lockMask = 0, lockState = 0, protMask = 0, notifyMask = 0x1F;
  uint8_t keepMask = 0, keepHold = 0;            // v2.8 keep always on · hold = a safety cut is in force
  uint32_t keepEvAt[4] = {0, 0, 0, 0};
  uint16_t autoOffMin[4] = {0, 0, 0, 0};
  uint32_t autoOffAt[4] = {0, 0, 0, 0};
  uint32_t hotSince[4] = {0, 0, 0, 0};
  uint32_t loadEventAt = 0, voltEventAt = 0;
  uint32_t ocSince = 0, vOkSince = 0;            // v2.10 over-current timer · voltage back to normal since
  uint8_t ovCount = 0, vCutMask = 0;             // consecutive high readings · outlets cut for over-voltage
  uint8_t ampX2[4] = {0, 0, 0, 0};               // v2.11 per-outlet current limit in 0.5 A steps (0 = none)
  uint32_t ocoSince[4] = {0, 0, 0, 0};           // per-outlet over-current timer
  uint8_t warnA = 0, warnT = 0;                  // near-limit warning already sent (bit per outlet): current · temperature
  uint8_t tripMask = 0, tripTries[4] = {0, 0, 0, 0}; // v2.15.9 safety cuts still waiting for the strip to report "off"
  uint32_t tripAt = 0, tripSeq = 0, olSince = 0; // last safety cut sent (time, infoSeq) · over 3500 W since
  bool dead = false;                             // a write could not go out: dropped on the next pump
  String txq;                                    // v2.15.2: bytes still waiting to go out to the strip (same bytes, same order)
  uint32_t txSince = 0;                          // when txq started waiting
  float voltage = NAN;
  int rssi = 0;
  Outlet o[4];
  uint32_t lastRx = 0, infoSeq = 0, connectedAt = 0;
  uint32_t cmdAt[4] = {0, 0, 0, 0};              // when the hub last switched each outlet (to tell button presses apart)
};

struct Timer { bool used = false; uint32_t id = 0; char mac[13] = {0}; uint8_t outlet = 0, kind = 0, phase = 0; bool on = false;
               uint32_t at = 0, offMs = 0, onMs = 0, periodS = 0, tries = 0; };
// kind: 0 = switch on/off (once, or every periodS), 1 = reboot: off, wait, on (once, or every periodS),
//       2 = loop: on for onMs, off for offMs, forever. All kept in NVS, so they survive a hub restart.
struct TimerNV { uint32_t id; char mac[13]; uint8_t outlet, kind, on, phase; uint32_t offS, onS, periodS, dueEpoch, remainS; };
struct Known { String mac, label, olabel[4]; uint8_t lock, prot, notify, keep; uint8_t amp[4]; };

struct Sched { uint32_t id; char mac[13]; uint8_t outlet, on, days, hh, mm, enabled; uint32_t date; char label[40]; };
struct AutomV2 { uint32_t id; char mac[13]; uint8_t outlet, above, act, enabled; float watts; uint16_t holdS; char label[40]; uint8_t metric; };
struct Autom { uint32_t id; char mac[13]; uint8_t outlet, above, act, enabled; float watts; uint16_t holdS; char label[40]; uint8_t metric; float limit2; };
// metric 2 = watts OR temperature: "watts" is the W limit and "limit2" the °C limit
// outlet 0 = whole strip (total W / hottest outlet) · metric 0 = power (W), 1 = temperature (°C), 3 = current (A, v2.11) · "watts" holds the threshold
// act: 1 notify, 2 switch off, 3 both
struct Ev { uint32_t ts = 0; String type, mac, msg; int outlet = 0; };
struct ApiRes { bool ok; String err; String data; };
struct Note { String type, mac, msg; int outlet; };   // queued phone notification (defined early for Arduino auto-prototypes)
struct NoteMsg { char topic[68]; char title[200]; char body[160]; uint8_t high; };   // handed to the notification task
// v2.9 shared users (hub-managed, EMQX built-in auth + ACL). role 0 view · 1 control · 2 admin
struct HubUser { char id[8]; char name[24]; uint8_t role, all, n, rsv; char strips[6][13]; char pw[20]; };
struct UsersNV { uint32_t magic; uint8_t count; HubUser u[10]; };

Strip strips[MAX_STRIPS];
ELog elogs[MAX_STRIPS];
PeakLog peaks[MAX_STRIPS];
uint32_t peakSavedAt[MAX_STRIPS];
Timer timers[MAX_TIMERS];
Sched scheds[MAX_SCHED];
uint32_t schedSkip[MAX_SCHED];                    // v2.15.0: ids whose next run is skipped once (own NVS key, Sched layout unchanged)
uint8_t schedCount = 0;
Autom autos[MAX_AUTO];
uint8_t autoCount = 0;
bool autoArmed[MAX_AUTO];
bool autoWarned[MAX_AUTO];                         // v2.11 near-limit warning sent for this crossing
uint32_t autoSince[MAX_AUTO];
Ev events[MAX_EVENTS];
uint8_t evHead = 0, evCount = 0;
uint32_t nextTimerId = 1;
uint8_t tempMax = 70;
bool tempProtect = true;
// v2.10 whole-strip protections
bool vProt = true, vRestore = true, aProt = true;
uint16_t vMax = 250;
uint16_t vMin = 190;                               // v2.11 under-voltage limit (170..260)
float aMax = 16.0f;
volatile uint32_t rebootAt = 0;

WiFiServer stripServer(STRIP_PORT);
WiFiServer stripServerAlt(STRIP_PORT_ALT);   // strips that switched to 21197 (2026-10-08)
WiFiServer sseServer(SSE_PORT);
WebServer web(WEB_PORT);
Preferences cfg;
bool webRoutesReady = false;
bool stripListenerReady = false;
bool wifiWasConnected = false;
volatile uint8_t wifiLastReason = 0;    // v2.15.3: why the hub last lost the home Wi-Fi (ESP-IDF reason code)
volatile uint32_t wifiDiscCount = 0;    // v2.15.3: home Wi-Fi disconnects since boot (outside provisioning)
volatile uint32_t wifiDiscAt = 0;       // v2.15.8: millis() of the last of those disconnects
uint32_t stallMaxMs = 0;                // v2.15.8: longest single loop step since boot, and which one
const char* stallWhere = "";
// v2.15.15: the slowest blocking call inside the current loop step (named in the "stall" event) and since boot (health)
uint32_t subMax = 0, subWorst = 0;
const char* subWhere = "";
const char* subWorstWhere = "";
String webUri;                          // v2.15.16: the request the web step was answering (named in a "web" stall)
uint32_t webSlow = 0;                   // v2.15.16: answers cut short because the phone stopped reading
struct SubT {
  const char* n; uint32_t t;
  SubT(const char* n_) : n(n_), t(millis()) {}
  ~SubT() {
    uint32_t d = millis() - t;
    if (d > subMax) { subMax = d; subWhere = n; }
    if (d > subWorst) { subWorst = d; subWorstWhere = n; }
  }
};
uint32_t lastPoll = 0, pollCount = 0;
volatile bool stateDirty = true;

// MQTT
struct MqttCmd { char payload[640]; char topic[96]; };
esp_mqtt_client_handle_t mqtt = nullptr;
QueueHandle_t mqttQ = nullptr;
volatile bool mqttUp = false, mqttFreshConnect = false;
String nvsId;                                     // v2.15.0: changes only when the saved data is erased
String hubId, tStatus, tInfo, tState, tEvent, tCmd, tAck;
char mqttClientId[32];
// v2.9: why the cloud link is down, and who sent the command being handled
volatile int mqttErrKind = 0, mqttErrCode = 0, mqttErrTls = 0;   // written by the MQTT task
String mqttErr = "";                                               // "" | no_pass | auth | refused | tls | net
volatile bool mqttRestartReq = false;
uint8_t apiSrc = 0;                                                // 0 local HTTP · 1 owner MQTT · 2 shared user
const uint8_t MAX_USERS = 10;
HubUser users[MAX_USERS];
// v2.15.13: hub lock. Owner phones hold a secret key; with no owner the hub stays open as before, so older apps keep
// working until the owner locks it from the app. A new phone asks for access and the owner approves by picking the
// number shown on that phone (one of 3), so a stranger on the Wi-Fi can't slip in by accident.
struct OwnerDev { char key[33]; char email[48]; char model[32]; uint32_t ts; };
const uint8_t MAX_OWNERS = 4, MAX_PAIRS = 3;
OwnerDev owners[MAX_OWNERS];
uint8_t ownerCount = 0;
struct PairReq { uint32_t id = 0, at = 0; uint8_t code = 0, ch[3] = {0, 0, 0}, state = 0; bool owner = false, job = false;
                 String email, model, result; };   // state: 0 free · 1 waiting for the owner · 2 approved · 3 refused
PairReq pairs[MAX_PAIRS];
uint32_t pairJobId = 0, claimLockUntil = 0, cloudTodoAt = 0;
String cloudTodoId, cloudTodoPw;                   // v2.15.14: an approved phone's server login, made in the background
uint8_t claimFails = 0;
uint8_t userCount = 0;
String exUrl, exKey, exSec, exLast;                                // EMQX management API (NVS "sec"), never returned

// provisioning
volatile bool provRequested = false;
uint32_t provAt = 0;
String provState = "idle", provMsg = "", provSsid = "", provTarget = "";   // provTarget = last 7 hex of the new strip's MAC
// v2.14.13: strip firmware (.fwr) kept raw in the spare OTA app slot, served to a strip in setup mode
bool provOta = false;                  // this provisioning run flashes the strip instead of pointing it at the hub
uint32_t stripFwSize = 0;              // bytes of the stored .fwr (0 = none), also in NVS "stripfw"/"size"
const uint32_t STRIP_FW_MAX = 0x60000; // 384 KB; stock .fwr files are ~320 KB
String stripOtaLog = "";               // last flash run, shown on /stripfw
bool stripFwOk = false;                // v2.15.8: the stored file passed stripFwCheck
String stripFwWhy = "";
struct SuItem { String mac, from, to, state, msg; };   // state: queued, sending, transfer, rebooting, ok, failed, skipped
SuItem suList[MAX_STRIPS];
uint8_t suN = 0, suCur = 0;
enum SuPhase : uint8_t { SU_IDLE, SU_SEND, SU_GET, SU_XFER, SU_BACK, SU_GAP };
SuPhase suPhase = SU_IDLE;
uint32_t suT0 = 0, suOff = 0, suDoneAt = 0, suReqAt = 0;
WiFiServer suSrv(80);
WiFiClient suCli;
String suReq;
bool suCancel = false;
uint8_t suBuf[1460];
uint16_t suBufLen = 0, suBufPos = 0;
bool suRunning();
const esp_partition_t* stripFwPart();

// ---------- helpers ----------
std::vector<String> split(const String& s, char sep) {
  std::vector<String> out;
  int start = 0;
  for (int i = 0; i <= (int)s.length(); i++) {
    if (i == (int)s.length() || s[i] == sep) { out.push_back(s.substring(start, i)); start = i + 1; }
  }
  return out;
}

bool isHex(const String& s) {
  if (!s.length()) return false;
  for (char ch : s) if (!isxdigit((unsigned char)ch)) return false;
  return true;
}

String jsonEsc(const String& v) {
  String o;
  o.reserve(v.length() + 4);
  for (size_t i = 0; i < v.length(); i++) {
    char c = v[i];
    if (c == '"' || c == '\\') { o += '\\'; o += c; }
    else if ((uint8_t)c < 0x20) o += ' ';
    else o += c;
  }
  return o;
}

// Small JSON reader for API objects. It handles escaped strings and skips nested values safely.
void jsonSkipWs(const String& body, int& p) {
  while (p < (int)body.length() && isspace((unsigned char)body[p])) p++;
}

int jsonHex(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

void jsonAppendUtf8(String& out, uint32_t cp) {
  if (cp <= 0x7F) out += (char)cp;
  else if (cp <= 0x7FF) { out += (char)(0xC0 | (cp >> 6)); out += (char)(0x80 | (cp & 0x3F)); }
  else if (cp <= 0xFFFF) { out += (char)(0xE0 | (cp >> 12)); out += (char)(0x80 | ((cp >> 6) & 0x3F)); out += (char)(0x80 | (cp & 0x3F)); }
  else { out += (char)(0xF0 | (cp >> 18)); out += (char)(0x80 | ((cp >> 12) & 0x3F)); out += (char)(0x80 | ((cp >> 6) & 0x3F)); out += (char)(0x80 | (cp & 0x3F)); }
}

bool jsonReadString(const String& body, int& p, String& out) {
  if (p >= (int)body.length() || body[p++] != '"') return false;
  out = "";
  while (p < (int)body.length()) {
    unsigned char c = (unsigned char)body[p++];
    if (c == '"') return true;
    if (c < 0x20) return false;
    if (c != '\\') { out += (char)c; continue; }
    if (p >= (int)body.length()) return false;
    char esc = body[p++];
    if (esc == '"' || esc == '\\' || esc == '/') out += esc;
    else if (esc == 'b') out += '\b';
    else if (esc == 'f') out += '\f';
    else if (esc == 'n') out += '\n';
    else if (esc == 'r') out += '\r';
    else if (esc == 't') out += '\t';
    else if (esc == 'u') {
      if (p + 4 > (int)body.length()) return false;
      uint32_t cp = 0;
      for (int i = 0; i < 4; i++) { int h = jsonHex(body[p++]); if (h < 0) return false; cp = (cp << 4) | h; }
      if (cp >= 0xD800 && cp <= 0xDBFF && p + 6 <= (int)body.length() && body[p] == '\\' && body[p + 1] == 'u') {
        int q = p + 2;
        uint16_t low = 0;
        bool valid = true;
        for (int i = 0; i < 4; i++) { int h = jsonHex(body[q++]); if (h < 0) { valid = false; break; } low = (low << 4) | h; }
        if (valid && low >= 0xDC00 && low <= 0xDFFF) { cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00); p = q; }
        else jsonAppendUtf8(out, 0xFFFD);
      } else if (cp >= 0xDC00 && cp <= 0xDFFF) jsonAppendUtf8(out, 0xFFFD);
      else jsonAppendUtf8(out, cp);
    } else return false;
  }
  return false;
}

void jsonSkipValue(const String& body, int& p) {
  if (p >= (int)body.length()) return;
  if (body[p] == '"') { String ignored; jsonReadString(body, p, ignored); return; }
  if (body[p] == '{' || body[p] == '[') {
    int depth = 0;
    bool inString = false, escaped = false;
    while (p < (int)body.length()) {
      char c = body[p++];
      if (inString) { if (escaped) escaped = false; else if (c == '\\') escaped = true; else if (c == '"') inString = false; continue; }
      if (c == '"') inString = true;
      else if (c == '{' || c == '[') depth++;
      else if (c == '}' || c == ']') { if (--depth == 0) return; }
    }
    return;
  }
  while (p < (int)body.length() && body[p] != ',' && body[p] != '}') p++;
}

bool jsonFindMember(const String& body, const char* key, int& valueAt) {
  int p = body.indexOf('{');
  if (p < 0) return false;
  p++;
  while (p < (int)body.length()) {
    jsonSkipWs(body, p);
    if (p >= (int)body.length() || body[p] == '}') return false;
    String name;
    if (!jsonReadString(body, p, name)) return false;
    jsonSkipWs(body, p);
    if (p >= (int)body.length() || body[p++] != ':') return false;
    jsonSkipWs(body, p);
    if (name == key) { valueAt = p; return true; }
    jsonSkipValue(body, p);
    jsonSkipWs(body, p);
    if (p >= (int)body.length() || body[p] != ',') return false;
    p++;
  }
  return false;
}

// Returns decoded strings and trimmed JSON text for booleans, numbers, arrays, and objects.
String jsonValue(const String& body, const char* key) {
  int p = 0;
  if (!jsonFindMember(body, key, p)) return "";
  if (p < (int)body.length() && body[p] == '"') { String value; return jsonReadString(body, p, value) ? value : ""; }
  int start = p;
  jsonSkipValue(body, p);
  String value = body.substring(start, p);
  value.trim();
  return value;
}
bool jsonHas(const String& body, const char* key) { int p = 0; return jsonFindMember(body, key, p); }
bool jsonBool(const String& body, const char* key) { String v = jsonValue(body, key); return v == "true" || v == "1"; }

bool timeOk() { return time(nullptr) > 1700000000; }

// days since 1970-01-01 for a civil date (Howard Hinnant)
int32_t daysFromCivil(int y, unsigned m, unsigned d) {
  y -= m <= 2;
  const int era = (y >= 0 ? y : y - 399) / 400;
  const unsigned yoe = (unsigned)(y - era * 400);
  const unsigned doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
  const unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  return era * 146097 + (int32_t)doe - 719468;
}
uint32_t civilFromDays(int32_t z) {              // -> yyyymmdd
  z += 719468;
  const int era = (z >= 0 ? z : z - 146096) / 146097;
  const unsigned doe = (unsigned)(z - era * 146097);
  const unsigned yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
  int y = (int)yoe + era * 400;
  const unsigned doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
  const unsigned mp = (5 * doy + 2) / 153;
  const unsigned d = doy - (153 * mp + 2) / 5 + 1;
  const unsigned m = mp + (mp < 10 ? 3 : -9);
  y += (m <= 2);
  return (uint32_t)y * 10000 + m * 100 + d;
}
bool localNow(struct tm& t) {
  if (!timeOk()) return false;
  time_t now = time(nullptr);
  localtime_r(&now, &t);
  return true;
}
int32_t localDay() {
  struct tm t;
  if (!localNow(t)) return 0;
  return daysFromCivil(t.tm_year + 1900, t.tm_mon + 1, t.tm_mday);
}

int findStrip(const String& macIn) {
  String mac = macIn; mac.toUpperCase();
  for (int i = 0; i < MAX_STRIPS; i++)
    if (strips[i].used && strips[i].identified && strips[i].mac == mac) return i;
  return -1;
}
int firstStrip() {
  for (int i = 0; i < MAX_STRIPS; i++) if (strips[i].used && strips[i].identified) return i;
  return -1;
}
int stripFor(const String& mac) { return mac.length() ? findStrip(mac) : firstStrip(); }

// ---------- non-blocking socket writes (v2.11) ----------
// WiFiClient::write() waits up to 10 x 1 s for room in the send buffer. A phone that went to sleep with the
// live page open, or a strip that lost power, never drains it, so every write froze the whole hub for seconds:
// strips went stale and dropped, keep-on/lock reverts and schedules were late. These writes give up quickly.
bool sendNB(WiFiClient& c, const char* p, size_t len, uint32_t maxMs) {
  int fd = c.fd();
  if (fd < 0 || !c.connected()) return false;
  uint32_t t0 = millis();
  while (len) {
    int r = lwip_send(fd, p, len, MSG_DONTWAIT);
    if (r > 0) { p += r; len -= r; continue; }
    if (r < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) && millis() - t0 < maxMs) { delay(1); continue; }
    return false;
  }
  return true;
}
bool sendStr(WiFiClient& c, const String& s, uint32_t maxMs) { return sendNB(c, s.c_str(), s.length(), maxMs); }
// v2.15.2: like sendNB but reports how much went out (-1 = the socket is broken), so the rest can wait
int sendSome(WiFiClient& c, const char* p, size_t len, uint32_t maxMs) {
  int fd = c.fd();
  if (fd < 0 || !c.connected()) return -1;
  SubT st("sock_send");
  uint32_t t0 = millis();
  int sent = 0;
  while (len) {
    int r = lwip_send(fd, p, len, MSG_DONTWAIT);
    if (r > 0) { p += r; len -= r; sent += r; continue; }
    if (r < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
      if (millis() - t0 < maxMs) { delay(1); continue; }
      return sent;
    }
    return -1;
  }
  return sent;
}

// TCP keep-alive so a peer that vanished without closing is noticed in ~25 s
void tcpKeepAlive(WiFiClient& c) {
  int fd = c.fd();
  if (fd < 0) return;
  int on = 1, idle = 10, intvl = 5, cnt = 3;
  lwip_setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, &on, sizeof on);
  lwip_setsockopt(fd, IPPROTO_TCP, TCP_KEEPIDLE, &idle, sizeof idle);
  lwip_setsockopt(fd, IPPROTO_TCP, TCP_KEEPINTVL, &intvl, sizeof intvl);
  lwip_setsockopt(fd, IPPROTO_TCP, TCP_KEEPCNT, &cnt, sizeof cnt);
}

// v2.15.2: a send that is slow for a moment (hub busy, Wi-Fi retry, low memory) no longer drops the strip.
// What did not go out waits in txq and is sent from pumpStrips(); the strip is dropped only if it stays
// stuck for TX_STUCK_MS or the backlog grows past TX_MAX. The bytes on the wire are unchanged.
const uint32_t TX_STUCK_MS = 3000;
const size_t TX_MAX = 2048;
bool flushTx(Strip& s, uint32_t maxMs) {
  if (!s.txq.length()) { s.txSince = 0; return true; }
  int n = sendSome(s.c, s.txq.c_str(), s.txq.length(), maxMs);
  if (n < 0) { s.dead = true; return false; }
  if (n) s.txq.remove(0, n);
  if (!s.txq.length()) { s.txSince = 0; return true; }
  if (!s.txSince) s.txSince = millis();
  if (millis() - s.txSince > TX_STUCK_MS) {
    s.dead = true;                               // dropped by pumpStrips(), the strip re-dials by itself
    Serial.printf("[tx %s] stuck %u ms, dropping\n", s.mac.length() ? s.mac.c_str() : s.ip.c_str(), (unsigned)(millis() - s.txSince));
  }
  return false;
}

void sendLine(Strip& s, const String& line) {
  if (s.dead || !s.c.connected()) return;
  if (s.txq.length() + line.length() + 2 > TX_MAX) {
    s.dead = true;
    Serial.printf("[tx %s] backlog full, dropping\n", s.mac.length() ? s.mac.c_str() : s.ip.c_str());
    return;
  }
  s.txq += line + "\r\n";
  if (!flushTx(s, 150) && !s.dead)
    Serial.printf("[tx %s] slow, %u bytes waiting\n", s.mac.length() ? s.mac.c_str() : s.ip.c_str(), s.txq.length());
  Serial.printf("[tx %s] %s\n", s.mac.length() ? s.mac.c_str() : s.ip.c_str(), line.c_str());
}

void mqttPub(const String& topic, const String& payload, int qos, bool retain);
void sseSend(const char* ev, const String& data);
void sseEvent(const String& data, const String& mac);

// ---------- phone notifications through ntfy (free, works while the app is closed) ----------
String ntfyTopic;
uint32_t notifyTypes = 0xFFFFFFFF;
const char* EV_TYPES[] = {"temp", "load", "auto_off", "automation", "schedule", "missed", "timer", "cycle", "lock", "added", "test",
                          "button", "remote", "online", "offline", "voltage", "overvolt", "overcurrent", "undervolt", "warn", "trip_fail", "overload"};
const int EV_COUNT = 22;
Note notes[6];
uint8_t noteCount = 0;
volatile bool tlsBusy = false;                    // the EMQX job holds the only spare TLS session
int stripFor(const String& mac);
int typeBit(const String& t) { for (int i = 0; i < EV_COUNT; i++) if (t == EV_TYPES[i]) return i; return -1; }

void queueNotify(const String& type, const String& mac, int outlet, const String& msg) {
  if (!ntfyTopic.length()) return;
  int bit = typeBit(type);
  // v2.15.9: a safety cut always reaches the phone. These types have no switch in the app, and an old app could save
  // notifyTypes without their bits, so they were never sent.
  bool safety = type == "overvolt" || type == "undervolt" || type == "overcurrent" || type == "overload" || type == "trip_fail" || type == "pair";
  if (!safety && type != "test" && (bit < 0 || !(notifyTypes & (1UL << bit)))) return;
  if (!safety && mac.length()) {
    int idx = stripFor(mac);
    if (idx >= 0) {
      uint8_t m = strips[idx].notifyMask;
      if (outlet == 0 ? !(m & 0x10) : !(m & (1 << (outlet - 1)))) return;
    }
  }
  if (noteCount >= 6) return;
  notes[noteCount++] = {type, mac, msg, outlet};
}

String noteTitle(const Note& n) {
  String who;
  int idx = n.mac.length() ? stripFor(n.mac) : -1;
  if (idx >= 0) {
    who = strips[idx].label.length() ? strips[idx].label : "MTTL " + strips[idx].mac.substring(8);
    if (n.outlet >= 1 && n.outlet <= 4) who += " - " + (strips[idx].olabel[n.outlet - 1].length() ? strips[idx].olabel[n.outlet - 1] : "Outlet " + String(n.outlet));
  }
  const char* t = n.type == "temp" ? "High temperature - turned off" : n.type == "load" ? "High load" : n.type == "auto_off" ? "Auto-off"
                : n.type == "automation" ? "Rule triggered" : n.type == "schedule" ? "Schedule ran" : n.type == "missed" ? "Missed (strip offline)"
                : n.type == "timer" ? "Timer ran" : n.type == "cycle" ? "Rebooted" : n.type == "lock" ? "Child lock reverted a button press"
                : n.type == "added" ? "New strip connected" : n.type == "button" ? "Switched on the strip"
                : n.type == "remote" ? "Switched from the app" : n.type == "online" ? "Strip back online" : n.type == "offline" ? "Strip offline"
                : n.type == "voltage" ? "Unusual voltage" : n.type == "overvolt" ? "High voltage - strip turned off"
                : n.type == "undervolt" ? "Low voltage - strip turned off" : n.type == "warn" ? "Close to the safety limit"
                : n.type == "overcurrent" ? "Over current - turned off" : n.type == "trip_fail" ? "Safety cut not confirmed - check the strip"
                : n.type == "overload" ? "Over 3500 W - biggest loads turned off"
                : n.type == "pair" ? "A new phone wants access - open Fisha to approve"
                : "Test notification";
  return who.length() ? String(t) + " | " + who : String(t);
}

// v2.11: the HTTPS call runs in its own task. On the loop it froze switching for 1-3 s per notification,
// and up to 2 minutes when the internet was slow (no handshake timeout).
QueueHandle_t noteQ = nullptr;
static void noteTask(void*) {
  static NoteMsg m;
  for (;;) {
    if (xQueueReceive(noteQ, &m, portMAX_DELAY) != pdTRUE) continue;
    if (WiFi.status() != WL_CONNECTED) continue;
    // TLS needs ~40 kB in one piece next to the MQTT session; fall back to plain HTTP rather than starve the hub
    bool tls = !tlsBusy && ESP.getMaxAllocHeap() > 45000;
    WiFiClientSecure sc;
    WiFiClient pc;
    HTTPClient http;
    http.setConnectTimeout(5000);
    http.setTimeout(5000);
    http.setReuse(false);
    bool ok;
    if (tls) {
      sc.setInsecure();                         // public push relay; the message carries no secrets
      sc.setHandshakeTimeout(8);
      ok = http.begin(sc, String("https://ntfy.sh/") + m.topic);
    } else ok = http.begin(pc, String("http://ntfy.sh/") + m.topic);
    if (!ok) continue;
    http.addHeader("Title", m.title);
    http.addHeader("Tags", m.high ? "warning" : "electric_plug");
    if (m.high) http.addHeader("Priority", "high");
    int code = http.POST(String(m.body));
    http.end();
    Serial.printf("[notify] %s -> %d%s\n", m.title, code, tls ? "" : " (http)");
    vTaskDelay(pdMS_TO_TICKS(700));
  }
}

void sendNotes() {
  if (!noteCount || !ntfyTopic.length() || provRequested || provState == "running") return;
  if (!noteQ) {
    noteQ = xQueueCreate(6, sizeof(NoteMsg));
    if (!noteQ || xTaskCreatePinnedToCore(noteTask, "ntfy", 10240, nullptr, 1, nullptr, 0) != pdPASS) { noteCount = 0; return; }
  }
  if (uxQueueSpacesAvailable(noteQ) == 0) return;
  Note n = notes[0];
  for (int i = 1; i < noteCount; i++) notes[i - 1] = notes[i];
  noteCount--;
  static NoteMsg m;
  memset(&m, 0, sizeof m);
  strlcpy(m.topic, ntfyTopic.c_str(), sizeof m.topic);
  strlcpy(m.title, noteTitle(n).c_str(), sizeof m.title);
  strlcpy(m.body, n.msg.length() ? n.msg.c_str() : "Fisha Hub", sizeof m.body);
  m.high = n.type == "temp" || n.type == "load" || n.type == "overvolt" || n.type == "undervolt" || n.type == "overcurrent" || n.type == "warn" || n.type == "trip_fail" || n.type == "overload";
  xQueueSend(noteQ, &m, 0);
}

// v2.15.4: an event made while the cloud link is down (Wi-Fi blip, MQTT reconnecting) used to be lost, so the phone
// never got its notification although the app's log showed it. It now waits here and goes out on reconnect.
const uint8_t EV_OUTBOX = 12;
String evOutJ[EV_OUTBOX], evOutMac[EV_OUTBOX];
uint8_t evOutN = 0;
// v2.15.13: access requests are the owner's business only, not shown to family members
bool ownerOnlyEvent(const String& j) { return j.indexOf("\"type\":\"pair") >= 0 || j.indexOf("\"type\":\"owner\"") >= 0; }
void publishEvent(const String& j, const String& mac) {
  mqttPub(tEvent, j, 1, false);
  if (ownerOnlyEvent(j)) return;
  for (int u = 0; u < userCount; u++)
    if (mac.length() ? userHas(users[u], mac) : users[u].all) mqttPub("mttl/" + hubId + "/u/" + users[u].id + "/event", j, 1, false);
}
void flushEventOutbox() {
  for (uint8_t i = 0; i < evOutN; i++) publishEvent(evOutJ[i], evOutMac[i]);
  for (uint8_t i = 0; i < evOutN; i++) { evOutJ[i] = ""; evOutMac[i] = ""; }
  evOutN = 0;
}

void addEvent(const String& type, const String& mac, int outlet, const String& msg) {
  Ev& e = events[evHead];
  e.ts = timeOk() ? (uint32_t)time(nullptr) : 0;
  e.type = type; e.mac = mac; e.outlet = outlet; e.msg = msg;
  evHead = (evHead + 1) % MAX_EVENTS;
  if (evCount < MAX_EVENTS) evCount++;
  String j = "{\"ts\":" + String(e.ts) + ",\"type\":\"" + type + "\",\"mac\":\"" + mac + "\",\"outlet\":" + String(outlet) +
             ",\"msg\":\"" + jsonEsc(msg) + "\"}";
  Serial.printf("[event] %s\n", j.c_str());
  if (mqtt && mqttUp) publishEvent(j, mac);
  else if (secMqtt.length()) {                     // keep the newest EV_OUTBOX events for the reconnect
    if (evOutN == EV_OUTBOX) {
      for (uint8_t i = 1; i < EV_OUTBOX; i++) { evOutJ[i - 1] = evOutJ[i]; evOutMac[i - 1] = evOutMac[i]; }
      evOutN--;
    }
    evOutJ[evOutN] = j; evOutMac[evOutN] = mac; evOutN++;
  }
  sseSend("event", j);
  queueNotify(type, mac, outlet, msg);
}

// ---------- NVS ----------
void saveLocks(Strip& s) {
  cfg.putUChar(("l" + s.mac).c_str(), s.lockMask);
  cfg.putUChar(("s" + s.mac).c_str(), s.lockState);
}
// v2.15.7: the energy/peak history (~2.4 KB per strip, rewritten every few minutes) lives in files on the unused
// SPIFFS partition (LittleFS), not in NVS: it filled NVS (500/630 entries) and saves started to fail.
bool fsOk = false;
bool fileSave(const String& path, const void* d, size_t n) {
  if (!fsOk) return false;
  SubT st("fs_save");
  String tmp = path + ".t";
  File f = LittleFS.open(tmp, "w");
  if (!f) return false;
  size_t w = f.write((const uint8_t*)d, n);
  f.close();
  if (w != n) { LittleFS.remove(tmp); return false; }
  LittleFS.remove(path);
  return LittleFS.rename(tmp, path);
}
bool fileLoad(const String& path, void* d, size_t n) {
  if (!fsOk || !LittleFS.exists(path)) return false;
  File f = LittleFS.open(path, "r");
  if (!f) return false;
  bool ok = f.size() == n && f.read((uint8_t*)d, n) == n;
  f.close();
  return ok;
}
// file first; NVS only as a fallback when the file system is not available
void saveBlob(const String& key, const void* d, size_t n) {
  if (fileSave("/" + key, d, n)) { if (cfg.isKey(key.c_str())) cfg.remove(key.c_str()); }
  else cfg.putBytes(key.c_str(), d, n);
}
// loads from the file, or from NVS once (old data), moving it to a file and freeing the NVS entries
bool loadBlob(const String& key, void* d, size_t n) {
  if (fileLoad("/" + key, d, n)) return true;
  if (cfg.getBytesLength(key.c_str()) != n) return false;
  cfg.getBytes(key.c_str(), d, n);
  if (fileSave("/" + key, d, n)) cfg.remove(key.c_str());
  return true;
}
void saveElog(int i) { saveBlob("e" + strips[i].mac, &elogs[i], sizeof(ELog)); }
void savePeak(int i) { saveBlob("k" + strips[i].mac, &peaks[i], sizeof(PeakLog)); peakSavedAt[i] = millis(); }

void loadStripCfg(int i) {
  Strip& s = strips[i];
  s.label = cfg.getString(("n" + s.mac).c_str(), "");
  for (int k = 0; k < 4; k++) s.olabel[k] = cfg.getString(("n" + s.mac + String(k + 1)).c_str(), "");
  s.lockMask = cfg.getUChar(("l" + s.mac).c_str(), 0);
  s.lockState = cfg.getUChar(("s" + s.mac).c_str(), 0);
  s.protMask = cfg.getUChar(("p" + s.mac).c_str(), 0);
  s.keepMask = cfg.getUChar(("q" + s.mac).c_str(), 0);
  s.notifyMask = cfg.getUChar(("m" + s.mac).c_str(), 0x1F);
  if (cfg.getBytesLength(("a" + s.mac).c_str()) == sizeof(s.autoOffMin)) cfg.getBytes(("a" + s.mac).c_str(), s.autoOffMin, sizeof(s.autoOffMin));
  else memset(s.autoOffMin, 0, sizeof(s.autoOffMin));
  if (cfg.getBytesLength(("x" + s.mac).c_str()) == sizeof(s.ampX2)) cfg.getBytes(("x" + s.mac).c_str(), s.ampX2, sizeof(s.ampX2));
  else memset(s.ampX2, 0, sizeof(s.ampX2));
  ELog& el = elogs[i];
  loadBlob("e" + s.mac, &el, sizeof(ELog));
  if (el.magic != 0xE1E1) {
    memset(&el, 0, sizeof(ELog));
    el.magic = 0xE1E1;
    for (int d = 0; d < ELOG_DAYS; d++) el.dayOf[d] = -1;
  }
  PeakLog& pl = peaks[i];
  loadBlob("k" + s.mac, &pl, sizeof(PeakLog));
  if (pl.magic != 0xBEA7) {
    memset(&pl, 0, sizeof(PeakLog));
    pl.magic = 0xBEA7;
    for (int d = 0; d < ELOG_DAYS; d++) pl.dayOf[d] = -1;
  }
  peakSavedAt[i] = millis();
}

void peakUpdate(int i, float watts) {
  if (!timeOk()) return;
  PeakLog& pl = peaks[i];
  int32_t today = localDay();
  if (pl.day != today) {
    if (pl.day) {
      int idx = ((pl.day % ELOG_DAYS) + ELOG_DAYS) % ELOG_DAYS;
      pl.pk[idx] = pl.today;
      pl.dayOf[idx] = pl.day;
    }
    pl.day = today;
    pl.today = 0;
    savePeak(i);
  }
  uint16_t w = (uint16_t)constrain(watts, 0.0f, 65000.0f);
  if (w > pl.today) {
    pl.today = w;
    if (millis() - peakSavedAt[i] > 600000) savePeak(i);   // at most every 10 min
  }
}

// v2.15.8: a save that NVS refused (full) shows up in the event log instead of vanishing (once a minute per item)
void saveFailed(const char* what) {
  static uint32_t lastAt = 0;
  static String lastWhat;
  Serial.printf("[nvs] save FAILED: %s\n", what);
  if (lastWhat == what && millis() - lastAt < 60000) return;
  lastWhat = what; lastAt = millis();
  addEvent("save_fail", "", 0, what);
}
void saveScheds() {
  cfg.putUChar("schN", schedCount);
  if (!cfg.putBytes("sch", scheds, sizeof(Sched) * MAX_SCHED)) saveFailed("schedules");
  stateDirty = true;   // v2.15.2: badges follow at once
}   // v2.15.2: badges follow at once
void saveSkips() { cfg.putBytes("schsk", schedSkip, sizeof(schedSkip)); }
bool schedSkipped(uint32_t id) { for (int i = 0; i < MAX_SCHED; i++) if (id && schedSkip[i] == id) return true; return false; }
void setSchedSkip(uint32_t id, bool on) {
  bool changed = false;
  for (int i = 0; i < MAX_SCHED; i++) if (schedSkip[i] == id) { schedSkip[i] = 0; changed = true; }
  if (on) for (int i = 0; i < MAX_SCHED; i++) if (!schedSkip[i]) { schedSkip[i] = id; changed = true; break; }
  if (changed) saveSkips();
}
void saveAutos() {
  cfg.putUChar("autN", autoCount);
  if (!cfg.putBytes("aut", autos, sizeof(Autom) * MAX_AUTO)) saveFailed("automations");
  stateDirty = true;
}

void loadGlobals() {
  tempMax = cfg.getUChar("tmax", 70);
  tempProtect = cfg.getBool("tprot", true);
  vProt = cfg.getBool("vprot", true);
  vRestore = cfg.getBool("vrest", true);
  vMax = cfg.getUShort("vmax", 250);
  vMin = cfg.getUShort("vmin", 190);
  aProt = cfg.getBool("aprot", true);
  aMax = cfg.getFloat("amax", 16.0f);
  schedCount = 0;
  memset(schedSkip, 0, sizeof(schedSkip));
  if (cfg.getBytesLength("schsk") == sizeof(schedSkip)) cfg.getBytes("schsk", schedSkip, sizeof(schedSkip));
  if (cfg.getBytesLength("sch") == sizeof(Sched) * MAX_SCHED) {
    cfg.getBytes("sch", scheds, sizeof(Sched) * MAX_SCHED);
    schedCount = min((int)cfg.getUChar("schN", 0), (int)MAX_SCHED);
  }
  autoCount = 0;
  if (cfg.getBytesLength("aut") == sizeof(Autom) * MAX_AUTO) {
    cfg.getBytes("aut", autos, sizeof(Autom) * MAX_AUTO);
    autoCount = min((int)cfg.getUChar("autN", 0), (int)MAX_AUTO);
  } else if (cfg.getBytesLength("aut") == sizeof(Autom) * OLD_MAX_AUTO) {   // v2.15.22 raised the cap 10 -> 40
    cfg.getBytes("aut", autos, sizeof(Autom) * OLD_MAX_AUTO);
    autoCount = min((int)cfg.getUChar("autN", 0), (int)OLD_MAX_AUTO);
    saveAutos();
  } else if (cfg.getBytesLength("aut") == sizeof(AutomV2) * OLD_MAX_AUTO) {   // migrate rules saved by v2.0 .. v2.2
    static AutomV2 old[OLD_MAX_AUTO];
    cfg.getBytes("aut", old, sizeof(old));
    autoCount = min((int)cfg.getUChar("autN", 0), (int)OLD_MAX_AUTO);
    for (int i = 0; i < autoCount; i++) {
      memset(&autos[i], 0, sizeof(Autom));
      memcpy(&autos[i], &old[i], offsetof(AutomV2, metric) + 1);
      autos[i].limit2 = 70;
    }
    saveAutos();
  }
  ntfyTopic = cfg.getString("ntfy", "");
  notifyTypes = cfg.getUInt("ntypes", 0xFFFFFFFF);
  for (int i = 0; i < MAX_AUTO; i++) { autoArmed[i] = true; autoSince[i] = 0; }
}

// ---------- strips the hub has seen (shown as offline instead of disappearing) ----------
const int MAX_KNOWN = 12;
Known known[MAX_KNOWN];
int knownCount = 0;

// v2.14.1: a rule or schedule must point at a strip the hub has seen (online now or remembered)
bool macKnown(String m) {
  m.toUpperCase();
  if (m.length() != 12) return false;
  if (findStrip(m) >= 0) return true;
  for (int i = 0; i < knownCount; i++) if (known[i].mac == m) return true;
  return false;
}

void refreshKnown(const String& mac) {
  int k = -1;
  for (int i = 0; i < knownCount; i++) if (known[i].mac == mac) k = i;
  if (k < 0) {
    if (knownCount >= MAX_KNOWN) return;
    k = knownCount++;
    String list;
    for (int i = 0; i < knownCount; i++) { if (i) list += ","; list += (i == k ? mac : known[i].mac); }
    cfg.putString("known", list);
  }
  Known& n = known[k];
  n.mac = mac;
  n.label = cfg.getString(("n" + mac).c_str(), "");
  for (int o = 0; o < 4; o++) n.olabel[o] = cfg.getString(("n" + mac + String(o + 1)).c_str(), "");
  n.lock = cfg.getUChar(("l" + mac).c_str(), 0);
  n.prot = cfg.getUChar(("p" + mac).c_str(), 0);
  n.keep = cfg.getUChar(("q" + mac).c_str(), 0);
  n.notify = cfg.getUChar(("m" + mac).c_str(), 0x1F);
  if (cfg.getBytesLength(("x" + mac).c_str()) == sizeof(n.amp)) cfg.getBytes(("x" + mac).c_str(), n.amp, sizeof(n.amp));
  else memset(n.amp, 0, sizeof(n.amp));
}

void loadKnown() {
  knownCount = 0;
  String list = cfg.getString("known", "");
  for (const String& m : split(list, ',')) if (m.length() == 12 && knownCount < MAX_KNOWN) { known[knownCount].mac = m; knownCount++; }
  for (int i = 0; i < knownCount; i++) refreshKnown(known[i].mac);
}

void forgetKnown(const String& mac) {
  String list;
  int w = 0;
  for (int i = 0; i < knownCount; i++) {
    if (known[i].mac == mac) continue;
    known[w++] = known[i];
  }
  knownCount = w;
  for (int i = 0; i < knownCount; i++) { if (i) list += ","; list += known[i].mac; }
  cfg.putString("known", list);
}

bool hasSched(const String& mac, int outlet);
bool hasRule(const String& mac, int outlet);

String offlineStripJson(const Known& n) {
  String outs = "[";
  for (int k = 0; k < 4; k++) {
    if (k) outs += ",";
    outs += "{\"n\":" + String(k + 1) + ",\"on\":false,\"power_w\":0,\"energy_kwh\":0,\"temp_c\":0,\"label\":\"" + jsonEsc(n.olabel[k]) +
            "\",\"locked\":" + ((n.lock & (1 << k)) ? "true" : "false") + ",\"protected\":" + ((n.prot & (1 << k)) ? "true" : "false") +
            ",\"keep_on\":" + ((n.keep & (1 << k)) ? "true" : "false") +
            ",\"amp_limit\":" + (n.amp[k] ? String(n.amp[k] * 0.5f, 1) : "0") +
            ",\"auto_off_min\":0,\"auto_off_in_s\":-1,\"sched\":" + (hasSched(n.mac, k + 1) ? "true" : "false") +
            ",\"rule\":" + (hasRule(n.mac, k + 1) ? "true" : "false") + "}";
  }
  return "{\"mac\":\"" + n.mac + "\",\"label\":\"" + jsonEsc(n.label) + "\",\"fw\":\"\",\"online\":false,\"on\":false,\"power_w\":0,\"voltage\":null,\"rssi\":null,\"notify\":" +
         String(n.notify) + ",\"sched\":" + (hasSched(n.mac, 0) ? "true" : "false") + ",\"rule\":" + (hasRule(n.mac, 0) ? "true" : "false") +
         ",\"outlets\":" + outs + "]}";
}

// ---------- strips removed from the app are ignored until they are added again ----------
bool isBlocked(const String& mac) { return ("," + cfg.getString("block", "") + ",").indexOf("," + mac + ",") >= 0; }
void setBlocked(const String& mac, bool on) {
  String out;
  for (const String& m : split(cfg.getString("block", ""), ',')) {
    if (m.length() != 12 || m == mac) continue;
    if (out.length()) out += ",";
    out += m;
  }
  if (on) { if (out.length()) out += ","; out += mac; }
  cfg.putString("block", out);
}
String offlineMacs;                               // strips that dropped off, to report when they come back

// ---------- strip control ----------
void dropStrip(Strip& s, const char* why) {
  Serial.printf("[-] %s %s\n", s.mac.length() ? s.mac.c_str() : s.ip.c_str(), why);
  if (s.identified && (!strcmp(why, "disconnected") || !strcmp(why, "stale") || !strcmp(why, "socket stuck"))) {
    String mac = s.mac;
    if (offlineMacs.indexOf(mac) < 0) offlineMacs += mac + ",";
    { SubT st("sock_close"); s.c.stop(); }
    s = Strip();
    stateDirty = true;
    linkDrop(mac);
    addEvent("offline", mac, 0, why);                 // why: "disconnected" (strip closed), "stale" (silent 45 s) or "socket stuck" (hub could not send, v2.15.2)
    return;
  }
  { SubT st("sock_close"); s.c.stop(); }
  s = Strip();
  stateDirty = true;
}

void noteCommanded(Strip& s, int outlet, bool on) {
  uint8_t before = s.lockState;
  for (int ch = (outlet ? outlet : 1); ch <= (outlet ? outlet : 4); ch++) {
    s.cmdAt[ch - 1] = millis();
    if (on) s.lockState |= (1 << (ch - 1)); else s.lockState &= ~(1 << (ch - 1));
  }
  if (s.lockState != before && s.lockMask) saveLocks(s);
}

// fire-and-forget switch (used by schedules, timers, automations); the next poll confirms it
// keep-always-on outlets ignore "off" unless it is a safety cut (force), which holds them off until switched on again
bool keepSkip(Strip& s, int ch, bool on, bool force) {
  uint8_t bit = 1 << (ch - 1);
  if (on || !(s.keepMask & bit)) return false;
  if (!force) return true;
  s.keepHold |= bit;
  return false;
}

// v2.15.23 fix: a master "all on/off" (outlet == 0) used to also re-command a child-locked outlet, which raced
// with the "keep a locked outlet where it belongs" resend (the lock enforcement loop) and could stall or confuse
// the whole batch for the strip, so the other (free) outlets did not respond properly either. A direct command to
// that one outlet (outlet == ch, from its own tile) still goes through — only the whole-strip master command skips
// locked channels now, the same way it already skips keep-always-on ones.
bool lockSkip(Strip& s, int ch, int outlet) { return outlet == 0 && (s.lockMask & (1 << (ch - 1))); }

void sendOnOffF(Strip& s, int outlet, bool on, bool force) {
  for (int ch = (outlet ? outlet : 1); ch <= (outlet ? outlet : 4); ch++) {
    if (on) s.tripMask &= ~(1 << (ch - 1));      // switched back on on purpose: stop chasing the safety cut
    if (lockSkip(s, ch, outlet) || keepSkip(s, ch, on, force)) continue;
    noteCommanded(s, ch, on);
    sendLine(s, "up:onoff:" + String(ch) + ":" + (on ? "on" : "off"));
    s.o[ch - 1].on = on;
  }
  sendLine(s, "up:getinfo:all");
  stateDirty = true;
}
void sendOnOff(Strip& s, int outlet, bool on) { sendOnOffF(s, outlet, on, false); }

// v2.15.9 safety cut: switch the outlet off and keep checking the strip's next reports. If it still says "on", send
// the off again (up to 4 more times), then raise "trip_fail" so the user knows the cut did not take.
void protectCut(Strip& s, int k) {
  sendOnOffF(s, k + 1, false, true);
  s.tripMask |= 1 << k;
  s.tripTries[k] = 0;
  s.tripAt = millis();
  s.tripSeq = s.infoSeq;
}
void tripVerify(Strip& s) {
  if (!s.tripMask) return;
  uint32_t now = millis();
  if (s.infoSeq == s.tripSeq || now - s.tripAt < 1500) return;   // wait for a report made after the last off
  for (int k = 0; k < 4; k++) {
    uint8_t bit = 1 << k;
    if (!(s.tripMask & bit)) continue;
    if (!s.o[k].on) { s.tripMask &= ~bit; continue; }             // confirmed off
    if (s.tripTries[k] >= 4) {
      s.tripMask &= ~bit;
      addEvent("trip_fail", s.mac, k + 1, String((int)s.o[k].powerW) + " W");
      continue;
    }
    s.tripTries[k]++;
    Serial.printf("[trip] %s outlet %d still on, off again (%u)\n", s.mac.c_str(), k + 1, s.tripTries[k]);
    sendOnOffF(s, k + 1, false, true);
    s.tripAt = now;
    s.tripSeq = s.infoSeq;
  }
}

void pumpStrips();
void pumpFor(uint32_t ms) { uint32_t t0 = millis(); while (millis() - t0 < ms) { pumpStrips(); delay(5); } }
bool waitForInfo(Strip& s, uint32_t seq, uint32_t ms) {
  uint32_t t0 = millis();
  while (millis() - t0 < ms) { pumpStrips(); if (!s.used) return false; if (s.infoSeq > seq) return true; delay(5); }
  return false;
}

// switch and wait for the strip to confirm (used by app commands)
bool setOutlets(Strip& s, int outlet, bool on) {
  for (int ch = (outlet ? outlet : 1); ch <= (outlet ? outlet : 4); ch++) {
    if (on) s.tripMask &= ~(1 << (ch - 1));
    if (lockSkip(s, ch, outlet) || keepSkip(s, ch, on, false)) continue;
    noteCommanded(s, ch, on);
    sendLine(s, "up:onoff:" + String(ch) + ":" + (on ? "on" : "off"));
    pumpFor(120);
  }
  pumpFor(300);
  if (!s.used) return false;
  uint32_t seq = s.infoSeq;
  sendLine(s, "up:getinfo:all");
  bool ok = waitForInfo(s, seq, 4000);
  stateDirty = true;
  return ok;
}

// ---------- energy ----------
void energyUpdate(int i) {
  if (!timeOk()) return;
  Strip& s = strips[i];
  ELog& el = elogs[i];
  int32_t today = localDay();
  bool changed = false;
  if (el.day == 0) {
    el.day = today;
    for (int k = 0; k < 4; k++) el.base[k] = s.o[k].energyWh;
    changed = true;
  } else if (today != el.day) {
    int idx = ((el.day % ELOG_DAYS) + ELOG_DAYS) % ELOG_DAYS;
    for (int k = 0; k < 4; k++) {
      uint32_t c = s.o[k].energyWh;
      el.wh[idx][k] = c >= el.base[k] ? c - el.base[k] : 0;
      el.base[k] = c;
    }
    el.dayOf[idx] = el.day;
    el.day = today;
    changed = true;
  } else {
    for (int k = 0; k < 4; k++) if (s.o[k].energyWh < el.base[k]) { el.base[k] = s.o[k].energyWh; changed = true; }  // counter reset
  }
  if (changed) saveElog(i);
}


// v2.10 over-voltage + v2.11 under-voltage protection for the whole strip
void voltCheck(Strip& s) {
  if (isnan(s.voltage)) return;
  uint32_t now = millis();
  // over-voltage is always enforced (v2.14); vProt only switches the under-voltage cut
  bool underOn = vProt && vMin > 0;
  bool badV = s.voltage > vMax || (underOn && s.voltage < vMin);
  if (badV) {
    s.vOkSince = 0;
    if (s.ovCount < 255) s.ovCount++;
    bool far = s.voltage > vMax + 15 || (underOn && s.voltage < vMin - 15);
    if (s.vCutMask || (s.ovCount < 2 && !far)) return;   // two readings in a row, or one far outside
    bool over = s.voltage > vMax;
    uint8_t cut = 0;
    for (int k = 0; k < 4; k++)                       // over-voltage cuts protected outlets too
      if (s.o[k].on && (over || !(s.protMask & (1 << k)))) { protectCut(s, k); cut |= 1 << k; }
    s.vCutMask = cut ? cut : 0x80;                     // 0x80 = tripped with nothing to cut
    addEvent(over ? "overvolt" : "undervolt", s.mac, 0, String(s.voltage, 0) + " V");
    stateDirty = true;
    return;
  }
  s.ovCount = 0;
  if (!s.vCutMask) return;
  // back inside the safe window with a 5 V hysteresis
  if (s.voltage > vMax - 5 || (underOn && s.voltage < vMin + 5)) { s.vOkSince = 0; return; }
  if (!s.vOkSince) { s.vOkSince = now ? now : 1; return; }
  if (now - s.vOkSince < 60000) return;
  if (vRestore)
    for (int k = 0; k < 4; k++) if (s.vCutMask & (1 << k)) sendOnOff(s, k + 1, true);
  addEvent("voltage", s.mac, 0, String(s.voltage, 0) + " V ok");
  s.vCutMask = 0;
  s.vOkSince = 0;
  stateDirty = true;
}

// ---------- automations / protections (evaluated after every poll) ----------
void evalStrip(int i) {
  Strip& s = strips[i];
  uint32_t now = millis();
  tripVerify(s);
  float total = 0;
  float volts = (!isnan(s.voltage) && s.voltage > 50) ? s.voltage : 220.0f;
  for (int k = 0; k < 4; k++) {
    Outlet& o = s.o[k];
    total += o.on ? o.powerW : 0;
    float oAmps = o.on ? (o.powerW / volts) : 0;

    // over-temperature protection & near-limit warning (v2.11)
    // v2.15.9: 10 °C past the limit cuts on the first reading instead of waiting 30 s
    if (tempProtect && o.on && o.tempC >= tempMax) {
      if (!s.hotSince[k]) s.hotSince[k] = now ? now : 1;
      if (o.tempC >= tempMax + 10 || now - s.hotSince[k] > 30000) {
        protectCut(s, k);
        addEvent("temp", s.mac, k + 1, String(o.tempC) + "°C");
        s.hotSince[k] = 0;
      }
    } else {
      s.hotSince[k] = 0;
    }
    // near temperature limit: 5 °C before tempMax (orange band)
    if (tempProtect && o.on && o.tempC >= tempMax - 5 && o.tempC < tempMax) {
      if (!(s.warnT & (1 << k))) { s.warnT |= (1 << k); addEvent("warn", s.mac, k + 1, String(o.tempC) + "°C (near " + String(tempMax) + "°C)"); }
    } else if (!o.on || o.tempC < tempMax - 8) s.warnT &= ~(1 << k);

    // v2.11 per-outlet current limit (ampX2 in 0.5 A steps) & near-limit warning
    float oMaxA = s.ampX2[k] ? (s.ampX2[k] * 0.5f) : 0;
    if (oMaxA > 0 && o.on) {
      if (oAmps >= oMaxA) {
        if (!s.ocoSince[k]) s.ocoSince[k] = now ? now : 1;
        if (oAmps >= oMaxA * 1.25f || now - s.ocoSince[k] > 3000) {   // v2.15.9: 25 % over cuts at once
          protectCut(s, k);
          addEvent("overcurrent", s.mac, k + 1, String(oAmps, 1) + " A (max " + String(oMaxA, 1) + " A)");
          s.ocoSince[k] = 0;
        }
      } else s.ocoSince[k] = 0;
      // near current limit (>= 85 %)
      if (oAmps >= oMaxA * 0.85f && oAmps < oMaxA) {
        if (!(s.warnA & (1 << k))) { s.warnA |= (1 << k); addEvent("warn", s.mac, k + 1, String(oAmps, 1) + " A (near " + String(oMaxA, 1) + " A)"); }
      } else if (!o.on || oAmps < oMaxA * 0.75f) s.warnA &= ~(1 << k);
    } else { s.ocoSince[k] = 0; s.warnA &= ~(1 << k); }

    // auto-off
    if (s.autoOffAt[k] && (int32_t)(now - s.autoOffAt[k]) >= 0) {
      s.autoOffAt[k] = 0;
      if (o.on && !(s.keepMask & (1 << k))) {
        sendOnOff(s, k + 1, false);
        addEvent("auto_off", s.mac, k + 1, String(s.autoOffMin[k]) + " min");
      }
    }
  }

  // v2.10 over-current on the whole strip
  float amps = total / volts;
  if (aProt && amps > aMax) {
    if (!s.ocSince) s.ocSince = now ? now : 1;
    if (amps > aMax * 1.15f || now - s.ocSince > 3000) {            // v2.15.9: 15 % over cuts at once
      for (int k = 0; k < 4; k++) if (s.o[k].on && !(s.protMask & (1 << k))) protectCut(s, k);
      addEvent("overcurrent", s.mac, 0, String(amps, 1) + " A");
      s.ocSince = 0;
    }
  } else s.ocSince = 0;

  // v2.15.9 strip load limit: one strip never carries more than 3500 W (the stock firmware only warns at 3000 W and
  // cuts at 16 A). After 3 s over (at once when 15 % over), the biggest unprotected loads go first until the rest
  // fits; protected outlets are cut only if they alone keep the strip over the limit.
  if (total > STRIP_MAX_W) {
    if (!s.olSince) s.olSince = now ? now : 1;
    if (total > STRIP_MAX_W * 1.15f || now - s.olSince > 3000) {
      float left = 0;                              // what is still on now (the current cut above may have run)
      for (int k = 0; k < 4; k++) left += s.o[k].on ? s.o[k].powerW : 0;
      for (int pass = 0; pass < 2 && left > STRIP_MAX_W; pass++)
        while (left > STRIP_MAX_W) {
          int big = -1;
          for (int k = 0; k < 4; k++)
            if (s.o[k].on && s.o[k].powerW > 0 && (pass == 1 || !(s.protMask & (1 << k))) && (big < 0 || s.o[k].powerW > s.o[big].powerW)) big = k;
          if (big < 0) break;
          left -= s.o[big].powerW;
          protectCut(s, big);
        }
      addEvent("overload", s.mac, 0, String((int)total) + " W");
      s.olSince = 0;
    }
  } else s.olSince = 0;
  if (total > 3300 && now - s.loadEventAt > 300000) {
    s.loadEventAt = now;
    addEvent("load", s.mac, 0, String((int)total) + " W");
  }
  int hottest = 0;
  bool anyOn = false;
  for (int k = 0; k < 4; k++) { hottest = max(hottest, s.o[k].tempC); anyOn |= s.o[k].on; }

  // automations: metric 0 W, 1 °C, 2 W or °C, 3 A (v2.11)
  for (int a = 0; a < autoCount; a++) {
    Autom& r = autos[a];
    if (!r.enabled || !s.mac.equalsIgnoreCase(r.mac) || r.outlet > 4) continue;
    float pw, tc, cur;
    bool on;
    if (r.outlet == 0) { pw = total; tc = hottest; cur = amps; on = anyOn; }
    else { Outlet& o = s.o[r.outlet - 1]; pw = o.on ? o.powerW : 0; tc = o.tempC; cur = o.on ? (o.powerW / volts) : 0; on = o.on; }
    float p = r.metric == 1 ? tc : (r.metric == 3 ? cur : pw);
    // v2.15.0: a rule is armed from the moment it is saved (and after every reboot), so a load that is already
    // past the limit counts. It fires once, then re-arms when the condition clears or the outlet is switched off.
    // Before, it only armed after the load crossed back first: a heater already above, or an outlet already in
    // standby, never tripped, and every hub reboot (firmware update) disarmed all rules.
    bool clear;
    if (r.metric == 2) { clear = pw < r.watts && tc < r.limit2; if (tc >= r.limit2) p = tc; }   // either limit (watts or temp)
    else clear = r.above ? p < r.watts : p > r.watts;
    if (clear || !on) { autoArmed[a] = true; autoWarned[a] = false; autoSince[a] = 0; continue; }
    bool cond = autoArmed[a];
    // near-threshold warning (color-code alert) before the countdown trips (v2.11)
    if (r.above && autoArmed[a] && on && !autoWarned[a]) {
      float warnAt = r.watts * 0.85f;
      if (r.metric == 1) warnAt = max(r.watts - 5.0f, 40.0f);
      if (p >= warnAt && p < r.watts) {
        autoWarned[a] = true;
        addEvent("warn", s.mac, r.outlet, String(p, r.metric == 1 ? 0 : 1) + (r.metric == 1 ? "°C" : (r.metric == 3 ? " A" : " W")) + " (near " + String(r.watts, r.metric == 1 ? 0 : 1) + ")");
      }
    }
    if (!cond) { autoSince[a] = 0; continue; }
    if (!autoSince[a]) autoSince[a] = now ? now : 1;
    if (now - autoSince[a] >= (uint32_t)r.holdS * 1000) {
      autoArmed[a] = false;
      autoWarned[a] = false;
      autoSince[a] = 0;
      if (r.act & 2) {
        if (r.outlet == 0) {                       // whole strip: never cut protected outlets (router)
          for (int k = 0; k < 4; k++) if (s.o[k].on && !(s.protMask & (1 << k))) sendOnOffF(s, k + 1, false, true);
        } else sendOnOffF(s, r.outlet, false, true);
      }
      String unit = (r.metric == 1 || (r.metric == 2 && p == tc)) ? " C" : (r.metric == 3 ? " A" : " W");
      addEvent("automation", s.mac, r.outlet, String(r.label).length() ? String(r.label) : String(p, (unit == " C") ? 0 : 1) + unit);
    }
  }
}

// ---------- strip protocol ----------
// up:getinfo:<ch>:<runtime>;<relay>;<state>;<flagA>;<flagB>;<power mW>;<energy hex Wh>;<prev>;<config>;<status>;<event>;<temp>  x4
void keepRestore(Strip& s, int ch) {
  s.cmdAt[ch - 1] = millis();
  sendLine(s, "up:onoff:" + String(ch) + ":on");
  if (!s.keepEvAt[ch - 1] || millis() - s.keepEvAt[ch - 1] > 60000) {
    s.keepEvAt[ch - 1] = millis() ? millis() : 1;
    addEvent("lock", s.mac, ch, "keep_on");
  }
}

bool tryParseInfo(int i) {
  Strip& s = strips[i];
  std::vector<String> t = split(s.pendingInfo.substring(11), ':');
  Outlet tmp[4];
  bool seen[4] = {false, false, false, false};
  for (size_t j = 0; j + 1 < t.size(); j += 2) {
    int ch = t[j].toInt();
    std::vector<String> f = split(t[j + 1], ';');
    if (f.size() < 12 || ch < 1 || ch > 4 || !isHex(f[6])) continue;
    Outlet& o = tmp[ch - 1];
    o.on = f[1].equalsIgnoreCase("on");
    o.powerW = f[5].toInt() / 1000.0f;
    o.energyWh = strtoul(f[6].c_str(), nullptr, 16);
    o.tempC = f[11].toInt();
    seen[ch - 1] = true;
  }
  if (!(seen[0] && seen[1] && seen[2] && seen[3])) {
    if (s.pendingInfo.length() > 2048) s.pendingInfo = "";
    return false;
  }
  uint32_t now = millis();
  float total = 0;
  for (int k = 0; k < 4; k++) {
    if (tmp[k].on) total += tmp[k].powerW;
    // a change the hub did not ask for in the last 8 s came from the strip's own buttons
    if (s.gotInfo && tmp[k].on != s.o[k].on && now - s.cmdAt[k] > 8000 && !(s.lockMask & (1 << k))) {
      s.cmdAt[k] = now;
      addEvent("button", s.mac, k + 1, tmp[k].on ? "on" : "off");
    }
    bool was = s.gotInfo ? s.o[k].on : false;
    if (tmp[k].on && !was && s.autoOffMin[k]) s.autoOffAt[k] = now + (uint32_t)s.autoOffMin[k] * 60000UL;
    if (!tmp[k].on) s.autoOffAt[k] = 0;
    s.o[k] = tmp[k];
  }
  s.gotInfo = true;
  s.pendingInfo = "";
  s.infoSeq++;
  for (int k = 0; k < 4; k++) {                  // keep always on (wins over the child lock)
    uint8_t bit = 1 << k;
    if (!(s.keepMask & bit)) continue;
    if (s.o[k].on) { s.keepHold &= ~bit; continue; }
    if (!(s.keepHold & bit)) keepRestore(s, k + 1);
  }
  for (int k = 0; k < 4; k++) {                  // child lock: keep a locked outlet where it belongs
    if (!(s.lockMask & (1 << k)) || (s.keepMask & (1 << k))) continue;
    bool want = s.lockState & (1 << k);
    if (s.o[k].on != want) sendLine(s, "up:onoff:" + String(k + 1) + ":" + (want ? "on" : "off"));
  }
  energyUpdate(i);
  peakUpdate(i, total);
  evalStrip(i);
  stateDirty = true;
  return true;
}

void handleLine(int i, const String& line) {
  Strip& s = strips[i];
  s.lastLine = line;
  s.lastLine.replace("\"", "'");
  Serial.printf("[rx %s] %s\n", s.mac.length() ? s.mac.c_str() : s.ip.c_str(), line.c_str());

  if (s.pendingInfo.length() && !line.startsWith("up:")) { s.pendingInfo += line; tryParseInfo(i); return; }
  if (line.startsWith("up:bootinfo:")) {                     // <model>;<mac>;<mac>;<fw>;connect
    std::vector<String> f = split(line.substring(12), ';');
    if (f.size() < 5 || f[1].length() != 12 || !isHex(f[1])) { Serial.printf("[?] bootinfo not understood from %s: %s\n", s.ip.c_str(), line.c_str()); return; }
    String mac = f[1]; mac.toUpperCase();
    bool target = provTarget.length() && mac.endsWith(provTarget) && (provState == "waiting" || provState == "error");
    if (isBlocked(mac)) {
      if (!target) { Serial.printf("[x] %s was removed in the app, ignoring\n", mac.c_str()); s.c.stop(); s = Strip(); return; }
      setBlocked(mac, false);
    }
    for (int j = 0; j < MAX_STRIPS; j++)
      if (j != i && strips[j].used && strips[j].mac == mac) dropStrip(strips[j], "replaced");
    s.mac = mac; s.model = f[0]; s.fw = f[3]; s.identified = true; s.connectedAt = millis();
    linkUp(mac);
    loadStripCfg(i);
    refreshKnown(mac);
    Serial.printf("[*] strip %s online  model=%s fw=%s\n", mac.c_str(), s.model.c_str(), s.fw.c_str());
    // only the strip we just configured counts — every other strip re-dials after the hub rejoins Wi-Fi
    bool isTarget = provTarget.length() && mac.endsWith(provTarget);
    if (isTarget && (provState == "waiting" || (provState == "error" &&
        (provMsg == "no_dial" || provMsg == "still_setup" || provMsg == "hub_tcp_no_client")))) {
      provState = "connected";
      provMsg = mac;
      addEvent("added", mac, 0, "");
    }
    int off = offlineMacs.indexOf(mac + ",");
    if (off >= 0) { offlineMacs.remove(off, 13); addEvent("online", mac, 0, ""); }
    sendLine(s, "up:getinfo:all");
    stateDirty = true;
    return;
  }
  if (line.startsWith("up:getinfo:")) { s.pendingInfo = line; tryParseInfo(i); return; }
  if (line.startsWith("up:power_report:")) {
    std::vector<String> f = split(line.substring(16), ':');
    if (f.size() == 2 && f[1].toInt() >= 50000) {
      s.voltage = f[1].toInt() / 1000.0f;
      if ((s.voltage < 200 || s.voltage > 250) && (!s.voltEventAt || millis() - s.voltEventAt > 600000)) {
        s.voltEventAt = millis();
        addEvent("voltage", s.mac, 0, String(s.voltage, 0) + " V");
      }
      voltCheck(s);
    }
    return;
  }
  if (line.startsWith("up:query:")) { s.rssi = line.substring(9).toInt(); s.hasRssi = true; return; }

  String l = line; l.toLowerCase();
  String body;
  if (l.startsWith("up:event:onoff:")) body = l.substring(15);
  else if (l.startsWith("up:onoff:")) body = l.substring(9);
  if (!body.length()) return;
  std::vector<String> f = split(body, ':');
  int ch = f.size() == 2 ? f[0].toInt() : -1;
  bool isEvent = l.startsWith("up:event:");
  if (ch >= 1 && ch <= 4) {
    bool on = (f[1] == "on");
    uint8_t kb = 1 << (ch - 1);
    if (on) s.keepHold &= ~kb;
    if ((s.keepMask & kb) && !on && !(s.keepHold & kb)) {
      s.o[ch - 1].on = false;
      keepRestore(s, ch);
      stateDirty = true;
    } else if (isEvent && (s.lockMask & (1 << (ch - 1)))) {
      bool want = s.lockState & (1 << (ch - 1));
      if (on != want) sendLine(s, "up:onoff:" + String(ch) + ":" + (want ? "on" : "off"));
      addEvent("lock", s.mac, ch, "");
    } else {
      bool changed = s.o[ch - 1].on != on;
      s.o[ch - 1].on = on;
      if (isEvent) noteCommanded(s, ch, on);
      if (isEvent && changed && millis() - s.cmdAt[ch - 1] > 8000) { s.cmdAt[ch - 1] = millis(); addEvent("button", s.mac, ch, on ? "on" : "off"); }
      stateDirty = true;
    }
  } else if (isEvent && ch == 0) {
    sendLine(s, "up:getinfo:all");                           // master button: next poll re-applies locks
  }
}

void acceptStrips() {
  SubT st("accept");
  WiFiClient n = stripServer.accept();
  if (!n) n = stripServerAlt.accept();
  if (!n) return;
  for (int i = 0; i < MAX_STRIPS; i++) {
    if (!strips[i].used) {
      strips[i] = Strip();
      strips[i].c = n;
      strips[i].used = true;
      strips[i].ip = n.remoteIP().toString();
      strips[i].lastRx = millis();
      n.setNoDelay(true);
      tcpKeepAlive(strips[i].c);
      Serial.printf("[+] connection from %s -> port %u\n", strips[i].ip.c_str(), strips[i].c.localPort());
      return;
    }
  }
  n.stop();
}

void pumpStrips() {
  acceptStrips();
  for (int i = 0; i < MAX_STRIPS; i++) {
    Strip& s = strips[i];
    if (!s.used) continue;
    if (s.dead) { dropStrip(s, "socket stuck"); continue; }
    while (s.c.available()) {
      char ch = s.c.read();
      s.lastRx = millis();
      if (ch == 0 || ch == '\r') continue;
      if (ch == '\n') {
        String line = s.rx; line.trim();
        s.rx = "";
        if (line.length()) handleLine(i, line);
        if (!s.used) break;
      } else if (s.rx.length() < 4096) s.rx += ch;
      else s.rx = "";
    }
    if (!s.used) continue;
    if (s.txq.length()) flushTx(s, 0);
    if (s.dead) { dropStrip(s, "socket stuck"); continue; }
    if (!s.identified && !s.poked && millis() - s.lastRx > 6000) {   // a strip that connected but never introduced itself
      s.poked = true;
      Serial.printf("[?] %s connected but sent no bootinfo, asking it\n", s.ip.c_str());
      sendLine(s, "up:getinfo:all");
    }
    if (!s.c.connected() && !s.c.available()) dropStrip(s, "disconnected");
    else if (millis() - s.lastRx > STALE_MS) dropStrip(s, "stale");
  }
}

void pollStrips() {
  if (millis() - lastPoll < POLL_MS) return;
  lastPoll = millis();
  pollCount++;
  for (int i = 0; i < MAX_STRIPS; i++) {
    Strip& s = strips[i];
    if (!s.used || !s.identified) continue;
    sendLine(s, "up:getinfo:all");
    if (pollCount % DIAG_EVERY == 0) { sendLine(s, "up:power_report:1:vol"); sendLine(s, "up:query:wifirssi"); }
  }
}

// ---------- timers (kept in NVS) ----------
bool timersRestored = false;
TimerNV timersNV[MAX_TIMERS];
uint8_t timersNVCount = 0;

void saveTimers() {
  static TimerNV out[MAX_TIMERS];
  uint8_t n = 0;
  uint32_t now = millis();
  uint32_t epoch = timeOk() ? (uint32_t)time(nullptr) : 0;
  for (int t = 0; t < MAX_TIMERS; t++) {
    const Timer& x = timers[t];
    if (!x.used) continue;
    TimerNV& v = out[n++];
    memset(&v, 0, sizeof v);
    v.id = x.id; memcpy(v.mac, x.mac, sizeof v.mac); v.outlet = x.outlet; v.kind = x.kind; v.on = x.on; v.phase = x.phase;
    v.offS = x.offMs / 1000; v.onS = x.onMs / 1000; v.periodS = x.periodS;
    int32_t left = (int32_t)(x.at - now) / 1000;
    v.remainS = left < 0 ? 0 : left;
    v.dueEpoch = epoch ? epoch + v.remainS : 0;
  }
  cfg.putUChar("tmN", n);
  cfg.putBytes("tm", out, sizeof(TimerNV) * MAX_TIMERS);
}

void loadTimers() {
  timersNVCount = 0;
  if (cfg.getBytesLength("tm") == sizeof(TimerNV) * MAX_TIMERS) {
    cfg.getBytes("tm", timersNV, sizeof(TimerNV) * MAX_TIMERS);
    timersNVCount = min((int)cfg.getUChar("tmN", 0), (int)MAX_TIMERS);
  }
}

// called once the clock is set (or after 30 s without internet time)
void restoreTimers() {
  if (timersRestored || (!timeOk() && millis() < 30000)) return;
  timersRestored = true;
  uint32_t now = millis();
  uint32_t epoch = timeOk() ? (uint32_t)time(nullptr) : 0;
  bool changed = false;
  for (int i = 0; i < timersNVCount && i < MAX_TIMERS; i++) {
    const TimerNV& v = timersNV[i];
    int32_t left = (epoch && v.dueEpoch) ? (int32_t)(v.dueEpoch - epoch) : (int32_t)v.remainS;
    bool repeating = v.kind == 2 || v.periodS > 0;
    if (left < 0 && !repeating && -left > 600) { addEvent("missed", v.mac, v.outlet, "timer"); changed = true; continue; }
    Timer& x = timers[i];
    x = Timer();
    x.used = true; x.id = v.id; memcpy(x.mac, v.mac, sizeof x.mac); x.outlet = v.outlet; x.kind = v.kind; x.on = v.on; x.phase = v.phase;
    x.offMs = v.offS * 1000; x.onMs = v.onS * 1000; x.periodS = v.periodS;
    x.at = now + (uint32_t)(left > 2 ? left : 2) * 1000;
    if (x.id >= nextTimerId) nextTimerId = x.id + 1;
  }
  Serial.printf("[timers] restored %d\n", timersNVCount);
  if (changed) saveTimers();
  stateDirty = true;
}

String addTimer(const String& mac, int outlet, int kind, bool on, uint32_t delayS, uint32_t offS, uint32_t onS, uint32_t periodS) {
  int idx = stripFor(mac);
  if (idx < 0) return "device offline";
  if (outlet < 0 || outlet > 4) return "bad outlet";
  if (kind == 1 && (offS < 3 || offS > 3600)) return "off time must be 3..3600 s";
  if (kind == 2 && (onS < 10 || offS < 10 || onS > 604800 || offS > 604800)) return "on/off time must be 10 s .. 7 days";
  if (periodS && (periodS < 60 || periodS > 604800)) return "repeat every 1 min .. 7 days";
  if (kind == 1 && periodS && periodS <= offS) return "repeat must be longer than the off time";
  if (delayS > 604800) return "delay too long";
  for (int t = 0; t < MAX_TIMERS; t++) {
    if (timers[t].used) continue;
    Timer& x = timers[t];
    x = Timer();
    x.used = true; x.id = nextTimerId++;
    strlcpy(x.mac, strips[idx].mac.c_str(), sizeof x.mac);
    x.outlet = outlet; x.kind = kind; x.on = on; x.offMs = offS * 1000; x.onMs = onS * 1000; x.phase = 0;
    x.periodS = kind == 2 ? 0 : periodS;
    x.at = millis() + delayS * 1000;
    saveTimers();
    stateDirty = true;
    return "";
  }
  return "too many timers";
}

void tickTimers() {
  restoreTimers();
  uint32_t now = millis();
  bool changed = false;
  for (int t = 0; t < MAX_TIMERS; t++) {
    Timer& x = timers[t];
    if (!x.used || (int32_t)(now - x.at) < 0) continue;
    changed = true;
    bool repeating = x.kind == 2 || x.periodS > 0;
    int idx = findStrip(x.mac);
    if (idx < 0) {                                   // strip offline
      if (x.kind == 1 && x.phase == 1 && x.tries++ < 120) { x.at = now + 5000; continue; }   // keep trying "back on" for 10 min
      addEvent("missed", x.mac, x.outlet, "timer");
      if (!repeating) { x.used = false; continue; }
      x.tries = 0;
      x.phase = 0;
      x.at = now + (x.kind == 2 ? x.onMs + x.offMs : x.periodS * 1000);
      continue;
    }
    Strip& s = strips[idx];
    x.tries = 0;
    if (x.kind == 0) {
      sendOnOff(s, x.outlet, x.on);
      addEvent("timer", s.mac, x.outlet, x.on ? "on" : "off");
      if (x.periodS) x.at = now + x.periodS * 1000; else x.used = false;
    } else if (x.kind == 1) {
      if (x.phase == 0) {
        sendOnOff(s, x.outlet, false);
        x.phase = 1;
        x.at = now + x.offMs;
      } else {
        sendOnOff(s, x.outlet, true);
        addEvent("cycle", s.mac, x.outlet, String(x.offMs / 1000) + " s");
        if (x.periodS) { x.phase = 0; x.at = now + x.periodS * 1000 - x.offMs; } else x.used = false;
      }
    } else {                                         // loop
      bool turnOn = x.phase == 0;
      sendOnOff(s, x.outlet, turnOn);
      x.phase = turnOn ? 1 : 0;
      x.at = now + (turnOn ? x.onMs : x.offMs);
    }
    stateDirty = true;
  }
  if (changed) saveTimers();
}

// ---------- schedules (NVS, run inside the hub) ----------
void tickSchedules() {
  static int lastMin = -1;
  struct tm t;
  if (!localNow(t) || t.tm_min == lastMin) return;
  lastMin = t.tm_min;
  uint32_t today = (uint32_t)(t.tm_year + 1900) * 10000 + (t.tm_mon + 1) * 100 + t.tm_mday;
  bool save = false;
  for (int i = 0; i < schedCount; i++) {
    Sched& c = scheds[i];
    if (!c.enabled || c.hh != t.tm_hour || c.mm != t.tm_min) continue;
    bool match = c.days ? (c.days & (1 << t.tm_wday)) : (c.date == today);
    if (!match) continue;
    if (schedSkipped(c.id)) {                      // v2.15.0: skipped once, runs again next time
      setSchedSkip(c.id, false);
      addEvent("skipped", c.mac, c.outlet, String(c.label));
      if (!c.days) { c.enabled = 0; save = true; }
      continue;
    }
    int idx = findStrip(c.mac);
    if (idx >= 0) { sendOnOff(strips[idx], c.outlet, c.on); addEvent("schedule", c.mac, c.outlet, String(c.label)); }
    else addEvent("missed", c.mac, c.outlet, String(c.label));
    if (!c.days) { c.enabled = 0; save = true; }
  }
  if (save) saveScheds();
}

// ---------- JSON builders ----------
bool hasSched(const String& mac, int outlet) {      // outlet 0 asks for whole-strip items only
  for (int i = 0; i < schedCount; i++)
    if (scheds[i].enabled && mac.equalsIgnoreCase(scheds[i].mac) && (scheds[i].outlet == outlet || scheds[i].outlet == 0)) return true;
  return false;
}
bool hasRule(const String& mac, int outlet) {
  for (int i = 0; i < autoCount; i++)
    if (autos[i].enabled && mac.equalsIgnoreCase(autos[i].mac) && (autos[i].outlet == outlet || autos[i].outlet == 0)) return true;
  return false;
}

String stripJson(int i) {
  const Strip& s = strips[i];
  float pw = 0, en = 0;
  bool any = false;
  uint32_t now = millis();
  String outs = "[";
  for (int k = 0; k < 4; k++) {
    const Outlet& o = s.o[k];
    float p = o.on ? o.powerW : 0;
    pw += p; en += o.energyWh / 1000.0f; any |= o.on;
    long left = s.autoOffAt[k] ? (long)((int32_t)(s.autoOffAt[k] - now) / 1000) : -1;
    if (k) outs += ",";
    outs += "{\"n\":" + String(k + 1) + ",\"on\":" + (o.on ? "true" : "false") + ",\"power_w\":" + String(o.powerW, 2) +
            ",\"energy_kwh\":" + String(o.energyWh / 1000.0f, 3) + ",\"temp_c\":" + String(o.tempC) +
            ",\"label\":\"" + jsonEsc(s.olabel[k]) + "\",\"locked\":" + ((s.lockMask & (1 << k)) ? "true" : "false") +
            ",\"protected\":" + ((s.protMask & (1 << k)) ? "true" : "false") + ",\"keep_on\":" + ((s.keepMask & (1 << k)) ? "true" : "false") +
            ",\"amp_limit\":" + (s.ampX2[k] ? String(s.ampX2[k] * 0.5f, 1) : "0") +
            ",\"auto_off_min\":" + String(s.autoOffMin[k]) +
            ",\"auto_off_in_s\":" + String(left < 0 ? -1 : left) + ",\"sched\":" + (hasSched(s.mac, k + 1) ? "true" : "false") +
            ",\"rule\":" + (hasRule(s.mac, k + 1) ? "true" : "false") + "}";
  }
  outs += "]";
  return "{\"mac\":\"" + s.mac + "\",\"name\":\"MTTL " + s.mac.substring(5) + "\",\"label\":\"" + jsonEsc(s.label) +
         "\",\"model\":\"" + s.model + "\",\"fw\":\"" + s.fw + "\",\"ip\":\"" + s.ip + "\",\"online\":true,\"on\":" + (any ? "true" : "false") +
         ",\"power_w\":" + String(pw, 2) + ",\"energy_kwh\":" + String(en, 3) +
         ",\"voltage\":" + (isnan(s.voltage) ? String("null") : String(s.voltage, 1)) +
         ",\"current_a\":" + (isnan(s.voltage) || s.voltage <= 0 ? String("0") : String(pw / s.voltage, 2)) +
         ",\"rssi\":" + (s.hasRssi ? String(s.rssi) : String("null")) + ",\"up_s\":" + String((millis() - s.connectedAt) / 1000) +
         ",\"notify\":" + String(s.notifyMask) +
         ",\"sched\":" + (hasSched(s.mac, 0) ? "true" : "false") + ",\"rule\":" + (hasRule(s.mac, 0) ? "true" : "false") + ",\"outlets\":" + outs + "}";
}

String timersJson() {
  String j = "[";
  bool first = true;
  uint32_t now = millis();
  for (int t = 0; t < MAX_TIMERS; t++) {
    const Timer& x = timers[t];
    if (!x.used) continue;
    if (!first) j += ",";
    first = false;
    long in = (int32_t)(x.at - now) / 1000;
    j += "{\"tid\":" + String(x.id) + ",\"mac\":\"" + String(x.mac) + "\",\"outlet\":" + String(x.outlet) +
         ",\"kind\":\"" + (x.kind == 2 ? "loop" : x.kind == 1 ? "cycle" : (x.on ? "on" : "off")) + "\",\"phase\":" + String(x.phase) +
         ",\"in_s\":" + String(in < 0 ? 0 : in) + ",\"off_s\":" + String(x.offMs / 1000) + ",\"on_s\":" + String(x.onMs / 1000) +
         ",\"repeat_s\":" + String(x.periodS) + "}";
  }
  return j + "]";
}

String buildStateJson() {
  String j = "{\"local_ip\":\"" + WiFi.localIP().toString() + "\",\"port\":" + String(STRIP_PORT) + ",\"hub_fw\":\"" + FW_VERSION +
             "\",\"hub\":\"" + hubId + "\",\"time_ok\":" + (timeOk() ? "true" : "false") + ",\"ts\":" + String((uint32_t)time(nullptr)) +
             ",\"uptime_s\":" + String(millis() / 1000) + ",\"nvs\":\"" + nvsId + "\"" +
             ",\"provision\":{\"state\":\"" + provState + "\",\"msg\":\"" + jsonEsc(provMsg) + "\"}" +
             ",\"config\":{\"temp_max\":" + String(tempMax) + ",\"temp_protect\":" + (tempProtect ? "true" : "false") +
             ",\"v_protect\":" + (vProt ? "true" : "false") + ",\"v_restore\":" + (vRestore ? "true" : "false") +
             ",\"v_max\":" + String(vMax) + ",\"v_min\":" + String(vMin) +
             ",\"a_protect\":" + (aProt ? "true" : "false") + ",\"a_max\":" + String(aMax, 1) +
             ",\"ntfy\":\"" + jsonEsc(ntfyTopic) + "\",\"ntypes\":" + String(notifyTypes) + ",\"ssid\":\"" + jsonEsc(secSsid) +
             "\",\"wifi_test\":\"" + wifiTestState + "\",\"wifi_test_ssid\":\"" + jsonEsc(wifiTestMsg) + "\"}" +
             ",\"cloud\":{\"up\":" + (mqttUp ? "true" : "false") + ",\"err\":\"" + mqttErr + "\",\"has_pass\":" + (secMqtt.length() ? "true" : "false") +
             ",\"user\":\"" + jsonEsc(secMqttUser) + "\",\"host\":\"" + mqttHost() + "\"}" +
             ",\"emqx_cfg\":" + (emqxReady() ? "true" : "false") + ",\"users_n\":" + String(userCount) +
             ",\"reset\":\"" + resetText() + "\"" + ",\"auth\":" + authJson() +
             ",\"timers\":" + timersJson() + ",\"devices\":[";
  bool first = true;
  for (int i = 0; i < MAX_STRIPS; i++) {
    if (!strips[i].used || !strips[i].identified) continue;
    if (!first) j += ",";
    j += stripJson(i);
    first = false;
  }
  for (int k = 0; k < knownCount; k++) {
    if (findStrip(known[k].mac) >= 0) continue;
    if (!first) j += ",";
    j += offlineStripJson(known[k]);
    first = false;
  }
  return j + "]}";
}

String schedJson(const Sched& c) {
  return "{\"sid\":" + String(c.id) + ",\"mac\":\"" + String(c.mac) + "\",\"outlet\":" + String(c.outlet) + ",\"on\":" + (c.on ? "true" : "false") +
         ",\"days\":" + String(c.days) + ",\"hh\":" + String(c.hh) + ",\"mm\":" + String(c.mm) + ",\"date\":" + String(c.date) +
         ",\"enabled\":" + (c.enabled ? "true" : "false") + ",\"skip\":" + (schedSkipped(c.id) ? "true" : "false") +
         ",\"label\":\"" + jsonEsc(String(c.label)) + "\"}";
}
String autoJson(const Autom& r) {
  return "{\"aid\":" + String(r.id) + ",\"mac\":\"" + String(r.mac) + "\",\"outlet\":" + String(r.outlet) + ",\"above\":" + (r.above ? "true" : "false") +
         ",\"watts\":" + String(r.watts, 1) + ",\"hold_s\":" + String(r.holdS) + ",\"act\":" + String(r.act) +
         ",\"enabled\":" + (r.enabled ? "true" : "false") + ",\"metric\":" + String(r.metric) + ",\"limit2\":" + String(r.limit2, 0) + ",\"label\":\"" + jsonEsc(String(r.label)) + "\"}";
}
// ---------- v2.15.10 link history per strip (the app's "network & connection" card) ----------
// Per strip and per day (7 days): seconds the hub was on Wi-Fi, seconds the strip was connected in that time, drops,
// the longest drop, and the lowest/average RSSI. Drops while the hub itself is off Wi-Fi are not counted: that is the
// hub's link, not the strip's. Kept in RAM and written to /links every 10 minutes.
const uint8_t LINK_NDAYS = 7, LINK_SLOTS = 8;
struct LinkDay { int32_t day; uint32_t hubS, upS, longS; uint16_t drops, rN; int32_t rSum; int8_t minR; uint8_t pad[3]; };
struct LinkLog { char mac[13]; uint8_t pad[3]; uint32_t lastDrop; LinkDay d[LINK_NDAYS]; };
struct LinkFile { uint32_t ver; uint32_t n; LinkLog l[LINK_SLOTS]; };
LinkFile linkF;
uint32_t linkDownAt[LINK_SLOTS];                     // epoch the strip dropped (RAM only, 0 = connected)
uint32_t linkTickAt = 0, linkSaveAt = 0;
uint32_t linkHubBlipAt = 0;                        // the hub's own Wi-Fi last dropped (strips drop with it: not counted)
bool linkDirty = false;

int linkIdx(const String& mac, bool create) {
  for (uint32_t i = 0; i < linkF.n; i++) if (mac.equalsIgnoreCase(linkF.l[i].mac)) return i;
  if (!create || mac.length() != 12) return -1;
  uint32_t i = linkF.n;
  if (i >= LINK_SLOTS) {                             // full: reuse the entry seen least recently
    i = 0;
    int32_t best = INT32_MAX;
    for (uint32_t k = 0; k < LINK_SLOTS; k++) {
      int32_t last = 0;
      for (int d = 0; d < LINK_NDAYS; d++) last = max(last, linkF.l[k].d[d].day);
      if (last < best) { best = last; i = k; }
    }
  } else linkF.n++;
  memset(&linkF.l[i], 0, sizeof(LinkLog));
  strlcpy(linkF.l[i].mac, mac.c_str(), sizeof linkF.l[i].mac);
  linkDownAt[i] = 0;
  linkDirty = true;
  return i;
}
LinkDay* linkToday(int i) {
  int32_t today = localDay();
  if (!today) return nullptr;
  LinkDay& d = linkF.l[i].d[((today % LINK_NDAYS) + LINK_NDAYS) % LINK_NDAYS];
  if (d.day != today) { memset(&d, 0, sizeof d); d.day = today; }
  return &d;
}
void linkLoad() {
  memset(&linkF, 0, sizeof linkF);
  if (!fileLoad("/links", &linkF, sizeof linkF) || linkF.ver != 1 || linkF.n > LINK_SLOTS) { memset(&linkF, 0, sizeof linkF); }
  linkF.ver = 1;
  memset(linkDownAt, 0, sizeof linkDownAt);
}
void linkSave() { if (fileSave("/links", &linkF, sizeof linkF)) linkDirty = false; }
void linkDrop(const String& mac) {
  if (!timeOk() || WiFi.status() != WL_CONNECTED) return;
  if (linkHubBlipAt && millis() - linkHubBlipAt < 90000) return;   // fallout of the hub's own Wi-Fi drop
  int i = linkIdx(mac, true);
  if (i < 0 || linkDownAt[i]) return;
  LinkDay* d = linkToday(i);
  if (!d) return;
  uint32_t t = (uint32_t)time(nullptr);
  linkDownAt[i] = t;
  linkF.l[i].lastDrop = t;
  d->drops++;
  linkDirty = true;
}
void linkUp(const String& mac) {
  int i = linkIdx(mac, true);
  if (i < 0 || !linkDownAt[i] || !timeOk()) { if (i >= 0) linkDownAt[i] = 0; return; }
  uint32_t dur = (uint32_t)time(nullptr) - linkDownAt[i];
  linkDownAt[i] = 0;
  LinkDay* d = linkToday(i);
  if (d && dur < 86400UL * 7 && dur > d->longS) d->longS = dur;
  linkDirty = true;
}
void linkTick() {
  uint32_t now = millis();
  if (now - linkTickAt < 10000) return;
  uint32_t dt = (now - linkTickAt) / 1000;
  linkTickAt = now;
  if (dt > 60 || !timeOk()) return;                // first tick, or the loop was held (Wi-Fi down): skip that gap
  for (uint32_t i = 0; i < linkF.n; i++) {
    String mac = linkF.l[i].mac;
    if (isBlocked(mac)) continue;
    LinkDay* d = linkToday(i);
    if (!d) return;
    d->hubS += dt;
    int idx = findStrip(mac);
    if (idx >= 0 && strips[idx].identified) {
      d->upS += dt;
      if (strips[idx].hasRssi && strips[idx].rssi < 0 && strips[idx].rssi > -127) {
        int8_t r = strips[idx].rssi;
        if (!d->rN || r < d->minR) d->minR = r;
        d->rSum += r;
        d->rN++;
      }
    }
  }
  linkDirty = true;
  if (now - linkSaveAt > 600000) { linkSaveAt = now; linkSave(); }
}
String linkJson(const String& mac) {
  int i = linkIdx(mac, false);
  int idx = findStrip(mac);
  String j = "{\"mac\":\"" + mac + "\",\"time_ok\":" + (timeOk() ? "true" : "false") + ",\"rssi\":" +
             (idx >= 0 && strips[idx].hasRssi ? String(strips[idx].rssi) : String("null")) + ",\"ip\":\"" + (idx >= 0 ? strips[idx].ip : String("")) + "\"";
  if (i < 0) return j + ",\"last_drop\":0,\"down_since\":0,\"days\":[]}";
  const LinkLog& L = linkF.l[i];
  j += ",\"last_drop\":" + String(L.lastDrop) + ",\"down_since\":" + String(linkDownAt[i]) + ",\"days\":[";
  // newest first; "day" counts days since 1970-01-01 (hub local date)
  int32_t today = localDay();
  bool first = true;
  for (int back = 0; back < LINK_NDAYS && today; back++) {
    int32_t want = today - back;
    const LinkDay& d = L.d[((want % LINK_NDAYS) + LINK_NDAYS) % LINK_NDAYS];
    if (d.day != want) continue;
    if (!first) j += ",";
    first = false;
    j += "{\"day\":" + String(d.day) + ",\"hub_s\":" + String(d.hubS) + ",\"up_s\":" + String(d.upS) + ",\"drops\":" + String((unsigned)d.drops) +
         ",\"long_s\":" + String(d.longS) + ",\"min\":" + (d.rN ? String((int)d.minR) : String("null")) +
         ",\"avg\":" + (d.rN ? String((int)lround((double)d.rSum / d.rN)) : String("null")) + "}";
  }
  return j + "]}";
}

String eventsJson() {
  String j = "{\"events\":[";
  for (int n = 0; n < evCount; n++) {
    int idx = ((int)evHead - 1 - n + MAX_EVENTS) % MAX_EVENTS;   // newest first
    const Ev& e = events[idx];
    if (n) j += ",";
    j += "{\"ts\":" + String(e.ts) + ",\"type\":\"" + e.type + "\",\"mac\":\"" + e.mac + "\",\"outlet\":" + String(e.outlet) +
         ",\"msg\":\"" + jsonEsc(e.msg) + "\"}";
  }
  return j + "]}";
}
String energyJson(int i) {
  const Strip& s = strips[i];
  const ELog& el = elogs[i];
  String j = "{\"mac\":\"" + s.mac + "\",\"time_ok\":" + (timeOk() ? "true" : "false") + ",\"today\":" +
             String(el.day ? civilFromDays(el.day) : 0) + ",\"today_wh\":[";
  for (int k = 0; k < 4; k++) {
    if (k) j += ",";
    uint32_t c = s.o[k].energyWh;
    j += String(el.day && c >= el.base[k] ? c - el.base[k] : 0);
  }
  const PeakLog& pl = peaks[i];
  j += "],\"today_peak_w\":" + String(pl.day == el.day ? pl.today : 0) + ",\"days\":[";
  bool first = true;
  for (int back = 1; back <= ELOG_DAYS; back++) {
    int32_t d = el.day - back;
    int idx = ((d % ELOG_DAYS) + ELOG_DAYS) % ELOG_DAYS;
    if (!el.day || el.dayOf[idx] != d) continue;
    if (!first) j += ",";
    first = false;
    int pk = pl.dayOf[idx] == d ? pl.pk[idx] : -1;
    j += "{\"date\":" + String(civilFromDays(d)) + ",\"wh\":[" + String(el.wh[idx][0]) + "," + String(el.wh[idx][1]) + "," +
         String(el.wh[idx][2]) + "," + String(el.wh[idx][3]) + "],\"peak_w\":" + String(pk) + "}";
  }
  return j + "]}";
}


// ---------- v2.9 shared users ----------
ApiRes api(String path, const String& b);
ApiRes okRes(const String& data);
ApiRes okRes();
ApiRes errRes(const String& e);
void publishUserState(const HubUser& u);
const uint32_t USERS_MAGIC = 0x55535231;
void loadUsers() {
  Preferences up; up.begin("users", true);
  static UsersNV nv;
  memset(&nv, 0, sizeof nv);
  if (up.getBytesLength("list") == sizeof nv) up.getBytes("list", &nv, sizeof nv);
  up.end();
  userCount = 0;
  if (nv.magic != USERS_MAGIC) return;
  for (int i = 0; i < nv.count && i < MAX_USERS; i++) if (nv.u[i].id[0]) users[userCount++] = nv.u[i];
}
void saveUsers() {
  static UsersNV nv;
  memset(&nv, 0, sizeof nv);
  nv.magic = USERS_MAGIC; nv.count = userCount;
  for (int i = 0; i < userCount; i++) nv.u[i] = users[i];
  Preferences up;
  bool ok = up.begin("users", false) && up.putBytes("list", &nv, sizeof nv) == sizeof nv;
  up.end();
  if (!ok) saveFailed("family accounts");
}
void loadEmqx() {
  Preferences sp; sp.begin("sec", true);
  exUrl = sp.getString("ex_url", ""); exKey = sp.getString("ex_key", ""); exSec = sp.getString("ex_sec", "");
  sp.end();
}
bool emqxReady() { return exUrl.length() && exKey.length() && exSec.length(); }
int findUser(const String& id) { for (int i = 0; i < userCount; i++) if (id == users[i].id) return i; return -1; }
bool userHas(const HubUser& u, const String& macIn) {
  if (u.all) return true;
  String m = macIn; m.toUpperCase();
  for (int k = 0; k < u.n && k < 6; k++) if (m == u.strips[k]) return true;
  return false;
}
void parseStrips(HubUser& u, const String& list) {
  u.n = 0; memset(u.strips, 0, sizeof u.strips);
  for (String p : split(list, ',')) {
    p.trim(); p.toUpperCase();
    if (p.length() == 12 && isHex(p) && u.n < 6) strlcpy(u.strips[u.n++], p.c_str(), 13);
  }
}
String userJson(const HubUser& u) {
  String j = "{\"id\":\"" + String(u.id) + "\",\"name\":\"" + jsonEsc(String(u.name)) + "\",\"role\":" + String(u.role) +
             ",\"all\":" + (u.all ? "true" : "false") + ",\"strips\":[";
  for (int k = 0; k < u.n && k < 6; k++) { if (k) j += ","; j += "\"" + String(u.strips[k]) + "\""; }
  return j + "]}";
}

// ---------- v2.15.13 hub lock ----------
void loadOwners() {
  Preferences ap; ap.begin("auth", true);
  size_t n = ap.getBytesLength("owners");
  ownerCount = 0;
  if (n && n % sizeof(OwnerDev) == 0 && n <= sizeof owners) { ap.getBytes("owners", owners, n); ownerCount = n / sizeof(OwnerDev); }
  ap.end();
}
void saveOwners() {
  Preferences ap;
  bool ok = ap.begin("auth", false);
  if (ok) ok = ownerCount ? ap.putBytes("owners", owners, ownerCount * sizeof(OwnerDev)) == ownerCount * sizeof(OwnerDev) : ap.remove("owners") || true;
  ap.end();
  if (!ok) saveFailed("owner phones");
  stateDirty = true;
}
bool isOwnerKey(const String& k) {
  if (k.length() < 16) return false;
  for (int i = 0; i < ownerCount; i++) if (k == owners[i].key) return true;
  return false;
}
int ownerByEmail(const String& e) { for (int i = 0; i < ownerCount; i++) if (e == owners[i].email) return i; return -1; }
// a phone of this email becomes an owner phone (the same email again replaces its old phone); returns its key
String addOwner(const String& email, const String& model) {
  int i = ownerByEmail(email);
  if (i < 0) {
    if (ownerCount < MAX_OWNERS) i = ownerCount++;
    else {                                       // full: the oldest phone gives way
      i = 0;
      for (int k = 1; k < ownerCount; k++) if (owners[k].ts < owners[i].ts) i = k;
    }
  }
  String key = randText(32);
  OwnerDev& o = owners[i];
  memset(&o, 0, sizeof o);
  strlcpy(o.key, key.c_str(), sizeof o.key);
  strlcpy(o.email, email.c_str(), sizeof o.email);
  strlcpy(o.model, model.c_str(), sizeof o.model);
  o.ts = timeOk() ? (uint32_t)time(nullptr) : 0;
  saveOwners();
  return key;
}
String cleanEmail(String e) { e.trim(); e.toLowerCase(); return (e.length() >= 3 && e.length() < 48 && e.indexOf('@') > 0 && e.indexOf('"') < 0) ? e : String(""); }
String cleanModel(String m) { m.trim(); m.replace("\"", ""); return m.substring(0, 31); }
void pairsExpire() {
  for (int i = 0; i < MAX_PAIRS; i++) {
    PairReq& p = pairs[i];
    if (!p.state || p.job) continue;
    if (millis() - p.at > (p.state == 1 ? 300000UL : 600000UL)) { if (p.state == 1) stateDirty = true; p = PairReq(); }
  }
}
int pairFind(uint32_t id) { for (int i = 0; i < MAX_PAIRS; i++) if (pairs[i].state && pairs[i].id == id) return i; return -1; }
String authJson() {
  pairsExpire();
  String j = "{\"claimed\":" + String(ownerCount ? "true" : "false") + ",\"owners\":[";
  for (int i = 0; i < ownerCount; i++) {
    if (i) j += ",";
    j += "{\"email\":\"" + jsonEsc(String(owners[i].email)) + "\",\"model\":\"" + jsonEsc(String(owners[i].model)) + "\",\"ts\":" + String(owners[i].ts) + "}";
  }
  j += "],\"pair\":[";
  bool f = true;
  for (int i = 0; i < MAX_PAIRS; i++) {
    const PairReq& p = pairs[i];
    if (p.state != 1 || p.job) continue;
    if (!f) j += ",";
    f = false;
    j += "{\"id\":" + String(p.id) + ",\"email\":\"" + jsonEsc(p.email) + "\",\"model\":\"" + jsonEsc(p.model) + "\",\"owner\":" +
         (p.owner ? "true" : "false") + ",\"choices\":[" + String(p.ch[0]) + "," + String(p.ch[1]) + "," + String(p.ch[2]) + "]}";
  }
  return j + "]}";
}
String inviteCode(const HubUser& u, const String& pw) {
  return b64url("{\"v\":1,\"h\":\"" + mqttHost() + "\",\"p\":8883,\"hub\":\"" + hubId + "\",\"u\":\"" + String(u.id) + "\",\"pw\":\"" + pw +
                "\",\"n\":\"" + jsonEsc(String(u.name)) + "\",\"r\":" + String(u.role) + ",\"lip\":\"" + WiFi.localIP().toString() + "\"}");
}
// the three routes a phone without a key may call
void authRoute(const String& uri, const String& b) {
  auto out = [](int code, const String& j) { web.send(code, "application/json", j); };
  if (uri == "/api/auth/claim") {                 // {"ota","email","model"}: the update password proves the hub is yours
    if (claimLockUntil && (int32_t)(millis() - claimLockUntil) < 0) return out(429, "{\"ok\":false,\"error\":\"wait\"}");
    String email = cleanEmail(jsonValue(b, "email"));
    if (!email.length()) return out(400, "{\"ok\":false,\"error\":\"email\"}");
    if (ownerCount) return out(409, "{\"ok\":false,\"error\":\"claimed\"}");   // later phones are added through pairing
    String key = addOwner(email, cleanModel(jsonValue(b, "model")));
    addEvent("owner", "", 0, email);
    return out(200, "{\"ok\":true,\"data\":{\"key\":\"" + key + "\"}}");
  }
  if (uri == "/api/pair/request") {               // {"email","model"} -> {"id","code"}: the code is shown on the new phone
    if (!ownerCount) return out(409, "{\"ok\":false,\"error\":\"not_claimed\"}");
    String email = cleanEmail(jsonValue(b, "email"));
    if (!email.length()) return out(400, "{\"ok\":false,\"error\":\"email\"}");
    pairsExpire();
    int slot = -1;
    for (int i = 0; i < MAX_PAIRS; i++) if (pairs[i].state == 1 && !pairs[i].job && pairs[i].email == email) slot = i;
    for (int i = 0; slot < 0 && i < MAX_PAIRS; i++) if (!pairs[i].state) slot = i;
    if (slot < 0) return out(429, "{\"ok\":false,\"error\":\"busy\"}");
    PairReq& p = pairs[slot];
    p = PairReq();
    do { p.id = esp_random() & 0x7FFFFFFF; } while (!p.id);
    p.code = 10 + esp_random() % 90;
    uint8_t a, c;
    do { a = 10 + esp_random() % 90; } while (a == p.code);
    do { c = 10 + esp_random() % 90; } while (c == p.code || c == a);
    uint8_t at = esp_random() % 3;
    p.ch[at] = p.code; p.ch[(at + 1) % 3] = a; p.ch[(at + 2) % 3] = c;
    p.email = email; p.model = cleanModel(jsonValue(b, "model"));
    p.owner = ownerByEmail(email) >= 0;
    p.state = 1; p.at = millis();
    addEvent("pair", "", 0, email);
    stateDirty = true;
    return out(200, "{\"ok\":true,\"data\":{\"id\":" + String(p.id) + ",\"code\":" + String(p.code) + "}}");
  }
  if (uri == "/api/pair/poll") {                  // {"id","code"} -> pending | ok (+ key or invite code, once) | refused | expired
    pairsExpire();
    int i = pairFind((uint32_t)strtoul(jsonValue(b, "id").c_str(), nullptr, 10));
    if (i < 0 || jsonValue(b, "code").toInt() != pairs[i].code) return out(200, "{\"ok\":true,\"data\":{\"state\":\"expired\"}}");
    PairReq& p = pairs[i];
    if (p.state == 1) return out(200, "{\"ok\":true,\"data\":{\"state\":\"pending\"}}");
    String d = p.state == 2 ? "{\"state\":\"ok\"," + p.result + "}" : String("{\"state\":\"refused\"}");
    p = PairReq();
    return out(200, "{\"ok\":true,\"data\":" + d + "}");
  }
  out(404, "{\"ok\":false,\"error\":\"not found\"}");
}
String randText(int len) {
  static const char A[] = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
  String s; for (int i = 0; i < len; i++) s += A[esp_random() % (sizeof(A) - 1)];
  return s;
}
String b64url(const String& in) {
  size_t olen = 0;
  size_t cap = ((in.length() + 2) / 3) * 4 + 4;
  std::vector<unsigned char> out(cap);
  if (mbedtls_base64_encode(out.data(), cap, &olen, (const unsigned char*)in.c_str(), in.length()) != 0) return "";
  String r;
  for (size_t i = 0; i < olen; i++) { char c = out[i]; if (c == '+') c = '-'; else if (c == '/') c = '_'; else if (c == '=') continue; r += c; }
  return r;
}
String mqttHost() {
  String u = secMqttUri;
  int s = u.indexOf("://"); if (s >= 0) u = u.substring(s + 3);
  int c = u.indexOf(':'); if (c > 0) u = u.substring(0, c);
  return u;
}
bool http2xx(int c) { return c >= 200 && c < 300; }
const char* EX_AUTHN = "/api/v5/authentication/password_based:built_in_database/users";
const char* EX_AUTHZ = "/api/v5/authorization/sources/built_in_database/rules/users";
// One HTTPS call to the EMQX management API (runs only inside the job task). Returns the HTTP code (<0 = no connection).
int emqxCall(const char* method, const String& path, const String& body) {
  int code;
  WiFiClientSecure tls;
  tls.setCACert(MQTT_CA);
  tls.setHandshakeTimeout(12);
  tls.setTimeout(12);
  HTTPClient h;
  h.setConnectTimeout(8000);
  h.setTimeout(10000);
  h.setReuse(false);
  if (!h.begin(tls, exUrl + path)) code = -1;
  else {
    h.setAuthorization(exKey.c_str(), exSec.c_str());
    h.addHeader("Content-Type", "application/json");
    code = h.sendRequest(method, body);
    exLast = code > 0 ? h.getString().substring(0, 160) : HTTPClient::errorToString(code);
    h.end();
  }
  Serial.printf("[emqx] %s %s -> %d %s\n", method, path.c_str(), code, exLast.c_str());
  return code;
}
// EMQX work runs in its own task so the hub keeps switching strips meanwhile.
// kind 1 invite · 2 revoke · 3 test the API details. state 0 idle · 1 running · 2 finished (loop collects) · 3 result ready
struct ExJob { volatile uint8_t state = 0; uint8_t kind = 0; HubUser u; String pw, base, err; int c1 = 0, c2 = 0; bool ok = false; String data; };
ExJob exJob;
static void exTask(void*) {
  ExJob& j = exJob;
  tlsBusy = true;
  bool paused = false;
  if (mqtt) { esp_mqtt_client_stop(mqtt); mqttUp = false; paused = true; }   // two TLS sessions don't fit in RAM
  vTaskDelay(pdMS_TO_TICKS(300));
  if (j.kind == 1 || j.kind == 4) {
    j.c1 = emqxCall("POST", EX_AUTHN, "{\"user_id\":\"" + String(j.u.id) + "\",\"password\":\"" + j.pw + "\"}");
    if (http2xx(j.c1)) {
      String rules = "[{\"username\":\"" + String(j.u.id) + "\",\"rules\":["
                     "{\"topic\":\"" + j.base + "u/" + j.u.id + "/cmd\",\"permission\":\"allow\",\"action\":\"publish\"},"
                     "{\"topic\":\"" + j.base + "u/" + j.u.id + "/#\",\"permission\":\"allow\",\"action\":\"subscribe\"},"
                     "{\"topic\":\"" + j.base + "status\",\"permission\":\"allow\",\"action\":\"subscribe\"},"
                     "{\"topic\":\"#\",\"permission\":\"deny\",\"action\":\"all\"}]}]";
      j.c2 = emqxCall("POST", EX_AUTHZ, rules);
      if (!http2xx(j.c2)) emqxCall("DELETE", String(EX_AUTHN) + "/" + j.u.id, "");   // rollback
    }
  } else if (j.kind == 2) {
    j.c1 = emqxCall("DELETE", String(EX_AUTHN) + "/" + j.u.id, "");
    j.c2 = emqxCall("DELETE", String(EX_AUTHZ) + "/" + j.u.id, "");
  } else {
    j.c1 = emqxCall("GET", String(EX_AUTHN) + "?limit=1", "");
    j.c2 = 200;
  }
  if (paused && mqtt) esp_mqtt_client_start(mqtt);
  tlsBusy = false;
  j.state = 2;
  vTaskDelete(nullptr);
}
bool exStart(uint8_t kind) {
  if (exJob.state == 1) return false;
  exJob.kind = kind; exJob.c1 = exJob.c2 = 0; exJob.ok = false; exJob.err = ""; exJob.data = "";
  exJob.state = 1;
  if (xTaskCreatePinnedToCore(exTask, "emqx", 12288, nullptr, 1, nullptr, 0) != pdPASS) { exJob.state = 0; return false; }
  return true;
}
String exCodeText(int c) { return c < 0 ? "no connection (" + exLast + ")" : "HTTP " + String(c) + (exLast.length() ? " " + exLast : ""); }
// called from loop(): applies a finished job (users[] is only touched here)
void exCollect() {
  if (exJob.state != 2) return;
  ExJob& j = exJob;
  if (j.kind == 1) {
    j.ok = http2xx(j.c1) && http2xx(j.c2);
    if (j.ok && userCount < MAX_USERS) {
      strlcpy(j.u.pw, j.pw.c_str(), sizeof(j.u.pw));
      users[userCount++] = j.u;
      saveUsers();
      publishUserState(j.u);
      String code = inviteCode(j.u, j.pw);
      j.data = "{\"code\":\"" + code + "\",\"user\":" + userJson(j.u) + "}";
      int pi = pairJobId ? pairFind(pairJobId) : -1;   // v2.15.13: an approved phone gets its invite on its next poll
      if (pi >= 0) { pairs[pi].result = "\"code\":\"" + code + "\""; pairs[pi].state = 2; pairs[pi].job = false; pairs[pi].at = millis(); }
    } else j.err = "emqx " + exCodeText(http2xx(j.c1) ? j.c2 : j.c1);
    if (pairJobId) { int pi = pairFind(pairJobId); if (pi >= 0 && pairs[pi].job) { pairs[pi].state = 3; pairs[pi].job = false; pairs[pi].at = millis(); } }
    pairJobId = 0;
    j.pw = "";
  } else if (j.kind == 2) {
    j.ok = (http2xx(j.c1) || j.c1 == 404) && (http2xx(j.c2) || j.c2 == 404);
    if (j.ok) {
      int i = findUser(j.u.id);
      mqttPub("mttl/" + hubId + "/u/" + String(j.u.id) + "/state", "", 1, true);
      if (i >= 0) { for (int k = i; k < userCount - 1; k++) users[k] = users[k + 1]; userCount--; saveUsers(); }
    } else j.err = "emqx " + exCodeText(http2xx(j.c1) || j.c1 == 404 ? j.c2 : j.c1);
  } else if (j.kind == 4) {                      // v2.15.14: server login for a phone that is already in
    j.ok = http2xx(j.c1) && http2xx(j.c2);
    if (j.ok && cloudTodoId == j.u.id) { cloudTodoId = ""; cloudTodoPw = ""; }
    else cloudTodoAt = millis();                 // try again later
    j.pw = "";
    j.state = 0;                                 // background job: nobody reads its result
    return;
  } else {
    j.ok = http2xx(j.c1);
    if (!j.ok) j.err = "emqx " + exCodeText(j.c1);
  }
  j.state = 3;
  stateDirty = true;
}

// v2.15.14: makes the server login of an approved phone when the server worker is free (every 10 min on failure)
void cloudTodoPump() {
  if (!cloudTodoId.length() || exJob.state == 1 || tlsBusy || !emqxReady()) return;
  if (cloudTodoAt && millis() - cloudTodoAt < 600000UL) return;
  int i = findUser(cloudTodoId);
  if (i < 0) { cloudTodoId = ""; cloudTodoPw = ""; return; }
  exJob.u = users[i]; exJob.pw = cloudTodoPw; exJob.base = "mttl/" + hubId + "/";
  cloudTodoAt = millis();
  exStart(4);
}
String resetText() {
  switch (esp_reset_reason()) {
    case ESP_RST_POWERON: return "power";
    case ESP_RST_SW: return "restart";
    case ESP_RST_PANIC: return "crash";
    case ESP_RST_INT_WDT: case ESP_RST_TASK_WDT: case ESP_RST_WDT: return "watchdog";
    case ESP_RST_BROWNOUT: return "brownout";
    default: return "other";
  }
}

// what a shared user may call · 0 view · 1 control · 2 admin · -1 never
int needRole(const String& p) {
  if (p == "state" || p == "events" || p == "energy" || p == "link" || p == "schedules" || p == "automations") return 0;
  if (p == "onoff" || p == "refresh" || p == "timer" || p == "timer_cancel" || p == "schedule_save" || p == "schedule_delete" || p == "schedule_skip") return 1;
  if (p == "label" || p == "lock" || p == "protect" || p == "autooff" || p == "keepon" || p == "amplimit" || p == "automation_save" || p == "automation_delete") return 2;
  return -1;
}
// the mac an action touches ("" = none / global)
String actionMac(const String& p, const String& b) {
  if (p == "timer_cancel") {
    uint32_t id = (uint32_t)jsonValue(b, "tid").toInt();
    for (int t = 0; t < MAX_TIMERS; t++) if (timers[t].used && timers[t].id == id) return String(timers[t].mac);
    return "?";
  }
  if (p == "schedule_delete" || p == "schedule_skip" || (p == "schedule_save" && jsonValue(b, "sid").toInt())) {
    uint32_t id = (uint32_t)jsonValue(b, "sid").toInt();
    for (int i = 0; i < schedCount; i++) if (scheds[i].id == id) {
      if (p == "schedule_save" && jsonHas(b, "mac") && !jsonValue(b, "mac").equalsIgnoreCase(scheds[i].mac)) return "?";
      return String(scheds[i].mac);
    }
    return p == "schedule_save" ? jsonValue(b, "mac") : "?";
  }
  if (p == "automation_delete" || (p == "automation_save" && jsonValue(b, "aid").toInt())) {
    uint32_t id = (uint32_t)jsonValue(b, "aid").toInt();
    for (int i = 0; i < autoCount; i++) if (autos[i].id == id) {
      if (p == "automation_save" && jsonHas(b, "mac") && !jsonValue(b, "mac").equalsIgnoreCase(autos[i].mac)) return "?";
      return String(autos[i].mac);
    }
    return p == "automation_delete" ? "?" : jsonValue(b, "mac");
  }
  return jsonValue(b, "mac");
}
String userStateJson(const HubUser& u) {
  String j = "{\"hub_fw\":\"" + String(FW_VERSION) + "\",\"hub\":\"" + hubId + "\",\"time_ok\":" + (timeOk() ? "true" : "false") +
             ",\"lip\":\"" + WiFi.localIP().toString() + "\",\"ts\":" + String((uint32_t)time(nullptr)) + ",\"uptime_s\":" + String(millis() / 1000) + ",\"me\":" + userJson(u) + ",\"timers\":[";
  bool first = true;
  uint32_t now = millis();
  for (int t = 0; t < MAX_TIMERS; t++) {
    const Timer& x = timers[t];
    if (!x.used || !userHas(u, x.mac)) continue;
    if (!first) j += ",";
    first = false;
    long in = (int32_t)(x.at - now) / 1000;
    j += "{\"tid\":" + String(x.id) + ",\"mac\":\"" + String(x.mac) + "\",\"outlet\":" + String(x.outlet) +
         ",\"kind\":\"" + (x.kind == 2 ? "loop" : x.kind == 1 ? "cycle" : (x.on ? "on" : "off")) + "\",\"phase\":" + String(x.phase) +
         ",\"in_s\":" + String(in < 0 ? 0 : in) + ",\"off_s\":" + String(x.offMs / 1000) + ",\"on_s\":" + String(x.onMs / 1000) +
         ",\"repeat_s\":" + String(x.periodS) + "}";
  }
  j += "],\"devices\":[";
  first = true;
  for (int i = 0; i < MAX_STRIPS; i++) {
    if (!strips[i].used || !strips[i].identified || !userHas(u, strips[i].mac)) continue;
    if (!first) j += ",";
    j += stripJson(i);
    first = false;
  }
  for (int k = 0; k < knownCount; k++) {
    if (findStrip(known[k].mac) >= 0 || !userHas(u, known[k].mac)) continue;
    if (!first) j += ",";
    j += offlineStripJson(known[k]);
    first = false;
  }
  return j + "]}";
}
// list actions answered per user (filtered to the user's strips)
bool userList(const HubUser& u, const String& p, ApiRes& r) {
  String j;
  if (p == "schedules") {
    j = "{\"schedules\":["; bool f = true;
    for (int i = 0; i < schedCount; i++) if (userHas(u, scheds[i].mac)) { if (!f) j += ","; f = false; j += schedJson(scheds[i]); }
    r = okRes(j + "]}"); return true;
  }
  if (p == "automations") {
    j = "{\"automations\":["; bool f = true;
    for (int i = 0; i < autoCount; i++) if (userHas(u, autos[i].mac)) { if (!f) j += ","; f = false; j += autoJson(autos[i]); }
    r = okRes(j + "]}"); return true;
  }
  if (p == "events") {
    j = "{\"events\":["; bool f = true;
    for (int n = 0; n < evCount; n++) {
      const Ev& e = events[((int)evHead - 1 - n + MAX_EVENTS) % MAX_EVENTS];
      if (e.mac.length() ? !userHas(u, e.mac) : !u.all) continue;
      if (e.type.startsWith("pair") || e.type == "owner") continue;
      if (!f) j += ","; f = false;
      j += "{\"ts\":" + String(e.ts) + ",\"type\":\"" + e.type + "\",\"mac\":\"" + e.mac + "\",\"outlet\":" + String(e.outlet) +
           ",\"msg\":\"" + jsonEsc(e.msg) + "\"}";
    }
    r = okRes(j + "]}"); return true;
  }
  if (p == "state") { r = okRes(userStateJson(u)); return true; }
  return false;
}
ApiRes userApi(const HubUser& u, String path, const String& b) {
  if (path.startsWith("/api/")) path = path.substring(5);
  int need = needRole(path);
  if (need < 0 || u.role < need) return errRes("forbidden");
  ApiRes r;
  if (userList(u, path, r)) return r;
  String m = actionMac(path, b);
  if (path == "refresh") { if (!u.all) return errRes("forbidden"); }
  else if (!m.length() || m == "?" || !userHas(u, m)) return errRes("forbidden");
  return api(path, b);
}

// ---------- API (shared by HTTP and MQTT) ----------
ApiRes okRes(const String& data) { return {true, "", data}; }
ApiRes okRes() { return {true, "", ""}; }
ApiRes errRes(const String& e) { return {false, e, ""}; }
void requestProvision() { provRequested = true; provAt = millis(); provState = "queued"; provMsg = ""; stateDirty = true; }

ApiRes api(String path, const String& b) {
  if (path.startsWith("/api/")) path = path.substring(5);
  String mac = jsonValue(b, "mac");
  int outlet = jsonValue(b, "outlet").toInt();

  if (path == "onoff") {
    int idx = stripFor(mac);
    if (idx < 0) return errRes("device offline");
    if (outlet < 0 || outlet > 4 || !jsonHas(b, "on")) return errRes("bad request");
    bool on = jsonBool(b, "on");
    if (!setOutlets(strips[idx], outlet, on)) return errRes("not confirmed");
    addEvent("remote", strips[idx].mac, outlet, on ? "on" : "off");
    return okRes();
  }
  if (path == "refresh") {
    for (int i = 0; i < MAX_STRIPS; i++) {
      Strip& s = strips[i];
      if (!s.used || !s.identified) continue;
      uint32_t seq = s.infoSeq;
      sendLine(s, "up:getinfo:all");
      waitForInfo(s, seq, 2000);
    }
    return okRes();
  }
  if (path == "label" || path == "lock" || path == "protect" || path == "autooff" || path == "keepon") {
    int idx = stripFor(mac);
    if (idx < 0) return errRes("device offline");
    Strip& s = strips[idx];
    if (path == "label") {
      String label = jsonValue(b, "label");
      if (outlet < 0 || outlet > 4) return errRes("bad outlet");
      if (label.length() > 96) return errRes("label too long");
      String key = outlet == 0 ? "n" + s.mac : "n" + s.mac + String(outlet);
      if (label.length()) cfg.putString(key.c_str(), label); else cfg.remove(key.c_str());
      if (outlet == 0) s.label = label; else s.olabel[outlet - 1] = label;
    } else {
      if (outlet < 1 || outlet > 4) return errRes("bad outlet");
      uint8_t bit = 1 << (outlet - 1);
      if (path == "lock") {
        if (jsonBool(b, "locked")) {
          s.lockMask |= bit;
          if (s.o[outlet - 1].on) s.lockState |= bit; else s.lockState &= ~bit;
        } else s.lockMask &= ~bit;
        saveLocks(s);
      } else if (path == "keepon") {
        bool en = jsonBool(b, "on");
        if (en) s.keepMask |= bit; else s.keepMask &= ~bit;
        s.keepHold &= ~bit;
        cfg.putUChar(("q" + s.mac).c_str(), s.keepMask);
        if (en && !s.o[outlet - 1].on) sendOnOff(s, outlet, true);
      } else if (path == "protect") {
        if (jsonBool(b, "protected")) s.protMask |= bit; else s.protMask &= ~bit;
        cfg.putUChar(("p" + s.mac).c_str(), s.protMask);
      } else {
        int m = jsonValue(b, "minutes").toInt();
        if (m < 0 || m > 1440) return errRes("minutes 0..1440");
        s.autoOffMin[outlet - 1] = m;
        cfg.putBytes(("a" + s.mac).c_str(), s.autoOffMin, sizeof(s.autoOffMin));
        s.autoOffAt[outlet - 1] = (m && s.o[outlet - 1].on) ? millis() + (uint32_t)m * 60000UL : 0;
      }
    }
    refreshKnown(s.mac);
    stateDirty = true;
    return okRes();
  }
  // ---- v2.9: cloud password + shared users (owner only) ----
  if (path == "cloud") {                          // {"host","user","pass"} local network only
    if (apiSrc != 0) return errRes("local_only");
    bool changed = false;
    if (jsonHas(b, "host")) {                     // server address (hostname only, port 8883)
      String h = jsonValue(b, "host");
      h.trim();
      bool ok = h.length() >= 4 && h.length() <= 120 && h.indexOf("://") < 0;
      for (size_t i = 0; ok && i < h.length(); i++) ok = isalnum((unsigned char)h[i]) || h[i] == '.' || h[i] == '-';
      if (!ok) return errRes("bad server address");
      String u = "mqtts://" + h + ":8883";
      if (u != secMqttUri) { changed = true; Preferences sp; sp.begin("sec", false); sp.putString("muri", u); sp.end(); secMqttUri = u; }
    }
    if (jsonHas(b, "lip")) {                      // hub address on the home network; the hub restarts to use it
      String s2 = jsonValue(b, "lip");
      s2.trim();
      IPAddress ip;
      bool ok = ip.fromString(s2) && ip[0] == GATEWAY[0] && ip[1] == GATEWAY[1] && ip[2] == GATEWAY[2] && ip[3] > 1 && ip[3] < 255 && ip != GATEWAY;
      if (!ok) return errRes("bad hub address (must be on the home network)");
      if (ip != secLocalIp) {
        Preferences sp; sp.begin("sec", false); sp.putString("lip", s2); sp.end();
        secLocalIp = ip;
        rebootAt = millis() + 1200;
        if (!rebootAt) rebootAt = 1;
      }
    }
    if (jsonHas(b, "user")) {
      String u = jsonValue(b, "user");
      if (!u.length() || u.length() > 64 || u.indexOf('"') >= 0) return errRes("bad server user");
      if (u != secMqttUser) { changed = true; Preferences sp; sp.begin("sec", false); sp.putString("muser", u); sp.end(); secMqttUser = u; }
    }
    if (jsonHas(b, "pass")) {
      String np = jsonValue(b, "pass");
      if (!np.length() || np.length() > 64 || np.indexOf('"') >= 0) return errRes("bad password");
      changed = np != secMqtt;
      if (changed) { Preferences sp; sp.begin("sec", false); sp.putString("mqtt", np); sp.end(); secMqtt = np; }
    }
    if (changed || !mqttUp) mqttRestartReq = true;   // same password and already online: nothing to do
    stateDirty = true;
    return okRes();
  }
  if (path == "emqx_config") {                    // {"url","key","secret"} local network only
    if (apiSrc != 0) return errRes("local_only");
    String u = jsonValue(b, "url"), k = jsonValue(b, "key"), sc = jsonValue(b, "secret");
    u.trim(); k.trim(); sc.trim();
    while (u.endsWith("/")) u.remove(u.length() - 1);
    if (u.endsWith("/api/v5")) u.remove(u.length() - 7);
    if (!u.startsWith("https://") || !k.length() || !sc.length()) return errRes("url (https://...), key and secret are required");
    Preferences sp; sp.begin("sec", false); sp.putString("ex_url", u); sp.putString("ex_key", k); sp.putString("ex_sec", sc); sp.end();
    exUrl = u; exKey = k; exSec = sc;
    stateDirty = true;
    if (!exStart(3)) return errRes("busy");
    return okRes("{\"job\":true}");
  }
  if (path == "users") {
    if (apiSrc == 2) return errRes("forbidden");
    String j = "{\"users\":[";
    for (int i = 0; i < userCount; i++) { if (i) j += ","; j += userJson(users[i]); }
    return okRes(j + "],\"emqx\":" + (emqxReady() ? "true" : "false") + "}");
  }
  if (path == "user_invite") {                    // {"name","role","all","strips":"MAC1,MAC2"} local network only
    if (apiSrc != 0) return errRes("local_only");
    if (!emqxReady()) return errRes("emqx_not_set");
    if (userCount >= MAX_USERS) return errRes("max 10 users");
    HubUser u; memset(&u, 0, sizeof u);
    String nm = jsonValue(b, "name"); nm.trim();
    if (!nm.length()) return errRes("name required");
    strlcpy(u.name, nm.c_str(), sizeof u.name);
    u.role = (uint8_t)constrain((int)jsonValue(b, "role").toInt(), 0, 2);
    u.all = jsonBool(b, "all") ? 1 : 0;
    parseStrips(u, jsonValue(b, "strips"));
    if (!u.all && !u.n) return errRes("pick at least one strip");
    do { snprintf(u.id, sizeof u.id, "u%06lx", (unsigned long)(esp_random() & 0xFFFFFF)); } while (findUser(u.id) >= 0);
    if (exJob.state == 1) return errRes("busy");
    exJob.u = u;
    exJob.pw = randText(18);
    exJob.base = "mttl/" + hubId + "/";
    if (!exStart(1)) return errRes("busy");
    return okRes("{\"job\":true}");
  }
  if (path == "user_update") {                    // {"id","name","role","all","strips"}
    if (apiSrc == 2) return errRes("forbidden");
    int i = findUser(jsonValue(b, "id"));
    if (i < 0) return errRes("no such user");
    HubUser u = users[i];
    if (jsonHas(b, "name")) { String nm = jsonValue(b, "name"); nm.trim(); if (nm.length()) strlcpy(u.name, nm.c_str(), sizeof u.name); }
    if (jsonHas(b, "role")) u.role = (uint8_t)constrain((int)jsonValue(b, "role").toInt(), 0, 2);
    if (jsonHas(b, "all")) u.all = jsonBool(b, "all") ? 1 : 0;
    if (jsonHas(b, "strips")) parseStrips(u, jsonValue(b, "strips"));
    if (!u.all && !u.n) return errRes("pick at least one strip");
    users[i] = u;
    saveUsers();
    publishUserState(u);
    return okRes();
  }
  if (path == "users_export") {                   // v2.15.0: family members with their passwords, for the owner's backup
    if (apiSrc == 2) return errRes("forbidden");
    String j = "{\"users\":[";
    for (int i = 0; i < userCount; i++) {
      if (i) j += ",";
      String uj = userJson(users[i]);
      j += uj.substring(0, uj.length() - 1) + ",\"pw\":\"" + jsonEsc(String(users[i].pw)) + "\"}";
    }
    return okRes(j + "]}");
  }
  if (path == "user_restore") {                   // v2.15.0: {"id","name","role","all","strips","pw"} puts a backed-up member back
    if (apiSrc == 2) return errRes("forbidden");  // (the cloud login stays on the server, so the member's phone keeps working)
    String id = jsonValue(b, "id"), pw = jsonValue(b, "pw"), nm = jsonValue(b, "name");
    nm.trim();
    if (id.length() < 2 || id.length() >= sizeof(HubUser::id) || pw.length() < 8 || pw.length() >= sizeof(HubUser::pw) || !nm.length())
      return errRes("bad user");
    HubUser u; memset(&u, 0, sizeof u);
    strlcpy(u.id, id.c_str(), sizeof u.id);
    strlcpy(u.name, nm.c_str(), sizeof u.name);
    strlcpy(u.pw, pw.c_str(), sizeof u.pw);
    u.role = (uint8_t)constrain((int)jsonValue(b, "role").toInt(), 0, 2);
    u.all = jsonBool(b, "all") ? 1 : 0;
    parseStrips(u, jsonValue(b, "strips"));
    if (!u.all && !u.n) return errRes("pick at least one strip");
    int i = findUser(u.id);
    if (i < 0) {
      if (userCount >= MAX_USERS) return errRes("max 10 users");
      i = userCount++;
    }
    users[i] = u;
    saveUsers();
    publishUserState(u);
    stateDirty = true;
    return okRes();
  }
  if (path == "user_revoke") {                    // {"id"} local network only
    if (apiSrc != 0) return errRes("local_only");
    int i = findUser(jsonValue(b, "id"));
    if (i < 0) return errRes("no such user");
    if (!emqxReady()) {                           // nothing on the server to remove
      mqttPub("mttl/" + hubId + "/u/" + String(users[i].id) + "/state", "", 1, true);
      for (int j = i; j < userCount - 1; j++) users[j] = users[j + 1];
      userCount--;
      saveUsers();
      stateDirty = true;
      return okRes();
    }
    if (exJob.state == 1) return errRes("busy");
    exJob.u = users[i];
    if (!exStart(2)) return errRes("busy");
    return okRes("{\"job\":true}");
  }
  if (path == "ujob") {                           // result of the last EMQX job
    if (apiSrc == 2) return errRes("forbidden");
    if (exJob.state == 1 || exJob.state == 2) return okRes("{\"state\":\"running\"}");
    if (exJob.state == 0) return okRes("{\"state\":\"idle\"}");
    String d = "{\"state\":\"done\",\"ok\":" + String(exJob.ok ? "true" : "false") + ",\"error\":\"" + jsonEsc(exJob.err) + "\"" +
               (exJob.data.length() ? ",\"data\":" + exJob.data : String("")) + "}";
    exJob.state = 0;
    exJob.data = "";
    return okRes(d);
  }
  if (path == "pair_answer") {                    // v2.15.13 {"id","pick","role"}: role -1 refuses; a wrong pick refuses too
    if (apiSrc == 2) return errRes("forbidden");
    pairsExpire();
    int i = pairFind((uint32_t)strtoul(jsonValue(b, "id").c_str(), nullptr, 10));
    if (i < 0 || pairs[i].state != 1 || pairs[i].job) return errRes("expired");
    PairReq& p = pairs[i];
    int role = jsonValue(b, "role").toInt();
    stateDirty = true;
    if (role < 0) { p.state = 3; p.at = millis(); addEvent("pair_no", "", 0, p.email); return okRes(); }
    if (jsonValue(b, "pick").toInt() != p.code) { p.state = 3; p.at = millis(); addEvent("pair_no", "", 0, p.email); return errRes("wrong_number"); }
    if (p.owner) {
      p.result = "\"key\":\"" + addOwner(p.email, p.model) + "\"";
      p.state = 2; p.at = millis();
      addEvent("pair_ok", "", 0, p.email);
      return okRes();
    }
    if (userCount >= MAX_USERS) return errRes("max 10 users");
    HubUser u; memset(&u, 0, sizeof u);
    String nm = p.email.substring(0, p.email.indexOf('@'));
    strlcpy(u.name, nm.c_str(), sizeof u.name);
    u.role = (uint8_t)constrain(role, 0, 2);
    u.all = 1;
    do { snprintf(u.id, sizeof u.id, "u%06lx", (unsigned long)(esp_random() & 0xFFFFFF)); } while (findUser(u.id) >= 0);
    addEvent("pair_ok", "", 0, p.email);
    // v2.15.14: the phone gets in at once (2.15.13 waited for the server login and answered "busy" when that worker
    // was taken); its server login for use away from home is made right after, in the background
    String pw = randText(18);
    strlcpy(u.pw, pw.c_str(), sizeof u.pw);
    if (emqxReady()) { cloudTodoId = u.id; cloudTodoPw = pw; cloudTodoAt = 0; }
    users[userCount++] = u;
    saveUsers();
    publishUserState(u);
    p.result = "\"code\":\"" + inviteCode(u, pw) + "\"";
    p.state = 2; p.at = millis();
    return okRes();
  }
  if (path == "owner_remove") {                   // v2.15.13 {"email"}: takes an owner phone off; with none left the hub is open again
    if (apiSrc != 0) return errRes("local_only");
    int i = ownerByEmail(cleanEmail(jsonValue(b, "email")));
    if (i < 0) return errRes("no such phone");
    for (int k = i; k < ownerCount - 1; k++) owners[k] = owners[k + 1];
    ownerCount--;
    saveOwners();
    return okRes();
  }
  if (path == "reboot") {                         // owner only, local or remote
    if (apiSrc == 2) return errRes("forbidden");
    rebootAt = millis() + 1200;
    if (!rebootAt) rebootAt = 1;
    addEvent("cycle", "", 0, "hub reboot");
    return okRes();
  }

  if (path == "wifi") {
    String ns = jsonValue(b, "ssid"), np = jsonValue(b, "pass");
    ns.trim();
    if (!ns.length() || ns.length() > 32 || np.length() > 63) return errRes("bad wifi name/password");
    if (ns.indexOf(':') >= 0 || np.indexOf(':') >= 0) return errRes("wifi name/password contains ':'");
    if (np.length() && np.length() < 8) return errRes("password must be at least 8 characters");
    wifiTestSsid = ns; wifiTestPass = np; wifiTestReq = true;
    wifiTestState = "queued"; wifiTestMsg = ns;
    stateDirty = true;
    return okRes();
  }
  if (path == "unblock") {
    String m = mac; m.toUpperCase();
    if (m.length() == 12) setBlocked(m, false);
    else cfg.putString("block", "");
    stateDirty = true;
    return okRes();
  }
  if (path == "forget") {
    String m = mac; m.toUpperCase();
    if (m.length() != 12) return errRes("bad mac");
    setBlocked(m, true);                         // it keeps dialling in; ignore it until it is added again
    cfg.remove(("q" + m).c_str());
    int idx = findStrip(m);
    if (idx >= 0) dropStrip(strips[idx], "removed");
    int off = offlineMacs.indexOf(m + ",");
    if (off >= 0) offlineMacs.remove(off, 13);
    forgetKnown(m);
    stateDirty = true;
    return okRes();
  }
  if (path == "timer") {
    String kind = jsonValue(b, "kind");
    int k = kind == "loop" ? 2 : kind == "cycle" ? 1 : 0;
    bool on = kind == "on";
    if (k == 0 && kind != "on" && kind != "off") return errRes("kind: on|off|cycle|loop");
    String e = addTimer(mac, outlet, k, on, (uint32_t)jsonValue(b, "delay_s").toInt(), (uint32_t)jsonValue(b, "off_s").toInt(),
                        (uint32_t)jsonValue(b, "on_s").toInt(), (uint32_t)jsonValue(b, "repeat_s").toInt());
    return e.length() ? errRes(e) : okRes();
  }
  if (path == "timer_cancel") {
    uint32_t id = (uint32_t)jsonValue(b, "tid").toInt();
    for (int t = 0; t < MAX_TIMERS; t++) if (timers[t].used && timers[t].id == id) { timers[t].used = false; saveTimers(); stateDirty = true; return okRes(); }
    return errRes("no such timer");
  }
  if (path == "scan") {                         // list strips that are in setup mode right now
    int n = WiFi.scanNetworks(false, false, false, 300);
    String j = "{\"found\":[";
    bool first = true;
    for (int i = 0; i < n; i++) {
      String ss = WiFi.SSID(i);
      if (!ss.startsWith("TONLY_TAP_") && !ss.startsWith("ONLY_TAP_")) continue;
      String id = ss.substring(ss.lastIndexOf('_') + 1);
      id.toUpperCase();
      bool known = false;
      for (int k = 0; k < MAX_STRIPS; k++) if (strips[k].used && strips[k].identified && strips[k].mac.endsWith(id)) known = true;
      if (!first) j += ",";
      first = false;
      j += "{\"ssid\":\"" + jsonEsc(ss) + "\",\"id\":\"" + id + "\",\"rssi\":" + String(WiFi.RSSI(i)) + ",\"known\":" + (known ? "true" : "false") + "}";
    }
    WiFi.scanDelete();
    return okRes(j + "]}");
  }
  if (path == "provision") {
    if (provState == "running" || provState == "waiting" || provRequested) return errRes("already running");
    if (secSsid.indexOf(':') >= 0 || secWifi.indexOf(':') >= 0) return errRes("wifi name/password contains ':'");
    provSsid = jsonValue(b, "ssid");
    requestProvision();
    return okRes();
  }
  if (path == "schedules") {
    String j = "{\"schedules\":[";
    for (int i = 0; i < schedCount; i++) { if (i) j += ","; j += schedJson(scheds[i]); }
    return okRes(j + "]}");
  }
  if (path == "schedule_save") {
    if (mac.length() && !macKnown(mac)) return errRes("unknown strip");
    uint32_t id = (uint32_t)jsonValue(b, "sid").toInt();
    int slot = -1;
    for (int i = 0; i < schedCount; i++) if (scheds[i].id == id && id) slot = i;
    if (slot < 0) {
      if (schedCount >= MAX_SCHED) return errRes("too many schedules");
      slot = schedCount++;
      uint32_t mx = 0;
      for (int i = 0; i < schedCount - 1; i++) mx = max(mx, scheds[i].id);
      memset(&scheds[slot], 0, sizeof(Sched));
      scheds[slot].id = mx + 1;
    }
    Sched& c = scheds[slot];
    int idx = stripFor(mac);
    String m = idx >= 0 ? strips[idx].mac : mac;
    m.toUpperCase();
    strlcpy(c.mac, m.c_str(), sizeof c.mac);
    c.outlet = constrain(outlet, 0, 4);
    c.on = jsonBool(b, "on");
    c.days = jsonValue(b, "days").toInt() & 0x7F;
    c.hh = constrain(jsonValue(b, "hh").toInt(), 0, 23);
    c.mm = constrain(jsonValue(b, "mm").toInt(), 0, 59);
    c.date = (uint32_t)jsonValue(b, "date").toInt();
    c.enabled = jsonHas(b, "enabled") ? jsonBool(b, "enabled") : 1;
    strlcpy(c.label, jsonValue(b, "label").c_str(), sizeof c.label);
    saveScheds();
    return okRes("{\"sid\":" + String(c.id) + "}");
  }
  if (path == "schedule_skip") {                 // v2.15.0: {"sid","skip":true|false} skip only the next run
    uint32_t id = (uint32_t)jsonValue(b, "sid").toInt();
    for (int i = 0; i < schedCount; i++) {
      if (scheds[i].id != id) continue;
      setSchedSkip(id, jsonHas(b, "skip") ? jsonBool(b, "skip") : true);
      return okRes();
    }
    return errRes("no such schedule");
  }
  if (path == "schedule_delete") {
    uint32_t id = (uint32_t)jsonValue(b, "sid").toInt();
    for (int i = 0; i < schedCount; i++) {
      if (scheds[i].id != id) continue;
      setSchedSkip(id, false);
      for (int j = i; j < schedCount - 1; j++) scheds[j] = scheds[j + 1];
      schedCount--;
      saveScheds();
      return okRes();
    }
    return errRes("no such schedule");
  }
  if (path == "automations") {
    String j = "{\"automations\":[";
    for (int i = 0; i < autoCount; i++) { if (i) j += ","; j += autoJson(autos[i]); }
    return okRes(j + "]}");
  }
  if (path == "automation_save") {
    if (mac.length() && !macKnown(mac)) return errRes("unknown strip");
    uint32_t id = (uint32_t)jsonValue(b, "aid").toInt();
    int slot = -1;
    for (int i = 0; i < autoCount; i++) if (autos[i].id == id && id) slot = i;
    if (slot < 0) {
      if (autoCount >= MAX_AUTO) return errRes("too many automations");
      slot = autoCount++;
      uint32_t mx = 0;
      for (int i = 0; i < autoCount - 1; i++) mx = max(mx, autos[i].id);
      memset(&autos[slot], 0, sizeof(Autom));
      autos[slot].id = mx + 1;
    }
    Autom& r = autos[slot];
    int idx = stripFor(mac);
    String m = idx >= 0 ? strips[idx].mac : mac;
    m.toUpperCase();
    strlcpy(r.mac, m.c_str(), sizeof r.mac);
    r.outlet = constrain(outlet, 0, 4);
    r.metric = constrain(jsonValue(b, "metric").toInt(), 0, 3);
    r.limit2 = jsonHas(b, "limit2") ? jsonValue(b, "limit2").toFloat() : 70;
    if (r.metric == 2) r.above = 1;
    if (r.metric != 2) r.above = jsonBool(b, "above");
    r.watts = jsonValue(b, "watts").toFloat();
    // keep thresholds in range: W 0..3500 · °C 0..120 · A 0..16
    r.watts = r.metric == 1 ? constrain(r.watts, 0.0f, 120.0f) : r.metric == 3 ? constrain(r.watts, 0.0f, 16.0f) : constrain(r.watts, 0.0f, 3500.0f);
    r.limit2 = constrain(r.limit2, 30.0f, 120.0f);
    r.holdS = constrain(jsonValue(b, "hold_s").toInt(), 5, 65535);
    r.act = constrain(jsonValue(b, "act").toInt(), 1, 3);
    r.enabled = jsonHas(b, "enabled") ? jsonBool(b, "enabled") : 1;
    strlcpy(r.label, jsonValue(b, "label").c_str(), sizeof r.label);
    autoArmed[slot] = true;
    autoWarned[slot] = false;
    autoSince[slot] = 0;
    saveAutos();
    return okRes("{\"aid\":" + String(r.id) + "}");
  }
  if (path == "automation_delete") {
    uint32_t id = (uint32_t)jsonValue(b, "aid").toInt();
    for (int i = 0; i < autoCount; i++) {
      if (autos[i].id != id) continue;
      for (int j = i; j < autoCount - 1; j++) { autos[j] = autos[j + 1]; autoArmed[j] = autoArmed[j + 1]; autoSince[j] = autoSince[j + 1]; }
      autoCount--;
      saveAutos();
      return okRes();
    }
    return errRes("no such automation");
  }
  if (path == "events") return okRes(eventsJson());
  if (path == "link") {                            // v2.15.10 link history of one strip (?mac= or "mac" in the body)
    String m = mac; m.toUpperCase();
    if (m.length() != 12) return errRes("mac required");
    return okRes(linkJson(m));
  }
  if (path == "energy") {
    int idx = stripFor(mac);
    if (idx < 0) return errRes("device offline");
    return okRes(energyJson(idx));
  }
  if (path == "amplimit") {
    int idx = stripFor(mac);
    if (idx < 0) return errRes("device offline");
    if (outlet < 1 || outlet > 4) return errRes("bad outlet");
    float maxA = jsonValue(b, "max_a").toFloat();
    if (maxA < 0 || maxA > 16.0f) return errRes("max_a 0..16");
    strips[idx].ampX2[outlet - 1] = (uint8_t)round(maxA * 2.0f);
    cfg.putBytes(("x" + strips[idx].mac).c_str(), strips[idx].ampX2, sizeof(strips[idx].ampX2));
    refreshKnown(strips[idx].mac);
    stateDirty = true;
    return okRes();
  }
  if (path == "config") {
    if (jsonHas(b, "temp_max")) { tempMax = constrain(jsonValue(b, "temp_max").toInt(), 40, 90); cfg.putUChar("tmax", tempMax); }
    if (jsonHas(b, "temp_protect")) { tempProtect = jsonBool(b, "temp_protect"); cfg.putBool("tprot", tempProtect); }
    if (jsonHas(b, "v_protect")) { vProt = jsonBool(b, "v_protect"); cfg.putBool("vprot", vProt); }
    if (jsonHas(b, "v_restore")) { vRestore = jsonBool(b, "v_restore"); cfg.putBool("vrest", vRestore); }
    if (jsonHas(b, "v_max")) { vMax = constrain((int)jsonValue(b, "v_max").toInt(), 225, 270); cfg.putUShort("vmax", vMax); }
    if (jsonHas(b, "v_min")) { vMin = constrain((int)jsonValue(b, "v_min").toInt(), 170, 260); cfg.putUShort("vmin", vMin); }
    if (jsonHas(b, "a_protect")) { aProt = jsonBool(b, "a_protect"); cfg.putBool("aprot", aProt); }
    if (jsonHas(b, "a_max")) { aMax = constrain(jsonValue(b, "a_max").toFloat(), 1.0f, 16.0f); cfg.putFloat("amax", aMax); }
    stateDirty = true;
    return okRes("{\"temp_max\":" + String(tempMax) + ",\"temp_protect\":" + (tempProtect ? "true" : "false") + ",\"v_min\":" + String(vMin) + ",\"v_max\":" + String(vMax) + "}");
  }
  if (path == "notify") {                        // {"ntfy":"topic","types":bitmask} and/or {"mac","mask"}
    if (jsonHas(b, "ntfy")) {
      String tpc = jsonValue(b, "ntfy");
      tpc.trim();
      if (tpc.length() > 64) return errRes("topic too long");
      for (char ch : tpc) if (!isalnum((unsigned char)ch) && ch != '-' && ch != '_') return errRes("topic: letters, digits, - and _ only");
      ntfyTopic = tpc;
      cfg.putString("ntfy", ntfyTopic);
    }
    if (jsonHas(b, "types")) { notifyTypes = (uint32_t)strtoul(jsonValue(b, "types").c_str(), nullptr, 10); cfg.putUInt("ntypes", notifyTypes); }
    if (jsonHas(b, "mask")) {
      int idx = stripFor(mac);
      if (idx < 0) return errRes("device offline");
      strips[idx].notifyMask = jsonValue(b, "mask").toInt() & 0x1F;
      cfg.putUChar(("m" + strips[idx].mac).c_str(), strips[idx].notifyMask);
      refreshKnown(strips[idx].mac);
    }
    if (jsonBool(b, "test")) addEvent("test", "", 0, "Fisha");   // reaches the app service and ntfy
    stateDirty = true;
    return okRes();
  }
  return errRes("unknown action");
}

String apiJson(const ApiRes& r) {
  String j = String("{\"ok\":") + (r.ok ? "true" : "false");
  if (r.err.length()) j += ",\"error\":\"" + jsonEsc(r.err) + "\"";
  if (r.data.length()) j += ",\"data\":" + r.data;
  return j + "}";
}

// ---------- HTTP ----------
int apiUserIdx = -1;

bool authorized() {
  webUri = web.uri() + " " + web.client().remoteIP().toString();
  apiUserIdx = -1;
  apiSrc = 0;
  String tok = web.header("X-Token");
  String uid = web.header("X-User");
  if (!tok.length()) tok = web.arg("t");
  if (!uid.length()) uid = web.arg("u");

  // 1. Shared users local access
  for (int i = 0; i < userCount; i++) {
    if (!users[i].id[0] || !strlen(users[i].pw)) continue;
    if (web.authenticate(users[i].id, users[i].pw)) {
      apiUserIdx = i;
      apiSrc = 2;
      return true;
    }
    if ((!uid.length() || uid == users[i].id) && tok == users[i].pw) {
      apiUserIdx = i;
      apiSrc = 2;
      return true;
    }
  }

  // 2. Owner check. v2.15.13: once the hub is locked only an owner phone's key (or, in a browser, admin + the update
  // password) gets in; before that it stays open as it always was.
  if (ownerCount) {
    if (isOwnerKey(tok)) return true;
    if (web.authenticate("admin", secOta.c_str())) return true;
    return strlen(API_TOKEN) && (tok == API_TOKEN || web.authenticate("hub", API_TOKEN));
  }
  if (!strlen(API_TOKEN)) return true;
  if (tok == API_TOKEN) return true;
  if (web.authenticate("hub", API_TOKEN)) return true;

  return false;
}

bool guard() {
  if (authorized()) return true;
  web.sendHeader("WWW-Authenticate", "Basic realm=\"mttl-hub\"");
  web.send(401, "application/json", "{\"ok\":false,\"error\":\"unauthorized\"}");
  return false;
}

// v2.15.16: the state goes out without blocking. A phone that stops reading (screen off, app paused) could hold
// the whole hub inside the web send for seconds, and every strip was then dropped as "socket stuck".
void webJsonNB(const String& body) {
  NetworkClient& c = web.client();
  String h = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " + String(body.length()) +
             "\r\nConnection: close\r\n\r\n";
  SubT st("web_send");
  if (!sendStr(c, h, 300) || !sendStr(c, body, 1500)) { webSlow++; c.stop(); }
}
void handleState() {
  if (!guard()) return;
  if (apiSrc == 2 && apiUserIdx >= 0 && apiUserIdx < userCount) webJsonNB(userStateJson(users[apiUserIdx]));
  else webJsonNB(buildStateJson());
}

int sseCount();
// v2.15.6: how full the settings storage is (a full NVS silently loses saves)
String nvsStatsJson() {
  nvs_stats_t st;
  if (nvs_get_stats(NULL, &st) != ESP_OK) return "";
  return ",\"nvs_used\":" + String(st.used_entries) + ",\"nvs_free\":" + String(st.free_entries) + ",\"nvs_total\":" + String(st.total_entries);
}

void handleHealth() {
  int n = 0;
  for (int i = 0; i < MAX_STRIPS; i++) if (strips[i].used && strips[i].identified) n++;
  web.send(200, "application/json", "{\"status\":\"ok\",\"fw\":\"" + String(FW_VERSION) + "\",\"hub\":\"" + hubId + "\",\"mqtt\":" +
           (mqttUp ? "true" : "false") + ",\"time_ok\":" + (timeOk() ? "true" : "false") + ",\"strips\":" + String(n) +
           ",\"uptime_s\":" + String(millis() / 1000) + ",\"lock\":" + (ownerCount ? "true" : "false") + ",\"heap\":" + String(ESP.getFreeHeap()) + ",\"max_alloc\":" + String(ESP.getMaxAllocHeap()) +
           ",\"heap_min\":" + String(ESP.getMinFreeHeap()) + ",\"sse\":" + String(sseCount()) +
           ",\"wifi_drops\":" + String(wifiDiscCount) + ",\"wifi_reason\":" + String(wifiLastReason) +
           ",\"stall_max_ms\":" + String(stallMaxMs) + ",\"stall_where\":\"" + String(stallWhere) + "\",\"stall_sub\":\"" + String(subWorstWhere) + " " + String(subWorst) + " ms\",\"web_slow\":" + String(webSlow) + nvsStatsJson() + ",\"fs\":" + (fsOk ? "true" : "false") +
           ",\"reset\":\"" + resetText() + "\",\"job\":" + String((int)exJob.state) + ",\"wifi_rssi\":" + String(WiFi.RSSI()) + "}");
}

void handleRaw() {
  if (!guard()) return;
  if (apiSrc == 2) { web.send(403, "application/json", "{\"ok\":false,\"error\":\"forbidden\"}"); return; }
  String cmd = web.arg("cmd");
  cmd.trim();
  int i = firstStrip();
  if (!cmd.startsWith("up:") || i < 0) { web.send(400, "application/json", "{\"ok\":false}"); return; }
  sendLine(strips[i], cmd);
  pumpFor(1500);
  web.send(200, "application/json", "{\"sent\":\"" + jsonEsc(cmd) + "\",\"last_rx\":\"" + jsonEsc(strips[i].lastLine) + "\"}");
}

void handleOther() {
  webUri = web.uri() + " " + web.client().remoteIP().toString();
  if (web.method() == HTTP_POST && (web.uri() == "/api/auth/claim" || web.uri().startsWith("/api/pair/"))) return authRoute(web.uri(), web.arg("plain"));
  if (web.method() == HTTP_POST && web.uri().startsWith("/api/")) {
    if (!guard()) return;
    ApiRes r;
    if (apiSrc == 2 && apiUserIdx >= 0 && apiUserIdx < userCount) {
      r = userApi(users[apiUserIdx], web.uri(), web.arg("plain"));
    } else {
      apiSrc = 0;
      r = api(web.uri(), web.arg("plain"));
    }
    stateDirty = true;
    web.send(r.ok ? 200 : 400, "application/json", apiJson(r));
    return;
  }
  web.send(404, "application/json", "{\"ok\":false,\"error\":\"not found\"}");
}

// v2.15.21: the built-in browser page and the web-app launcher are gone; the Fisha app is the only client.
// "/" answers with one plain line (no data), so a browser pointed at the hub's IP still gets a sane reply.
void handleRoot() { web.send(200, "text/plain; charset=utf-8", "Fisha Hub v" + String(FW_VERSION) + " - open the Fisha app"); }

// ---------- firmware update from the browser / curl (no inbound port needed on the PC) ----------
bool otaAuth() { return web.authenticate("admin", secOta.c_str()); }
void handleUpdatePage() {
  if (!otaAuth()) return web.requestAuthentication();
  web.send(200, "text/html; charset=utf-8",
           "<meta name=viewport content='width=device-width,initial-scale=1'><body style='font-family:sans-serif;background:#0d1117;color:#e8edf3;padding:20px'>"
           "<h3>Fisha Hub v" + String(FW_VERSION) + " &mdash; firmware update</h3>"
           "<form method=POST action=/update enctype=multipart/form-data><input type=file name=f accept=.bin><br><br>"
           "<button style='padding:12px 20px'>Upload</button></form></body>");
}
void handleUpdateDone() {
  if (!otaAuth()) return web.requestAuthentication();
  bool ok = !Update.hasError();
  web.send(ok ? 200 : 500, "text/plain", ok ? "OK - rebooting\n" : String("FAILED: ") + Update.errorString() + "\n");
  if (ok) { delay(600); ESP.restart(); }
}
void handleUpdateUpload() {
  if (!otaAuth()) return;
  HTTPUpload& u = web.upload();
  if (u.status == UPLOAD_FILE_START) {
    Serial.printf("[ota-web] %s\n", u.filename.c_str());
    if (!Update.begin(UPDATE_SIZE_UNKNOWN)) Update.printError(Serial);
  } else if (u.status == UPLOAD_FILE_WRITE) {
    if (Update.write(u.buf, u.currentSize) != u.currentSize) Update.printError(Serial);
  } else if (u.status == UPLOAD_FILE_END) {
    if (Update.end(true)) Serial.printf("[ota-web] done %u bytes\n", u.totalSize); else Update.printError(Serial);
  } else if (u.status == UPLOAD_FILE_ABORTED) {
    Update.abort();
  }
}

// ---------- v2.14.13: strip firmware flashing (/stripfw) ----------
uint32_t stripFwWritten = 0;
bool stripFwErr = false;
void handleStripFwPage() {
  if (!otaAuth()) return web.requestAuthentication();
  String h = "<meta name=viewport content='width=device-width,initial-scale=1'><meta charset=utf-8>"
             "<body style='font-family:sans-serif;background:#0d1117;color:#e8edf3;padding:20px'>"
             "<h3>Fisha Hub v" + String(FW_VERSION) + " &mdash; strip firmware</h3>"
             "<p>Stored .fwr: <b>" + (stripFwSize ? String(stripFwSize) + " bytes" : String("none")) + "</b>" +
             (stripFwWhy.length() ? " &mdash; refused: " + stripFwWhy : String("")) + "</p>"
             "<form method=POST action=/stripfw enctype=multipart/form-data><input type=file name=f accept=.fwr,.bin> "
             "<button style='padding:10px 16px'>1) Upload .fwr</button></form><hr>"
             "<form method=POST action=/stripfw/flash>Strip in setup mode (Wi-Fi name): "
             "<input name=ssid placeholder=TONLY_TAP_91778E8 style='padding:8px'> "
             "<button style='padding:10px 16px'>2) Flash</button></form>"
             "<p>State: <b>" + provState + "</b> " + provMsg + "</p><pre style='white-space:pre-wrap'>" + stripOtaLog + "</pre>"
             + String((provState == "running" || provState == "queued" || suRunning()) ? "<script>setTimeout(()=>location.reload(),5000)</script>" : "");
  // v2.15.8: connected strips, updated over their normal connection (no button press)
  h += "<hr><h4>Update connected strips</h4><form method=POST action=/stripfw/live>"
       "<label><input type=checkbox onclick=\"for(const c of document.querySelectorAll('.sm'))c.checked=this.checked\"> <b>Select all</b></label><br>";
  for (int i = 0; i < MAX_STRIPS; i++) {
    const Strip& st = strips[i];
    if (!st.used || !st.identified) continue;
    h += "<label><input type=checkbox class=sm name=mac value=" + st.mac + "> " + (st.label.length() ? st.label : String("Strip")) + " &middot; " + st.mac +
         " &middot; fw " + st.fw + "</label><br>";
  }
  h += "<button style='padding:10px 16px;margin-top:8px'" + String(stripFwOk && !suRunning() ? "" : " disabled") + ">Update selected</button></form><pre>";
  for (uint8_t k = 0; k < suN; k++)
    h += suList[k].mac + "  " + suList[k].state + (suList[k].from.length() ? "  " + suList[k].from : String("")) +
         (suList[k].to.length() ? " -> " + suList[k].to : String("")) + (suList[k].msg.length() ? "  " + suList[k].msg : String("")) + "\n";
  h += "</pre></body>";
  web.send(200, "text/html; charset=utf-8", h);
}
// v2.15.8: an MTTL-W01 .fwr is a 16-byte plain header (body length, load address 0x10006000) and a body XOR'd
// with a 16-byte key (the padding rows give it away); the last 4 decoded bytes are the sum of everything before.
bool stripFwCheck(uint32_t size, String& why) {
  const esp_partition_t* part = stripFwPart();
  uint32_t h[4];
  if (!part || size < 64 * 1024 || esp_partition_read(part, 0, h, 16) != ESP_OK) { why = "file too small"; return false; }
  if (h[1] != 0x10006000 || h[0] + 20 != size) { why = "not an MTTL-W01 firmware (header)"; return false; }
  // most common 16-byte row = the XOR key (Misra-Gries, 8 slots)
  static uint8_t cand[8][16];
  uint16_t cnt[8] = {0};
  static uint8_t buf[1024];
  uint32_t end = size - 4;
  for (uint32_t off = 16; off + 16 <= end; off += sizeof buf) {
    uint32_t n = min((uint32_t)sizeof buf, (end - off) & ~15u);
    if (!n || esp_partition_read(part, off, buf, n) != ESP_OK) break;
    for (uint32_t r = 0; r < n; r += 16) {
      int hit = -1, empty = -1;
      for (int k = 0; k < 8; k++) {
        if (cnt[k] && !memcmp(cand[k], buf + r, 16)) { hit = k; break; }
        if (!cnt[k] && empty < 0) empty = k;
      }
      if (hit >= 0) cnt[hit]++;
      else if (empty >= 0) { memcpy(cand[empty], buf + r, 16); cnt[empty] = 1; }
      else for (int k = 0; k < 8; k++) cnt[k]--;
    }
    esp_task_wdt_reset();
  }
  int best = 0;
  for (int k = 1; k < 8; k++) if (cnt[k] > cnt[best]) best = k;
  const uint8_t* key = cand[best];
  uint32_t sum = 0;
  const uint8_t* hb = (const uint8_t*)h;
  for (int i = 0; i < 16; i++) sum += hb[i];
  for (uint32_t off = 16; off < end; off += sizeof buf) {
    uint32_t n = min((uint32_t)sizeof buf, end - off);
    if (esp_partition_read(part, off, buf, n) != ESP_OK) { why = "flash read failed"; return false; }
    for (uint32_t i = 0; i < n; i++) sum += buf[i] ^ key[(off + i) & 15];
    esp_task_wdt_reset();
  }
  uint8_t t[4];
  if (esp_partition_read(part, end, t, 4) != ESP_OK) { why = "flash read failed"; return false; }
  uint32_t stored = 0;
  for (int i = 0; i < 4; i++) stored |= (uint32_t)(t[i] ^ key[(end + i) & 15]) << (8 * i);
  if (stored != sum) { why = "checksum does not match (damaged file)"; return false; }
  return true;
}
// keeps the upload (already written to the spare slot) only if it is a valid strip firmware
bool stripFwStore(String& why) {
  if (stripFwErr || !stripFwWritten) { why = "upload failed (file empty or larger than 384 KB)"; stripFwSize = 0; }
  else if (!stripFwCheck(stripFwWritten, why)) stripFwSize = 0;
  else stripFwSize = stripFwWritten;
  stripFwOk = stripFwSize > 0;
  stripFwWhy = stripFwOk ? "" : why;
  Preferences p;
  p.begin("stripfw", false);
  p.putUInt("size", stripFwSize);
  p.end();
  Serial.printf("[strip-ota] stored %u bytes%s\n", stripFwSize, stripFwOk ? "" : (" (refused: " + why + ")").c_str());
  return stripFwOk;
}
void handleStripFwDone() {
  if (!otaAuth()) return web.requestAuthentication();
  String why;
  if (!stripFwStore(why)) { web.send(400, "text/plain", "REFUSED: " + why + "\n"); return; }
  web.sendHeader("Location", "/stripfw");
  web.send(303, "text/plain", "OK " + String(stripFwSize) + " bytes\n");
}
void stripFwChunk(HTTPUpload& u) {
  const esp_partition_t* part = stripFwPart();
  if (u.status == UPLOAD_FILE_START) {
    stripFwWritten = 0;
    stripFwErr = !part || part->size < STRIP_FW_MAX;
    if (!stripFwErr) stripFwErr = esp_partition_erase_range(part, 0, STRIP_FW_MAX) != ESP_OK;
    Serial.printf("[strip-ota] upload %s%s\n", u.filename.c_str(), stripFwErr ? " (no spare slot)" : "");
  } else if (u.status == UPLOAD_FILE_WRITE && !stripFwErr) {
    if (stripFwWritten + u.currentSize > STRIP_FW_MAX) { stripFwErr = true; return; }
    if (esp_partition_write(part, stripFwWritten, u.buf, u.currentSize) != ESP_OK) { stripFwErr = true; return; }
    stripFwWritten += u.currentSize;
  } else if (u.status == UPLOAD_FILE_ABORTED) {
    stripFwErr = true;
  }
}
void handleStripFwUpload() {
  if (!otaAuth()) return;
  stripFwChunk(web.upload());
}
void handleStripFwFlash() {
  if (!otaAuth()) return web.requestAuthentication();
  String ssid = web.arg("ssid");
  ssid.trim();
  if (!stripFwSize) { web.send(400, "text/plain", "upload the .fwr first\n"); return; }
  if (!ssid.startsWith("TONLY_TAP_") && !ssid.startsWith("ONLY_TAP_")) { web.send(400, "text/plain", "ssid must be TONLY_TAP_...\n"); return; }
  if (provState == "running" || provState == "waiting" || provRequested || suRunning()) { web.send(409, "text/plain", "busy\n"); return; }
  stripOtaLog = "";
  provOta = true;
  provSsid = ssid;
  requestProvision();
  web.sendHeader("Location", "/stripfw");
  web.send(303, "text/plain", "started: the hub leaves the home Wi-Fi for up to 2 minutes\n");
}

// ---------- v2.15.8: update strips over their normal hub connection ----------
// Stock 1.0.66 takes "up:ota:<host>" on the hub connection too (verified 2026-10-10): it answers ota_ok, fetches
// http://<host>/ota.bin on port 80, flashes and reboots. Same command as the setup-mode flasher, no protocol change.
// One strip at a time: wait for its GET, stream the stored .fwr without blocking the loop, wait for it to dial
// back in and compare the fw in its bootinfo. The first failure stops the run.
bool suRunning() { return suPhase != SU_IDLE; }

void suStop(bool failed, const String& msg) {
  SuItem& it = suList[suCur];
  if (failed) {
    it.state = "failed"; it.msg = msg;
    addEvent("strip_fw_fail", it.mac, 0, msg);
    for (uint8_t k = suCur + 1; k < suN; k++) if (suList[k].state == "queued") suList[k].state = "skipped";
  }
  if (suCli) suCli.stop();
  suSrv.end();
  suPhase = SU_IDLE;
  stateDirty = true;
  Serial.printf("[strip-upd] stopped%s %s\n", failed ? " (failed)" : "", msg.c_str());
}

void suNext() {
  while (suCur < suN && suList[suCur].state != "queued") suCur++;
  if (suCur >= suN || suCancel) {
    for (uint8_t k = 0; k < suN; k++) if (suList[k].state == "queued") suList[k].state = "skipped";
    suSrv.end();
    suPhase = SU_IDLE;
    stateDirty = true;
    return;
  }
  suPhase = SU_SEND;
}

void suTick() {
  if (suPhase == SU_IDLE) return;
  SuItem& it = suList[suCur];
  int i = findStrip(it.mac);
  switch (suPhase) {
    case SU_SEND: {
      if (i < 0) { suStop(true, "strip offline"); return; }
      it.from = strips[i].fw;
      it.state = "sending";
      suSrv.begin();                   // listening before the command: the strip dials :80 right after ota_ok
      suSrv.setNoDelay(true);
      String cmd = "up:ota:" + WiFi.localIP().toString();
      sendLine(strips[i], cmd);
      Serial.printf("[strip-upd] %s (fw %s) << %s\n", it.mac.c_str(), it.from.c_str(), cmd.c_str());
      suT0 = millis();
      suPhase = SU_GET;
      stateDirty = true;
      return;
    }
    case SU_GET: {
      if (!suCli) {
        suCli = suSrv.accept();
        if (suCli) { suReq = ""; suReqAt = millis(); }
      }
      if (suCli) {
        while (suCli.available() && suReq.length() < 512) suReq += (char)suCli.read();
        if (suReq.indexOf("\r\n\r\n") >= 0) {
          String first = suReq.substring(0, suReq.indexOf('\r'));
          Serial.printf("[strip-upd] request from %s: %s\n", suCli.remoteIP().toString().c_str(), first.c_str());
          if (first.startsWith("GET ") && first.indexOf("/ota.bin") > 0) {
            suCli.setNoDelay(true);
            suCli.print("HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: " + String(stripFwSize) +
                        "\r\nConnection: close\r\n\r\n");
            suOff = 0; suBufLen = suBufPos = 0; suT0 = millis();
            it.state = "transfer";
            suPhase = SU_XFER;
            stateDirty = true;
            return;
          }
          suCli.print("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
          suCli.stop();
        } else if (millis() - suReqAt > 5000 || !suCli.connected()) {
          suCli.stop();
        }
      }
      if (millis() - suT0 > 60000) {
        String last = i >= 0 ? strips[i].lastLine : String("");
        suStop(true, "the strip did not ask for the file" + (last.length() ? " (last: " + last + ")" : String("")));
      }
      return;
    }
    case SU_XFER: {
      const esp_partition_t* part = stripFwPart();
      uint32_t t = millis();
      while (millis() - t < 30) {
        if (suBufPos >= suBufLen) {
          if (suOff >= stripFwSize) break;
          uint32_t n = min((uint32_t)sizeof suBuf, stripFwSize - suOff);
          if (!part || esp_partition_read(part, suOff, suBuf, n) != ESP_OK) { suStop(true, "flash read failed"); return; }
          suBufLen = n; suBufPos = 0; suOff += n;
        }
        int w = sendSome(suCli, (const char*)suBuf + suBufPos, suBufLen - suBufPos, 0);
        if (w < 0) { suStop(true, "connection lost at " + String((suOff - suBufLen + suBufPos) * 100 / stripFwSize) + "%"); return; }
        if (w == 0) break;             // socket full; next loop pass
        suBufPos += w;
      }
      if (suOff >= stripFwSize && suBufPos >= suBufLen) {
        suDoneAt = millis();
        it.state = "rebooting";
        suPhase = SU_BACK;
        stateDirty = true;
        Serial.printf("[strip-upd] %s: sent %u bytes in %u s\n", it.mac.c_str(), stripFwSize, (suDoneAt - suT0) / 1000);
      } else if (millis() - suT0 > 150000) {
        suStop(true, "transfer too slow");
      }
      return;
    }
    case SU_BACK: {
      if (suCli && millis() - suDoneAt > 1500) { suCli.stop(); suSrv.end(); }
      if (i >= 0 && (int32_t)(strips[i].connectedAt - suDoneAt) > 0 && strips[i].fw.length()) {
        it.to = strips[i].fw;
        if (it.to == it.from) { suStop(true, "came back on the same version " + it.from); return; }
        it.state = "ok";
        addEvent("strip_fw", it.mac, 0, it.from + " → " + it.to);
        suT0 = millis();
        suPhase = SU_GAP;
        stateDirty = true;
      } else if (millis() - suDoneAt > 240000) {
        suStop(true, "the strip did not come back within 4 minutes");
      }
      return;
    }
    case SU_GAP:
      if (millis() - suT0 > 3000) { suCur++; suNext(); }
      return;
    default:
      return;
  }
}

// starts a run; macs = the strips to update in order. Returns "" or an error.
String suStart(const String* macs, int n) {
  if (!stripFwSize || !stripFwOk) return "no valid strip firmware stored";
  if (suRunning() || provRequested || provState == "running" || provState == "waiting") return "busy";
  if (n <= 0) return "no strip selected";
  suN = 0;
  for (int k = 0; k < n && suN < MAX_STRIPS; k++) {
    String m = macs[k]; m.trim(); m.toUpperCase();
    if (findStrip(m) < 0) return "strip " + m + " is offline";
    bool dup = false;
    for (uint8_t j = 0; j < suN; j++) dup |= suList[j].mac == m;
    if (dup) continue;
    suList[suN] = SuItem();
    suList[suN].mac = m; suList[suN].state = "queued";
    suN++;
  }
  suCur = 0; suCancel = false;
  suNext();
  return "";
}

String suJson() {
  String j = "{\"size\":" + String(stripFwSize) + ",\"valid\":" + (stripFwOk ? "true" : "false") + ",\"why\":\"" + jsonEsc(stripFwWhy) +
             "\",\"running\":" + (suRunning() ? "true" : "false") + ",\"items\":[";
  for (uint8_t k = 0; k < suN; k++) {
    const SuItem& it = suList[k];
    int pct = it.state == "transfer" && stripFwSize ? (int)((uint64_t)suOff * 100 / stripFwSize) : (it.state == "ok" || it.state == "rebooting" ? 100 : 0);
    if (k) j += ",";
    j += "{\"mac\":\"" + it.mac + "\",\"from\":\"" + jsonEsc(it.from) + "\",\"to\":\"" + jsonEsc(it.to) + "\",\"state\":\"" + it.state +
         "\",\"msg\":\"" + jsonEsc(it.msg) + "\",\"pct\":" + String(pct) + "}";
  }
  return j + "]}";
}

bool ownerOnly() {
  if (!guard()) return false;
  if (apiSrc == 2) { web.send(403, "application/json", "{\"ok\":false,\"error\":\"forbidden\"}"); return false; }
  return true;
}
void handleSuState() {
  if (!ownerOnly()) return;
  web.send(200, "application/json", suJson());
}
// body {"macs":["88D039...", ...]}
void handleSuStart() {
  if (!ownerOnly()) return;
  String b = web.arg("plain");
  String macs[MAX_STRIPS];
  int n = 0, at = b.indexOf("\"macs\"");
  int lb = at >= 0 ? b.indexOf('[', at) : -1, rb = lb >= 0 ? b.indexOf(']', lb) : -1;
  for (int q = lb; q >= 0 && q < rb && n < MAX_STRIPS;) {
    int a = b.indexOf('"', q + 1);
    if (a < 0 || a > rb) break;
    int e = b.indexOf('"', a + 1);
    if (e < 0 || e > rb) break;
    macs[n++] = b.substring(a + 1, e);
    q = e;
  }
  String err = suStart(macs, n);
  if (err.length()) { web.send(400, "application/json", "{\"ok\":false,\"error\":\"" + jsonEsc(err) + "\"}"); return; }
  web.send(200, "application/json", suJson());
}
void handleSuCancel() {
  if (!ownerOnly()) return;
  suCancel = true;                     // the strip in progress finishes; the rest are skipped
  web.send(200, "application/json", suJson());
}
bool suUploadAuth = false;
void handleSuUpload() {
  HTTPUpload& u = web.upload();
  if (u.status == UPLOAD_FILE_START) suUploadAuth = authorized() && apiSrc != 2;
  if (!suUploadAuth || suRunning()) { stripFwErr = true; return; }
  stripFwChunk(u);
}
void handleSuUploadDone() {
  if (!ownerOnly()) return;
  if (suRunning()) { web.send(409, "application/json", "{\"ok\":false,\"error\":\"busy\"}"); return; }
  String why;
  if (!stripFwStore(why)) { web.send(400, "application/json", "{\"ok\":false,\"error\":\"" + jsonEsc(why) + "\"}"); return; }
  web.send(200, "application/json", suJson());
}
// v2.15.22: the hub fetches the .fwr itself over HTTP(S), so the file never passes through the phone. Reuses the
// same spare slot and validation (stripFwCheck) as a phone upload — only where the bytes come from differs.
bool stripFwFetch(const String& url, String& why) {
  const esp_partition_t* part = stripFwPart();
  if (!part || part->size < STRIP_FW_MAX) { why = "no spare slot"; return false; }
  bool https = url.startsWith("https://");
  if (!https && !url.startsWith("http://")) { why = "url must start with http:// or https://"; return false; }
  WiFiClientSecure sc;
  WiFiClient pc;
  HTTPClient http;
  http.setConnectTimeout(8000);
  http.setTimeout(15000);
  bool ok = https ? (sc.setInsecure(), http.begin(sc, url)) : http.begin(pc, url);
  if (!ok) { why = "could not open the url"; return false; }
  int code = http.GET();
  if (code != 200) { why = "server replied " + String(code); http.end(); return false; }
  int len = http.getSize();
  if (len <= 0 || (uint32_t)len > STRIP_FW_MAX) { why = "file too big or unknown size"; http.end(); return false; }
  if (esp_partition_erase_range(part, 0, STRIP_FW_MAX) != ESP_OK) { why = "flash erase failed"; http.end(); return false; }
  WiFiClient* stream = http.getStreamPtr();
  uint8_t buf[1024];
  uint32_t written = 0;
  uint32_t lastByte = millis();
  while (http.connected() && written < (uint32_t)len && millis() - lastByte < 15000) {
    size_t avail = stream->available();
    if (!avail) { delay(5); esp_task_wdt_reset(); continue; }
    size_t n = stream->readBytes(buf, min(avail, sizeof buf));
    if (!n) break;
    if (esp_partition_write(part, written, buf, n) != ESP_OK) { why = "flash write failed"; http.end(); return false; }
    written += n;
    lastByte = millis();
    esp_task_wdt_reset();
  }
  http.end();
  if (written != (uint32_t)len) { why = "download incomplete (" + String(written) + "/" + String(len) + " bytes)"; return false; }
  stripFwWritten = written;
  stripFwErr = false;
  return stripFwStore(why);
}
void handleSuFetch() {
  if (!ownerOnly()) return;
  if (suRunning()) { web.send(409, "application/json", "{\"ok\":false,\"error\":\"busy\"}"); return; }
  String b = web.arg("plain");
  int at = b.indexOf("\"url\"");
  int a = at >= 0 ? b.indexOf('"', b.indexOf(':', at) + 1) : -1;
  int e = a >= 0 ? b.indexOf('"', a + 1) : -1;
  String url = a >= 0 && e > a ? b.substring(a + 1, e) : "";
  if (!url.length()) { web.send(400, "application/json", "{\"ok\":false,\"error\":\"no url\"}"); return; }
  String why;
  if (!stripFwFetch(url, why)) { web.send(400, "application/json", "{\"ok\":false,\"error\":\"" + jsonEsc(why) + "\"}"); return; }
  web.send(200, "application/json", suJson());
}
// form on /stripfw: mac=...&mac=... (checkboxes)
void handleSuForm() {
  if (!otaAuth()) return web.requestAuthentication();
  String macs[MAX_STRIPS];
  int n = 0;
  for (int k = 0; k < web.args() && n < MAX_STRIPS; k++) if (web.argName(k) == "mac") macs[n++] = web.arg(k);
  String err = suStart(macs, n);
  if (err.length()) { web.send(400, "text/plain", err + "\n"); return; }
  web.sendHeader("Location", "/stripfw");
  web.send(303, "text/plain", "started\n");
}

// ---------- live push: Server-Sent Events on :8081 ----------
struct SseClient { WiFiClient c; bool used = false, ready = false; String req; uint32_t since = 0; int userIdx = -1; };
SseClient sse[MAX_SSE];
int sseCount() { int n = 0; for (int i = 0; i < MAX_SSE; i++) n += sse[i].used && sse[i].ready; return n; }
uint32_t lastSsePush = 0, lastSseBeat = 0;

// v2.15.2: the state goes out in three pieces straight from the one copy (it used to be copied twice more per
// phone, ~3 x the state size in RAM at once) and without blocking, so a push no longer starves the strips.
bool sseWrite(WiFiClient& c, const char* ev, const String& body) {
  String head = String("event: ") + ev + "\ndata: ";
  return sendNB(c, head.c_str(), head.length(), 80) && sendNB(c, body.c_str(), body.length(), 80) && sendNB(c, "\n\n", 2, 80);
}
void sseSend(const char* ev, const String& data) {
  SubT st("sse");
  bool isState = !strcmp(ev, "state");
  for (int i = 0; i < MAX_SSE; i++) {
    if (!sse[i].used || !sse[i].ready) continue;
    if (!sse[i].c.connected()) { sse[i].c.stop(); sse[i] = SseClient(); continue; }
    if (!isState && sse[i].userIdx >= 0 && ownerOnlyEvent(data)) continue;
    bool ok;
    if (isState && sse[i].userIdx >= 0 && sse[i].userIdx < userCount) ok = sseWrite(sse[i].c, ev, userStateJson(users[sse[i].userIdx]));
    else ok = sseWrite(sse[i].c, ev, data);
    if (!ok) {
      sse[i].c.stop();
      sse[i] = SseClient();
    }
  }
}

// value of ?k= / &k= in a request line like "GET /events?u=..&t=.. HTTP/1.1" (no URL decoding needed: ids and tokens are plain)
String queryArg(const String& line, const char* k) {
  String key = String(k) + "=";
  int q = line.indexOf('?');
  if (q < 0) return "";
  int sp = line.indexOf(' ', q);
  String qs = line.substring(q + 1, sp < 0 ? line.length() : sp);
  int i = 0;
  while (i < (int)qs.length()) {
    int amp = qs.indexOf('&', i);
    if (amp < 0) amp = qs.length();
    if (qs.substring(i, i + key.length()) == key) return qs.substring(i + key.length(), amp);
    i = amp + 1;
  }
  return "";
}

void ssePump() {
  WiFiClient n = sseServer.accept();
  if (n) {
    int slot = -1;
    for (int i = 0; i < MAX_SSE; i++) if (!sse[i].used) { slot = i; break; }
    if (slot < 0) { sse[0].c.stop(); sse[0] = SseClient(); slot = 0; }   // replace the oldest
    sse[slot] = SseClient();
    sse[slot].c = n; sse[slot].used = true; sse[slot].since = millis();
    n.setNoDelay(true);
    n.setTimeout(150);
  }
  for (int i = 0; i < MAX_SSE; i++) {
    SseClient& x = sse[i];
    if (!x.used) continue;
    if (!x.ready) {
      while (x.c.available() && x.req.length() < 1024) x.req += (char)x.c.read();
      if (x.req.indexOf("\r\n\r\n") >= 0) {
        // v2.13.2: a shared user is matched first (exact u=/t= values) so it gets only its own strips,
        // even when API_TOKEN is empty; before, an empty token made every SSE client the owner.
        String line0 = x.req.substring(0, x.req.indexOf('\r'));
        String qu = queryArg(line0, "u"), qt = queryArg(line0, "t");
        int matchedUser = -1;
        for (int k = 0; qt.length() && k < userCount; k++) {
          if (strlen(users[k].pw) && qt == users[k].pw && (!qu.length() || qu == users[k].id)) {
            matchedUser = k;
            break;
          }
        }
        bool owner = matchedUser < 0 && (ownerCount ? isOwnerKey(qt) || (strlen(API_TOKEN) && qt == API_TOKEN) : (!strlen(API_TOKEN) || qt == API_TOKEN));
        bool ok = owner || matchedUser >= 0;
        if (!ok || !x.req.startsWith("GET /events")) {
          sendStr(x.c, "HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\n\r\n", 250);
          x.c.stop(); x = SseClient(); continue;
        }
        x.userIdx = matchedUser;
        // v2.15.17: the SSE answers no longer wait on a phone that stopped reading (they could freeze the hub ~5-10 s)
        if (!sendStr(x.c, "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n"
                          "Access-Control-Allow-Origin: *\r\n\r\nretry: 3000\n\n", 250)) { x.c.stop(); x = SseClient(); continue; }
        String initData = (x.userIdx >= 0 && x.userIdx < userCount) ? userStateJson(users[x.userIdx]) : buildStateJson();
        if (!sseWrite(x.c, "state", initData)) { x.c.stop(); x = SseClient(); continue; }
        x.ready = true;
      } else if (millis() - x.since > 3000) { x.c.stop(); x = SseClient(); continue; }
    }
    if (x.used && !x.c.connected()) { x.c.stop(); x = SseClient(); }
  }
  if (stateDirty && millis() - lastSsePush > 250) {
    stateDirty = false;
    lastSsePush = millis();
    bool any = false;
    for (int i = 0; i < MAX_SSE; i++) any |= sse[i].used && sse[i].ready;
    if (any) sseSend("state", buildStateJson());
  }
  if (millis() - lastSseBeat > 15000) {
    lastSseBeat = millis();
    for (int i = 0; i < MAX_SSE; i++) {
      if (sse[i].used && sse[i].ready) {
        SubT st("sse_beat");
        if (!sendNB(sse[i].c, ": hb\n\n", 6, 250)) {
          sse[i].c.stop();
          sse[i] = SseClient();
        }
      }
    }
  }
}

// ---------- MQTT cloud relay ----------
uint32_t lastStatePub = 0;
String lastRelaySig, lastProvPub;
float lastPubPower = -1;

static void mqttEvent(void*, esp_event_base_t, int32_t id, void* data) {
  esp_mqtt_event_handle_t e = (esp_mqtt_event_handle_t)data;
  switch ((esp_mqtt_event_id_t)id) {
    case MQTT_EVENT_CONNECTED: {
      mqttUp = true; mqttFreshConnect = true; mqttErrKind = 0;
      esp_mqtt_client_subscribe(mqtt, tCmd.c_str(), 1);
      String uc = "mttl/" + hubId + "/u/+/cmd";
      esp_mqtt_client_subscribe(mqtt, uc.c_str(), 1);
      break;
    }
    case MQTT_EVENT_DISCONNECTED: mqttUp = false; break;
    case MQTT_EVENT_ERROR:
      if (e->error_handle) {
        if (e->error_handle->error_type == MQTT_ERROR_TYPE_CONNECTION_REFUSED) { mqttErrKind = 1; mqttErrCode = e->error_handle->connect_return_code; }
        else if (e->error_handle->error_type == MQTT_ERROR_TYPE_TCP_TRANSPORT) {
          mqttErrKind = 2; mqttErrCode = e->error_handle->esp_tls_last_esp_err; mqttErrTls = e->error_handle->esp_tls_cert_verify_flags;
        }
      }
      break;
    case MQTT_EVENT_DATA: {
      if (e->current_data_offset != 0 || e->data_len <= 0 || e->data_len >= (int)sizeof(MqttCmd::payload)) break;
      if (e->topic_len <= 0 || e->topic_len >= (int)sizeof(MqttCmd::topic)) break;
      MqttCmd c;
      memcpy(c.payload, e->data, e->data_len);
      c.payload[e->data_len] = 0;
      memcpy(c.topic, e->topic, e->topic_len);
      c.topic[e->topic_len] = 0;
      if (mqttQ) xQueueSend(mqttQ, &c, 0);
      break;
    }
    default: break;
  }
}

void mqttStart() {
  if (!secMqttUri.length()) { Serial.println("MQTT    : no server set yet (the app sends it)"); return; }
  uint8_t m[6];
  WiFi.macAddress(m);
  char id[13];
  snprintf(id, sizeof id, "%02X%02X%02X%02X%02X%02X", m[0], m[1], m[2], m[3], m[4], m[5]);
  hubId = id;
  String base = "mttl/" + hubId + "/";
  tStatus = base + "status"; tInfo = base + "info"; tState = base + "state"; tEvent = base + "event"; tCmd = base + "cmd"; tAck = base + "cmd/ack";
  snprintf(mqttClientId, sizeof mqttClientId, "hub-%s", id);
  if (!mqttQ) mqttQ = xQueueCreate(6, sizeof(MqttCmd));
  esp_mqtt_client_config_t cfgm = {};
#if ESP_IDF_VERSION_MAJOR >= 5
  cfgm.broker.address.uri = secMqttUri.c_str();
  cfgm.broker.verification.certificate = MQTT_CA;
  cfgm.credentials.username = secMqttUser.c_str();
  cfgm.credentials.client_id = mqttClientId;
  cfgm.credentials.authentication.password = secMqtt.c_str();
  cfgm.session.last_will.topic = tStatus.c_str();
  cfgm.session.last_will.msg = "offline";
  cfgm.session.last_will.qos = 1;
  cfgm.session.last_will.retain = 1;
  cfgm.session.keepalive = 30;
  cfgm.network.reconnect_timeout_ms = 5000;
  cfgm.buffer.size = 8192;
  cfgm.buffer.out_size = 8192;
#else
  cfgm.uri = secMqttUri.c_str(); cfgm.cert_pem = MQTT_CA; cfgm.username = secMqttUser.c_str(); cfgm.client_id = mqttClientId; cfgm.password = secMqtt.c_str();
  cfgm.lwt_topic = tStatus.c_str(); cfgm.lwt_msg = "offline"; cfgm.lwt_qos = 1; cfgm.lwt_retain = 1; cfgm.keepalive = 30;
  cfgm.reconnect_timeout_ms = 5000; cfgm.buffer_size = 8192; cfgm.out_buffer_size = 8192;
#endif
  mqtt = esp_mqtt_client_init(&cfgm);
  esp_mqtt_client_register_event(mqtt, MQTT_EVENT_ANY, mqttEvent, nullptr);
  esp_mqtt_client_start(mqtt);
  Serial.printf("MQTT    : %s  hub=%s\n", secMqttUri.c_str(), id);
}

void mqttPub(const String& topic, const String& payload, int qos, bool retain) {
  if (!mqtt || !mqttUp || !topic.length()) return;
  SubT st("mqtt_pub");
  esp_mqtt_client_enqueue(mqtt, topic.c_str(), payload.c_str(), payload.length(), qos, retain ? 1 : 0, true);
}

String relaySignature() {
  String sig;
  for (int i = 0; i < MAX_STRIPS; i++) {
    const Strip& s = strips[i];
    if (!s.used || !s.identified) continue;
    sig += s.mac;
    for (int k = 0; k < 4; k++) sig += s.o[k].on ? '1' : '0';
    sig += String(s.lockMask) + String(s.protMask) + String(s.keepMask);
  }
  for (int t = 0; t < MAX_TIMERS; t++) if (timers[t].used) sig += String(timers[t].id) + String(timers[t].phase);
  return sig;
}
float totalPower() {
  float p = 0;
  for (int i = 0; i < MAX_STRIPS; i++)
    if (strips[i].used && strips[i].identified) for (int k = 0; k < 4; k++) p += strips[i].o[k].on ? strips[i].o[k].powerW : 0;
  return p;
}

void publishUserState(const HubUser& u) {
  mqttPub("mttl/" + hubId + "/u/" + u.id + "/state", userStateJson(u), 0, true);
}
void mqttRestart() {
  if (mqtt) { esp_mqtt_client_stop(mqtt); esp_mqtt_client_destroy(mqtt); mqtt = nullptr; }
  mqttUp = false; mqttErrKind = 0; mqttErr = "";
  mqttStart();
}
void mqttHealth() {
  if (mqttRestartReq && exJob.state != 1) { mqttRestartReq = false; mqttRestart(); stateDirty = true; }
  String e;
  if (!secMqtt.length()) e = "no_pass";
  else if (mqttUp) e = "";
  else if (mqttErrKind == 1) e = (mqttErrCode == 4 || mqttErrCode == 5) ? "auth" : "refused";
  else if (mqttErrKind == 2) e = mqttErrTls ? "tls" : "net";
  else e = mqttErr == "no_pass" ? "" : mqttErr;
  if (e != mqttErr) { mqttErr = e; stateDirty = true; if (e.length()) Serial.printf("[mqtt] down: %s (%d)\n", e.c_str(), (int)mqttErrCode); }
}
void publishState() {
  mqttPub(tState, buildStateJson(), 0, true);
  for (int u = 0; u < userCount; u++) publishUserState(users[u]);
  lastStatePub = millis();
  lastRelaySig = relaySignature();
  lastPubPower = totalPower();
  lastProvPub = provState;
}

void mqttProcess() {
  if (!mqttQ) return;
  if (mqttFreshConnect) {
    mqttFreshConnect = false;
    Serial.println("[mqtt] connected");
    mqttPub(tStatus, "online", 1, true);
    mqttPub(tInfo, "{\"hub\":\"" + hubId + "\",\"fw\":\"" + FW_VERSION + "\",\"ip\":\"" + WiFi.localIP().toString() +
            "\",\"web_port\":" + String(WEB_PORT) + ",\"sse_port\":" + String(SSE_PORT) + "}", 1, true);
    publishState();
    flushEventOutbox();
  }
  MqttCmd c;
  while (xQueueReceive(mqttQ, &c, 0) == pdTRUE) {
    String body = c.payload;
    String id = jsonValue(body, "id");
    id.replace("\"", "");
    if (id.length() > 40) id = id.substring(0, 40);
    String path = jsonValue(body, "path");
    if (!path.length()) {                       // legacy messages from app v0.x
      String action = jsonValue(body, "action");
      path = action.length() ? "/api/" + action : "/api/onoff";
    }
    String topic = c.topic, ackTopic = tAck;
    ApiRes r;
    String ub = "mttl/" + hubId + "/u/";
    if (topic.startsWith(ub) && topic.endsWith("/cmd")) {
      String uid = topic.substring(ub.length(), topic.length() - 4);
      int ui = findUser(uid);
      if (ui < 0) continue;                       // revoked or unknown: no answer
      ackTopic = ub + uid + "/cmd/ack";
      apiSrc = 2;
      r = userApi(users[ui], path, body);
    } else {
      apiSrc = 1;
      r = api(path, body);
    }
    apiSrc = 0;
    String ack = "{\"id\":\"" + id + "\",\"ok\":" + (r.ok ? "true" : "false") + ",\"error\":\"" + jsonEsc(r.err) + "\"";
    if (r.data.length()) ack += ",\"data\":" + r.data;
    mqttPub(ackTopic, ack + "}", 1, false);
    publishState();
  }
  if (!mqttUp) return;
  float p = totalPower();
  bool powerMoved = lastPubPower < 0 || fabs(p - lastPubPower) > max(2.0f, lastPubPower * 0.1f);
  if (relaySignature() != lastRelaySig || provState != lastProvPub ||
      (powerMoved && millis() - lastStatePub > 3000) || millis() - lastStatePub > 30000)
    publishState();
}

// ---------- provisioning: the hub points a strip in setup mode at itself ----------
bool setupCmd(const String& cmd, const char* expect, String& reply) {
  WiFiClient c;
  reply = "";
  if (!c.connect(IPAddress(192, 168, 1, 1), 30300, 5000)) { reply = "no answer on 30300"; return false; }
  c.print(cmd);
  c.print("\r\n");
  uint32_t t0 = millis();
  bool gotLine = false;
  while (!gotLine && millis() - t0 < 6000) {
    while (c.available()) {
      char ch = c.read();
      if (ch == '\n') { gotLine = true; break; }
      if (ch != '\r' && ch != 0) reply += ch;
    }
    if (!gotLine && !c.connected()) break;
    delay(10);
  }
  delay(200);
  c.stop();
  Serial.printf("[prov] >> %s  << %s\n", cmd.c_str(), reply.c_str());
  return expect == nullptr || reply.indexOf(expect) >= 0;
}

bool readSetupLine(WiFiClient& c, String& reply, uint32_t ms) {
  reply = "";
  uint32_t t0 = millis();
  while (millis() - t0 < ms) {
    while (c.available()) {
      char ch = c.read();
      if (ch == '\n') return true;
      if (ch != '\r' && ch != 0) reply += ch;
    }
    // v2.14.8: the strip may send its answer slowly and without a newline: stop on a complete ..._ok / fail
    if (reply.endsWith("_ok") || reply.indexOf("fail") >= 0) { delay(150); while (c.available()) { char ch = c.read(); if (ch != '\r' && ch != '\n' && ch != 0) reply += ch; } return true; }
    if (!c.connected()) return reply.length() > 0;
    esp_task_wdt_reset();
    delay(10);
  }
  return reply.length() > 0;
}

// Same as FG Link / mttl_local.py and hub 2.10.1, which provisioned strips successfully:
// ONE TCP session -> up:ip, up:connect, up:reboot:0
// v2.14.8: the home router and the strip's setup AP are BOTH 192.168.1.1. After switching networks the ARP cache
// still maps .1 to the other side's MAC, so TCP to the strip went to the router's MAC (no answer on 30300) and,
// back home, DNS/MQTT went to the strip's MAC for minutes. Drop the cached entries on every switch.
static void flushArpCb(void*) {
  esp_netif_t* nif = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF");
  if (!nif) return;
  struct netif* n = (struct netif*)esp_netif_get_netif_impl(nif);
  if (n) etharp_cleanup_netif(n);
}
void flushArp() {
  tcpip_callback(flushArpCb, nullptr);
  delay(100);
}

// v2.14.9: link diagnostics on the strip's setup network (does the strip answer ARP for .1 at all?)
static volatile int provArpState = -1;
static uint8_t provArpMac[6];
static volatile int provLinkUp = -1, provNetifUp = -1;
static struct netif* staNetif() {
  esp_netif_t* nif = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF");
  return nif ? (struct netif*)esp_netif_get_netif_impl(nif) : nullptr;
}
static void arpRequestCb(void*) {
  struct netif* n = staNetif();
  if (!n) return;
  provLinkUp = netif_is_link_up(n) ? 1 : 0;
  provNetifUp = netif_is_up(n) ? 1 : 0;
  ip4_addr_t a;
  IP4_ADDR(&a, 192, 168, 1, 1);
  etharp_request(n, &a);
}
static void arpFindCb(void*) {
  struct netif* n = staNetif();
  if (!n) { provArpState = -2; return; }
  ip4_addr_t a;
  IP4_ADDR(&a, 192, 168, 1, 1);
  struct eth_addr* e = nullptr;
  const ip4_addr_t* ip = nullptr;
  if (etharp_find_addr(n, &a, &e, &ip) >= 0 && e) { memcpy(provArpMac, e->addr, 6); provArpState = 1; }
  else provArpState = 0;
}
void provLinkReport() {
  uint8_t* b = WiFi.BSSID();
  Serial.printf("[prov] diag: bssid %02X:%02X:%02X:%02X:%02X:%02X  rssi %d  ch %d  status %d\n",
                b ? b[0] : 0, b ? b[1] : 0, b ? b[2] : 0, b ? b[3] : 0, b ? b[4] : 0, b ? b[5] : 0,
                WiFi.RSSI(), WiFi.channel(), (int)WiFi.status());
  for (int k = 0; k < 3; k++) {
    provArpState = -1;
    tcpip_callback(arpRequestCb, nullptr);
    delay(1000);
    tcpip_callback(arpFindCb, nullptr);
    delay(100);
    Serial.printf("[prov] diag: try %d  netif up %d  link up %d  arp .1 %s", k + 1, provNetifUp, provLinkUp,
                  provArpState == 1 ? "answered by " : "NO ANSWER");
    if (provArpState == 1)
      Serial.printf("%02X:%02X:%02X:%02X:%02X:%02X", provArpMac[0], provArpMac[1], provArpMac[2], provArpMac[3],
                    provArpMac[4], provArpMac[5]);
    Serial.println();
    if (provArpState == 1) break;
    esp_task_wdt_reset();
  }
}

bool setupSession(const String& hubIp, String& r) {
  // v2.14.4: the setup service is on the strip AP's gateway (192.168.1.1 on older firmware); try the gateway
  // DHCP gave us first, then the usual addresses, a few rounds while the strip's service comes up
  WiFiClient c;
  IPAddress gw = WiFi.gatewayIP();
  IPAddress cands[3] = {gw, IPAddress(192, 168, 1, 1), IPAddress(192, 168, 4, 1)};
  if (WiFi.localIP() != IPAddress(192, 168, 1, 2)) {     // config before begin did not stick: apply it on the live link
    bool okc = WiFi.config(IPAddress(192, 168, 1, 2), IPAddress(192, 168, 1, 1), IPAddress(255, 255, 255, 0));
    Serial.printf("[prov] re-applied 192.168.1.2: %s\n", okc ? "ok" : "failed");
    delay(500);
    gw = WiFi.gatewayIP();
    cands[0] = gw;
  }
  flushArp();
  Serial.printf("[prov] joined, my ip %s gw %s (arp flushed)\n", WiFi.localIP().toString().c_str(), gw.toString().c_str());
  provLinkReport();
  bool up = false;
  for (int round = 0; round < 3 && !up; round++) {
    for (int k = 0; k < 3 && !up; k++) {
      if (k > 0 && cands[k] == gw) continue;
      if ((uint32_t)cands[k] == 0) continue;
      up = c.connect(cands[k], 30300, 3000);
      if (up) Serial.printf("[prov] setup service at %s:30300\n", cands[k].toString().c_str());
      esp_task_wdt_reset();
    }
    if (!up) delay(1500);
  }
  if (!up) { r = provArpState == 1 ? "no answer on 30300" : "no answer on 30300 (strip silent: no ARP)"; return false; }
  String reply;
  String cmd = "up:ip:" + hubIp;
  c.print(cmd + "\r\n");
  readSetupLine(c, reply, 12000);
  Serial.printf("[prov] >> %s  << %s\n", cmd.c_str(), reply.c_str());
  if (reply.indexOf("ip_ok") < 0) { r = reply; c.stop(); return false; }
  cmd = "up:connect:" + secSsid + ":" + secWifi;
  c.print(cmd + "\r\n");
  readSetupLine(c, reply, 12000);
  Serial.printf("[prov] >> up:connect:%s:****  << %s\n", secSsid.c_str(), reply.c_str());
  if (reply.indexOf("connect_ok") < 0) { r = reply; c.stop(); return false; }
  c.print("up:reboot:0\r\n");
  readSetupLine(c, reply, 6000);     // the strip may answer or just drop the link
  Serial.printf("[prov] >> up:reboot:0  << %s\n", reply.c_str());
  delay(300);
  c.stop();
  delay(3000);                       // let the strip reboot into station mode
  return true;
}

// v2.14.13: flash a strip in setup mode. Same TCP 30300 service as provisioning: "up:ota:<our ip>" makes the strip
// (fw 1.0.141 too, seen in Wireshark) fetch http://<our ip>:80/ota.bin, which the hub answers from the spare OTA slot.
const esp_partition_t* stripFwPart() { return esp_ota_get_next_update_partition(nullptr); }

void otaLog(const String& m) { Serial.println("[strip-ota] " + m); stripOtaLog += m + "\n"; }

// srv must already be listening before "up:ota" goes out: the strip dials :80 about 0.1 s after ota_ok,
// and a reset on that first SYN makes it give up (2.14.13-2.15.4 opened the port only afterwards).
bool serveStripFw(WiFiServer& srv, uint32_t waitMs) {
  const esp_partition_t* part = stripFwPart();
  if (!part || !stripFwSize) { otaLog("no firmware stored"); srv.end(); return false; }
  bool sent = false;
  uint32_t t0 = millis();
  while (!sent && millis() - t0 < waitMs) {
    esp_task_wdt_reset();
    WiFiClient c = srv.accept();
    if (!c) { delay(20); continue; }
    String req;
    uint32_t r0 = millis();
    while (c.connected() && millis() - r0 < 5000 && req.indexOf("\r\n\r\n") < 0) {
      while (c.available()) req += (char)c.read();
      delay(5);
    }
    String first = req.substring(0, req.indexOf('\r'));
    otaLog("request from " + c.remoteIP().toString() + ": " + first);
    if (!first.startsWith("GET ") || first.indexOf("/ota.bin") < 0) {
      c.print("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
      c.stop();
      continue;
    }
    c.setNoDelay(true);
    c.print("HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: " + String(stripFwSize) +
            "\r\nConnection: close\r\n\r\n");
    static uint8_t buf[1460];
    uint32_t off = 0, lastLog = 0, s0 = millis();
    while (off < stripFwSize && c.connected() && millis() - s0 < 120000) {
      uint32_t n = min((uint32_t)sizeof buf, stripFwSize - off);
      if (esp_partition_read(part, off, buf, n) != ESP_OK) { otaLog("flash read failed"); break; }
      size_t w = 0;
      while (w < n && c.connected()) {
        size_t k = c.write(buf + w, n - w);
        if (k == 0) delay(2); else w += k;
        esp_task_wdt_reset();
      }
      off += w;
      if (off - lastLog >= 65536) { lastLog = off; Serial.printf("[strip-ota] sent %u/%u\n", off, stripFwSize); }
    }
    c.flush();
    delay(500);
    c.stop();
    otaLog("sent " + String(off) + "/" + String(stripFwSize) + " bytes in " + String((millis() - s0) / 1000) + " s");
    sent = off == stripFwSize;
  }
  srv.end();
  if (!sent && millis() - t0 >= waitMs) otaLog("the strip did not fetch /ota.bin");
  return sent;
}

bool setupOtaSession(String& r) {
  if (WiFi.localIP() != IPAddress(192, 168, 1, 2)) {
    WiFi.config(IPAddress(192, 168, 1, 2), IPAddress(192, 168, 1, 1), IPAddress(255, 255, 255, 0));
    delay(500);
  }
  flushArp();
  String me = WiFi.localIP().toString();
  otaLog("joined, my ip " + me);
  WiFiServer srv(80);
  srv.begin();
  WiFiClient c;
  bool up = false;
  for (int k = 0; k < 6 && !up; k++) { up = c.connect(IPAddress(192, 168, 1, 1), 30300, 3000); if (!up) delay(1500); esp_task_wdt_reset(); }
  if (!up) { r = "no answer on 30300"; otaLog(r); srv.end(); return false; }
  String reply, cmd = "up:ota:" + me;
  c.print(cmd + "\r\n");
  readSetupLine(c, reply, 12000);
  otaLog(">> " + cmd + "  << " + reply);
  delay(200);
  c.stop();
  if (reply.indexOf("ota_ok") < 0) { r = "strip_said:" + reply; srv.end(); return false; }
  if (!serveStripFw(srv, 90000)) { r = "not_fetched"; return false; }
  otaLog("transfer done; the strip flashes and reboots by itself (keep it powered for 2 minutes)");
  delay(5000);
  return true;
}

void connectWiFi();
volatile uint8_t provDiscReason = 0;   // last STA disconnect reason, for join_failed details
volatile int provStaEvents = 0;        // STA connect/disconnect events seen during a provisioning join

void provFail(const String& msg) { provState = "error"; provMsg = msg; stateDirty = true; Serial.printf("[prov] error: %s\n", msg.c_str()); }

void runProvision() {
  provRequested = false;
  provState = "running";
  provMsg = "";
  stateDirty = true;
  ssePump();
  String hubIp = WiFi.localIP().toString();
  int n = WiFi.scanNetworks();
  String ap;
  int best = -1000;
  int apCh = 0;
  int apEnc = -1;
  uint8_t apBssid[6] = {0};
  for (int i = 0; i < n; i++) {
    String ss = WiFi.SSID(i);
    if ((ss.startsWith("TONLY_TAP_") || ss.startsWith("ONLY_TAP_")) && WiFi.RSSI(i) > best) {
      ap = ss; best = WiFi.RSSI(i); apCh = WiFi.channel(i); memcpy(apBssid, WiFi.BSSID(i), 6); apEnc = (int)WiFi.encryptionType(i);
    }
  }
  WiFi.scanDelete();
  if (provSsid.length()) {                       // the user picked a specific strip
    if (ap != provSsid) {
      bool seen = false;
      int m = WiFi.scanNetworks();
      for (int i = 0; i < m; i++)
        if (WiFi.SSID(i) == provSsid) { seen = true; best = WiFi.RSSI(i); apCh = WiFi.channel(i); memcpy(apBssid, WiFi.BSSID(i), 6); apEnc = (int)WiFi.encryptionType(i); }
      WiFi.scanDelete();
      if (!seen) { provFail("no_ap"); return; }
    }
    ap = provSsid;
  }
  if (!ap.length()) { provFail("no_ap"); return; }
  provTarget = ap.substring(ap.lastIndexOf('_') + 1);
  provTarget.toUpperCase();
  String pass = "LGU_" + ap.substring(ap.lastIndexOf('_') + 1);
  Serial.printf("[prov] joining %s (%d dBm, ch %d, auth %d)\n", ap.c_str(), best, apCh, apEnc);

  for (int i = 0; i < MAX_STRIPS; i++) if (strips[i].used) dropStrip(strips[i], "provisioning");
  // v2.14.3: no auto-reconnect to the home Wi-Fi meanwhile, pin the strip's channel + BSSID, two tries,
  // and report why the join failed (wrong password vs AP gone) instead of a bare join_failed
  WiFi.setAutoReconnect(false);
  // v2.14.11: Arduino-ESP32 3.x refuses APs weaker than WPA2-PSK by default (2.x accepted anything). The strip's
  // setup AP is older WPA, so the join silently never happened (join_failed, no disconnect reason). Allow it here.
  WiFi.setMinSecurity(WIFI_AUTH_OPEN);
  // v2.14.10: the loop below used to start with "status != CONNECTED" while the hub was still on the home Wi-Fi, so it
  // never ran and the hub "joined" YAYA (BSSID = router). Now: leave home first, forget the stored home AP, and only
  // count the join when the BSSID we are on is the strip's.
  bool onStrip = false;
  for (int attempt = 0; attempt < 3 && !onStrip; attempt++) {
    WiFi.disconnect(false, true);                    // leave + erase the stored (home) AP config
    for (int i = 0; i < 20 && WiFi.status() == WL_CONNECTED; i++) delay(100);
    // v2.14.12: join through ESP-IDF directly, like a laptop does: any security, no PMF, full scan, no BSSID pin,
    // and every step's result in the log (the Arduino WiFi.begin wrapper failed silently with reason 0)
    provDiscReason = 0;
    provStaEvents = 0;
    wifi_config_t cfg = {};
    strlcpy((char*)cfg.sta.ssid, ap.c_str(), sizeof(cfg.sta.ssid));
    strlcpy((char*)cfg.sta.password, pass.c_str(), sizeof(cfg.sta.password));
    cfg.sta.threshold.authmode = WIFI_AUTH_OPEN;
    cfg.sta.pmf_cfg.capable = false;
    cfg.sta.pmf_cfg.required = false;
    cfg.sta.scan_method = WIFI_ALL_CHANNEL_SCAN;
    cfg.sta.sort_method = WIFI_CONNECT_AP_BY_SIGNAL;
    esp_wifi_set_storage(WIFI_STORAGE_RAM);
    esp_err_t eCfg = esp_wifi_set_config(WIFI_IF_STA, &cfg);
    esp_err_t eCon = esp_wifi_connect();
    Serial.printf("[prov] try %d: set_config %s, connect %s\n", attempt + 1, esp_err_to_name(eCfg), esp_err_to_name(eCon));
    // associated = the radio reports an AP (independent of IP/DHCP, which the Arduino status waits for)
    wifi_ap_record_t rec;
    bool assoc = false;
    uint32_t t0 = millis();
    while (millis() - t0 < 15000) {
      if (esp_wifi_sta_get_ap_info(&rec) == ESP_OK) { assoc = true; break; }
      delay(250);
      esp_task_wdt_reset();
    }
    if (!assoc) {
      Serial.printf("[prov] join try %d failed: status %d, reason %u, sta events %d (ch %d)\n", attempt + 1,
                    (int)WiFi.status(), provDiscReason, provStaEvents, apCh);
      continue;
    }
    // v2.15.6: the strip is also recognised by its BSSID (its MAC): rec.ssid came back empty although the hub was on it
    onStrip = strcmp((const char*)rec.ssid, ap.c_str()) == 0 || ((apBssid[0] | apBssid[1] | apBssid[2]) && memcmp(rec.bssid, apBssid, 6) == 0);
    Serial.printf("[prov] join try %d: on %s (%02X:%02X:%02X:%02X:%02X:%02X)%s\n", attempt + 1, (const char*)rec.ssid,
                  rec.bssid[0], rec.bssid[1], rec.bssid[2], rec.bssid[3], rec.bssid[4], rec.bssid[5],
                  onStrip ? "" : " - not the strip, retrying");
    if (onStrip) {                                   // address on the strip's network: 192.168.1.2 (what it leases)
      WiFi.config(IPAddress(192, 168, 1, 2), IPAddress(192, 168, 1, 1), IPAddress(255, 255, 255, 0));
      delay(500);
    }
  }
  if (!onStrip) WiFi.disconnect(false, true);
  WiFi.setAutoReconnect(true);
  WiFi.setMinSecurity(WIFI_AUTH_WPA2_PSK);         // back to the default for the home network

  bool ok = false;
  String r;
  if (!onStrip) {
    uint8_t why = provDiscReason;
    // 2 AUTH_EXPIRE, 15 4WAY_HANDSHAKE_TIMEOUT, 202 AUTH_FAIL, 204 HANDSHAKE_TIMEOUT: the AP refused the password
    if (why == 2 || why == 15 || why == 202 || why == 204) r = "join_failed:auth";
    else if (why == 201) r = "join_failed:gone";   // NO_AP_FOUND: it left setup mode or another device holds it
    else r = "join_failed:" + String(why);
  } else {
    delay(800);
    if (provOta) {
      ok = setupOtaSession(r);
    } else {
      // one TCP session: up:ip, up:connect, up:reboot:0
      ok = setupSession(hubIp, r);
      if (!ok && !r.startsWith("no answer on 30300")) r = "strip_said:" + r;
    }
  }
  WiFi.disconnect();
  delay(200);
  connectWiFi();
  flushArp();                          // .1 is the home router again, not the strip
  if (provOta) {
    provOta = false;
    if (ok) { provState = "idle"; provMsg = "ota_sent"; } else provFail("ota:" + r);
    otaLog(ok ? "done" : "failed: " + r);
    stateDirty = true;
    return;
  }
  if (ok) {
    provState = "waiting";            // success is reported only when the strip dials in (bootinfo)
    provMsg = "";
    provAt = millis();
  } else {
    provFail(r);
  }
  stateDirty = true;
}

// ---------- WiFi / setup / loop ----------
void saveWifi(const String& ssid, const String& pass);

bool tryWiFi(const String& ssid, const String& pass, uint32_t ms) {
  // v2.15.6: Wi-Fi settings stay in RAM (the hub keeps its own copy in "sec"); with NVS full, writing them failed
  // (ESP_ERR_NVS_NOT_ENOUGH_SPACE) and the join to a strip's setup network never got its SSID
  WiFi.persistent(false);
  WiFi.mode(WIFI_STA);
  WiFi.setHostname(HOSTNAME);
#if USE_STATIC_IP
  WiFi.config(secLocalIp, GATEWAY, SUBNET, DNS1);
#endif
  WiFi.setSleep(false);
  WiFi.setAutoReconnect(true);
  WiFi.begin(ssid.c_str(), pass.c_str());
  Serial.printf("Connecting to %s", ssid.c_str());
  uint32_t t0 = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - t0 < ms) { delay(500); Serial.print("."); esp_task_wdt_reset(); }
  Serial.println();
  return WiFi.status() == WL_CONNECTED;
}

bool startStripListener() {
  // Rebind after Wi-Fi changes; the old listening socket can remain stale across STA disconnects.
  stripServer.end();
  stripServerAlt.end();
  sseServer.end();
  stripServer.begin();
  stripServer.setNoDelay(true);
  stripServerAlt.begin();
  stripServerAlt.setNoDelay(true);
  sseServer.begin();
  sseServer.setNoDelay(true);
  if (webRoutesReady) web.begin();
  stripListenerReady = (bool)stripServer && (bool)stripServerAlt;
  if (stripListenerReady) Serial.printf("[tcp] strip listener listening on ports %u + %u\n", STRIP_PORT, STRIP_PORT_ALT);
  else Serial.printf("[tcp] ERROR: failed to listen on port %u/%u\n", STRIP_PORT, STRIP_PORT_ALT);
  return stripListenerReady;
}

// The home Wi-Fi is not reachable (router changed?): open "Fisha-Hub-XXXX" so the phone can give it the new network.
void setupPortal() {
  uint8_t m[6];
  WiFi.macAddress(m);
  char ap[24];
  snprintf(ap, sizeof ap, "Fisha-Hub-%02X%02X", m[4], m[5]);
  WiFi.disconnect();
  WiFi.mode(WIFI_AP_STA);
  WiFi.softAP(ap);                                // open: the firmware has no fixed password
  Serial.printf("[portal] Wi-Fi '%s' failed. Join '%s' and open http://192.168.4.1\n", secSsid.c_str(), ap);
  WebServer portal(80);
  bool saved = false;
  portal.on("/", HTTP_GET, [&]() {
    String opts;
    int n = WiFi.scanNetworks();
    for (int i = 0; i < n && i < 20; i++) opts += "<option>" + jsonEsc(WiFi.SSID(i)) + "</option>";
    WiFi.scanDelete();
    portal.send(200, "text/html; charset=utf-8",
                "<meta name=viewport content='width=device-width,initial-scale=1'><body style='font-family:sans-serif;background:#070d19;color:#e9f2ff;padding:20px'>"
                "<h3>Fisha Hub &mdash; Wi-Fi</h3><p>The hub can't reach <b>" + jsonEsc(secSsid) + "</b>. Choose the home network (2.4 GHz):</p>"
                "<form method=POST action=/save><input name=s list=n placeholder='Wi-Fi name' style='width:100%;padding:10px'><datalist id=n>" + opts +
                "</datalist><br><br><input name=p type=password placeholder='Password' style='width:100%;padding:10px'><br><br>"
                "<button style='padding:12px 20px'>Save &amp; restart</button></form></body>");
  });
  portal.on("/save", HTTP_POST, [&]() {
    String ns = portal.arg("s"), np = portal.arg("p");
    ns.trim();
    if (!ns.length() || ns.indexOf(':') >= 0 || np.indexOf(':') >= 0) { portal.send(400, "text/plain", "Name/password can't be empty or contain ':'"); return; }
    saveWifi(ns, np);
    portal.send(200, "text/plain", "Saved. The hub restarts and joins " + ns + ".");
    saved = true;
  });
  portal.begin();
  uint32_t lastTry = millis();
  while (true) {
    esp_task_wdt_reset();
    portal.handleClient();
    if (saved) { delay(1500); ESP.restart(); }
    if (millis() - lastTry > 120000) {           // the old network may simply have been down: retry it now and then
      lastTry = millis();
      WiFi.begin(secSsid.c_str(), secWifi.c_str());
      uint32_t t0 = millis();
      while (WiFi.status() != WL_CONNECTED && millis() - t0 < 10000) { esp_task_wdt_reset(); portal.handleClient(); delay(50); }
      if (WiFi.status() == WL_CONNECTED) { Serial.println("[portal] home Wi-Fi is back"); delay(500); ESP.restart(); }
    }
    delay(5);
  }
}

void connectWiFi() {
  for (int attempt = 0; attempt < 3; attempt++) {
    if (tryWiFi(secSsid, secWifi, 20000)) {
      Serial.printf("WiFi OK  IP=%s  RSSI=%d\n", WiFi.localIP().toString().c_str(), WiFi.RSSI());
      wifiWasConnected = true;
      startStripListener();
      return;
    }
  }
  setupPortal();                                 // never returns
}

// switch to a new home network from the app; keep the old one if the new one does not work
void runWifiTest() {
  wifiTestReq = false;
  wifiTestState = "testing";
  wifiTestMsg = wifiTestSsid;
  stateDirty = true;
  ssePump();
  delay(300);
  for (int i = 0; i < MAX_STRIPS; i++) if (strips[i].used) dropStrip(strips[i], "wifi change");
  WiFi.disconnect();
  delay(300);
  if (tryWiFi(wifiTestSsid, wifiTestPass, 20000)) {
    saveWifi(wifiTestSsid, wifiTestPass);
    wifiWasConnected = true;
    startStripListener();
    wifiTestState = "ok";
    Serial.printf("[wifi] switched to %s\n", secSsid.c_str());
  } else {
    wifiTestState = "failed";
    Serial.printf("[wifi] %s failed, back to %s\n", wifiTestSsid.c_str(), secSsid.c_str());
    WiFi.disconnect();
    delay(300);
    connectWiFi();
  }
  wifiTestPass = "";
  stateDirty = true;
}

void serialRaw() {
  if (!Serial.available()) return;
  String cmd = Serial.readStringUntil('\n');
  cmd.trim();
  int i = firstStrip();
  if (cmd.startsWith("up:") && i >= 0) sendLine(strips[i], cmd);
}

// A value typed in the code wins only when it changed since the last build; values set from the app stay otherwise.
String pickSecret(Preferences& sp, const char* key, const char* compiled, const char* placeholder) {
  String stored = sp.getString(key, "");
  String lastCompiled = sp.getString((String("c") + key).c_str(), "");
  bool real = strlen(compiled) && strcmp(compiled, placeholder) != 0;
  if (real && lastCompiled != compiled) {
    sp.putString((String("c") + key).c_str(), compiled);
    sp.putString(key, compiled);
    return String(compiled);
  }
  return stored.length() ? stored : String(compiled);
}

void saveWifi(const String& ssid, const String& pass) {
  Preferences sp;
  sp.begin("sec", false);
  sp.putString("ssid", ssid);
  sp.putString("wifi", pass);
  sp.end();
  secSsid = ssid;
  secWifi = pass;
}

String randomPass() {                             // 16 characters, no look-alikes
  const char* abc = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  String s;
  for (int i = 0; i < 16; i++) s += abc[esp_random() % 32];
  return s;
}

void loadSecrets() {
  Preferences sp;
  sp.begin("sec", false);
  secSsid = pickSecret(sp, "ssid", WIFI_SSID, "YOUR_WIFI_NAME");
  secWifi = pickSecret(sp, "wifi", WIFI_PASS, "YOUR_WIFI_PASSWORD");
  secMqtt = pickSecret(sp, "mqtt", MQTT_PASS, "YOUR_MQTT_PASSWORD");
  secOta = pickSecret(sp, "ota", OTA_PASS, "");
  secMqttUri = sp.getString("muri", "");
  secMqttUser = sp.getString("muser", MQTT_USER);
  secLocalIp = LOCAL_IP;
  String lip = sp.getString("lip", "");
  if (lip.length() && secLocalIp.fromString(lip)) { lipCheckAt = millis() + 60000; if (!lipCheckAt) lipCheckAt = 1; }
  if (!secOta.length()) { secOta = randomPass(); sp.putString("ota", secOta); }
  sp.end();
}

void setup() {
  Serial.begin(115200);
  // v2.15.8: armed first thing (it used to be armed only at the end of setup, so a hang while booting
  // needed the reset button); 90 s covers a first-boot LittleFS format and the Wi-Fi join
  esp_task_wdt_config_t wc = {};
  wc.timeout_ms = 90000;
  wc.idle_core_mask = 0;
  wc.trigger_panic = true;
  if (esp_task_wdt_reconfigure(&wc) != ESP_OK) esp_task_wdt_init(&wc);
  esp_task_wdt_add(nullptr);
  delay(300);
  Serial.println("\n=== Fisha Hub v" + String(FW_VERSION) + " — @ahmadalhelly ===");
  loadSecrets();
  loadEmqx();
  loadUsers();
  loadOwners();
  cfg.begin("mttl", false);
  fsOk = LittleFS.begin(true);                   // v2.15.7: formats the unused SPIFFS partition on first boot
  esp_task_wdt_reset();
  Serial.printf("[fs] %s\n", fsOk ? "LittleFS ok" : "LittleFS FAILED, history stays in NVS");
  loadGlobals();
  linkLoad();
  loadKnown();
  loadTimers();
  nvsId = cfg.getString("nvsid", "");
  if (!nvsId.length()) { nvsId = randText(8); cfg.putString("nvsid", nvsId); }
  if (cfg.getUChar("nver", 0) < 2) {             // v2.6: every event, every outlet by default
    notifyTypes = 0xFFFFFFFF;
    cfg.putUInt("ntypes", notifyTypes);
    for (int i = 0; i < knownCount; i++) { cfg.remove(("m" + known[i].mac).c_str()); refreshKnown(known[i].mac); }
    cfg.putUChar("nver", 2);
  }
  for (int i = 0; i < MAX_STRIPS; i++) { memset(&elogs[i], 0, sizeof(ELog)); }
  WiFi.onEvent([](WiFiEvent_t, WiFiEventInfo_t info) {
                 provDiscReason = info.wifi_sta_disconnected.reason; provStaEvents++;
                 if (!provRequested && provState != "running") { wifiLastReason = info.wifi_sta_disconnected.reason; wifiDiscCount++; wifiDiscAt = millis(); }
               },
               ARDUINO_EVENT_WIFI_STA_DISCONNECTED);
  WiFi.onEvent([](WiFiEvent_t, WiFiEventInfo_t) { provStaEvents++; }, ARDUINO_EVENT_WIFI_STA_CONNECTED);
  { Preferences p; p.begin("stripfw", true); stripFwSize = p.getUInt("size", 0); p.end(); }
  if (stripFwSize) { stripFwOk = stripFwCheck(stripFwSize, stripFwWhy); if (!stripFwOk) Serial.printf("[strip-ota] stored file refused: %s\n", stripFwWhy.c_str()); }
  connectWiFi();
  configTzTime(TZ_INFO, "pool.ntp.org", "time.google.com");

  const char* hk[] = {"X-Token", "X-User"};
  web.collectHeaders(hk, 2);
  web.on("/", HTTP_GET, handleRoot);
  web.on("/api/state", HTTP_GET, handleState);
  web.on("/api/health", HTTP_GET, handleHealth);
  web.on("/api/raw", HTTP_GET, handleRaw);
  web.on("/update", HTTP_GET, handleUpdatePage);
  web.on("/update", HTTP_POST, handleUpdateDone, handleUpdateUpload);
  web.on("/stripfw", HTTP_GET, handleStripFwPage);
  web.on("/stripfw", HTTP_POST, handleStripFwDone, handleStripFwUpload);
  web.on("/stripfw/flash", HTTP_POST, handleStripFwFlash);
  web.on("/stripfw/live", HTTP_POST, handleSuForm);
  web.on("/api/stripfw", HTTP_GET, handleSuState);
  web.on("/api/stripfw/start", HTTP_POST, handleSuStart);
  web.on("/api/stripfw/cancel", HTTP_POST, handleSuCancel);
  web.on("/api/stripfw/upload", HTTP_POST, handleSuUploadDone, handleSuUpload);
  web.on("/api/stripfw/fetch", HTTP_POST, handleSuFetch);
  web.onNotFound(handleOther);
  web.begin();
  webRoutesReady = true;

  ArduinoOTA.setHostname(HOSTNAME);
  ArduinoOTA.setPassword(secOta.c_str());
  ArduinoOTA.begin();
  MDNS.addService("http", "tcp", WEB_PORT);

  Serial.printf("Web UI  : http://%s:%u  · live: http://%s:%u/events\n", WiFi.localIP().toString().c_str(), WEB_PORT,
                WiFi.localIP().toString().c_str(), SSE_PORT);
  mqttStart();
  // v2.10: a frozen loop reboots the hub after 90 s instead of hanging forever (armed at the top of setup since 2.15.8)
  esp_task_wdt_reset();
  Serial.printf("[hub] last reset: %s\n", resetText().c_str());
}

uint32_t wifiLostAt = 0;

// v2.15.8: times each loop step; one that blocks 5 s or more is logged as a "stall" event once it returns
const char* stgName = "boot";
uint32_t stgAt = 0;
void stg(const char* next) {
  uint32_t now = millis(), d = now - stgAt;
  const char* was = stgName;
  stgName = next; stgAt = now;
  if (d > stallMaxMs) { stallMaxMs = d; stallWhere = was; }
  uint32_t sm = subMax; const char* sw = subWhere;
  subMax = 0; subWhere = "";
  // v2.15.16: time the hub itself stood still is not the strip's fault: a send that was waiting restarts its
  // "stuck" clock, so one slow step no longer drops every strip at once
  if (d >= 1000) for (int i = 0; i < MAX_STRIPS; i++) if (strips[i].used && strips[i].txSince) strips[i].txSince = now;
  if (d >= 5000 && strcmp(was, "boot") && strcmp(was, "wifi_down") && strcmp(was, "provision"))
    addEvent("stall", "", 0, String(was) + " · " + String(d / 1000) + " s" +
                             (sm >= 200 ? " · " + String(sw) + " " + String(sm) + " ms" : String(" · other")) +
                             (!strcmp(was, "web") ? " · " + (webUri.length() ? webUri : String("reading request")) : String("")));
  subMax = 0; subWhere = "";
}

// ---------- v2.15.23: re-link known strips after a Wi-Fi/router change, with no "Add strip" tap needed ----------
// A strip keeps its own Wi-Fi credentials; when the router's name or password changes, the strip can't reconnect
// and used to just sit offline until the user ran "Add strip" on it again by hand. Stock firmware falls back to
// its own setup network (TONLY_TAP_<id>) on its own after it fails to reconnect for a while, so the hub now keeps
// scanning for that network from any strip it already knows and, once it sees one, re-provisions it with the
// current Wi-Fi automatically - the same flow "Add strip" uses, just started by the hub instead of a tap. This
// can only relink a strip that has already fallen back to its own setup network; the hub cannot force that step.
uint32_t autoResyncAt = 0;
void autoResyncScan() {
  if (provState == "running" || provState == "waiting" || provRequested || suRunning()) return;
  if (autoResyncAt && millis() - autoResyncAt < 90000) return;   // once every 90 s at most; a scan briefly interrupts Wi-Fi
  bool anyOffline = false;
  for (int i = 0; i < knownCount; i++) if (findStrip(known[i].mac) < 0) { anyOffline = true; break; }
  if (!anyOffline) return;
  autoResyncAt = millis();
  int n = WiFi.scanNetworks(false, false, false, 300);
  for (int i = 0; i < n; i++) {
    String ss = WiFi.SSID(i);
    if (!ss.startsWith("TONLY_TAP_") && !ss.startsWith("ONLY_TAP_")) continue;
    String id = ss.substring(ss.lastIndexOf('_') + 1);
    id.toUpperCase();
    for (int k = 0; k < knownCount; k++) {
      if (!known[k].mac.endsWith(id) || findStrip(known[k].mac) >= 0) continue;
      Serial.printf("[auto-resync] %s is back in setup mode, re-linking\n", known[k].mac.c_str());
      addEvent("resync", known[k].mac, 0, "auto");
      provSsid = ss;
      requestProvision();
      WiFi.scanDelete();
      return;
    }
  }
  WiFi.scanDelete();
}

void loop() {
  esp_task_wdt_reset();
  stg("loop");
  if (rebootAt && (int32_t)(millis() - rebootAt) >= 0) { Serial.println("[hub] reboot requested"); delay(200); ESP.restart(); }
  if (lipCheckAt && (int32_t)(millis() - lipCheckAt) >= 0) {       // the saved address must reach the router, else back to the default
    if (WiFi.status() != WL_CONNECTED) lipCheckAt = millis() + 10000;
    else {
      lipCheckAt = 0;
      WiFiClient c;
      uint32_t t0 = millis();
      bool up = c.connect(GATEWAY, 80, 3000);
      c.stop();
      if (!up && millis() - t0 >= 2500) {                          // silence, not a refusal: the router is not answering
        Serial.println("[lip] router not reachable on the saved address, back to the default");
        Preferences sp; sp.begin("sec", false); sp.remove("lip"); sp.end();
        secLocalIp = LOCAL_IP;
        rebootAt = millis() + 1000;
        if (!rebootAt) rebootAt = 1;
      }
    }
  }
  if (WiFi.status() != WL_CONNECTED) {
    wifiWasConnected = false;
    if (!wifiLostAt) wifiLostAt = millis();
    static uint32_t lastRecon = 0;
    if (millis() - lastRecon > 8000) {
      lastRecon = millis();
      WiFi.reconnect();
    }
    if (millis() - wifiLostAt > 600000) ESP.restart();
    stg("wifi_down");
    delay(100);
    return;
  }
  if (!wifiWasConnected) {
    wifiWasConnected = true;
    linkHubBlipAt = millis();
    Serial.println("[wifi] link restored; restarting listeners");
    startStripListener();
  }
  wifiLostAt = 0;
  // v2.15.3/2.15.8: every home Wi-Fi loss goes to the event log with its reason code and how long it lasted,
  // counted from the driver so a drop that heals between two loop passes (a stalled loop) is not missed
  static uint32_t wifiDiscSeen = 0;
  if (wifiDiscCount != wifiDiscSeen) {
    linkHubBlipAt = millis();
    uint32_t n = wifiDiscCount - wifiDiscSeen;
    wifiDiscSeen = wifiDiscCount;
    if (!provRequested && provState != "running")
      addEvent("wifi", "", 0, "reason " + String(wifiLastReason) + " · " + String((millis() - wifiDiscAt) / 1000) + " s" +
                              (n > 1 ? " · x" + String(n) : String("")));
  }
  stg("ota");
  ArduinoOTA.handle();
  stg("web");
  webUri = "";
  web.handleClient();
  stg("strips_rx");
  pumpStrips();
  stg("strips_poll");
  pollStrips();
  stg("timers");
  tickTimers();
  stg("schedules");
  tickSchedules();
  stg("links");
  linkTick();
  for (int i = 0; i < MAX_STRIPS; i++) if (strips[i].used && strips[i].identified && strips[i].gotInfo) {
    // auto-off timers must fire even between polls
    for (int k = 0; k < 4; k++) if (strips[i].autoOffAt[k] && (int32_t)(millis() - strips[i].autoOffAt[k]) >= 0) { evalStrip(i); break; }
  }
  stg("sse");
  ssePump();
  serialRaw();
  stg("energy");
  exCollect();
  cloudTodoPump();
  stg("mqtt");
  mqttHealth();
  mqttProcess();
  stg("notify");
  sendNotes();
  stg("strip_update");
  suTick();
  stg("provision");
  if (provRequested && (int32_t)(millis() - provAt) > 600) runProvision();
  else autoResyncScan();
  static uint32_t wifiReqAt = 0;
  if (wifiTestReq) { if (!wifiReqAt) wifiReqAt = millis(); else if (millis() - wifiReqAt > 1500) { wifiReqAt = 0; runWifiTest(); } }
  stg("loop_end");
  if (provState == "waiting" && millis() - provAt > 120000) {
    Serial.printf("[prov] no strip TCP connection accepted on port %u/%u within 120s\n", STRIP_PORT, STRIP_PORT_ALT);
    provFail(stripListenerReady ? "hub_tcp_no_client" : "hub_listener_unavailable");
  }
  delay(2);
}
