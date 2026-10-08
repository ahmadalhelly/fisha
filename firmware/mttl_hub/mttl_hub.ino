// These declarations must precede Arduino's auto-generated function prototypes.
struct Strip;
struct Note;
struct Known;
struct Sched;
struct Autom;
struct HubUser;
struct ApiRes;

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
*/
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
#include "esp_netif.h"
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
const char* OTA_PASS  = "change-me";
const char* MQTT_URI  = "mqtts://t0eb1112.ala.eu-central-1.emqxsl.com:8883";
const char* MQTT_USER = "ESP32_hub";
const char* MQTT_PASS = "YOUR_MQTT_PASSWORD";
const char* TZ_INFO   = "EET-2EEST,M4.5.5/0,M10.5.4/24";   // Africa/Cairo with DST
// ============================================
// From v2.3 the three passwords are also kept in the hub's memory. A firmware built with the placeholders
// above keeps using the stored ones, so later updates can be installed from the app without editing the code.
String secSsid, secWifi, secMqtt, secOta;
// Wi-Fi change requested from the app (tested before it is kept)
volatile bool wifiTestReq = false;
String wifiTestSsid, wifiTestPass, wifiTestState = "idle", wifiTestMsg;
const char* FW_VERSION = "2.14.5";

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
const uint8_t  DIAG_EVERY = 3, MAX_STRIPS = 6, MAX_TIMERS = 12, MAX_SCHED = 20, MAX_AUTO = 10, MAX_EVENTS = 40, MAX_SSE = 4;
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
  bool dead = false;                             // a write could not go out: dropped on the next pump
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
uint32_t lastPoll = 0, pollCount = 0;
volatile bool stateDirty = true;

// MQTT
struct MqttCmd { char payload[640]; char topic[96]; };
esp_mqtt_client_handle_t mqtt = nullptr;
QueueHandle_t mqttQ = nullptr;
volatile bool mqttUp = false, mqttFreshConnect = false;
String hubId, tStatus, tInfo, tState, tEvent, tCmd, tAck;
char mqttClientId[32];
// v2.9: why the cloud link is down, and who sent the command being handled
volatile int mqttErrKind = 0, mqttErrCode = 0, mqttErrTls = 0;   // written by the MQTT task
String mqttErr = "";                                               // "" | no_pass | auth | refused | tls | net
volatile bool mqttRestartReq = false;
uint8_t apiSrc = 0;                                                // 0 local HTTP · 1 owner MQTT · 2 shared user
const uint8_t MAX_USERS = 10;
HubUser users[MAX_USERS];
uint8_t userCount = 0;
String exUrl, exKey, exSec, exLast;                                // EMQX management API (NVS "sec"), never returned

// provisioning
volatile bool provRequested = false;
uint32_t provAt = 0;
String provState = "idle", provMsg = "", provSsid = "", provTarget = "";   // provTarget = last 7 hex of the new strip's MAC

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

void sendLine(Strip& s, const String& line) {
  if (s.dead || !s.c.connected()) return;
  if (!sendStr(s.c, line + "\r\n", 400)) {
    s.dead = true;                               // dropped by pumpStrips(), the strip re-dials by itself
    Serial.printf("[tx %s] stuck, dropping\n", s.mac.length() ? s.mac.c_str() : s.ip.c_str());
    return;
  }
  Serial.printf("[tx %s] %s\n", s.mac.length() ? s.mac.c_str() : s.ip.c_str(), line.c_str());
}

void mqttPub(const String& topic, const String& payload, int qos, bool retain);
void sseSend(const char* ev, const String& data);
void sseEvent(const String& data, const String& mac);

// ---------- phone notifications through ntfy (free, works while the app is closed) ----------
String ntfyTopic;
uint32_t notifyTypes = 0xFFFFFFFF;
const char* EV_TYPES[] = {"temp", "load", "auto_off", "automation", "schedule", "missed", "timer", "cycle", "lock", "added", "test",
                          "button", "remote", "online", "offline", "voltage", "overvolt", "overcurrent", "undervolt", "warn"};
const int EV_COUNT = 20;
Note notes[6];
uint8_t noteCount = 0;
volatile bool tlsBusy = false;                    // the EMQX job holds the only spare TLS session
int stripFor(const String& mac);
int typeBit(const String& t) { for (int i = 0; i < EV_COUNT; i++) if (t == EV_TYPES[i]) return i; return -1; }

