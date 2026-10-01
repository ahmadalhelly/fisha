/*
  MTTL Hub v1.1 — ESP32 local controller + cloud relay for LG U+ MTTL-W01 smart strips
  Board: ESP32 Dev Module (ESP32-WROOM-32)  |  Core: esp32 by Espressif 2.x or 3.x
  No external libraries needed.

  - TCP 10086 : the strips dial in here (plain-text "up:..." protocol)
  - HTTP 8080 : web UI + JSON API compatible with the powerk Android app
                GET  /api/state
                POST /api/onoff  {"mac":"...","outlet":0-4,"on":true}   (0 = all)
                GET  /api/health
                GET  /api/raw?cmd=up:getinfo:all   (debug: send a raw line to the first strip)
                POST /api/label     {"mac":"...","outlet":0-4,"label":"..."}   (0 = the strip itself; "" resets)
                POST /api/lock      {"mac":"...","outlet":1-4,"locked":true}   (child lock: physical button is reverted)
                POST /api/provision {}   (hub joins TONLY_TAP_* and points the strip at itself; watch "provision" in /api/state)
  - Serial    : type any "up:..." line in Serial Monitor (Newline) to send it to the first strip
  - OTA       : Arduino IDE -> Tools -> Port -> mttl-hub (network)
  - MQTT/TLS  : outbound to the cloud broker (remote control from anywhere, no port forwarding)
                mttl/<HUB_ID>/status   retained  online | offline (LWT)
                mttl/<HUB_ID>/info     retained  {"hub","fw","ip","web_port"}
                mttl/<HUB_ID>/state    retained  same JSON as GET /api/state
                mttl/<HUB_ID>/cmd      <- {"id":"x1","mac":"...","outlet":0-4,"on":true} | {"id":"x2","action":"refresh"}
                                          {"id","action":"label","mac","outlet","label"} | {"id","action":"lock","mac","outlet","locked"}
                                          {"id","action":"provision"}
                mttl/<HUB_ID>/cmd/ack  -> {"id":"x1","ok":true,"error":""}
*/
#include <WiFi.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include <ArduinoOTA.h>
#include <Preferences.h>
#include "mqtt_client.h"
#include "esp_idf_version.h"
#include <vector>

// ================== CONFIG ==================
const char* WIFI_SSID = "YAYA";                 // 2.4 GHz home network (same one the strip joins)
const char* WIFI_PASS = "YOUR_WIFI_PASSWORD";
#define USE_STATIC_IP 1                         // 1 = fixed IP below (the IP the strip was provisioned with)
IPAddress LOCAL_IP(192, 168, 1, 110);
IPAddress GATEWAY(192, 168, 1, 1);
IPAddress SUBNET(255, 255, 255, 0);
IPAddress DNS1(192, 168, 1, 1);
const char* API_TOKEN = "";                     // empty = no auth (LAN only). Set one before any remote access.
const char* HOSTNAME  = "mttl-hub";
const char* OTA_PASS  = "change-me";
const char* MQTT_URI  = "mqtts://t0eb1112.ala.eu-central-1.emqxsl.com:8883";
const char* MQTT_USER = "ESP32_hub";
const char* MQTT_PASS = "YOUR_MQTT_PASSWORD";   // the password you set for ESP32_hub in EMQX
// ============================================
const char* FW_VERSION = "1.1";

// EMQX Serverless CA (DigiCert Global Root G2, valid until 2038) — public certificate
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

const uint16_t STRIP_PORT = 10086;
const uint16_t WEB_PORT   = 8080;
const uint32_t POLL_MS    = 5000;
const uint32_t STALE_MS   = 45000;              // drop a strip that sent nothing for this long
const uint8_t  DIAG_EVERY = 3;                  // voltage + RSSI every Nth poll
const uint8_t  MAX_STRIPS = 6;

struct Outlet { bool on = false; float powerW = 0; float energyKwh = 0; int tempC = 0; };

struct Strip {
  WiFiClient c;
  bool used = false, identified = false, hasRssi = false;
  String mac, model, fw, ip, rx, pendingInfo, lastLine;
  String label, olabel[4];                        // user names, stored in NVS
  uint8_t lockMask = 0, lockState = 0;            // child lock: which outlets, and the state they are held at
  float voltage = NAN;
  int rssi = 0;
  Outlet o[4];
  uint32_t lastRx = 0, infoSeq = 0;
};

Strip strips[MAX_STRIPS];
Preferences cfg;
volatile bool provRequested = false;
uint32_t provAt = 0;
String provState = "idle", provMsg = "";
WiFiServer stripServer(STRIP_PORT);
WebServer web(WEB_PORT);
uint32_t lastPoll = 0, pollCount = 0;

