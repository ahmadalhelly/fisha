// Fisha hub: shared users and hub lock. Part of mttl_hub.ino, included in order from there.
// ---------- shared users ----------
ApiRes api(String path, const String& b);
ApiRes okRes(const String& data);
ApiRes okRes();
ApiRes errRes(const String& e);
void publishUserState(const HubUser& u);
const uint32_t USERS_MAGIC = 0x55535231;
// one buffer for loading and saving the users blob (both run on the main loop only)
union UsersBuf { UsersNV v2; UsersNVV1 v1; };
static UsersBuf usersBuf;
const uint32_t USERS_MAGIC2 = 0x55535232;          // layout: 10 strips per member
void loadUsers() {
  Preferences up; up.begin("users", true);
  UsersBuf& b = usersBuf;
  memset(&b, 0, sizeof b);
  // saves to "list2" and leaves the old "list" as it was, so going back to an older firmware keeps its members
  size_t len = up.getBytesLength("list2");
  if (len == sizeof(UsersNV)) up.getBytes("list2", &b, len);
  else if ((len = up.getBytesLength("list")) == sizeof(UsersNVV1)) up.getBytes("list", &b, len);
  up.end();
  userCount = 0;
  if (len == sizeof(UsersNV) && b.v2.magic == USERS_MAGIC2) {
    for (int i = 0; i < b.v2.count && i < MAX_USERS; i++) if (b.v2.u[i].id[0]) users[userCount++] = b.v2.u[i];
  } else if (len == sizeof(UsersNVV1) && b.v1.magic == USERS_MAGIC) {    // saved by same fields, 6 strips
    for (int i = 0; i < b.v1.count && i < MAX_USERS; i++) {
      const HubUserV1& o = b.v1.u[i];
      if (!o.id[0]) continue;
      HubUser& u = users[userCount++];
      memset(&u, 0, sizeof u);
      memcpy(u.id, o.id, sizeof u.id); memcpy(u.name, o.name, sizeof u.name);
      u.role = o.role; u.all = o.all; u.n = o.n > 6 ? 6 : o.n; u.rsv = o.rsv;
      memcpy(u.strips, o.strips, sizeof o.strips); memcpy(u.pw, o.pw, sizeof u.pw);
    }
  }
}
void saveUsers() {
  UsersNV& nv = usersBuf.v2;
  memset(&usersBuf, 0, sizeof usersBuf);
  nv.magic = USERS_MAGIC2; nv.count = userCount;
  for (int i = 0; i < userCount; i++) nv.u[i] = users[i];
  Preferences up;
  bool ok = up.begin("users", false) && up.putBytes("list2", &nv, sizeof nv) == sizeof nv;
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
  for (int k = 0; k < u.n && k < USER_STRIPS; k++) if (m == u.strips[k]) return true;
  return false;
}
void parseStrips(HubUser& u, const String& list) {
  u.n = 0; memset(u.strips, 0, sizeof u.strips);
  for (String p : split(list, ',')) {
    p.trim(); p.toUpperCase();
    if (p.length() == 12 && isHex(p) && u.n < USER_STRIPS) strlcpy(u.strips[u.n++], p.c_str(), 13);
  }
}
// each member's Google email and photo link, kept apart from the users blob so its layout stays the same
String profGet(const char* id, char k) {
  Preferences pp; pp.begin("uprof", true);
  String v = pp.getString((String(k) + id).c_str(), "");
  pp.end();
  return v;
}
void profSet(const char* id, char k, const String& v) {
  Preferences pp; pp.begin("uprof", false);
  if (v.length()) pp.putString((String(k) + id).c_str(), v); else pp.remove((String(k) + id).c_str());
  pp.end();
}
String userJson(const HubUser& u) {
  String j = "{\"id\":\"" + String(u.id) + "\",\"name\":\"" + jsonEsc(String(u.name)) + "\",\"role\":" + String(u.role) +
             ",\"perms\":" + String(u.rsv & 0x3F) + ",\"email\":\"" + jsonEsc(profGet(u.id, 'e')) + "\",\"photo\":\"" +
             jsonEsc(profGet(u.id, 'p')) + "\",\"all\":" + (u.all ? "true" : "false") + ",\"strips\":[";
  for (int k = 0; k < u.n && k < USER_STRIPS; k++) { if (k) j += ","; j += "\"" + String(u.strips[k]) + "\""; }
  return j + "]}";
}

