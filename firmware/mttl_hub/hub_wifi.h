// Fisha hub: Wi-Fi, setup portal, setup() and loop(). Part of mttl_hub.ino, included in order from there.
// ---------- WiFi / setup / loop ----------
void saveWifi(const String& ssid, const String& pass);

bool tryWiFi(const String& ssid, const String& pass, uint32_t ms) {
  // Wi-Fi settings stay in RAM (the hub keeps its own copy in "sec"); with NVS full, writing them failed
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
  // the Fisha app sets the hub up from here in one step (Wi-Fi, address, owner, update password) so the
  // customer never leaves the app. GET /api/setup/info -> hub id and state; POST /api/setup {ssid,pass,ip,email,model,ota,key}
  portal.on("/api/setup/info", HTTP_GET, [&]() {
    portal.send(200, "application/json", "{\"ok\":true,\"data\":{\"hub\":\"" + defOta().substring(6) + "\",\"fw\":\"" + String(FW_VERSION) +
                "\",\"claimed\":" + (ownerCount ? "true" : "false") + ",\"claim_open\":" + (millis() < CLAIM_WINDOW_MS ? "true" : "false") +
                ",\"ip\":\"" + secLocalIp.toString() + "\",\"gw\":\"" + GATEWAY.toString() + "\"}}");
  });
  portal.on("/api/setup", HTTP_POST, [&]() {
    auto bad = [&](int code, const char* e) { portal.send(code, "application/json", String("{\"ok\":false,\"error\":\"") + e + "\"}"); };
    String b = portal.arg("plain");
    String ns = jsonValue(b, "ssid"), np = jsonValue(b, "pass"), ipS = jsonValue(b, "ip"), ota = jsonValue(b, "ota");
    String email = cleanEmail(jsonValue(b, "email"));
    ns.trim(); ipS.trim();
    if (!ns.length() || ns.length() > 32 || np.length() > 63 || ns.indexOf(':') >= 0 || np.indexOf(':') >= 0) return bad(400, "wifi");
    if (np.length() && np.length() < 8) return bad(400, "wifi_pass");
    IPAddress ip = secLocalIp;
    if (ipS.length() && !(ip.fromString(ipS) && ip[0] == GATEWAY[0] && ip[1] == GATEWAY[1] && ip[2] == GATEWAY[2] && ip[3] > 1 && ip[3] < 255 && ip != GATEWAY)) return bad(400, "ip");
    if (ota.length() && (ota.length() < 8 || ota.length() > 40)) return bad(400, "ota");
    String key;
    if (!ownerCount) {                           // first owner: no password, but only soon after the hub was powered
      if (millis() >= CLAIM_WINDOW_MS) return bad(403, "claim_window");
      if (!email.length()) return bad(400, "email");
      key = addOwner(email, cleanModel(jsonValue(b, "model")));
      addEvent("owner", "", 0, email);
    } else {                                     // already has an owner: their phone key or the update password
      String k = jsonValue(b, "key"), c = jsonValue(b, "cur");
      if (!isOwnerKey(k) && c != defOta() && c != secOta) return bad(401, "owner");
    }
    saveWifi(ns, np);
    Preferences sp; sp.begin("sec", false);
    sp.putString("lip", ip.toString());
    if (ota.length() && ota != defOta()) { sp.putString("ota", ota); secOta = ota; }
    sp.end();
    portal.send(200, "application/json", "{\"ok\":true,\"data\":{\"key\":\"" + key + "\",\"hub\":\"" + defOta().substring(6) + "\",\"ip\":\"" + ip.toString() + "\"}}");
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
  if (!secSsid.length()) setupPortal();          // a new (or erased) hub goes straight to setup
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
  String had[MAX_STRIPS];                        // strips online before the change get the new network handed over
  int hadN = 0;
  for (int i = 0; i < MAX_STRIPS; i++) if (strips[i].used && strips[i].mac.length()) had[hadN++] = strips[i].mac;
  for (int i = 0; i < MAX_STRIPS; i++) if (strips[i].used) dropStrip(strips[i], "wifi change");
  WiFi.disconnect();
  delay(300);
  if (tryWiFi(wifiTestSsid, wifiTestPass, 20000)) {
    if (hadN) {
      // the new network works. Go back, wait for the strips to re-dial, hand each one the new network on its
      // normal link (up:connect, then up:reboot:0 once it answers connect_ok, as in "Add strip"), then move for good.
      // A strip that misses it stays on the old network; holding its button 10 s lets autoResyncScan() relink it.
      wifiTestState = "moving";
      WiFi.disconnect();
      delay(300);
      connectWiFi();
      uint32_t t0 = millis();
      uint32_t keepAt[MAX_STRIPS] = {0};
      auto pump = [&](uint32_t ms) {
        uint32_t ts = millis();
        while (millis() - ts < ms) {
          esp_task_wdt_reset();
          pumpStrips();
          uint32_t n = millis();
          // a strip silent for 8 s is asked for its state, so its link is not dropped as stale (45 s) while the others are slow
          for (int i = 0; i < MAX_STRIPS; i++) {
            Strip& s = strips[i];
            if (s.used && s.identified && n - s.lastRx > 8000 && n - keepAt[i] > 8000) { keepAt[i] = n; sendLine(s, "up:getinfo:all"); }
          }
          delay(10);
        }
      };
      while (millis() - t0 < 60000) {
        int back = 0;
        for (int h = 0; h < hadN; h++) if (findStrip(had[h]) >= 0) back++;
        if (back == hadN) break;
        pump(500);
      }
      pump(1500);
      wifiOkMacs = "";
      uint32_t lastSend[MAX_STRIPS] = {0}, okAt[MAX_STRIPS] = {0};
      uint8_t sends[MAX_STRIPS] = {0};
      t0 = millis();
      for (int h = 0; h < hadN; h++) {
        int k = findStrip(had[h]);
        if (k < 0) continue;
        if (sendWifiTo(strips[k], wifiTestSsid, wifiTestPass)) { lastSend[h] = millis(); sends[h] = 1; }
      }
      // up to 40 s for every strip to answer connect_ok (a strip that is still re-dialling gets the network as soon as it
      // is back; one that has not answered gets it again every 12 s, up to 3 times). It ends at once when all answered.
      while (millis() - t0 < 40000) {
        bool all = true;
        uint32_t n = millis();
        for (int h = 0; h < hadN; h++) {
          if (wifiOkMacs.indexOf(had[h]) >= 0) { if (!okAt[h]) okAt[h] = n - t0 + 1; continue; }
          all = false;
          int k = findStrip(had[h]);
          if (k < 0) continue;                   // not back yet: keep waiting
          // nothing new is started in the last 10 s: a strip would have no time left to answer before the revert decision
          if (n - t0 < 30000 && (!sends[h] || (sends[h] < 3 && n - lastSend[h] > 12000))) {
            if (sendWifiTo(strips[k], wifiTestSsid, wifiTestPass)) { lastSend[h] = n; sends[h]++; }
          }
        }
        if (all) break;
        pump(300);
      }
      // move only if EVERY strip took the new network. A strip that answered while another did not would be
      // stranded on the wrong network (all offline), so in that case the old network is handed back to the ones that answered.
      int missed = 0;
      wifiMoveInfo = "";
      for (int h = 0; h < hadN; h++) {
        int k = findStrip(had[h]);
        bool ok = wifiOkMacs.indexOf(had[h]) >= 0;
        if (wifiMoveInfo.length() < 420) {
          wifiMoveInfo += had[h].substring(6) + ":";
          if (ok) wifiMoveInfo += "ok " + String((okAt[h] ? okAt[h] - 1 : 0) / 1000.0f, 1) + "s";
          else if (k < 0) wifiMoveInfo += "missed offline";
          else wifiMoveInfo += "missed no_reply rssi=" + String(strips[k].hasRssi ? strips[k].rssi : 0) + " fw=" + strips[k].fw;
          wifiMoveInfo += " sends=" + String(sends[h]) + "; ";
        }
        if (!ok) { missed++; addEvent("wifipush", had[h], 0, "missed"); }
      }
      if (missed) {
        String oldS = secSsid, oldP = secWifi;
        // every strip that was sent the new network gets the old one back (also one whose answer was lost or came late);
        // a strip that never left the old network just keeps it. Done twice to catch a strip that re-dials meanwhile.
        for (int pass = 0; pass < 2; pass++) {
          for (int h = 0; h < hadN; h++) { int k = findStrip(had[h]); if (k >= 0 && sends[h]) sendWifiTo(strips[k], oldS, oldP); }
          pump(pass ? 500 : 2500);
        }
        wifiTestState = "failed";
        wifiTestMsg = "strips:" + String(missed);
        wifiTestPass = "";
        stateDirty = true;
        Serial.printf("[wifi] %d strip(s) did not take the new network; staying on %s\n", missed, oldS.c_str());
        return;
      }
      for (int h = 0; h < hadN; h++) { int k = findStrip(had[h]); if (k >= 0) sendLine(strips[k], "up:reboot:0"); }
      pump(1500);
      for (int i = 0; i < MAX_STRIPS; i++) if (strips[i].used) dropStrip(strips[i], "wifi change");
      WiFi.disconnect();
      delay(300);
      saveWifi(wifiTestSsid, wifiTestPass);
      if (!tryWiFi(wifiTestSsid, wifiTestPass, 20000)) Serial.println("[wifi] rejoin of the new network slow; loop keeps retrying");
    }
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
  secOta = pickSecret(sp, "ota", OTA_PASS, "");
  secMqttUri = sp.getString("muri", "");
  secMqttUser = sp.getString("muser", MQTT_USER);
  secLocalIp = LOCAL_IP;
  String lip = sp.getString("lip", "");
  if (lip.length() && secLocalIp.fromString(lip)) { lipCheckAt = millis() + 60000; if (!lipCheckAt) lipCheckAt = 1; }
  if (!secOta.length()) secOta = defOta();   // fixed fallback fisha-<MAC>, never random
  sp.end();
}

void setup() {
  Serial.begin(115200);
  heap_caps_register_failed_alloc_callback(allocFailCb);   // diagnostics, see allocFailCb
  // armed first thing (it used to be armed only at the end of setup, so a hang while booting
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
  fsOk = LittleFS.begin(true);                   // formats the unused SPIFFS partition on first boot
  esp_task_wdt_reset();
  Serial.printf("[fs] %s\n", fsOk ? "LittleFS ok" : "LittleFS FAILED, history stays in NVS");
  loadGlobals();
  linkLoad();
  loadKnown();
  loadTimers();
  nvsId = cfg.getString("nvsid", "");
  if (!nvsId.length()) { nvsId = randText(8); cfg.putString("nvsid", nvsId); }
  if (cfg.getUChar("nver", 0) < 2) {             // every event, every outlet by default
    notifyTypes = 0xFFFFFFFF;
    cfg.putUInt("ntypes", notifyTypes);
    for (int i = 0; i < knownCount; i++) { cfg.remove(("m" + known[i].mac).c_str()); refreshKnown(known[i].mac); }
    cfg.putUChar("nver", 2);
  }
  for (int i = 0; i < MAX_STRIPS; i++) { elogs[i] = ElogHead(); peaks[i] = PeakHead(); }
  WiFi.onEvent([](WiFiEvent_t, WiFiEventInfo_t info) {
                 provDiscReason = info.wifi_sta_disconnected.reason; provStaEvents++;
                 if (!provRequested && provState != "running") { wifiLastReason = info.wifi_sta_disconnected.reason; wifiDiscCount++; wifiDiscAt = millis(); }
               },
               ARDUINO_EVENT_WIFI_STA_DISCONNECTED);
  WiFi.onEvent([](WiFiEvent_t, WiFiEventInfo_t) { provStaEvents++; }, ARDUINO_EVENT_WIFI_STA_CONNECTED);
  { Preferences p; p.begin("stripfw", true); stripFwSize = p.getUInt("size", 0); p.end(); }
  if (stripFwSize) { stripFwOk = stripFwCheck(stripFwSize, stripFwWhy); if (!stripFwOk) Serial.printf("[strip-ota] stored file refused: %s\n", stripFwWhy.c_str()); }
  connectWiFi();
  applyHubTimezone();

  const char* hk[] = {"X-Token", "X-User"};
  web.collectHeaders(hk, 2);
  web.on("/", HTTP_GET, handleRoot);
  web.on("/api/state", HTTP_GET, handleState);
  web.on("/api/health", HTTP_GET, handleHealth);
  web.on("/api/raw", HTTP_GET, handleRaw);
  web.on("/api/heapdiag", HTTP_GET, handleHeapDiag);
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
  web.on("/api/stripfw/chunk", HTTP_POST, handleSuChunk);
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
  // a frozen loop reboots the hub after 90 s instead of hanging forever (armed at the top of setup since
  esp_task_wdt_reset();
  Serial.printf("[hub] last reset: %s\n", resetText().c_str());
}

uint32_t wifiLostAt = 0;

// times each loop step; one that blocks 5 s or more is logged as a "stall" event once it returns
const char* stgName = "boot";
uint32_t stgAt = 0;
void stg(const char* next) {
  uint32_t now = millis(), d = now - stgAt;
  const char* was = stgName;
  stgName = next; stgAt = now;
  if (d > stallMaxMs) { stallMaxMs = d; stallWhere = was; }
  uint32_t sm = subMax; const char* sw = subWhere;
  subMax = 0; subWhere = "";
  // time the hub itself stood still is not the strip's fault: a send that was waiting restarts its
  // "stuck" clock, so one slow step no longer drops every strip at once
  if (d >= 1000) for (int i = 0; i < MAX_STRIPS; i++) if (strips[i].used && strips[i].txSince) strips[i].txSince = now;
  if (d >= 5000 && strcmp(was, "boot") && strcmp(was, "wifi_down") && strcmp(was, "provision"))
    addEvent("stall", "", 0, String(was) + " · " + String(d / 1000) + " s" +
                             (sm >= 200 ? " · " + String(sw) + " " + String(sm) + " ms" : String(" · other")) +
                             (!strcmp(was, "web") ? " · " + (webUri.length() ? webUri : String("reading request")) : String("")));
  subMax = 0; subWhere = "";
}

// ---------- re-link known strips after a Wi-Fi/router change, with no "Add strip" tap needed ----------
// A strip keeps its own Wi-Fi credentials; when the router's name or password changes, the strip can't reconnect
// and used to just sit offline until the user ran "Add strip" on it again by hand. Stock firmware keeps retrying
// the old network ("auto reconnect" in its strings) and opens its setup network (TONLY_TAP_<id>) only after the
// button is held ~10 s; no automatic fallback was found. So the hub keeps scanning for that network from any strip
// it already knows and, once it sees one, re-provisions it with the current Wi-Fi automatically - the same flow
// "Add strip" uses, just started by the hub instead of a tap in the app.
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
  // every home Wi-Fi loss goes to the event log with its reason code and how long it lasted,
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
  if (lastSuChunkAt && (uint32_t)(millis() - lastSuChunkAt) < 4000) {
    mqttMemTick();                                // update mode starts here too, not only after the upload
    esp_task_wdt_reset();
    delay(1);
    return;
  }
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
  mqttMemTick();
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