// MQTT state (used by HTTP handlers too)
struct MqttCmd { char payload[256]; };
esp_mqtt_client_handle_t mqtt = nullptr;
QueueHandle_t mqttQ = nullptr;
volatile bool mqttUp = false, mqttFreshConnect = false;
String hubId, tStatus, tInfo, tState, tCmd, tAck;

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

void loadStripCfg(Strip& s) {
  s.label = cfg.getString(("n" + s.mac).c_str(), "");
  for (int k = 0; k < 4; k++) s.olabel[k] = cfg.getString(("n" + s.mac + String(k + 1)).c_str(), "");
  s.lockMask = cfg.getUChar(("l" + s.mac).c_str(), 0);
  s.lockState = cfg.getUChar(("s" + s.mac).c_str(), 0);
}

void saveLocks(Strip& s) {
  cfg.putUChar(("l" + s.mac).c_str(), s.lockMask);
  cfg.putUChar(("s" + s.mac).c_str(), s.lockState);
}

void sendLine(Strip& s, const String& line) {
  if (!s.c.connected()) return;
  s.c.print(line);
  s.c.print("\r\n");
  Serial.printf("[tx %s] %s\n", s.mac.length() ? s.mac.c_str() : s.ip.c_str(), line.c_str());
}

void dropStrip(Strip& s, const char* why) {
  Serial.printf("[-] %s %s\n", s.mac.length() ? s.mac.c_str() : s.ip.c_str(), why);
  s.c.stop();
  s = Strip();
}

int findStrip(const String& mac) {
  for (int i = 0; i < MAX_STRIPS; i++)
    if (strips[i].used && strips[i].identified && strips[i].mac.equalsIgnoreCase(mac)) return i;
  return -1;
}

// ---------- protocol ----------
// up:getinfo:<ch>:<runtime>;<relay>;<state>;<overload>;<overheat>;<power mW>;<energy hex Wh>;
//            <prev hex>;<config hex>;<status>;<event hex>;<temp C>  (x4, optional ch5 = aggregate)
bool tryParseInfo(Strip& s) {
  std::vector<String> t = split(s.pendingInfo.substring(11), ':');
  Outlet tmp[4];
  bool seen[4] = {false, false, false, false};
  for (size_t i = 0; i + 1 < t.size(); i += 2) {
    int ch = t[i].toInt();
    std::vector<String> f = split(t[i + 1], ';');
    if (f.size() < 12) continue;
    if (ch < 1 || ch > 4) continue;                        // skip aggregate / junk
    if (!isHex(f[6])) continue;
    Outlet& o = tmp[ch - 1];
    o.on        = f[1].equalsIgnoreCase("on");
    o.powerW    = f[5].toInt() / 1000.0f;
    o.energyKwh = strtoul(f[6].c_str(), nullptr, 16) / 1000.0f;
    o.tempC     = f[11].toInt();
    seen[ch - 1] = true;
  }
  if (!(seen[0] && seen[1] && seen[2] && seen[3])) {
    if (s.pendingInfo.length() > 2048) s.pendingInfo = "";
    return false;
  }
  for (int i = 0; i < 4; i++) s.o[i] = tmp[i];
  s.pendingInfo = "";
  s.infoSeq++;
  for (int k = 0; k < 4; k++) {                          // child lock: put a locked outlet back where it belongs
    if (!(s.lockMask & (1 << k))) continue;
    bool want = s.lockState & (1 << k);
    if (s.o[k].on != want) sendLine(s, "up:onoff:" + String(k + 1) + ":" + (want ? "on" : "off"));
  }
  return true;
}

