/*
  Fisha Hub v2.0 — ESP32 local controller + cloud relay for LG U+ MTTL-W01 smart strips
  Board: ESP32 Dev Module (ESP32-WROOM-32) | Core: esp32 by Espressif 3.x | Partition: Minimal SPIFFS (1.9MB APP with OTA)
  No external libraries.  By: @ahmadalhelly

  Strips  : TCP 10086 (the strip dials the hub, plain-text "up:..." lines)
  HTTP    : 8080   GET /api/state · GET /api/health · GET /api/raw?cmd=up:... · POST /api/<action> (JSON body)
  Live    : 8081   GET /events  (Server-Sent Events: "state" on every change, "event" for alerts)
  MQTT    : mttl/<HUB_ID>/{status,info,state,event,cmd,cmd/ack}   cmd = {"id","path":"/api/...", ...same fields as HTTP}
  Storage : names, child lock, protected outlets, auto-off, schedules, automations, energy history -> NVS (survive reboots)
            countdown / power-cycle timers -> RAM (lost if the hub restarts)

  POST actions: onoff, refresh, label, lock, protect, autooff, timer, timer_cancel, provision,
                schedules, schedule_save, schedule_delete, automations, automation_save, automation_delete,
                events, energy, config
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
#include <vector>

// ================== CONFIG ==================
const char* WIFI_SSID = "YAYA";                 // 2.4 GHz home network — also given to new strips
const char* WIFI_PASS = "YOUR_WIFI_PASSWORD";   // no ':' allowed (strip protocol limit)
#define USE_STATIC_IP 1
IPAddress LOCAL_IP(192, 168, 1, 110);
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
const char* FW_VERSION = "2.2";

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

const uint16_t STRIP_PORT = 10086, WEB_PORT = 8080, SSE_PORT = 8081;
const uint32_t POLL_MS = 3000, STALE_MS = 45000;
const uint8_t  DIAG_EVERY = 5, MAX_STRIPS = 6, MAX_TIMERS = 12, MAX_SCHED = 20, MAX_AUTO = 10, MAX_EVENTS = 40, MAX_SSE = 4;
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

struct Strip {
  WiFiClient c;
  bool used = false, identified = false, hasRssi = false, gotInfo = false, poked = false;
  String mac, model, fw, ip, rx, pendingInfo, lastLine;
  String label, olabel[4];
  uint8_t lockMask = 0, lockState = 0, protMask = 0, keepOnMask = 0, notifyMask = 0x1F;
  uint16_t autoOffMin[4] = {0, 0, 0, 0};
  uint32_t autoOffAt[4] = {0, 0, 0, 0};
  uint32_t hotSince[4] = {0, 0, 0, 0};
  uint32_t loadEventAt = 0;
  float voltage = NAN;
  int rssi = 0;
  Outlet o[4];
  uint32_t lastRx = 0, infoSeq = 0;
};

struct Timer { bool used = false; uint32_t id = 0; char mac[13] = {0}; uint8_t outlet = 0, kind = 0, phase = 0; bool on = false; uint32_t at = 0, offMs = 0, tries = 0; };
// kind: 0 = switch on/off once, 1 = power cycle (off, wait, on)

struct Sched { uint32_t id; char mac[13]; uint8_t outlet, on, days, hh, mm, enabled; uint32_t date; char label[40]; };
struct AutomV1 { uint32_t id; char mac[13]; uint8_t outlet, above, act, enabled; float watts; uint16_t holdS; char label[40]; };
struct Autom { uint32_t id; char mac[13]; uint8_t outlet, above, act, enabled; float watts; uint16_t holdS; char label[40]; uint8_t metric; };
// outlet 0 = whole strip (total W / hottest outlet) · metric 0 = power (W), 1 = temperature (°C) · "watts" holds the threshold
// act: 1 notify, 2 switch off, 3 both
struct Ev { uint32_t ts = 0; String type, mac, msg; int outlet = 0; };
struct ApiRes { bool ok; String err; String data; };
struct Note { String type, mac, msg; int outlet; };   // queued phone notification (defined early for Arduino auto-prototypes)

Strip strips[MAX_STRIPS];
ELog elogs[MAX_STRIPS];
Timer timers[MAX_TIMERS];
Sched scheds[MAX_SCHED];
uint8_t schedCount = 0;
Autom autos[MAX_AUTO];
uint8_t autoCount = 0;
bool autoArmed[MAX_AUTO];
uint32_t autoSince[MAX_AUTO];
Ev events[MAX_EVENTS];
uint8_t evHead = 0, evCount = 0;
uint32_t nextTimerId = 1;
uint8_t tempMax = 70;
bool tempProtect = true;

WiFiServer stripServer(STRIP_PORT);
WiFiServer sseServer(SSE_PORT);
WebServer web(WEB_PORT);
Preferences cfg;
uint32_t lastPoll = 0, pollCount = 0;
volatile bool stateDirty = true;

// MQTT
struct MqttCmd { char payload[640]; };
esp_mqtt_client_handle_t mqtt = nullptr;
QueueHandle_t mqttQ = nullptr;
volatile bool mqttUp = false, mqttFreshConnect = false;
String hubId, tStatus, tInfo, tState, tEvent, tCmd, tAck;
char mqttClientId[32];

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

// Flat JSON reader (our payloads have no nesting). Returns the raw value text, strings without quotes.
String jsonValue(const String& body, const char* key) {
  String k = String("\"") + key + "\"";
  int p = body.indexOf(k);
  if (p < 0) return "";
  p = body.indexOf(':', p + k.length());
  if (p < 0) return "";
  p++;
  while (p < (int)body.length() && isspace((unsigned char)body[p])) p++;
  if (p < (int)body.length() && body[p] == '"') {
    int e = body.indexOf('"', p + 1);
    return e < 0 ? "" : body.substring(p + 1, e);
  }
  int e = p;
  while (e < (int)body.length() && body[e] != ',' && body[e] != '}') e++;
  String v = body.substring(p, e);
  v.trim();
  return v;
}
bool jsonHas(const String& body, const char* key) { return body.indexOf(String("\"") + key + "\"") >= 0; }
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

void sendLine(Strip& s, const String& line) {
  if (!s.c.connected()) return;
  s.c.print(line);
  s.c.print("\r\n");
  Serial.printf("[tx %s] %s\n", s.mac.length() ? s.mac.c_str() : s.ip.c_str(), line.c_str());
}

void mqttPub(const String& topic, const String& payload, int qos, bool retain);
void sseSend(const char* ev, const String& data);

// ---------- phone notifications through ntfy (free, works while the app is closed) ----------
String ntfyTopic;
uint32_t notifyTypes = 0xFFFFFFFF;
const char* EV_TYPES[] = {"temp", "load", "auto_off", "automation", "schedule", "missed", "timer", "cycle", "lock", "added", "test"};
Note notes[6];
uint8_t noteCount = 0;
int stripFor(const String& mac);
int typeBit(const String& t) { for (int i = 0; i < 11; i++) if (t == EV_TYPES[i]) return i; return -1; }

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
                : n.type == "added" ? "New strip connected" : "Test notification";
  return who.length() ? String(t) + " | " + who : String(t);
}

void sendNotes() {
  if (!noteCount || !ntfyTopic.length() || provRequested || provState == "running") return;
  static uint32_t last = 0;
  if (millis() - last < 1500) return;
  last = millis();
  Note n = notes[0];
  for (int i = 1; i < noteCount; i++) notes[i - 1] = notes[i];
  noteCount--;
  WiFiClientSecure tls;
  tls.setInsecure();                          // public push relay; the message carries no secrets
  HTTPClient http;
  http.setTimeout(4000);
  if (!http.begin(tls, "https://ntfy.sh/" + ntfyTopic)) return;
  http.addHeader("Title", noteTitle(n));
  http.addHeader("Tags", n.type == "temp" || n.type == "load" ? "warning" : "electric_plug");
  if (n.type == "temp" || n.type == "load") http.addHeader("Priority", "high");
  int code = http.POST(n.msg.length() ? n.msg : String("Fisha Hub"));
  http.end();
  Serial.printf("[notify] %s -> %d\n", n.type.c_str(), code);
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
  sseSend("event", j);
  queueNotify(type, mac, outlet, msg);
}

// ---------- NVS ----------
void saveLocks(Strip& s) {
  cfg.putUChar(("l" + s.mac).c_str(), s.lockMask);
  cfg.putUChar(("s" + s.mac).c_str(), s.lockState);
}
void saveElog(int i) { cfg.putBytes(("e" + strips[i].mac).c_str(), &elogs[i], sizeof(ELog)); }

void loadStripCfg(int i) {
  Strip& s = strips[i];
  s.label = cfg.getString(("n" + s.mac).c_str(), "");
  for (int k = 0; k < 4; k++) s.olabel[k] = cfg.getString(("n" + s.mac + String(k + 1)).c_str(), "");
  s.lockMask = cfg.getUChar(("l" + s.mac).c_str(), 0);
  s.lockState = cfg.getUChar(("s" + s.mac).c_str(), 0);
  s.protMask = cfg.getUChar(("p" + s.mac).c_str(), 0);
  s.keepOnMask = cfg.getUChar(("k" + s.mac).c_str(), 0);
  s.notifyMask = cfg.getUChar(("m" + s.mac).c_str(), 0x1F);
  if (cfg.getBytesLength(("a" + s.mac).c_str()) == sizeof(s.autoOffMin)) cfg.getBytes(("a" + s.mac).c_str(), s.autoOffMin, sizeof(s.autoOffMin));
  else memset(s.autoOffMin, 0, sizeof(s.autoOffMin));
  ELog& el = elogs[i];
  if (cfg.getBytesLength(("e" + s.mac).c_str()) == sizeof(ELog)) cfg.getBytes(("e" + s.mac).c_str(), &el, sizeof(ELog));
  if (el.magic != 0xE1E1) {
    memset(&el, 0, sizeof(ELog));
    el.magic = 0xE1E1;
    for (int d = 0; d < ELOG_DAYS; d++) el.dayOf[d] = -1;
  }
}

void saveScheds() { cfg.putUChar("schN", schedCount); cfg.putBytes("sch", scheds, sizeof(Sched) * MAX_SCHED); }
void saveAutos() { cfg.putUChar("autN", autoCount); cfg.putBytes("aut", autos, sizeof(Autom) * MAX_AUTO); }

void loadGlobals() {
  tempMax = cfg.getUChar("tmax", 70);
  tempProtect = cfg.getBool("tprot", true);
  schedCount = 0;
  if (cfg.getBytesLength("sch") == sizeof(Sched) * MAX_SCHED) {
    cfg.getBytes("sch", scheds, sizeof(Sched) * MAX_SCHED);
    schedCount = min((int)cfg.getUChar("schN", 0), (int)MAX_SCHED);
  }
  autoCount = 0;
  if (cfg.getBytesLength("aut") == sizeof(Autom) * MAX_AUTO) {
    cfg.getBytes("aut", autos, sizeof(Autom) * MAX_AUTO);
    autoCount = min((int)cfg.getUChar("autN", 0), (int)MAX_AUTO);
  } else if (cfg.getBytesLength("aut") == sizeof(AutomV1) * MAX_AUTO) {   // migrate rules saved by v2.0/2.1
    static AutomV1 old[MAX_AUTO];
    cfg.getBytes("aut", old, sizeof(old));
    autoCount = min((int)cfg.getUChar("autN", 0), (int)MAX_AUTO);
    for (int i = 0; i < autoCount; i++) {
      memset(&autos[i], 0, sizeof(Autom));
      autos[i].id = old[i].id; memcpy(autos[i].mac, old[i].mac, sizeof old[i].mac);
      autos[i].outlet = old[i].outlet; autos[i].above = old[i].above; autos[i].act = old[i].act; autos[i].enabled = old[i].enabled;
      autos[i].watts = old[i].watts; autos[i].holdS = old[i].holdS; memcpy(autos[i].label, old[i].label, sizeof old[i].label);
    }
    saveAutos();
  }
  ntfyTopic = cfg.getString("ntfy", "");
  notifyTypes = cfg.getUInt("ntypes", 0xFFFFFFFF);
  for (int i = 0; i < MAX_AUTO; i++) { autoArmed[i] = false; autoSince[i] = 0; }
}

// ---------- strip control ----------
void dropStrip(Strip& s, const char* why) {
  Serial.printf("[-] %s %s\n", s.mac.length() ? s.mac.c_str() : s.ip.c_str(), why);
  s.c.stop();
  s = Strip();
  stateDirty = true;
}

void noteCommanded(Strip& s, int outlet, bool on) {
  uint8_t before = s.lockState;
  for (int ch = (outlet ? outlet : 1); ch <= (outlet ? outlet : 4); ch++) {
    if (on) s.lockState |= (1 << (ch - 1)); else s.lockState &= ~(1 << (ch - 1));
  }
  if (s.lockState != before && s.lockMask) saveLocks(s);
}

// fire-and-forget switch (used by schedules, timers, automations); the next poll confirms it
void sendOnOff(Strip& s, int outlet, bool on) {
  noteCommanded(s, outlet, on);
  for (int ch = (outlet ? outlet : 1); ch <= (outlet ? outlet : 4); ch++) {
    if (!on && (s.keepOnMask & (1 << (ch - 1)))) continue;
    sendLine(s, "up:onoff:" + String(ch) + ":" + (on ? "on" : "off"));
    s.o[ch - 1].on = on;
  }
  sendLine(s, "up:getinfo:all");
  stateDirty = true;
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
  noteCommanded(s, outlet, on);
  for (int ch = (outlet ? outlet : 1); ch <= (outlet ? outlet : 4); ch++) {
    if (!on && (s.keepOnMask & (1 << (ch - 1)))) continue;
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

// ---------- automations / protections (evaluated after every poll) ----------
void evalStrip(int i) {
  Strip& s = strips[i];
  uint32_t now = millis();
  float total = 0;
  for (int k = 0; k < 4; k++) {
    Outlet& o = s.o[k];
    total += o.on ? o.powerW : 0;
    // over-temperature protection
    if (tempProtect && o.on && o.tempC >= tempMax) {
      if (!s.hotSince[k]) s.hotSince[k] = now ? now : 1;
      else if (now - s.hotSince[k] > 30000) {
        sendOnOff(s, k + 1, false);
        addEvent("temp", s.mac, k + 1, String(o.tempC) + "°C");
        s.hotSince[k] = 0;
      }
    } else {
      s.hotSince[k] = 0;
    }
    // auto-off
    if (s.autoOffAt[k] && (int32_t)(now - s.autoOffAt[k]) >= 0) {
      s.autoOffAt[k] = 0;
      if (o.on) {
        sendOnOff(s, k + 1, false);
        addEvent("auto_off", s.mac, k + 1, String(s.autoOffMin[k]) + " min");
      }
    }
  }
  if (total > 3300 && now - s.loadEventAt > 300000) {
    s.loadEventAt = now;
    addEvent("load", s.mac, 0, String((int)total) + " W");
  }
  int hottest = 0;
  bool anyOn = false;
  for (int k = 0; k < 4; k++) { hottest = max(hottest, s.o[k].tempC); anyOn |= s.o[k].on; }
  for (int a = 0; a < autoCount; a++) {
    Autom& r = autos[a];
    if (!r.enabled || !s.mac.equalsIgnoreCase(r.mac) || r.outlet > 4) continue;
    float p;
    bool on;
    if (r.outlet == 0) { p = r.metric ? hottest : total; on = anyOn; }
    else { Outlet& o = s.o[r.outlet - 1]; p = r.metric ? o.tempC : (o.on ? o.powerW : 0); on = o.on; }
    bool cond;
    if (r.above) {
      if (p < r.watts) { autoArmed[a] = true; autoSince[a] = 0; continue; }
      cond = autoArmed[a] && on;
    } else {
      if (p > r.watts) { autoArmed[a] = true; autoSince[a] = 0; continue; }   // it went above first -> arm
      cond = autoArmed[a] && on;
    }
    if (!cond) continue;
    if (!autoSince[a]) autoSince[a] = now ? now : 1;
    if (now - autoSince[a] >= (uint32_t)r.holdS * 1000) {
      autoArmed[a] = false;
      autoSince[a] = 0;
      if (r.act & 2) {
        if (r.outlet == 0) {                       // whole strip: never cut protected outlets (router)
          for (int k = 0; k < 4; k++) if (s.o[k].on && !(s.protMask & (1 << k))) sendOnOff(s, k + 1, false);
        } else sendOnOff(s, r.outlet, false);
      }
      addEvent("automation", s.mac, r.outlet, String(r.label).length() ? String(r.label) : String(p, r.metric ? 0 : 1) + (r.metric ? " C" : " W"));
    }
  }
}

// ---------- strip protocol ----------
// up:getinfo:<ch>:<runtime>;<relay>;<state>;<flagA>;<flagB>;<power mW>;<energy hex Wh>;<prev>;<config>;<status>;<event>;<temp>  x4
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
  for (int k = 0; k < 4; k++) {
    bool was = s.gotInfo ? s.o[k].on : false;
    if (tmp[k].on && !was && s.autoOffMin[k]) s.autoOffAt[k] = now + (uint32_t)s.autoOffMin[k] * 60000UL;
    if (!tmp[k].on) s.autoOffAt[k] = 0;
    s.o[k] = tmp[k];
  }
  s.gotInfo = true;
  s.pendingInfo = "";
  s.infoSeq++;
  for (int k = 0; k < 4; k++) {                  // enforce keep_on and child lock
    if ((s.keepOnMask & (1 << k)) && !s.o[k].on) {
      sendLine(s, "up:onoff:" + String(k + 1) + ":on");
    } else if (s.lockMask & (1 << k)) {
      bool want = s.lockState & (1 << k);
      if (s.o[k].on != want) sendLine(s, "up:onoff:" + String(k + 1) + ":" + (want ? "on" : "off"));
    }
  }
  energyUpdate(i);
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
    for (int j = 0; j < MAX_STRIPS; j++)
      if (j != i && strips[j].used && strips[j].mac == mac) dropStrip(strips[j], "replaced");
    s.mac = mac; s.model = f[0]; s.fw = f[3]; s.identified = true;
    loadStripCfg(i);
    Serial.printf("[*] strip %s online  model=%s fw=%s\n", mac.c_str(), s.model.c_str(), s.fw.c_str());
    // only the strip we just configured counts — every other strip re-dials after the hub rejoins Wi-Fi
    bool isTarget = provTarget.length() && mac.endsWith(provTarget);
    if (isTarget && (provState == "waiting" || (provState == "error" && (provMsg == "no_dial" || provMsg == "still_setup")))) {
      provState = "connected";
      provMsg = mac;
      addEvent("added", mac, 0, "");
    }
    sendLine(s, "up:getinfo:all");
    stateDirty = true;
    return;
  }
  if (line.startsWith("up:getinfo:")) { s.pendingInfo = line; tryParseInfo(i); return; }
  if (line.startsWith("up:power_report:")) {
    std::vector<String> f = split(line.substring(16), ':');
    if (f.size() == 2 && f[1].toInt() >= 50000) s.voltage = f[1].toInt() / 1000.0f;
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
    if ((s.keepOnMask & (1 << (ch - 1))) && !on) {
      sendLine(s, "up:onoff:" + String(ch) + ":on");
      if (isEvent) {
        static uint32_t last[MAX_STRIPS][4] = {0};
        uint32_t now = millis();
        if (now - last[i][ch - 1] > 60000) { addEvent("lock", s.mac, ch, "keep_on"); last[i][ch - 1] = now; }
      }
    } else if (isEvent && (s.lockMask & (1 << (ch - 1)))) {
      bool want = s.lockState & (1 << (ch - 1));
      if (on != want) sendLine(s, "up:onoff:" + String(ch) + ":" + (want ? "on" : "off"));
      addEvent("lock", s.mac, ch, "");
    } else {
      s.o[ch - 1].on = on;
      if (isEvent) noteCommanded(s, ch, on);
      stateDirty = true;
    }
  } else if (isEvent && ch == 0) {
    sendLine(s, "up:getinfo:all");                           // master button: next poll re-applies locks
  }
}

void acceptStrips() {
  WiFiClient n = stripServer.accept();
  if (!n) return;
  for (int i = 0; i < MAX_STRIPS; i++) {
    if (!strips[i].used) {
      strips[i] = Strip();
      strips[i].c = n;
      strips[i].used = true;
      strips[i].ip = n.remoteIP().toString();
      strips[i].lastRx = millis();
      n.setNoDelay(true);
      Serial.printf("[+] connection from %s\n", strips[i].ip.c_str());
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

// ---------- timers (RAM) ----------
String addTimer(const String& mac, int outlet, int kind, bool on, uint32_t delayS, uint32_t offS) {
  int idx = stripFor(mac);
  if (idx < 0) return "device offline";
  if (outlet < 0 || outlet > 4) return "bad outlet";
  if (kind == 1 && (offS < 3 || offS > 3600)) return "off time must be 3..3600 s";
  if (delayS > 86400) return "delay too long";
  for (int t = 0; t < MAX_TIMERS; t++) {
    if (timers[t].used) continue;
    Timer& x = timers[t];
    x = Timer();
    x.used = true; x.id = nextTimerId++;
    strlcpy(x.mac, strips[idx].mac.c_str(), sizeof x.mac);
    x.outlet = outlet; x.kind = kind; x.on = on; x.offMs = offS * 1000; x.phase = 0;
    x.at = millis() + delayS * 1000;
    stateDirty = true;
    return "";
  }
  return "too many timers";
}

void tickTimers() {
  uint32_t now = millis();
  for (int t = 0; t < MAX_TIMERS; t++) {
    Timer& x = timers[t];
    if (!x.used || (int32_t)(now - x.at) < 0) continue;
    int idx = findStrip(x.mac);
    if (idx < 0) {                                   // strip offline: keep trying the "back on" step for 10 min
      if (x.kind == 1 && x.phase == 1 && x.tries++ < 120) { x.at = now + 5000; continue; }
      addEvent("missed", x.mac, x.outlet, "timer");
      x.used = false; stateDirty = true;
      continue;
    }
    Strip& s = strips[idx];
    if (x.kind == 0) {
      sendOnOff(s, x.outlet, x.on);
      addEvent("timer", s.mac, x.outlet, x.on ? "on" : "off");
      x.used = false;
    } else if (x.phase == 0) {
      sendOnOff(s, x.outlet, false);
      x.phase = 1;
      x.at = now + x.offMs;
    } else {
      sendOnOff(s, x.outlet, true);
      addEvent("cycle", s.mac, x.outlet, String(x.offMs / 1000) + " s");
      x.used = false;
    }
    stateDirty = true;
  }
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
            ",\"keep_on\":" + ((s.keepOnMask & (1 << k)) ? "true" : "false") + ",\"protected\":" + ((s.protMask & (1 << k)) ? "true" : "false") + ",\"auto_off_min\":" + String(s.autoOffMin[k]) +
            ",\"auto_off_in_s\":" + String(left < 0 ? -1 : left) + "}";
  }
  outs += "]";
  return "{\"mac\":\"" + s.mac + "\",\"name\":\"MTTL " + s.mac.substring(5) + "\",\"label\":\"" + jsonEsc(s.label) +
         "\",\"model\":\"" + s.model + "\",\"fw\":\"" + s.fw + "\",\"ip\":\"" + s.ip + "\",\"online\":true,\"on\":" + (any ? "true" : "false") +
         ",\"power_w\":" + String(pw, 2) + ",\"energy_kwh\":" + String(en, 3) +
         ",\"voltage\":" + (isnan(s.voltage) ? String("null") : String(s.voltage, 1)) +
         ",\"current_a\":" + (isnan(s.voltage) || s.voltage <= 0 ? String("0") : String(pw / s.voltage, 2)) +
         ",\"rssi\":" + (s.hasRssi ? String(s.rssi) : String("null")) + ",\"notify\":" + String(s.notifyMask) + ",\"outlets\":" + outs + "}";
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
         ",\"kind\":\"" + (x.kind == 1 ? "cycle" : (x.on ? "on" : "off")) + "\",\"phase\":" + String(x.phase) +
         ",\"in_s\":" + String(in < 0 ? 0 : in) + ",\"off_s\":" + String(x.offMs / 1000) + "}";
  }
  return j + "]";
}

String buildStateJson() {
  String j = "{\"local_ip\":\"" + WiFi.localIP().toString() + "\",\"port\":" + String(STRIP_PORT) + ",\"hub_fw\":\"" + FW_VERSION +
             "\",\"hub\":\"" + hubId + "\",\"time_ok\":" + (timeOk() ? "true" : "false") + ",\"ts\":" + String((uint32_t)time(nullptr)) +
             ",\"provision\":{\"state\":\"" + provState + "\",\"msg\":\"" + jsonEsc(provMsg) + "\"}" +
             ",\"config\":{\"temp_max\":" + String(tempMax) + ",\"temp_protect\":" + (tempProtect ? "true" : "false") +
             ",\"ntfy\":\"" + jsonEsc(ntfyTopic) + "\",\"ntypes\":" + String(notifyTypes) + "}" +
             ",\"timers\":" + timersJson() + ",\"devices\":[";
  bool first = true;
  for (int i = 0; i < MAX_STRIPS; i++) {
    if (!strips[i].used || !strips[i].identified) continue;
    if (!first) j += ",";
    j += stripJson(i);
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
         ",\"enabled\":" + (r.enabled ? "true" : "false") + ",\"metric\":" + String(r.metric) + ",\"label\":\"" + jsonEsc(String(r.label)) + "\"}";
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
  j += "],\"days\":[";
  bool first = true;
  for (int back = 1; back <= ELOG_DAYS; back++) {
    int32_t d = el.day - back;
    int idx = ((d % ELOG_DAYS) + ELOG_DAYS) % ELOG_DAYS;
    if (!el.day || el.dayOf[idx] != d) continue;
    if (!first) j += ",";
    first = false;
    j += "{\"date\":" + String(civilFromDays(d)) + ",\"wh\":[" + String(el.wh[idx][0]) + "," + String(el.wh[idx][1]) + "," +
         String(el.wh[idx][2]) + "," + String(el.wh[idx][3]) + "]}";
  }
  return j + "]}";
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
    return setOutlets(strips[idx], outlet, jsonBool(b, "on")) ? okRes() : errRes("not confirmed");
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
        if (jsonBool(b, "on")) s.keepOnMask |= bit; else s.keepOnMask &= ~bit;
        cfg.putUChar(("k" + s.mac).c_str(), s.keepOnMask);
        if ((s.keepOnMask & bit) && !s.o[outlet - 1].on) sendOnOff(s, outlet, true);
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
    stateDirty = true;
    return okRes();
  }
  if (path == "timer") {
    String kind = jsonValue(b, "kind");
    int k = kind == "cycle" ? 1 : 0;
    bool on = kind == "on";
    if (k == 0 && kind != "on" && kind != "off") return errRes("kind: on|off|cycle");
    String e = addTimer(mac, outlet, k, on, (uint32_t)jsonValue(b, "delay_s").toInt(), (uint32_t)jsonValue(b, "off_s").toInt());
    return e.length() ? errRes(e) : okRes();
  }
  if (path == "timer_cancel") {
    uint32_t id = (uint32_t)jsonValue(b, "tid").toInt();
    for (int t = 0; t < MAX_TIMERS; t++) if (timers[t].used && timers[t].id == id) { timers[t].used = false; stateDirty = true; return okRes(); }
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
    if (strchr(WIFI_SSID, ':') || strchr(WIFI_PASS, ':')) return errRes("wifi name/password contains ':'");
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
    r.metric = jsonValue(b, "metric").toInt() == 1 ? 1 : 0;
    r.above = jsonBool(b, "above");
    r.watts = jsonValue(b, "watts").toFloat();
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
  if (path == "config") {
    if (jsonHas(b, "temp_max")) { tempMax = constrain(jsonValue(b, "temp_max").toInt(), 40, 90); cfg.putUChar("tmax", tempMax); }
    if (jsonHas(b, "temp_protect")) { tempProtect = jsonBool(b, "temp_protect"); cfg.putBool("tprot", tempProtect); }
    stateDirty = true;
    return okRes("{\"temp_max\":" + String(tempMax) + ",\"temp_protect\":" + (tempProtect ? "true" : "false") + "}");
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
    }
    if (jsonBool(b, "test")) queueNotify("test", "", 0, "Fisha");
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
bool authorized() {
  if (!strlen(API_TOKEN)) return true;
  if (web.header("X-Token") == API_TOKEN) return true;
  if (web.arg("t") == API_TOKEN) return true;
  return web.authenticate("hub", API_TOKEN);
}
bool guard() {
  if (authorized()) return true;
  web.sendHeader("WWW-Authenticate", "Basic realm=\"mttl-hub\"");
  web.send(401, "application/json", "{\"ok\":false,\"error\":\"unauthorized\"}");
  return false;
}

void handleState() { if (guard()) web.send(200, "application/json", buildStateJson()); }

void handleHealth() {
  int n = 0;
  for (int i = 0; i < MAX_STRIPS; i++) if (strips[i].used && strips[i].identified) n++;
  web.send(200, "application/json", "{\"status\":\"ok\",\"fw\":\"" + String(FW_VERSION) + "\",\"hub\":\"" + hubId + "\",\"mqtt\":" +
           (mqttUp ? "true" : "false") + ",\"time_ok\":" + (timeOk() ? "true" : "false") + ",\"strips\":" + String(n) +
           ",\"uptime_s\":" + String(millis() / 1000) + ",\"heap\":" + String(ESP.getFreeHeap()) + ",\"wifi_rssi\":" + String(WiFi.RSSI()) + "}");
}

void handleRaw() {
  if (!guard()) return;
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
    ApiRes r = api(web.uri(), web.arg("plain"));
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

// ---------- firmware update from the browser / curl (no inbound port needed on the PC) ----------
bool otaAuth() { return web.authenticate("admin", OTA_PASS); }
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
struct SseClient { WiFiClient c; bool used = false, ready = false; String req; uint32_t since = 0; };
SseClient sse[MAX_SSE];
uint32_t lastSsePush = 0, lastSseBeat = 0;

void sseSend(const char* ev, const String& data) {
  for (int i = 0; i < MAX_SSE; i++) {
    if (!sse[i].used || !sse[i].ready) continue;
    sse[i].c.print(String("event: ") + ev + "\ndata: " + data + "\n\n");
  }
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
  }
  for (int i = 0; i < MAX_SSE; i++) {
    SseClient& x = sse[i];
    if (!x.used) continue;
    if (!x.ready) {
      while (x.c.available() && x.req.length() < 1024) x.req += (char)x.c.read();
      if (x.req.indexOf("\r\n\r\n") >= 0) {
        bool ok = !strlen(API_TOKEN) || x.req.indexOf(String("t=") + API_TOKEN) >= 0;
        if (!ok || !x.req.startsWith("GET /events")) {
          x.c.print("HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\n\r\n");
          x.c.stop(); x = SseClient(); continue;
        }
        x.c.print("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n"
                  "Access-Control-Allow-Origin: *\r\n\r\nretry: 3000\n\n");
        x.c.print("event: state\ndata: " + buildStateJson() + "\n\n");
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
    for (int i = 0; i < MAX_SSE; i++) if (sse[i].used && sse[i].ready) sse[i].c.print(": hb\n\n");
  }
}

// ---------- MQTT cloud relay ----------
uint32_t lastStatePub = 0;
String lastRelaySig, lastProvPub;
float lastPubPower = -1;

static void mqttEvent(void*, esp_event_base_t, int32_t id, void* data) {
  esp_mqtt_event_handle_t e = (esp_mqtt_event_handle_t)data;
  switch ((esp_mqtt_event_id_t)id) {
    case MQTT_EVENT_CONNECTED: mqttUp = true; mqttFreshConnect = true; esp_mqtt_client_subscribe(mqtt, tCmd.c_str(), 1); break;
    case MQTT_EVENT_DISCONNECTED: mqttUp = false; break;
    case MQTT_EVENT_DATA: {
      if (e->current_data_offset != 0 || e->data_len <= 0 || e->data_len >= (int)sizeof(MqttCmd::payload)) break;
      MqttCmd c;
      memcpy(c.payload, e->data, e->data_len);
      c.payload[e->data_len] = 0;
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
  mqttQ = xQueueCreate(6, sizeof(MqttCmd));
  esp_mqtt_client_config_t cfgm = {};
#if ESP_IDF_VERSION_MAJOR >= 5
  cfgm.broker.address.uri = MQTT_URI;
  cfgm.broker.verification.certificate = MQTT_CA;
  cfgm.credentials.username = MQTT_USER;
  cfgm.credentials.client_id = mqttClientId;
  cfgm.credentials.authentication.password = MQTT_PASS;
  cfgm.session.last_will.topic = tStatus.c_str();
  cfgm.session.last_will.msg = "offline";
  cfgm.session.last_will.qos = 1;
  cfgm.session.last_will.retain = 1;
  cfgm.session.keepalive = 30;
  cfgm.network.reconnect_timeout_ms = 5000;
  cfgm.buffer.size = 8192;
  cfgm.buffer.out_size = 8192;
#else
  cfgm.uri = MQTT_URI; cfgm.cert_pem = MQTT_CA; cfgm.username = MQTT_USER; cfgm.client_id = mqttClientId; cfgm.password = MQTT_PASS;
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
    sig += String(s.lockMask) + String(s.protMask) + String(s.keepOnMask);
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

void publishState() {
  mqttPub(tState, buildStateJson(), 0, true);
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
    ApiRes r = api(path, body);
    String ack = "{\"id\":\"" + id + "\",\"ok\":" + (r.ok ? "true" : "false") + ",\"error\":\"" + jsonEsc(r.err) + "\"";
    if (r.data.length()) ack += ",\"data\":" + r.data;
    mqttPub(tAck, ack + "}", 1, false);
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

bool setupSession(const String& hubIp, String& r) {
  WiFiClient c;
  if (!c.connect(IPAddress(192, 168, 1, 1), 30300, 5000)) { r = "no answer on 30300"; return false; }
  String reply;
  String cmd = "up:ip:" + hubIp;
  c.print(cmd + "\r\n");
  readSetupLine(c, reply, 4000);
  Serial.printf("[prov] >> %s  << %s\n", cmd.c_str(), reply.c_str());
  if (reply.indexOf("ip_ok") < 0) { r = reply; c.stop(); return false; }
  cmd = "up:connect:" + String(WIFI_SSID) + ":" + WIFI_PASS;
  c.print(cmd + "\r\n");
  readSetupLine(c, reply, 4000);
  Serial.printf("[prov] >> up:connect:%s:****  << %s\n", WIFI_SSID, reply.c_str());
  if (reply.indexOf("connect_ok") < 0) { r = reply; c.stop(); return false; }
  c.print("up:reboot:0\r\n");
  readSetupLine(c, reply, 2500);     // the strip may answer or just drop the link
  Serial.printf("[prov] >> up:reboot:0  << %s\n", reply.c_str());
  delay(300);
  c.stop();
  return true;
}

void connectWiFi();
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
  for (int i = 0; i < n; i++) {
    String ss = WiFi.SSID(i);
    if ((ss.startsWith("TONLY_TAP_") || ss.startsWith("ONLY_TAP_")) && WiFi.RSSI(i) > best) { ap = ss; best = WiFi.RSSI(i); }
  }
  WiFi.scanDelete();
  if (provSsid.length()) {                       // the user picked a specific strip
    if (ap != provSsid) {
      bool seen = false;
      int m = WiFi.scanNetworks();
      for (int i = 0; i < m; i++) if (WiFi.SSID(i) == provSsid) { seen = true; best = WiFi.RSSI(i); }
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
  WiFi.disconnect();
  delay(300);
  WiFi.config(IPAddress((uint32_t)0), IPAddress((uint32_t)0), IPAddress((uint32_t)0));   // DHCP on the strip's AP
  WiFi.begin(ap.c_str(), pass.c_str());
  uint32_t t0 = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - t0 < 15000) delay(250);

  bool ok = false;
  String r;
  if (WiFi.status() != WL_CONNECTED) {
    r = "join_failed";
  } else {
    delay(800);
    // Same as the official app (FG Link) and mttl_local.py, which provisioned strips successfully:
    // ONE TCP session -> up:ip, up:connect, up:reboot:0 (separate connections are not enough)
    ok = setupSession(hubIp, r);
    if (!ok && r != "no answer on 30300") r = "strip_said:" + r;
    if (ok) delay(3000);              // let the strip reboot into station mode
  }
  WiFi.disconnect();
  delay(300);
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
void connectWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.setHostname(HOSTNAME);
#if USE_STATIC_IP
  WiFi.config(LOCAL_IP, GATEWAY, SUBNET, DNS1);
#endif
  WiFi.setSleep(false);
  WiFi.setAutoReconnect(true);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  Serial.printf("Connecting to %s", WIFI_SSID);
  uint32_t t0 = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - t0 < 20000) { delay(500); Serial.print("."); }
  if (WiFi.status() != WL_CONNECTED) { Serial.println("\nWiFi failed, rebooting in 10s"); delay(10000); ESP.restart(); }
  Serial.printf("\nWiFi OK  IP=%s  RSSI=%d\n", WiFi.localIP().toString().c_str(), WiFi.RSSI());
}

void serialRaw() {
  if (!Serial.available()) return;
  String cmd = Serial.readStringUntil('\n');
  cmd.trim();
  int i = firstStrip();
  if (cmd.startsWith("up:") && i >= 0) sendLine(strips[i], cmd);
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\n=== Fisha Hub v2.2 — @ahmadalhelly ===");
  cfg.begin("mttl", false);
  loadGlobals();
  for (int i = 0; i < MAX_STRIPS; i++) { memset(&elogs[i], 0, sizeof(ELog)); }
  connectWiFi();
  configTzTime(TZ_INFO, "pool.ntp.org", "time.google.com");

  stripServer.begin();
  stripServer.setNoDelay(true);
  sseServer.begin();
  sseServer.setNoDelay(true);

  const char* hk[] = {"X-Token"};
  web.collectHeaders(hk, 1);
  web.on("/", HTTP_GET, handleRoot);
  web.on("/api/state", HTTP_GET, handleState);
  web.on("/api/health", HTTP_GET, handleHealth);
  web.on("/api/raw", HTTP_GET, handleRaw);
  web.on("/update", HTTP_GET, handleUpdatePage);
  web.on("/update", HTTP_POST, handleUpdateDone, handleUpdateUpload);
  web.onNotFound(handleOther);
  web.begin();

  ArduinoOTA.setHostname(HOSTNAME);
  ArduinoOTA.setPassword(OTA_PASS);
  ArduinoOTA.begin();
  MDNS.addService("http", "tcp", WEB_PORT);

  Serial.printf("Web UI  : http://%s:%u  · live: http://%s:%u/events\n", WiFi.localIP().toString().c_str(), WEB_PORT,
                WiFi.localIP().toString().c_str(), SSE_PORT);
  mqttStart();
}

uint32_t wifiLostAt = 0;

void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    if (!wifiLostAt) wifiLostAt = millis();
    if (millis() - wifiLostAt > 60000) ESP.restart();
    delay(100);
    return;
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
  mqttProcess();
  sendNotes();
  if (provRequested && (int32_t)(millis() - provAt) > 600) runProvision();
  if (provState == "waiting" && millis() - provAt > 120000) {
    Serial.println("[prov] the new strip never dialed the hub");
    // did the strip keep its setup AP? then it never accepted the settings
    bool stillSetup = false;
    int n = WiFi.scanNetworks(false, false, false, 300);
    for (int i = 0; i < n; i++) { String ss = WiFi.SSID(i); ss.toUpperCase(); if (ss.endsWith("_" + provTarget)) stillSetup = true; }
    WiFi.scanDelete();
    provFail(stillSetup ? "still_setup" : "no_dial");
  }
  delay(2);
}
