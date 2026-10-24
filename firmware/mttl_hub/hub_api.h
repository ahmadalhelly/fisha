// Fisha hub: API shared by HTTP and MQTT. Part of mttl_hub.ino, included in order from there.
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
      if (path == "lock" && outlet == 0) {         // strip-level child lock: blocks the strip's physical master button
        s.masterLock = jsonBool(b, "locked");
        cfg.putUChar(("ml" + s.mac).c_str(), s.masterLock ? 1 : 0);
        sendChildLock(s);
        refreshKnown(s.mac);
        stateDirty = true;
        return okRes();
      }
      if (outlet < 1 || outlet > 4) return errRes("bad outlet");
      uint8_t bit = 1 << (outlet - 1);
      if (path == "lock") {
        if (jsonBool(b, "locked")) {
          s.lockMask |= bit;
          if (s.o[outlet - 1].on) s.lockState |= bit; else s.lockState &= ~bit;
        } else s.lockMask &= ~bit;
        saveLocks(s);
        sendChildLock(s);
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
  // ---- cloud password + shared users (owner only) ----
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
    u.rsv = (uint8_t)(jsonValue(b, "perms").toInt() & 0x3F);
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
    if (jsonHas(b, "perms")) u.rsv = (uint8_t)(jsonValue(b, "perms").toInt() & 0x3F);
    if (jsonHas(b, "strips")) parseStrips(u, jsonValue(b, "strips"));
    if (!u.all && !u.n) return errRes("pick at least one strip");
    users[i] = u;
    saveUsers();
    publishUserState(u);
    clearUserStrips(u, false);                   // strips taken away can no longer be read
    pubMarksReset();                             // and strips given are sent
    return okRes();
  }
  if (path == "users_export") {                   // family members with their passwords, for the owner's backup
    if (apiSrc == 2) return errRes("forbidden");
    String j = "{\"users\":[";
    for (int i = 0; i < userCount; i++) {
      if (i) j += ",";
      String uj = userJson(users[i]);
      j += uj.substring(0, uj.length() - 1) + ",\"pw\":\"" + jsonEsc(String(users[i].pw)) + "\"}";
    }
    return okRes(j + "]}");
  }
  if (path == "user_restore") {                   // {"id","name","role","all","strips","pw"} puts a backed-up member back
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
    u.rsv = (uint8_t)(jsonValue(b, "perms").toInt() & 0x3F);
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
    clearUserStrips(u, false);
    pubMarksReset();
    stateDirty = true;
    return okRes();
  }
  if (path == "user_revoke") {                    // {"id"} local network only
    if (apiSrc != 0) return errRes("local_only");
    int i = findUser(jsonValue(b, "id"));
    if (i < 0) return errRes("no such user");
    if (!emqxReady()) {                           // nothing on the server to remove
      mqttPub("mttl/" + hubId + "/u/" + String(users[i].id) + "/state", "", 1, true);
      clearUserStrips(users[i], true);
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
  if (path == "pair_answer") {                    // {"id","pick","role"}: role -1 refuses; a wrong pick refuses too
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
    // the phone gets in at once waited for the server login and answered "busy" when that worker
    // was taken); its server login for use away from home is made right after, in the background
    String pw = randText(18);
    strlcpy(u.pw, pw.c_str(), sizeof u.pw);
    if (emqxReady()) { cloudTodoId = u.id; cloudTodoPw = pw; cloudTodoAt = 0; }
    users[userCount++] = u;
    saveUsers();
    profSet(u.id, 'e', p.email);                  // the family page shows each member's email
    publishUserState(u);
    pubMarksReset();
    p.result = "\"code\":\"" + inviteCode(u, pw) + "\"";
    p.state = 2; p.at = millis();
    return okRes();
  }
  if (path == "owner_remove") {                   // {"email"}: takes an owner phone off; with none left the hub is open again
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

  if (path == "ota_pass") {                       // {"cur","new"}: owner only. cur = fisha-<MAC> or the current own password; new "" = back to the default
    if (apiSrc == 2) return errRes("forbidden");
    String cur = jsonValue(b, "cur"), nw = jsonValue(b, "new");
    String d = defOta();
    if (cur != d && cur != secOta) return errRes("wrong current password");
    if (nw.length() && (nw.length() < 8 || nw.length() > 40)) return errRes("new password must be 8-40 characters");
    Preferences sp;
    sp.begin("sec", false);
    if (nw.length() && nw != d) { sp.putString("ota", nw); secOta = nw; }
    else { sp.remove("ota"); sp.remove("cota"); secOta = d; }
    sp.end();
    ArduinoOTA.setPassword(secOta.c_str());
    addEvent("owner", "", 0, "update password changed");
    return okRes();
  }
  if (path == "strip_wifi_test") {                // {"mac"}: hand the CURRENT network to one strip on its normal link
    String m = jsonValue(b, "mac"); m.toUpperCase();   // (safe: it rejoins the same Wi-Fi); a connect_ok reply proves handover works
    int k = findStrip(m);
    if (k < 0) return errRes("strip not connected");
    sendWifiTo(strips[k], secSsid, secWifi);
    addEvent("wifipush", strips[k].mac, 0, "test sent");
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
    if (idx >= 0 && stripFwNum(strips[idx].fw) >= 90) strips[idx].cfgSyncStep = 1;   // tz, time, limits, then the schedule
    return okRes("{\"sid\":" + String(c.id) + "}");
  }
  if (path == "schedule_skip") {                 // {"sid","skip":true|false} skip only the next run
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
      String delMac = String(scheds[i].mac);
      for (int j = i; j < schedCount - 1; j++) scheds[j] = scheds[j + 1];
      schedCount--;
      saveScheds();
      int sIdx = findStrip(delMac);
      if (sIdx >= 0 && stripFwNum(strips[sIdx].fw) >= 90) strips[sIdx].cfgSyncStep = 1;
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
    r.metric = constrain(jsonValue(b, "metric").toInt(), 0, 4);
    if (r.metric == 4) r.outlet = 0;              // voltage is the whole strip's
    r.limit2 = jsonHas(b, "limit2") ? jsonValue(b, "limit2").toFloat() : 70;
    if (r.metric == 2) r.above = 1;
    if (r.metric != 2) r.above = jsonBool(b, "above");
    r.watts = jsonValue(b, "watts").toFloat();
    // keep thresholds in range: W 0..3500 · °C 0..120 · A 0..16
    r.watts = r.metric == 1 ? constrain(r.watts, 0.0f, 120.0f) : r.metric == 3 ? constrain(r.watts, 0.0f, 16.0f) : r.metric == 4 ? constrain(r.watts, 100.0f, 280.0f) : constrain(r.watts, 0.0f, 3680.0f);
    r.limit2 = constrain(r.limit2, 30.0f, 120.0f);
    r.holdS = constrain(jsonValue(b, "hold_s").toInt(), 5, 65535);
    r.act = constrain(jsonValue(b, "act").toInt(), 1, 3);
    r.enabled = jsonHas(b, "enabled") ? jsonBool(b, "enabled") : 1;
    strlcpy(r.label, jsonValue(b, "label").c_str(), sizeof r.label);
    autoArmed[slot] = true;
    autoWarned[slot] = false;
    autoSince[slot] = 0;
    autoFiredAt[slot] = 0;
    autoSaid[slot] = false;
    saveAutos();
    for (int i = 0; i < MAX_STRIPS; i++) {
      if (strips[i].used && strips[i].identified && stripFwNum(strips[i].fw) >= 90) strips[i].cfgSyncStep = 3;
    }
    return okRes("{\"aid\":" + String(r.id) + "}");
  }
  if (path == "automation_delete") {
    uint32_t id = (uint32_t)jsonValue(b, "aid").toInt();
    for (int i = 0; i < autoCount; i++) {
      if (autos[i].id != id) continue;
      for (int j = i; j < autoCount - 1; j++) { autos[j] = autos[j + 1]; autoArmed[j] = autoArmed[j + 1]; autoSince[j] = autoSince[j + 1]; autoFiredAt[j] = autoFiredAt[j + 1]; autoSaid[j] = autoSaid[j + 1]; }
      autoCount--;
      saveAutos();
      for (int k = 0; k < MAX_STRIPS; k++) {
        if (strips[k].used && strips[k].identified && stripFwNum(strips[k].fw) >= 90) strips[k].cfgSyncStep = 3;
      }
      return okRes();
    }
    return errRes("no such automation");
  }
  if (path == "events") return okRes(eventsJson());
  if (path == "link") {                            // link history of one strip (?mac= or "mac" in the body)
    String m = mac; m.toUpperCase();
    if (m.length() != 12) return errRes("mac required");
    return okRes(linkJson(m));
  }
  if (path == "energy") {
    int idx = stripFor(mac);
    if (idx < 0) return errRes("device offline");
    String ej = energyJson(idx);
    if (!ej.length()) return errRes("busy, try again");
    return okRes(ej);
  }
  if (path == "energy_restore") {                // owner only {"mac","d":"yyyymmdd:w0:w1:w2:w3:peak;..."}: put saved daily history back
    if (apiSrc == 2) return errRes("forbidden");
    int idx = stripFor(mac);
    if (idx < 0) return errRes("device offline");
    if (!histHeads(idx)) return errRes("busy, try again");
    if (!elogs[idx].day) return errRes("clock not set");
    ELog* elp = elogGet(idx);
    PeakLog* plp = elp ? peakGet(idx) : nullptr;
    if (!plp) { delete elp; return errRes("busy, try again"); }
    ELog& el = *elp;
    PeakLog& pl = *plp;
    String d = jsonValue(b, "d");
    int put = 0, pos = 0;
    while (pos < (int)d.length()) {
      int e = d.indexOf(';', pos);
      if (e < 0) e = d.length();
      String row = d.substring(pos, e);
      pos = e + 1;
      uint32_t f[6] = {0, 0, 0, 0, 0, 0};
      int n = 0, q = 0;
      while (n < 6 && q <= (int)row.length()) {
        int c = row.indexOf(':', q);
        if (c < 0) c = row.length();
        f[n++] = (uint32_t)strtoul(row.substring(q, c).c_str(), nullptr, 10);
        q = c + 1;
      }
      if (n < 6) continue;
      int y = f[0] / 10000, m = (f[0] / 100) % 100, dd = f[0] % 100;
      if (y < 2020 || m < 1 || m > 12 || dd < 1 || dd > 31) continue;
      int32_t z = daysFromCivil(y, m, dd);
      if (z >= el.day || z <= el.day - ELOG_DAYS) continue;      // past days inside the window only
      int ix = ((z % ELOG_DAYS) + ELOG_DAYS) % ELOG_DAYS;
      if (el.dayOf[ix] == z) continue;                           // never overwrite what the hub already has
      for (int k = 0; k < 4; k++) el.wh[ix][k] = f[1 + k] > 100000000UL ? 0 : f[1 + k];
      el.dayOf[ix] = z;
      pl.pk[ix] = f[5] > 65535 ? 0 : (uint16_t)f[5];
      pl.dayOf[ix] = z;
      put++;
    }
    if (put) { elogPut(idx, elp); peakPut(idx, plp); } else { delete elp; delete plp; }
    return okRes("{\"restored\":" + String(put) + "}");
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
    if (stripFwNum(strips[idx].fw) >= 95) strips[idx].cfgSyncStep = 3;   // the strip keeps the outlet's limit itself (F1.0.95)
    stateDirty = true;
    return okRes();
  }
  if (path == "config") {
    if (jsonHas(b, "tz_zone")) {                 // checked first, so a bad zone leaves everything else untouched
      String z0 = jsonValue(b, "tz_zone");
      z0.trim();
      if (z0.length() && !tzPosixFor(z0.c_str())) return errRes("unknown zone");
    }
    if (jsonHas(b, "temp_max")) { tempMax = constrain(jsonValue(b, "temp_max").toInt(), 15, 95); cfg.putUChar("tmax", tempMax); }   // the strip accepts 40..95
    if (jsonHas(b, "temp_protect")) { tempProtect = jsonBool(b, "temp_protect"); cfg.putBool("tprot", tempProtect); }
    if (jsonHas(b, "v_protect")) { vProt = jsonBool(b, "v_protect"); cfg.putBool("vprot", vProt); }
    if (jsonHas(b, "v_restore")) { vRestore = jsonBool(b, "v_restore"); cfg.putBool("vrest", vRestore); }
    if (jsonHas(b, "v_back_s")) { vBackS = (uint16_t)constrain((int)jsonValue(b, "v_back_s").toInt(), 10, 1800); cfg.putUShort("vbacks", vBackS); }
    if (jsonHas(b, "v_back_lo")) { vBackLo = (uint16_t)constrain((int)jsonValue(b, "v_back_lo").toInt(), 0, 280); cfg.putUShort("vbacklo", vBackLo); }
    if (jsonHas(b, "v_back_hi")) { vBackHi = (uint16_t)constrain((int)jsonValue(b, "v_back_hi").toInt(), 0, 280); cfg.putUShort("vbackhi", vBackHi); }
    if (jsonHas(b, "v_max")) { vMax = constrain((int)jsonValue(b, "v_max").toInt(), 220, 280); cfg.putUShort("vmax", vMax); }
    if (jsonHas(b, "v_min")) { vMin = constrain((int)jsonValue(b, "v_min").toInt(), 100, 220); cfg.putUShort("vmin", vMin); }   // the ranges are the strip's own
    if (jsonHas(b, "a_protect")) { aProt = jsonBool(b, "a_protect"); cfg.putBool("aprot", aProt); }
    if (jsonHas(b, "a_max")) { aMax = constrain(jsonValue(b, "a_max").toFloat(), 0.5f, 16.5f); cfg.putFloat("amax", aMax); }
    if (jsonHas(b, "w_max")) { STRIP_MAX_W = (float)constrain((int)jsonValue(b, "w_max").toInt(), 50, 3680); cfg.putUShort("wmax", (uint16_t)STRIP_MAX_W); }
    if (jsonHas(b, "hold_s")) { protHoldS = (uint16_t)constrain((int)jsonValue(b, "hold_s").toInt(), 1, 600); cfg.putUShort("phold2", protHoldS); }
    if (jsonHas(b, "tz_zone")) {                 // a zone from the app's list ("" = back to the fixed offset)
      String z = jsonValue(b, "tz_zone");
      z.trim();
      strlcpy(tzZone, z.c_str(), sizeof tzZone);
      cfg.putString("tzzone", z);
      applyHubTimezone();
      cfg.putShort("tzmin3", tzOffsetMin);
    } else if (jsonHas(b, "tz_min")) {           // a fixed offset replaces any zone
      tzZone[0] = 0;
      cfg.putString("tzzone", "");
      tzOffsetMin = (int16_t)constrain((int)jsonValue(b, "tz_min").toInt(), -720, 840);
      cfg.putShort("tzmin3", tzOffsetMin);
      applyHubTimezone();
    }
    for (int i = 0; i < MAX_STRIPS; i++) {
      if (strips[i].used && strips[i].identified && stripFwNum(strips[i].fw) >= 90) {
        strips[i].cfgSyncStep = 1;
      }
    }
    stateDirty = true;
    return okRes("{\"temp_max\":" + String(tempMax) + ",\"temp_protect\":" + (tempProtect ? "true" : "false") +
                 ",\"v_min\":" + String(vMin) + ",\"v_max\":" + String(vMax) +
                 ",\"w_max\":" + String((int)STRIP_MAX_W) + ",\"hold_s\":" + String(protHoldS) + ",\"tz_min\":" + String(tzOffsetMin) +
                 ",\"tz_zone\":\"" + String(tzZone) + "\",\"tz_dst\":" + (tzNowDst() ? "true" : "false") + "}");
  }
  if (path == "outlet_log") {                   // {"mac","outlet":0..4,"days":1..30} -> the cycles of that outlet, newest first
    String m = jsonValue(b, "mac");
    if (!m.length()) return errRes("mac required");
    return okRes(outletLogJson(m, jsonValue(b, "outlet").toInt(), jsonHas(b, "days") ? jsonValue(b, "days").toInt() : 7));
  }
  if (path == "scen_list") return okRes(scenListJson());
  if (path == "scen_save") return scenSave(b);
  if (path == "scen_delete") return scenDelete((uint16_t)jsonValue(b, "id").toInt());
  if (path == "set_time") {                      // {"ts": UTC epoch, "tz_min"}: the phone gives the hub the time when it has none yet
    if (timeOk()) return okRes("{\"set\":false}");
    uint32_t ts = (uint32_t)jsonValue(b, "ts").toInt();
    if (ts < 1700000000UL) return errRes("bad time");
    struct timeval tv = { (time_t)ts, 0 };
    settimeofday(&tv, nullptr);
    if (jsonHas(b, "tz_min") && !tzZone[0]) {
      tzOffsetMin = (int16_t)constrain((int)jsonValue(b, "tz_min").toInt(), -720, 840);
      cfg.putShort("tzmin3", tzOffsetMin);
      applyHubTimezone();
    }
    for (int i = 0; i < MAX_STRIPS; i++)
      if (strips[i].used && strips[i].identified && stripFwNum(strips[i].fw) >= 90) strips[i].cfgSyncStep = 1;
    stateDirty = true;
    return okRes("{\"set\":true}");
  }
  if (path == "time_sync") {                     // send every strip the time and the offset again now
    for (int i = 0; i < MAX_STRIPS; i++)
      if (strips[i].used && strips[i].identified && stripFwNum(strips[i].fw) >= 90) strips[i].cfgSyncStep = 1;
    return okRes("{}");
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