void handleLine(Strip& s, const String& line) {
  s.lastLine = line;
  s.lastLine.replace("\"", "'");
  Serial.printf("[rx %s] %s\n", s.mac.length() ? s.mac.c_str() : s.ip.c_str(), line.c_str());

  if (s.pendingInfo.length() && !line.startsWith("up:")) {  // continuation of a split getinfo frame
    s.pendingInfo += line;
    tryParseInfo(s);
    return;
  }
  if (line.startsWith("up:bootinfo:")) {                    // <model>;<mac>;<mac>;<fw>;connect
    std::vector<String> f = split(line.substring(12), ';');
    if (f.size() < 5 || f[1].length() != 12 || !isHex(f[1])) return;
    String mac = f[1]; mac.toUpperCase();
    for (int i = 0; i < MAX_STRIPS; i++)                    // a re-dial replaces the old session
      if (&strips[i] != &s && strips[i].used && strips[i].mac == mac) dropStrip(strips[i], "replaced");
    s.mac = mac; s.model = f[0]; s.fw = f[3]; s.identified = true;
    loadStripCfg(s);
    Serial.printf("[*] strip %s online  model=%s fw=%s\n", mac.c_str(), s.model.c_str(), s.fw.c_str());
    sendLine(s, "up:getinfo:all");
    return;
  }
  if (line.startsWith("up:getinfo:")) { s.pendingInfo = line; tryParseInfo(s); return; }
  if (line.startsWith("up:power_report:")) {                // <ch>:<mV> (>=50000) or <mA>
    std::vector<String> f = split(line.substring(16), ':');
    if (f.size() == 2 && f[1].toInt() >= 50000) s.voltage = f[1].toInt() / 1000.0f;
    return;
  }
  if (line.startsWith("up:query:")) { s.rssi = line.substring(9).toInt(); s.hasRssi = true; return; }

  String l = line; l.toLowerCase();
  String body;
  if (l.startsWith("up:event:onoff:")) body = l.substring(15);
  else if (l.startsWith("up:onoff:")) body = l.substring(9);
  if (body.length()) {
    std::vector<String> f = split(body, ':');
    int ch = f.size() == 2 ? f[0].toInt() : -1;
    bool isEvent = l.startsWith("up:event:");
    if (ch >= 1 && ch <= 4) {
      bool on = (f[1] == "on");
      if (isEvent && (s.lockMask & (1 << (ch - 1)))) {       // physical button on a locked outlet: undo it
        bool want = s.lockState & (1 << (ch - 1));
        if (on != want) sendLine(s, "up:onoff:" + String(ch) + ":" + (want ? "on" : "off"));
        Serial.printf("[lock] outlet %d is locked, reverted\n", ch);
      } else {
        s.o[ch - 1].on = on;
      }
    } else if (isEvent && ch == 0 && s.lockMask) {
      sendLine(s, "up:getinfo:all");                           // master button: the next getinfo re-applies locks
    }
  }
}

void acceptStrips() {
#if ESP_ARDUINO_VERSION_MAJOR >= 3
  WiFiClient n = stripServer.accept();
#else
  WiFiClient n = stripServer.available();
#endif
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
  Serial.println("[!] no free slot, rejecting connection");
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
      if (ch == 0 || ch == '\r') continue;                 // firmware pads some frames with NULs
      if (ch == '\n') {
        String line = s.rx; line.trim();
        s.rx = "";
        if (line.length()) handleLine(s, line);
        if (!s.used) break;
      } else if (s.rx.length() < 4096) {
        s.rx += ch;
      } else {
        s.rx = "";
      }
    }
    if (!s.used) continue;
    if (!s.c.connected() && !s.c.available()) dropStrip(s, "disconnected");
    else if (millis() - s.lastRx > STALE_MS) dropStrip(s, "stale");
  }
}

void pumpFor(uint32_t ms) {
  uint32_t t0 = millis();
  while (millis() - t0 < ms) { pumpStrips(); delay(5); }
}

bool waitForInfo(Strip& s, uint32_t seq, uint32_t ms) {
  uint32_t t0 = millis();
  while (millis() - t0 < ms) {
    pumpStrips();
    if (!s.used) return false;
    if (s.infoSeq > seq) return true;
    delay(5);
  }
  return false;
}

void pollStrips() {
  if (millis() - lastPoll < POLL_MS) return;
  lastPoll = millis();
  pollCount++;
  for (int i = 0; i < MAX_STRIPS; i++) {
    Strip& s = strips[i];
    if (!s.used || !s.identified) continue;
    sendLine(s, "up:getinfo:all");
    if (pollCount % DIAG_EVERY == 0) {
      sendLine(s, "up:power_report:1:vol");
      sendLine(s, "up:query:wifirssi");
    }
  }
}

// ---------- debug: raw commands ----------
int firstStrip() {
  for (int i = 0; i < MAX_STRIPS; i++) if (strips[i].used && strips[i].identified) return i;
  return -1;
}

void serialRaw() {
  if (!Serial.available()) return;
  String cmd = Serial.readStringUntil('\n');
  cmd.trim();
  if (!cmd.startsWith("up:")) { if (cmd.length()) Serial.println("[!] commands must start with up:"); return; }
  int i = firstStrip();
  if (i < 0) { Serial.println("[!] no strip connected"); return; }
  sendLine(strips[i], cmd);
}