void queueNotify(const String& type, const String& mac, int outlet, const String& msg) {
  if (!ntfyTopic.length()) return;
  int bit = typeBit(type);
  if (type != "test" && (bit < 0 || !(notifyTypes & (1UL << bit)))) return;
  if (mac.length()) {
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
                : n.type == "overcurrent" ? "Over current - turned off" : "Test notification";
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
  m.high = n.type == "temp" || n.type == "load" || n.type == "overvolt" || n.type == "undervolt" || n.type == "overcurrent" || n.type == "warn";
  xQueueSend(noteQ, &m, 0);
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
  mqttPub(tEvent, j, 1, false);
  for (int u = 0; u < userCount; u++)
    if (mac.length() ? userHas(users[u], mac) : users[u].all) mqttPub("mttl/" + hubId + "/u/" + users[u].id + "/event", j, 1, false);
  sseSend("event", j);
  queueNotify(type, mac, outlet, msg);
}

// ---------- NVS ----------
void saveLocks(Strip& s) {
  cfg.putUChar(("l" + s.mac).c_str(), s.lockMask);
  cfg.putUChar(("s" + s.mac).c_str(), s.lockState);
}
void saveElog(int i) { cfg.putBytes(("e" + strips[i].mac).c_str(), &elogs[i], sizeof(ELog)); }
void savePeak(int i) { cfg.putBytes(("k" + strips[i].mac).c_str(), &peaks[i], sizeof(PeakLog)); peakSavedAt[i] = millis(); }

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
  if (cfg.getBytesLength(("e" + s.mac).c_str()) == sizeof(ELog)) cfg.getBytes(("e" + s.mac).c_str(), &el, sizeof(ELog));
  if (el.magic != 0xE1E1) {
    memset(&el, 0, sizeof(ELog));
    el.magic = 0xE1E1;
    for (int d = 0; d < ELOG_DAYS; d++) el.dayOf[d] = -1;
  }
  PeakLog& pl = peaks[i];
  if (cfg.getBytesLength(("k" + s.mac).c_str()) == sizeof(PeakLog)) cfg.getBytes(("k" + s.mac).c_str(), &pl, sizeof(PeakLog));
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

void saveScheds() { cfg.putUChar("schN", schedCount); cfg.putBytes("sch", scheds, sizeof(Sched) * MAX_SCHED); }
void saveAutos() { cfg.putUChar("autN", autoCount); cfg.putBytes("aut", autos, sizeof(Autom) * MAX_AUTO); }

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
  if (cfg.getBytesLength("sch") == sizeof(Sched) * MAX_SCHED) {
    cfg.getBytes("sch", scheds, sizeof(Sched) * MAX_SCHED);
    schedCount = min((int)cfg.getUChar("schN", 0), (int)MAX_SCHED);
  }
  autoCount = 0;
  if (cfg.getBytesLength("aut") == sizeof(Autom) * MAX_AUTO) {
    cfg.getBytes("aut", autos, sizeof(Autom) * MAX_AUTO);
    autoCount = min((int)cfg.getUChar("autN", 0), (int)MAX_AUTO);
  } else if (cfg.getBytesLength("aut") == sizeof(AutomV2) * MAX_AUTO) {   // migrate rules saved by v2.0 .. v2.2
    static AutomV2 old[MAX_AUTO];
    cfg.getBytes("aut", old, sizeof(old));
    autoCount = min((int)cfg.getUChar("autN", 0), (int)MAX_AUTO);
    for (int i = 0; i < autoCount; i++) {
      memset(&autos[i], 0, sizeof(Autom));
      memcpy(&autos[i], &old[i], offsetof(AutomV2, metric) + 1);
      autos[i].limit2 = 70;
    }
    saveAutos();
  }
  ntfyTopic = cfg.getString("ntfy", "");
  notifyTypes = cfg.getUInt("ntypes", 0xFFFFFFFF);
  for (int i = 0; i < MAX_AUTO; i++) { autoArmed[i] = false; autoSince[i] = 0; }
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
  if (s.identified && (!strcmp(why, "disconnected") || !strcmp(why, "stale"))) {
    String mac = s.mac;
    if (offlineMacs.indexOf(mac) < 0) offlineMacs += mac + ",";
    s.c.stop();
    s = Strip();
    stateDirty = true;
    addEvent("offline", mac, 0, why);                 // why: "disconnected" (strip closed) or "stale" (silent 45 s)
    return;
  }
  s.c.stop();
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

void sendOnOffF(Strip& s, int outlet, bool on, bool force) {
  for (int ch = (outlet ? outlet : 1); ch <= (outlet ? outlet : 4); ch++) {
    if (keepSkip(s, ch, on, force)) continue;
    noteCommanded(s, ch, on);
    sendLine(s, "up:onoff:" + String(ch) + ":" + (on ? "on" : "off"));
    s.o[ch - 1].on = on;
  }
  sendLine(s, "up:getinfo:all");
  stateDirty = true;
}
void sendOnOff(Strip& s, int outlet, bool on) { sendOnOffF(s, outlet, on, false); }

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
    if (keepSkip(s, ch, on, false)) continue;
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
      if (s.o[k].on && (over || !(s.protMask & (1 << k)))) { sendOnOffF(s, k + 1, false, true); cut |= 1 << k; }
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
  float total = 0;
  float volts = (!isnan(s.voltage) && s.voltage > 50) ? s.voltage : 220.0f;
  for (int k = 0; k < 4; k++) {
    Outlet& o = s.o[k];
    total += o.on ? o.powerW : 0;
    float oAmps = o.on ? (o.powerW / volts) : 0;

    // over-temperature protection & near-limit warning (v2.11)
    if (tempProtect && o.on && o.tempC >= tempMax) {
      if (!s.hotSince[k]) s.hotSince[k] = now ? now : 1;
      else if (now - s.hotSince[k] > 30000) {
        sendOnOffF(s, k + 1, false, true);
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
        else if (now - s.ocoSince[k] > 3000) {
          sendOnOffF(s, k + 1, false, true);
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
    else if (now - s.ocSince > 3000) {
      for (int k = 0; k < 4; k++) if (s.o[k].on && !(s.protMask & (1 << k))) sendOnOffF(s, k + 1, false, true);
      addEvent("overcurrent", s.mac, 0, String(amps, 1) + " A");
      s.ocSince = 0;
    }
  } else s.ocSince = 0;
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
    bool cond;
    if (r.metric == 2) {                         // either limit (watts or temp)
      if (pw < r.watts && tc < r.limit2) { autoArmed[a] = true; autoWarned[a] = false; autoSince[a] = 0; continue; }
      cond = autoArmed[a] && on;
      if (tc >= r.limit2) p = tc;
    } else if (r.above) {
      if (p < r.watts) { autoArmed[a] = true; autoWarned[a] = false; autoSince[a] = 0; continue; }
      cond = autoArmed[a] && on;
    } else {
      if (p > r.watts) { autoArmed[a] = true; autoWarned[a] = false; autoSince[a] = 0; continue; }   // it went above first -> arm
      cond = autoArmed[a] && on;
    }
    // near-threshold warning (color-code alert) before the countdown trips (v2.11)
    if (r.above && autoArmed[a] && on && !autoWarned[a]) {
      float warnAt = r.watts * 0.85f;
      if (r.metric == 1) warnAt = max(r.watts - 5.0f, 40.0f);
      if (p >= warnAt && p < r.watts) {
        autoWarned[a] = true;
        addEvent("warn", s.mac, r.outlet, String(p, r.metric == 1 ? 0 : 1) + (r.metric == 1 ? "°C" : (r.metric == 3 ? " A" : " W")) + " (near " + String(r.watts, r.metric == 1 ? 0 : 1) + ")");
      }
    }
    if (!cond) continue;
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
             ",\"uptime_s\":" + String(millis() / 1000) +
             ",\"provision\":{\"state\":\"" + provState + "\",\"msg\":\"" + jsonEsc(provMsg) + "\"}" +
             ",\"config\":{\"temp_max\":" + String(tempMax) + ",\"temp_protect\":" + (tempProtect ? "true" : "false") +
             ",\"v_protect\":" + (vProt ? "true" : "false") + ",\"v_restore\":" + (vRestore ? "true" : "false") +
             ",\"v_max\":" + String(vMax) + ",\"v_min\":" + String(vMin) +
             ",\"a_protect\":" + (aProt ? "true" : "false") + ",\"a_max\":" + String(aMax, 1) +
             ",\"ntfy\":\"" + jsonEsc(ntfyTopic) + "\",\"ntypes\":" + String(notifyTypes) + ",\"ssid\":\"" + jsonEsc(secSsid) +
             "\",\"wifi_test\":\"" + wifiTestState + "\",\"wifi_test_ssid\":\"" + jsonEsc(wifiTestMsg) + "\"}" +
             ",\"cloud\":{\"up\":" + (mqttUp ? "true" : "false") + ",\"err\":\"" + mqttErr + "\",\"has_pass\":" + (secMqtt.length() ? "true" : "false") +
             ",\"user\":\"" + String(MQTT_USER) + "\",\"host\":\"" + mqttHost() + "\"}" +
             ",\"emqx_cfg\":" + (emqxReady() ? "true" : "false") + ",\"users_n\":" + String(userCount) +
             ",\"reset\":\"" + resetText() + "\"" +
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
         ",\"enabled\":" + (c.enabled ? "true" : "false") + ",\"label\":\"" + jsonEsc(String(c.label)) + "\"}";
}
String autoJson(const Autom& r) {
  return "{\"aid\":" + String(r.id) + ",\"mac\":\"" + String(r.mac) + "\",\"outlet\":" + String(r.outlet) + ",\"above\":" + (r.above ? "true" : "false") +
         ",\"watts\":" + String(r.watts, 1) + ",\"hold_s\":" + String(r.holdS) + ",\"act\":" + String(r.act) +
         ",\"enabled\":" + (r.enabled ? "true" : "false") + ",\"metric\":" + String(r.metric) + ",\"limit2\":" + String(r.limit2, 0) + ",\"label\":\"" + jsonEsc(String(r.label)) + "\"}";
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
  Preferences up; up.begin("users", false); up.putBytes("list", &nv, sizeof nv); up.end();
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
  String u = MQTT_URI;
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
  if (j.kind == 1) {
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
      j.data = "{\"code\":\"" + b64url("{\"v\":1,\"h\":\"" + mqttHost() + "\",\"p\":8883,\"hub\":\"" + hubId + "\",\"u\":\"" + String(j.u.id) +
                                     "\",\"pw\":\"" + j.pw + "\",\"n\":\"" + jsonEsc(String(j.u.name)) + "\",\"r\":" + String(j.u.role) +
                                     ",\"lip\":\"" + WiFi.localIP().toString() + "\"}") +
               "\",\"user\":" + userJson(j.u) + "}";
    } else j.err = "emqx " + exCodeText(http2xx(j.c1) ? j.c2 : j.c1);
    j.pw = "";
  } else if (j.kind == 2) {
    j.ok = (http2xx(j.c1) || j.c1 == 404) && (http2xx(j.c2) || j.c2 == 404);
    if (j.ok) {
      int i = findUser(j.u.id);
      mqttPub("mttl/" + hubId + "/u/" + String(j.u.id) + "/state", "", 1, true);
      if (i >= 0) { for (int k = i; k < userCount - 1; k++) users[k] = users[k + 1]; userCount--; saveUsers(); }
    } else j.err = "emqx " + exCodeText(http2xx(j.c1) || j.c1 == 404 ? j.c2 : j.c1);
  } else {
    j.ok = http2xx(j.c1);
    if (!j.ok) j.err = "emqx " + exCodeText(j.c1);
  }
  j.state = 3;
  stateDirty = true;
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
  if (p == "state" || p == "events" || p == "energy" || p == "schedules" || p == "automations") return 0;
  if (p == "onoff" || p == "refresh" || p == "timer" || p == "timer_cancel" || p == "schedule_save" || p == "schedule_delete") return 1;
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
  if (p == "schedule_delete" || (p == "schedule_save" && jsonValue(b, "sid").toInt())) {
    uint32_t id = (uint32_t)jsonValue(b, "sid").toInt();
    for (int i = 0; i < schedCount; i++) if (scheds[i].id == id) {
      if (p == "schedule_save" && jsonHas(b, "mac") && !jsonValue(b, "mac").equalsIgnoreCase(scheds[i].mac)) return "?";
      return String(scheds[i].mac);
    }
    return p == "schedule_delete" ? "?" : jsonValue(b, "mac");
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
  if (path == "cloud") {                          // {"pass":"..."} local network only
    if (apiSrc != 0) return errRes("local_only");
    bool changed = false;
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
  if (path == "schedule_delete") {
    uint32_t id = (uint32_t)jsonValue(b, "sid").toInt();
    for (int i = 0; i < schedCount; i++) {
      if (scheds[i].id != id) continue;
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
    autoArmed[slot] = false;
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

  // 2. Owner check
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

void handleState() {
  if (!guard()) return;
  if (apiSrc == 2 && apiUserIdx >= 0 && apiUserIdx < userCount) {
    web.send(200, "application/json", userStateJson(users[apiUserIdx]));
  } else {
    web.send(200, "application/json", buildStateJson());
  }
}

void handleHealth() {
  int n = 0;
  for (int i = 0; i < MAX_STRIPS; i++) if (strips[i].used && strips[i].identified) n++;
  web.send(200, "application/json", "{\"status\":\"ok\",\"fw\":\"" + String(FW_VERSION) + "\",\"hub\":\"" + hubId + "\",\"mqtt\":" +
           (mqttUp ? "true" : "false") + ",\"time_ok\":" + (timeOk() ? "true" : "false") + ",\"strips\":" + String(n) +
           ",\"uptime_s\":" + String(millis() / 1000) + ",\"heap\":" + String(ESP.getFreeHeap()) + ",\"max_alloc\":" + String(ESP.getMaxAllocHeap()) +
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

const char PAGE[] PROGMEM = R"HTML(<!doctype html><html dir=rtl lang=ar><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1"><title>Fisha Hub</title>
<style>body{font-family:system-ui,sans-serif;background:#0d1117;color:#e8edf3;margin:0;padding:16px}
.card{background:#151b23;border:1px solid #263040;border-radius:14px;padding:14px;margin-bottom:14px}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:10px}
button{border:0;border-radius:12px;padding:16px 8px;font-size:16px;background:#2a323b;color:#e8edf3}
button.on{background:#f2b544;color:#1a1300}small{display:block;opacity:.75;margin-top:4px}</style>
<h2>&#9889; Fisha Hub</h2><div id=app>...</div><p style="opacity:.5;font-size:12px">@ahmadalhelly</p>
<script>
const q=location.search;
async function load(){try{const r=await fetch('/api/state'+q);render(await r.json())}catch(e){app.textContent='No connection'}}
function render(d){if(!d.devices.length){app.innerHTML='<div class=card>No strip connected</div>';return}
app.innerHTML=d.devices.map(s=>`<div class=card><b>${s.label||s.name}</b><small>${s.power_w} W</small><div class=grid>${s.outlets.map(o=>`<button class="${o.on?'on':''}" onclick="t('${s.mac}',${o.n},${!o.on})">${o.label||o.n}<small>${o.power_w} W · ${o.temp_c}&deg;C</small></button>`).join('')}</div></div>`).join('')}
async function t(mac,outlet,on){await fetch('/api/onoff'+q,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({mac,outlet,on})});load()}
load();setInterval(load,3000);
</script>)HTML";

void handleRoot() { if (guard()) web.send_P(200, "text/html; charset=utf-8", PAGE); }

// v2.14.2: launcher for the web app (iPhone). The app's code comes from the public site, but the page runs on the
// hub's http origin, so the app can reach /api/* here on the LAN (an https page could not) and the cloud as well.
// Static and secret-free: the app itself asks for the invite code. Needs internet to load the app the first time.
const char APP_PAGE[] PROGMEM = R"HTML(<!doctype html><html><head><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name=apple-mobile-web-app-capable content=yes><meta name=mobile-web-app-capable content=yes>
<meta name=apple-mobile-web-app-status-bar-style content=black-translucent>
<meta name=apple-mobile-web-app-title content=Fisha><meta name=theme-color content="#060B18">
<title>Fisha</title><style>html,body{margin:0;height:100%;background:#060B18}</style>
<script>window.FISHA_BASE='https://ahmadalhelly.github.io/fisha-web/';
document.write('<link rel=apple-touch-icon href="'+FISHA_BASE+'icons/Icon-192.png"><link rel=icon href="'+FISHA_BASE+'favicon.png">');</script>
</head><body><script>var s=document.createElement('script');s.src=FISHA_BASE+'flutter_bootstrap.js';s.async=true;
s.onerror=function(){document.body.innerHTML='<p dir=rtl style="color:#e8edf3;font-family:sans-serif;padding:24px">Fisha: محتاج إنترنت عشان يحمّل التطبيق أول مرة.</p>'};
document.body.appendChild(s);</script></body></html>)HTML";

void handleApp() { web.send_P(200, "text/html; charset=utf-8", APP_PAGE); }

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

// ---------- live push: Server-Sent Events on :8081 ----------
struct SseClient { WiFiClient c; bool used = false, ready = false; String req; uint32_t since = 0; int userIdx = -1; };
SseClient sse[MAX_SSE];
uint32_t lastSsePush = 0, lastSseBeat = 0;

void sseSend(const char* ev, const String& data) {
  for (int i = 0; i < MAX_SSE; i++) {
    if (!sse[i].used || !sse[i].ready) continue;
    if (!sse[i].c.connected()) { sse[i].c.stop(); sse[i] = SseClient(); continue; }
    String body = (sse[i].userIdx >= 0 && sse[i].userIdx < userCount && String(ev) == "state") ?
                  userStateJson(users[sse[i].userIdx]) : data;
    String chunk = String("event: ") + ev + "\ndata: " + body + "\n\n";
    sse[i].c.setTimeout(80);
    int written = sse[i].c.write((const uint8_t*)chunk.c_str(), chunk.length());
    if (written < 0 || (size_t)written < chunk.length()) {
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
        bool owner = matchedUser < 0 && (!strlen(API_TOKEN) || qt == API_TOKEN);
        bool ok = owner || matchedUser >= 0;
        if (!ok || !x.req.startsWith("GET /events")) {
          x.c.print("HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\n\r\n");
          x.c.stop(); x = SseClient(); continue;
        }
        x.userIdx = matchedUser;
        x.c.print("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n"
                  "Access-Control-Allow-Origin: *\r\n\r\nretry: 3000\n\n");
        String initData = (x.userIdx >= 0 && x.userIdx < userCount) ? userStateJson(users[x.userIdx]) : buildStateJson();
        x.c.print("event: state\ndata: " + initData + "\n\n");
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
        sse[i].c.setTimeout(80);
        if (sse[i].c.write((const uint8_t*)": hb\n\n", 6) != 6) {
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
  cfgm.broker.address.uri = MQTT_URI;
  cfgm.broker.verification.certificate = MQTT_CA;
  cfgm.credentials.username = MQTT_USER;
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
  cfgm.uri = MQTT_URI; cfgm.cert_pem = MQTT_CA; cfgm.username = MQTT_USER; cfgm.client_id = mqttClientId; cfgm.password = secMqtt.c_str();
  cfgm.lwt_topic = tStatus.c_str(); cfgm.lwt_msg = "offline"; cfgm.lwt_qos = 1; cfgm.lwt_retain = 1; cfgm.keepalive = 30;
  cfgm.reconnect_timeout_ms = 5000; cfgm.buffer_size = 8192; cfgm.out_buffer_size = 8192;
#endif
  mqtt = esp_mqtt_client_init(&cfgm);
  esp_mqtt_client_register_event(mqtt, MQTT_EVENT_ANY, mqttEvent, nullptr);
  esp_mqtt_client_start(mqtt);
  Serial.printf("MQTT    : %s  hub=%s\n", MQTT_URI, id);
}

void mqttPub(const String& topic, const String& payload, int qos, bool retain) {
  if (!mqtt || !mqttUp || !topic.length()) return;
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
    if (!c.connected()) return reply.length() > 0;
    delay(10);
  }
  return reply.length() > 0;
}

// Same as FG Link / mttl_local.py and hub 2.10.1, which provisioned strips successfully:
// ONE TCP session -> up:ip, up:connect, up:reboot:0
bool setupSession(const String& hubIp, String& r) {
  // v2.14.4: the setup service is on the strip AP's gateway (192.168.1.1 on older firmware); try the gateway
  // DHCP gave us first, then the usual addresses, a few rounds while the strip's service comes up
  WiFiClient c;
  IPAddress gw = WiFi.gatewayIP();
  IPAddress cands[3] = {gw, IPAddress(192, 168, 1, 1), IPAddress(192, 168, 4, 1)};
  // wait for a DHCP lease from the strip (anything but our home static address)
  for (int i = 0; i < 20 && WiFi.localIP() == LOCAL_IP; i++) { delay(250); esp_task_wdt_reset(); }
  gw = WiFi.gatewayIP();
  cands[0] = gw;
  Serial.printf("[prov] joined, my ip %s gw %s%s\n", WiFi.localIP().toString().c_str(), gw.toString().c_str(),
                WiFi.localIP() == LOCAL_IP ? " (still the home static IP: no DHCP lease)" : "");
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
  if (!up) { r = "no answer on 30300"; return false; }
  String reply;
  String cmd = "up:ip:" + hubIp;
  c.print(cmd + "\r\n");
  readSetupLine(c, reply, 4000);
  Serial.printf("[prov] >> %s  << %s\n", cmd.c_str(), reply.c_str());
  if (reply.indexOf("ip_ok") < 0) { r = reply; c.stop(); return false; }
  cmd = "up:connect:" + secSsid + ":" + secWifi;
  c.print(cmd + "\r\n");
  readSetupLine(c, reply, 4000);
  Serial.printf("[prov] >> up:connect:%s:****  << %s\n", secSsid.c_str(), reply.c_str());
  if (reply.indexOf("connect_ok") < 0) { r = reply; c.stop(); return false; }
  c.print("up:reboot:0\r\n");
  readSetupLine(c, reply, 2500);     // the strip may answer or just drop the link
  Serial.printf("[prov] >> up:reboot:0  << %s\n", reply.c_str());
  delay(300);
  c.stop();
  delay(3000);                       // let the strip reboot into station mode
  return true;
}

void connectWiFi();
volatile uint8_t provDiscReason = 0;   // last STA disconnect reason, for join_failed details

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
  uint8_t apBssid[6] = {0};
  for (int i = 0; i < n; i++) {
    String ss = WiFi.SSID(i);
    if ((ss.startsWith("TONLY_TAP_") || ss.startsWith("ONLY_TAP_")) && WiFi.RSSI(i) > best) {
      ap = ss; best = WiFi.RSSI(i); apCh = WiFi.channel(i); memcpy(apBssid, WiFi.BSSID(i), 6);
    }
  }
  WiFi.scanDelete();
  if (provSsid.length()) {                       // the user picked a specific strip
    if (ap != provSsid) {
      bool seen = false;
      int m = WiFi.scanNetworks();
      for (int i = 0; i < m; i++)
        if (WiFi.SSID(i) == provSsid) { seen = true; best = WiFi.RSSI(i); apCh = WiFi.channel(i); memcpy(apBssid, WiFi.BSSID(i), 6); }
      WiFi.scanDelete();
      if (!seen) { provFail("no_ap"); return; }
    }
    ap = provSsid;
  }
  if (!ap.length()) { provFail("no_ap"); return; }
  provTarget = ap.substring(ap.lastIndexOf('_') + 1);
  provTarget.toUpperCase();
  String pass = "LGU_" + ap.substring(ap.lastIndexOf('_') + 1);
  Serial.printf("[prov] joining %s (%d dBm)\n", ap.c_str(), best);

  for (int i = 0; i < MAX_STRIPS; i++) if (strips[i].used) dropStrip(strips[i], "provisioning");
  // v2.14.3: no auto-reconnect to the home Wi-Fi meanwhile, pin the strip's channel + BSSID, two tries,
  // and report why the join failed (wrong password vs AP gone) instead of a bare join_failed
  WiFi.setAutoReconnect(false);
  for (int attempt = 0; attempt < 2 && WiFi.status() != WL_CONNECTED; attempt++) {
    WiFi.disconnect(true);
    delay(400);
    WiFi.mode(WIFI_STA);
    WiFi.config(IPAddress((uint32_t)0), IPAddress((uint32_t)0), IPAddress((uint32_t)0));   // DHCP on the strip's AP
    // v2.14.5: the line above left the home static 192.168.1.100 in place on some cores; force the DHCP client on
    if (esp_netif_t* nif = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF")) esp_netif_dhcpc_start(nif);
    provDiscReason = 0;
    if (apCh > 0) WiFi.begin(ap.c_str(), pass.c_str(), apCh, apBssid);
    else WiFi.begin(ap.c_str(), pass.c_str());
    uint32_t t0 = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - t0 < 15000) { delay(250); esp_task_wdt_reset(); }
    if (WiFi.status() != WL_CONNECTED)
      Serial.printf("[prov] join try %d failed: reason %u (ch %d)\n", attempt + 1, provDiscReason, apCh);
  }
  WiFi.setAutoReconnect(true);

  bool ok = false;
  String r;
  if (WiFi.status() != WL_CONNECTED) {
    uint8_t why = provDiscReason;
    // 2 AUTH_EXPIRE, 15 4WAY_HANDSHAKE_TIMEOUT, 202 AUTH_FAIL, 204 HANDSHAKE_TIMEOUT: the AP refused the password
    if (why == 2 || why == 15 || why == 202 || why == 204) r = "join_failed:auth";
    else if (why == 201) r = "join_failed:gone";   // NO_AP_FOUND: it left setup mode or another device holds it
    else r = "join_failed:" + String(why);
  } else {
    delay(800);
    // one TCP session: up:ip, up:connect, up:reboot:0
    ok = setupSession(hubIp, r);
    if (!ok && r != "no answer on 30300") r = "strip_said:" + r;
  }
  WiFi.disconnect();
  delay(200);
  connectWiFi();
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
  WiFi.mode(WIFI_STA);
  WiFi.setHostname(HOSTNAME);
#if USE_STATIC_IP
  WiFi.config(LOCAL_IP, GATEWAY, SUBNET, DNS1);
#endif
  WiFi.setSleep(false);
  WiFi.setAutoReconnect(true);
  WiFi.begin(ssid.c_str(), pass.c_str());
  Serial.printf("Connecting to %s", ssid.c_str());
  uint32_t t0 = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - t0 < ms) { delay(500); Serial.print("."); }
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
  String apPass = (secOta.length() >= 8 && secOta != "change-me") ? secOta : String("fisha1234");
  WiFi.disconnect();
  WiFi.mode(WIFI_AP_STA);
  WiFi.softAP(ap, apPass.c_str());
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

void loadSecrets() {
  Preferences sp;
  sp.begin("sec", false);
  secSsid = pickSecret(sp, "ssid", WIFI_SSID, "YOUR_WIFI_NAME");
  secWifi = pickSecret(sp, "wifi", WIFI_PASS, "YOUR_WIFI_PASSWORD");
  secMqtt = pickSecret(sp, "mqtt", MQTT_PASS, "YOUR_MQTT_PASSWORD");
  secOta = pickSecret(sp, "ota", OTA_PASS, "change-me");
  sp.end();
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\n=== Fisha Hub v" + String(FW_VERSION) + " — @ahmadalhelly ===");
  loadSecrets();
  loadEmqx();
  loadUsers();
  cfg.begin("mttl", false);
  loadGlobals();
  loadKnown();
  loadTimers();
  if (cfg.getUChar("nver", 0) < 2) {             // v2.6: every event, every outlet by default
    notifyTypes = 0xFFFFFFFF;
    cfg.putUInt("ntypes", notifyTypes);
    for (int i = 0; i < knownCount; i++) { cfg.remove(("m" + known[i].mac).c_str()); refreshKnown(known[i].mac); }
    cfg.putUChar("nver", 2);
  }
  for (int i = 0; i < MAX_STRIPS; i++) { memset(&elogs[i], 0, sizeof(ELog)); }
  WiFi.onEvent([](WiFiEvent_t, WiFiEventInfo_t info) { provDiscReason = info.wifi_sta_disconnected.reason; },
               ARDUINO_EVENT_WIFI_STA_DISCONNECTED);
  connectWiFi();
  configTzTime(TZ_INFO, "pool.ntp.org", "time.google.com");

  const char* hk[] = {"X-Token", "X-User"};
  web.collectHeaders(hk, 2);
  web.on("/", HTTP_GET, handleRoot);
  web.on("/app", HTTP_GET, handleApp);
  web.on("/api/state", HTTP_GET, handleState);
  web.on("/api/health", HTTP_GET, handleHealth);
  web.on("/api/raw", HTTP_GET, handleRaw);
  web.on("/update", HTTP_GET, handleUpdatePage);
  web.on("/update", HTTP_POST, handleUpdateDone, handleUpdateUpload);
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
  // v2.10: a frozen loop reboots the hub after 90 s instead of hanging forever
  esp_task_wdt_config_t wc = {};
  wc.timeout_ms = 90000;
  wc.idle_core_mask = 0;
  wc.trigger_panic = true;
  if (esp_task_wdt_reconfigure(&wc) != ESP_OK) esp_task_wdt_init(&wc);
  esp_task_wdt_add(nullptr);
  Serial.printf("[hub] last reset: %s\n", resetText().c_str());
}

uint32_t wifiLostAt = 0;

void loop() {
  esp_task_wdt_reset();
  if (rebootAt && (int32_t)(millis() - rebootAt) >= 0) { Serial.println("[hub] reboot requested"); delay(200); ESP.restart(); }
  if (WiFi.status() != WL_CONNECTED) {
    wifiWasConnected = false;
    if (!wifiLostAt) wifiLostAt = millis();
    static uint32_t lastRecon = 0;
    if (millis() - lastRecon > 8000) {
      lastRecon = millis();
      WiFi.reconnect();
    }
    if (millis() - wifiLostAt > 600000) ESP.restart();
    delay(100);
    return;
  }
  if (!wifiWasConnected) {
    wifiWasConnected = true;
    Serial.println("[wifi] link restored; restarting listeners");
    startStripListener();
  }
  wifiLostAt = 0;
  ArduinoOTA.handle();
  web.handleClient();
  pumpStrips();
  pollStrips();
  tickTimers();
  tickSchedules();
  for (int i = 0; i < MAX_STRIPS; i++) if (strips[i].used && strips[i].identified && strips[i].gotInfo) {
    // auto-off timers must fire even between polls
    for (int k = 0; k < 4; k++) if (strips[i].autoOffAt[k] && (int32_t)(millis() - strips[i].autoOffAt[k]) >= 0) { evalStrip(i); break; }
  }
  ssePump();
  serialRaw();
  exCollect();
  mqttHealth();
  mqttProcess();
  sendNotes();
  if (provRequested && (int32_t)(millis() - provAt) > 600) runProvision();
  static uint32_t wifiReqAt = 0;
  if (wifiTestReq) { if (!wifiReqAt) wifiReqAt = millis(); else if (millis() - wifiReqAt > 1500) { wifiReqAt = 0; runWifiTest(); } }
  if (provState == "waiting" && millis() - provAt > 120000) {
    Serial.printf("[prov] no strip TCP connection accepted on port %u/%u within 120s\n", STRIP_PORT, STRIP_PORT_ALT);
    provFail(stripListenerReady ? "hub_tcp_no_client" : "hub_listener_unavailable");
  }
  delay(2);
}