// ---------- hub lock ----------
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
// the update password as text: the owner's own one, or the fixed fisha-<MAC> (same set otaPassOk accepts)
bool otaTextOk(const String& p) {
  if (p.length() < 8) return false;
  if (secOta.length() && p == secOta) return true;
  String d = defOta();
  if (p == d) return true;
  d.setCharAt(0, 'F');
  return p == d;
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
    if (ownerCount) {                            // later phones are added through pairing; the same owner email may win its key back
      String ota = jsonValue(b, "ota");
      if (ownerByEmail(email) < 0 || !ota.length()) return out(409, "{\"ok\":false,\"error\":\"claimed\"}");
      if (!otaTextOk(ota)) {                     // the update password is the proof: slow guessing down
        if (++claimFails >= 5) { claimFails = 0; claimLockUntil = (millis() + 300000UL) | 1; }
        return out(401, "{\"ok\":false,\"error\":\"wrong_password\"}");
      }
      claimFails = 0;
      String key = addOwner(email, cleanModel(jsonValue(b, "model")));   // replaces the old key of this email
      addEvent("owner", "", 0, email);
      return out(200, "{\"ok\":true,\"data\":{\"key\":\"" + key + "\"}}");
    }
    if (millis() >= CLAIM_WINDOW_MS) return out(403, "{\"ok\":false,\"error\":\"claim_window\"}");
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
  mqttLock();
  if (mqtt) { esp_mqtt_client_stop(mqtt); mqttUp = false; paused = true; }   // two TLS sessions don't fit in RAM
  mqttUnlock();
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
      pubMarksReset();                           // the new member gets its strips too
      String code = inviteCode(j.u, j.pw);
      j.data = "{\"code\":\"" + code + "\",\"user\":" + userJson(j.u) + "}";
      int pi = pairJobId ? pairFind(pairJobId) : -1;   // an approved phone gets its invite on its next poll
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
      clearUserStrips(j.u, true);
      if (i >= 0) { for (int k = i; k < userCount - 1; k++) users[k] = users[k + 1]; userCount--; saveUsers(); }
    } else j.err = "emqx " + exCodeText(http2xx(j.c1) || j.c1 == 404 ? j.c2 : j.c1);
  } else if (j.kind == 4) {                      // server login for a phone that is already in
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

// makes the server login of an approved phone when the server worker is free (every 10 min on failure)
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
  if (p == "state" || p == "events" || p == "energy" || p == "link" || p == "schedules" || p == "automations" || p == "profile" || p == "outlet_log") return 0;
  if (p == "onoff" || p == "refresh" || p == "timer" || p == "timer_cancel" || p == "schedule_save" || p == "schedule_delete" || p == "schedule_skip") return 1;
  if (p == "label" || p == "lock" || p == "protect" || p == "autooff" || p == "keepon" || p == "amplimit" || p == "automation_save" || p == "automation_delete" || p == "scen_list" || p == "scen_save" || p == "scen_delete") return 2;
  if (p == "wifi" || p == "strip_wifi_test" || p == "reboot" || p == "time_sync") return 2;
  return -1;
}
// the extra permission that lets a lower role do an admin action anyway (0 = none)
uint8_t grantFor(const String& p) {
  if (p == "automation_save" || p == "automation_delete" || p == "scen_list" || p == "scen_save" || p == "scen_delete") return P_AUTO;
  if (p == "label" || p == "lock" || p == "protect" || p == "autooff" || p == "keepon" || p == "amplimit") return P_PROT;
  if (p == "wifi" || p == "strip_wifi_test") return P_WIFI;
  return 0;
}
bool globalAction(const String& p) { return p == "wifi" || p == "strip_wifi_test" || p == "reboot" || p == "profile" || p == "time_sync"; }
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
// a member's state up to its strips ("devices":[ included); the strips follow through stateStream
String userStateHeadJson(const HubUser& u) {
  String j = "{\"hub_fw\":\"" + String(FW_VERSION) + "\",\"hub_build\":" + String(FISHA_BUILD) + ",\"hub\":\"" + hubId + "\",\"time_ok\":" + (timeOk() ? "true" : "false") +
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
  return j;
}
String userStateJson(const HubUser& u) { return stateJsonFor(&u); }
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
  uint8_t g = grantFor(path);
  if (need < 0 || (u.role < need && !(g && (u.rsv & g)))) return errRes("forbidden");
  ApiRes r;
  if (userList(u, path, r)) return r;
  if (path == "profile") {                        // {"email","photo"}: a member's own Google email and photo
    String e = jsonValue(b, "email"), ph = jsonValue(b, "photo");
    if (e.length() > 64 || ph.length() > 300 || (ph.length() && !ph.startsWith("https://"))) return errRes("bad profile");
    profSet(u.id, 'e', e);
    profSet(u.id, 'p', ph);
    stateDirty = true;
    return okRes();
  }
  if (globalAction(path)) {
    if (!u.all) return errRes("forbidden");
    apiSrc = 0;                                   // allowed above; run it as the hub's own action
    ApiRes ar = api(path, b);
    apiSrc = 2;
    return ar;
  }
  String m = actionMac(path, b);
  // control members switch outlets but not overload-protected ones, unless allowed to change protections
  if (path == "onoff" && u.role < 2 && !(u.rsv & P_PROT)) {
    int si = findStrip(m);
    int o = jsonValue(b, "outlet").toInt();
    if (si >= 0 && strips[si].protMask && (o == 0 ? true : (strips[si].protMask & (1 << (o - 1))))) return errRes("protected");
  }
  if (path == "refresh") { if (!u.all) return errRes("forbidden"); }
  else if (!m.length() || m == "?" || !userHas(u, m)) return errRes("forbidden");
  return api(path, b);
}