// Switch one outlet (1-4) or all (0), then confirm with a fresh getinfo.
bool setOutlets(Strip& s, int outlet, bool on) {
  uint8_t before = s.lockState;
  for (int ch = (outlet ? outlet : 1); ch <= (outlet ? outlet : 4); ch++) {   // app commands move the held state
    if (on) s.lockState |= (1 << (ch - 1)); else s.lockState &= ~(1 << (ch - 1));
  }
  if (s.lockState != before && s.lockMask) saveLocks(s);
  for (int ch = (outlet ? outlet : 1); ch <= (outlet ? outlet : 4); ch++) {   // no up:onoff:0 — loop 1..4
    sendLine(s, "up:onoff:" + String(ch) + ":" + (on ? "on" : "off"));
    pumpFor(120);
  }
  pumpFor(300);                                                               // let the relay settle
  if (!s.used) return false;
  uint32_t seq = s.infoSeq;
  sendLine(s, "up:getinfo:all");
  return waitForInfo(s, seq, 4000);
}

// ---------- HTTP ----------
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
  String v = body.substring(p, e); v.trim();
  return v;
}

bool authorized() {
  if (!strlen(API_TOKEN)) return true;
  if (web.header("X-Token") == API_TOKEN) return true;
  if (web.arg("t") == API_TOKEN) return true;
  return web.authenticate("powerk", API_TOKEN);
}

bool guard() {
  if (authorized()) return true;
  web.sendHeader("WWW-Authenticate", "Basic realm=\"mttl-hub\"");
  web.send(401, "application/json", "{\"error\":\"unauthorized\"}");
  return false;
}

String stripJson(const Strip& s) {
  float pw = 0, en = 0; bool any = false;
  String outs = "[";
  for (int i = 0; i < 4; i++) {
    const Outlet& o = s.o[i];
    pw += o.powerW; en += o.energyKwh; any |= o.on;
    if (i) outs += ",";
    outs += "{\"n\":" + String(i + 1) + ",\"on\":" + (o.on ? "true" : "false") +
            ",\"power_w\":" + String(o.powerW, 2) + ",\"energy_kwh\":" + String(o.energyKwh, 3) +
            ",\"temp_c\":" + String(o.tempC) + ",\"label\":\"" + jsonEsc(s.olabel[i]) +
            "\",\"locked\":" + ((s.lockMask & (1 << i)) ? "true" : "false") + "}";
  }
  outs += "]";
  String j = "{\"mac\":\"" + s.mac + "\",\"name\":\"MTTL " + s.mac.substring(5) + "\",\"label\":\"" + jsonEsc(s.label) +
             "\",\"model\":\"" + s.model +
             "\",\"fw\":\"" + s.fw + "\",\"ip\":\"" + s.ip + "\",\"online\":true,\"on\":" + (any ? "true" : "false") +
             ",\"power_w\":" + String(pw, 2) + ",\"energy_kwh\":" + String(en, 3) +
             ",\"voltage\":" + (isnan(s.voltage) ? String("null") : String(s.voltage, 1)) +
             ",\"current_a\":" + (isnan(s.voltage) || s.voltage <= 0 ? String("0") : String(pw / s.voltage, 2)) +
             ",\"rssi\":" + (s.hasRssi ? String(s.rssi) : String("null")) +
             ",\"outlets\":" + outs + "}";
  return j;
}

String buildStateJson() {
  String j = "{\"local_ip\":\"" + WiFi.localIP().toString() + "\",\"port\":" + String(STRIP_PORT) +
             ",\"hub_fw\":\"" + FW_VERSION + "\",\"provision\":{\"state\":\"" + provState + "\",\"msg\":\"" + jsonEsc(provMsg) +
             "\"},\"devices\":[";
  bool first = true;
  for (int i = 0; i < MAX_STRIPS; i++) {
    if (!strips[i].used || !strips[i].identified) continue;
    if (!first) j += ",";
    j += stripJson(strips[i]);
    first = false;
  }
  j += "]}";
  return j;
}

void handleState() {
  if (!guard()) return;
  web.send(200, "application/json", buildStateJson());
}

void handleOnOff() {
  if (!guard()) return;
  String body = web.arg("plain");
  String mac = jsonValue(body, "mac"); mac.toUpperCase();
  String outStr = jsonValue(body, "outlet"), onStr = jsonValue(body, "on");
  if (!mac.length() || !outStr.length() || !onStr.length()) { web.send(400, "application/json", "{\"error\":\"bad request\"}"); return; }
  int outlet = outStr.toInt();
  bool on = onStr == "true" || onStr == "1";
  if (outlet < 0 || outlet > 4) { web.send(400, "application/json", "{\"error\":\"bad outlet\"}"); return; }
  int idx = findStrip(mac);
  if (idx < 0) { web.send(503, "application/json", "{\"error\":\"device offline\"}"); return; }
  bool ok = setOutlets(strips[idx], outlet, on);
  web.send(200, "application/json", String("{\"ok\":") + (ok ? "true" : "false") + ",\"confirmed\":" + (ok ? "true" : "false") + "}");
}

