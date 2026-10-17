// Fisha hub: provisioning of strips in setup mode. Part of mttl_hub.ino, included in order from there.
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
    // the strip may send its answer slowly and without a newline: stop on a complete ..._ok / fail
    if (reply.endsWith("_ok") || reply.indexOf("fail") >= 0) { delay(150); while (c.available()) { char ch = c.read(); if (ch != '\r' && ch != '\n' && ch != 0) reply += ch; } return true; }
    if (!c.connected()) return reply.length() > 0;
    esp_task_wdt_reset();
    delay(10);
  }
  return reply.length() > 0;
}

// Same as FG Link / mttl_local.py and hub which provisioned strips successfully:
// ONE TCP session -> up:ip, up:connect, up:reboot:0
// the home router and the strip's setup AP are BOTH 192.168.1.1. After switching networks the ARP cache
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

// link diagnostics on the strip's setup network (does the strip answer ARP for .1 at all?)
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
  // the setup service is on the strip AP's gateway (192.168.1.1 on older firmware); try the gateway
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

// flash a strip in setup mode. Same TCP 30300 service as provisioning: "up:ota:<our ip>" makes the strip
// (fw 1.0.141 too, seen in Wireshark) fetch http://<our ip>:80/ota.bin, which the hub answers from the spare OTA slot.
const esp_partition_t* stripFwPart() { return esp_ota_get_next_update_partition(nullptr); }

void otaLog(const String& m) { Serial.println("[strip-ota] " + m); stripOtaLog += m + "\n"; }

// srv must already be listening before "up:ota" goes out: the strip dials :80 about 0.1 s after ota_ok,
// and a reset on that first SYN makes it give up opened the port only afterwards).
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
  // no auto-reconnect to the home Wi-Fi meanwhile, pin the strip's channel + BSSID, two tries,
  // and report why the join failed (wrong password vs AP gone) instead of a bare join_failed
  WiFi.setAutoReconnect(false);
  // Arduino-ESP32 3.x refuses APs weaker than WPA2-PSK by default (2.x accepted anything). The strip's
  // setup AP is older WPA, so the join silently never happened (join_failed, no disconnect reason). Allow it here.
  WiFi.setMinSecurity(WIFI_AUTH_OPEN);
  // the loop below used to start with "status != CONNECTED" while the hub was still on the home Wi-Fi, so it
  // never ran and the hub "joined" YAYA (BSSID = router). Now: leave home first, forget the stored home AP, and only
  // count the join when the BSSID we are on is the strip's.
  bool onStrip = false;
  for (int attempt = 0; attempt < 3 && !onStrip; attempt++) {
    WiFi.disconnect(false, true);                    // leave + erase the stored (home) AP config
    for (int i = 0; i < 20 && WiFi.status() == WL_CONNECTED; i++) delay(100);
    // join through ESP-IDF directly, like a laptop does: any security, no PMF, full scan, no BSSID pin,
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
    // the strip is also recognised by its BSSID (its MAC): rec.ssid came back empty although the hub was on it
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