void handleRaw() {
  if (!guard()) return;
  String cmd = web.arg("cmd");
  cmd.trim();
  if (!cmd.startsWith("up:")) { web.send(400, "application/json", "{\"error\":\"cmd must start with up:\"}"); return; }
  int i = firstStrip();
  if (i < 0) { web.send(503, "application/json", "{\"error\":\"no strip connected\"}"); return; }
  Strip& s = strips[i];
  String before = s.lastLine;
  sendLine(s, cmd);
  pumpFor(1500);                                   // collect whatever the strip answers
  String j = "{\"sent\":\"" + cmd + "\",\"last_rx\":\"" + s.lastLine + "\"}";
  web.send(200, "application/json", j);
}

// ---------- names, child lock, provisioning (shared by HTTP and MQTT) ----------
String applyLabel(const String& macIn, int outlet, const String& label) {
  String mac = macIn; mac.toUpperCase();
  int idx = mac.length() ? findStrip(mac) : firstStrip();
  if (idx < 0) return "device offline";
  if (outlet < 0 || outlet > 4) return "bad outlet";
  if (label.length() > 96) return "label too long";
  Strip& s = strips[idx];
  String key = outlet == 0 ? "n" + s.mac : "n" + s.mac + String(outlet);
  if (label.length()) cfg.putString(key.c_str(), label); else cfg.remove(key.c_str());
  if (outlet == 0) s.label = label; else s.olabel[outlet - 1] = label;
  return "";
}

String applyLock(const String& macIn, int outlet, bool locked) {
  String mac = macIn; mac.toUpperCase();
  int idx = mac.length() ? findStrip(mac) : firstStrip();
  if (idx < 0) return "device offline";
  if (outlet < 1 || outlet > 4) return "bad outlet";
  Strip& s = strips[idx];
  uint8_t bit = 1 << (outlet - 1);
  if (locked) {
    s.lockMask |= bit;
    if (s.o[outlet - 1].on) s.lockState |= bit; else s.lockState &= ~bit;   // hold the current state
  } else {
    s.lockMask &= ~bit;
  }
  saveLocks(s);
  return "";
}

void requestProvision() {
  provRequested = true;
  provAt = millis();
  provState = "queued";
  provMsg = "";
}

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
  c.stop();
  Serial.printf("[prov] >> %s  << %s\n", cmd.c_str(), reply.c_str());
  return expect == nullptr || reply.indexOf(expect) >= 0;
}

void connectWiFi();

void provFail(const String& msg) {
  provState = "error";
  provMsg = msg;
  Serial.printf("[prov] error: %s\n", msg.c_str());
}

void runProvision() {
  provRequested = false;
  provState = "running";
  provMsg = "بدوّر على شبكة المشترك";
  String hubIp = WiFi.localIP().toString();
  if (strchr(WIFI_SSID, ':') || strchr(WIFI_PASS, ':')) { provFail("اسم الواي فاي أو الباسورد فيه ':' والمشترك مش بيقبلها"); return; }

  int n = WiFi.scanNetworks();
  String ap;
  int best = -1000;
  for (int i = 0; i < n; i++) {
    String ss = WiFi.SSID(i);
    if ((ss.startsWith("TONLY_TAP_") || ss.startsWith("ONLY_TAP_")) && WiFi.RSSI(i) > best) { ap = ss; best = WiFi.RSSI(i); }
  }
  WiFi.scanDelete();
  if (!ap.length()) { provFail("مش لاقي شبكة TONLY_TAP. دوس على زرار المشترك 10 ثواني لحد ما يرمش بسرعة وجرب تاني"); return; }
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
    r = "مقدرتش أدخل على شبكة " + ap;
  } else {
    delay(500);
    ok = setupCmd("up:ip:" + hubIp, "ip_ok", r) &&
         setupCmd("up:connect:" + String(WIFI_SSID) + ":" + WIFI_PASS, "connect_ok", r);
    if (ok) setupCmd("up:reboot:0", nullptr, r);
    else r = "المشترك رد بـ: " + r;
  }

  WiFi.disconnect();
  delay(300);
  connectWiFi();                                     // back home (static IP again)
  if (ok) {
    provState = "done";
    provMsg = "المشترك اتظبط وهيتصل بالـ Hub خلال ثواني";
    Serial.println("[prov] done");
  } else {
    provFail(r);
  }
}

void handleLabel() {
  if (!guard()) return;
  String b = web.arg("plain");
  String err = applyLabel(jsonValue(b, "mac"), jsonValue(b, "outlet").toInt(), jsonValue(b, "label"));
  web.send(err.length() ? 400 : 200, "application/json", err.length() ? "{\"ok\":false,\"error\":\"" + err + "\"}" : "{\"ok\":true}");
}

void handleLock() {
  if (!guard()) return;
  String b = web.arg("plain");
  String l = jsonValue(b, "locked");
  String err = applyLock(jsonValue(b, "mac"), jsonValue(b, "outlet").toInt(), l == "true" || l == "1");
  web.send(err.length() ? 400 : 200, "application/json", err.length() ? "{\"ok\":false,\"error\":\"" + err + "\"}" : "{\"ok\":true}");
}

void handleProvision() {
  if (!guard()) return;
  if (provState == "running" || provRequested) { web.send(409, "application/json", "{\"ok\":false,\"error\":\"already running\"}"); return; }
  requestProvision();
  web.send(200, "application/json", "{\"ok\":true,\"started\":true}");
}

void handleHealth() {
  int n = 0;
  for (int i = 0; i < MAX_STRIPS; i++) if (strips[i].used && strips[i].identified) n++;
  web.send(200, "application/json", "{\"status\":\"ok\",\"fw\":\"" + String(FW_VERSION) + "\",\"hub\":\"" + hubId +
           "\",\"mqtt\":" + (mqttUp ? "true" : "false") + ",\"strips\":" + String(n) + ",\"uptime_s\":" + String(millis() / 1000) +
           ",\"heap\":" + String(ESP.getFreeHeap()) + ",\"wifi_rssi\":" + String(WiFi.RSSI()) + "}");
}

const char PAGE[] PROGMEM = R"HTML(<!doctype html><html dir=rtl lang=ar><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1"><title>MTTL Hub</title>
<style>body{font-family:system-ui,sans-serif;background:#0f1419;color:#e6e6e6;margin:0;padding:16px}
h1{font-size:20px;margin:0 0 12px}.card{background:#1a2027;border-radius:14px;padding:14px;margin-bottom:14px}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:10px}
button{border:0;border-radius:12px;padding:16px 8px;font-size:16px;background:#2a323b;color:#e6e6e6;cursor:pointer}
button.on{background:#1f9d6b;color:#fff}.all{grid-column:span 2}small{display:block;opacity:.75;margin-top:4px}.muted{opacity:.6}</style>
<h1>&#9889; MTTL Hub</h1><div id=app class=muted>...</div>
<script>
const q=location.search;
async function load(){try{const r=await fetch('/api/state'+q);render(await r.json())}catch(e){app.textContent='No connection to hub'}}
function render(d){if(!d.devices.length){app.innerHTML='<div class=card>No strip connected yet. Strip must be provisioned to '+d.local_ip+'</div>';return}
app.innerHTML=d.devices.map(s=>`<div class=card><b>${s.name}</b> <span class=muted>fw ${s.fw}</span>
<small>${s.power_w} W &middot; ${s.energy_kwh} kWh${s.voltage?' &middot; '+s.voltage+' V':''}${s.rssi!=null?' &middot; '+s.rssi+' dBm':''}</small>
<div class=grid>${s.outlets.map(o=>`<button class="${o.on?'on':''}" onclick="t('${s.mac}',${o.n},${!o.on})">${o.n}<small>${o.on?'ON':'OFF'} &middot; ${o.power_w} W &middot; ${o.temp_c}&deg;C</small></button>`).join('')}
<button class=all onclick="t('${s.mac}',0,${!s.on})">${s.on?'ALL OFF':'ALL ON'}</button></div></div>`).join('')}
async function t(mac,outlet,on){await fetch('/api/onoff'+q,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({mac,outlet,on})});load()}
load();setInterval(load,2000);
</script>)HTML";

void handleRoot() {
  if (!guard()) return;
  web.send_P(200, "text/html; charset=utf-8", PAGE);
}

// ---------- MQTT cloud relay ----------
// esp-mqtt runs in its own task; commands are queued and executed in loop() so strips are only touched from one task.
char mqttClientId[32];
uint32_t lastStatePub = 0;
String lastRelaySig;
const uint32_t STATE_EVERY_MS = 15000;          // heartbeat publish; relay changes publish immediately

static void mqttEvent(void*, esp_event_base_t, int32_t id, void* data) {
  esp_mqtt_event_handle_t e = (esp_mqtt_event_handle_t)data;
  switch ((esp_mqtt_event_id_t)id) {
    case MQTT_EVENT_CONNECTED:
      mqttUp = true;
      mqttFreshConnect = true;
      esp_mqtt_client_subscribe(mqtt, tCmd.c_str(), 1);
      break;
    case MQTT_EVENT_DISCONNECTED:
      mqttUp = false;
      break;
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
  tStatus = base + "status"; tInfo = base + "info"; tState = base + "state"; tCmd = base + "cmd"; tAck = base + "cmd/ack";
  snprintf(mqttClientId, sizeof mqttClientId, "hub-%s", id);
  mqttQ = xQueueCreate(8, sizeof(MqttCmd));

  esp_mqtt_client_config_t cfg = {};
#if ESP_IDF_VERSION_MAJOR >= 5
  cfg.broker.address.uri = MQTT_URI;
  cfg.broker.verification.certificate = MQTT_CA;
  cfg.credentials.username = MQTT_USER;
  cfg.credentials.client_id = mqttClientId;
  cfg.credentials.authentication.password = MQTT_PASS;
  cfg.session.last_will.topic = tStatus.c_str();
  cfg.session.last_will.msg = "offline";
  cfg.session.last_will.qos = 1;
  cfg.session.last_will.retain = 1;
  cfg.session.keepalive = 30;
  cfg.network.reconnect_timeout_ms = 5000;
  cfg.buffer.size = 4096;
  cfg.buffer.out_size = 4096;
#else
  cfg.uri = MQTT_URI;
  cfg.cert_pem = MQTT_CA;
  cfg.username = MQTT_USER;
  cfg.client_id = mqttClientId;
  cfg.password = MQTT_PASS;
  cfg.lwt_topic = tStatus.c_str();
  cfg.lwt_msg = "offline";
  cfg.lwt_qos = 1;
  cfg.lwt_retain = 1;
  cfg.keepalive = 30;
  cfg.reconnect_timeout_ms = 5000;
  cfg.buffer_size = 4096;
  cfg.out_buffer_size = 4096;
#endif
  mqtt = esp_mqtt_client_init(&cfg);
  esp_mqtt_client_register_event(mqtt, MQTT_EVENT_ANY, mqttEvent, nullptr);
  esp_mqtt_client_start(mqtt);
  Serial.printf("MQTT    : %s  hub=%s\n", MQTT_URI, id);
  Serial.printf("Topics  : mttl/%s/{status,info,state,cmd,cmd/ack}\n", id);
}

void mqttPub(const String& topic, const String& payload, int qos, bool retain) {
  if (!mqtt || !mqttUp) return;
  esp_mqtt_client_enqueue(mqtt, topic.c_str(), payload.c_str(), payload.length(), qos, retain ? 1 : 0, true);
}

String relaySignature() {
  String sig;
  for (int i = 0; i < MAX_STRIPS; i++) {
    const Strip& s = strips[i];
    if (!s.used || !s.identified) continue;
    sig += s.mac;
    for (int k = 0; k < 4; k++) sig += s.o[k].on ? '1' : '0';
  }
  return sig;
}

void publishState() {
  mqttPub(tState, buildStateJson(), 0, true);
  lastStatePub = millis();
  lastRelaySig = relaySignature();
}

String cleanId(String v) {
  v.replace("\"", ""); v.replace("\\", "");
  if (v.length() > 40) v = v.substring(0, 40);
  return v;
}

void mqttProcess() {
  if (!mqttQ) return;
  if (mqttFreshConnect) {
    mqttFreshConnect = false;
    Serial.println("[mqtt] connected");
    mqttPub(tStatus, "online", 1, true);
    mqttPub(tInfo, "{\"hub\":\"" + hubId + "\",\"fw\":\"" + FW_VERSION + "\",\"ip\":\"" + WiFi.localIP().toString() +
            "\",\"web_port\":" + String(WEB_PORT) + "}", 1, true);
    publishState();
  }
  MqttCmd c;
  while (xQueueReceive(mqttQ, &c, 0) == pdTRUE) {
    String body = c.payload;
    Serial.printf("[mqtt] cmd %s\n", c.payload);
    String id = cleanId(jsonValue(body, "id"));
    String action = jsonValue(body, "action");
    bool ok = false;
    String err;
    if (action == "refresh") {
      for (int i = 0; i < MAX_STRIPS; i++) {
        Strip& s = strips[i];
        if (!s.used || !s.identified) continue;
        uint32_t seq = s.infoSeq;
        sendLine(s, "up:getinfo:all");
        waitForInfo(s, seq, 2000);
      }
      ok = true;
    } else if (action == "label") {
      err = applyLabel(jsonValue(body, "mac"), jsonValue(body, "outlet").toInt(), jsonValue(body, "label"));
      ok = !err.length();
    } else if (action == "lock") {
      String l = jsonValue(body, "locked");
      err = applyLock(jsonValue(body, "mac"), jsonValue(body, "outlet").toInt(), l == "true" || l == "1");
      ok = !err.length();
    } else if (action == "provision") {
      if (provState == "running" || provRequested) err = "already running";
      else { requestProvision(); provAt = millis() + 1200; ok = true; }   // give the ack time to leave first
    } else {
      String mac = jsonValue(body, "mac"); mac.toUpperCase();
      String outStr = jsonValue(body, "outlet"), onStr = jsonValue(body, "on");
      int idx = mac.length() ? findStrip(mac) : firstStrip();
      int outlet = outStr.toInt();
      if (!outStr.length() || !onStr.length()) err = "bad request";
      else if (outlet < 0 || outlet > 4) err = "bad outlet";
      else if (idx < 0) err = "device offline";
      else {
        ok = setOutlets(strips[idx], outlet, onStr == "true" || onStr == "1");
        if (!ok) err = "not confirmed";
      }
    }
    mqttPub(tAck, "{\"id\":\"" + id + "\",\"ok\":" + (ok ? "true" : "false") + ",\"error\":\"" + err + "\"}", 1, false);
    publishState();
  }
  static String lastProv;
  if (mqttUp && (relaySignature() != lastRelaySig || provState != lastProv || millis() - lastStatePub > STATE_EVERY_MS)) {
    lastProv = provState;
    publishState();
  }
}

// ---------- WiFi ----------
void connectWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.setHostname(HOSTNAME);
#if USE_STATIC_IP
  WiFi.config(LOCAL_IP, GATEWAY, SUBNET, DNS1);
#endif
  WiFi.setSleep(false);                     // keep the radio awake so strips/API respond instantly
  WiFi.setAutoReconnect(true);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  Serial.printf("Connecting to %s", WIFI_SSID);
  uint32_t t0 = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - t0 < 20000) { delay(500); Serial.print("."); }
  if (WiFi.status() != WL_CONNECTED) { Serial.println("\nWiFi failed, rebooting in 10s"); delay(10000); ESP.restart(); }
  Serial.printf("\nWiFi OK  IP=%s  RSSI=%d\n", WiFi.localIP().toString().c_str(), WiFi.RSSI());
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\n=== MTTL Hub v1.1 ===");
  cfg.begin("mttl", false);
  connectWiFi();

  stripServer.begin();
  stripServer.setNoDelay(true);

  const char* hk[] = {"X-Token"};
  web.collectHeaders(hk, 1);
  web.on("/", HTTP_GET, handleRoot);
  web.on("/index.html", HTTP_GET, handleRoot);
  web.on("/api/state", HTTP_GET, handleState);
  web.on("/api/onoff", HTTP_POST, handleOnOff);
  web.on("/api/health", HTTP_GET, handleHealth);
  web.on("/api/raw", HTTP_GET, handleRaw);
  web.on("/api/label", HTTP_POST, handleLabel);
  web.on("/api/lock", HTTP_POST, handleLock);
  web.on("/api/provision", HTTP_POST, handleProvision);
  web.onNotFound([]() { web.send(404, "application/json", "{\"error\":\"not found\"}"); });
  web.begin();

  ArduinoOTA.setHostname(HOSTNAME);
  ArduinoOTA.setPassword(OTA_PASS);
  ArduinoOTA.begin();                       // also starts mDNS
  MDNS.addService("http", "tcp", WEB_PORT);

  Serial.printf("Web UI  : http://%s:%u   (or http://%s.local:%u)\n", WiFi.localIP().toString().c_str(), WEB_PORT, HOSTNAME, WEB_PORT);
  Serial.printf("Strips  : TCP %u\n", STRIP_PORT);
  Serial.printf("Auth    : %s\n", strlen(API_TOKEN) ? "token" : "NONE (LAN only)");
  mqttStart();
}

uint32_t wifiLostAt = 0;

void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    uint32_t& lost = wifiLostAt;
    if (!lost) lost = millis();
    if (millis() - lost > 60000) ESP.restart();
    delay(100);
    return;
  }
  wifiLostAt = 0;
  ArduinoOTA.handle();
  web.handleClient();
  pumpStrips();
  pollStrips();
  serialRaw();
  mqttProcess();
  if (provRequested && (int32_t)(millis() - provAt) > 400) runProvision();
  delay(2);
}
