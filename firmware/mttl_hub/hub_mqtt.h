// Fisha hub: MQTT cloud relay. Part of mttl_hub.ino, included in order from there.
// ---------- MQTT cloud relay ----------
uint32_t lastStatePub = 0;
String lastRelaySig, lastProvPub;

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
  mqttOutInit();
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
  cfgm.buffer.size = 2048;      // receive only (was 8192); commands are under 1 KB and bigger ones are refused anyway
  cfgm.buffer.out_size = 8192;
#else
  cfgm.uri = secMqttUri.c_str(); cfgm.cert_pem = MQTT_CA; cfgm.username = secMqttUser.c_str(); cfgm.client_id = mqttClientId; cfgm.password = secMqtt.c_str();
  cfgm.lwt_topic = tStatus.c_str(); cfgm.lwt_msg = "offline"; cfgm.lwt_qos = 1; cfgm.lwt_retain = 1; cfgm.keepalive = 30;
  cfgm.reconnect_timeout_ms = 5000; cfgm.buffer_size = 2048; cfgm.out_buffer_size = 8192;
#endif
  mqtt = esp_mqtt_client_init(&cfgm);
  esp_mqtt_client_register_event(mqtt, MQTT_EVENT_ANY, mqttEvent, nullptr);
  esp_mqtt_client_start(mqtt);
  Serial.printf("MQTT    : %s  hub=%s\n", secMqttUri.c_str(), id);
}

// esp_mqtt_client_enqueue waits for the MQTT client's lock, which the MQTT task holds for the whole of a
// slow network write or a TLS reconnect (seen: 19-21 s, "mqtt_pub" stalls). The main loop then froze and every strip
// dropped. Publishes now go through a small queue to their own task; the main loop never waits on the MQTT client.
struct MqttOut { char* topic; char* data; int len; uint8_t qos; uint8_t retain; };
static QueueHandle_t mqttOutQ = nullptr;
static SemaphoreHandle_t mqttMx = nullptr;          // held while the publisher task uses the client (stop/destroy wait on it)
static volatile uint32_t mqttOutBytes = 0;          // bytes waiting in the queue, capped so a stuck server can't eat the heap
static portMUX_TYPE mqttOutMux = portMUX_INITIALIZER_UNLOCKED;
// 8 KB (was 16 KB): the extra copies right after connecting ran the heap out (see mqttPub). Retained state
// copies may fill only MQTT_OUT_STATE_BYTES, so events and command answers keep room (the state is re-sent every 30 s).
const uint32_t MQTT_OUT_MAX_BYTES = 6144;          // 8 KB -> 6 KB, retained 6 KB -> 4.5 KB (one state at a time)
const uint32_t MQTT_OUT_STATE_BYTES = 4608;
uint32_t mqttOutDropped = 0;

static void mqttOutTask(void*) {
  MqttOut m;
  for (;;) {
    if (xQueueReceive(mqttOutQ, &m, portMAX_DELAY) != pdTRUE) continue;
    xSemaphoreTake(mqttMx, portMAX_DELAY);
    if (mqtt && mqttUp) esp_mqtt_client_enqueue(mqtt, m.topic, m.data, m.len, m.qos, m.retain, true);
    xSemaphoreGive(mqttMx);
    portENTER_CRITICAL(&mqttOutMux);
    mqttOutBytes -= m.len;
    portEXIT_CRITICAL(&mqttOutMux);
    free(m.topic);
    free(m.data);
  }
}

void mqttOutInit() {
  if (mqttOutQ) return;
  mqttMx = xSemaphoreCreateMutex();
  mqttOutQ = xQueueCreate(48, sizeof(MqttOut));   // 12 was too few for a reconnect burst (state + user states + 12 saved events per user)
  xTaskCreatePinnedToCore(mqttOutTask, "mqtt_out", 4096, nullptr, 1, nullptr, 0);
}

// stop/destroy the client only while the publisher task isn't inside it
void mqttLock() { if (mqttMx) xSemaphoreTake(mqttMx, portMAX_DELAY); }
void mqttUnlock() { if (mqttMx) xSemaphoreGive(mqttMx); }

// true = queued reports it, so the per-strip publisher can try a refused copy again later)
bool mqttPub(const String& topic, const String& payload, int qos, bool retain) {
  if (!mqtt || !mqttUp || !topic.length() || !mqttOutQ) return false;
  // a String whose building ran out of memory comes back empty with no buffer (c_str() == nullptr). That is
  // what crashed (a user state right after connecting). Publishing it as "" would also wipe the retained state
  // on the server, so it is dropped; a real empty message ("") always has a buffer and still goes out.
  if (!payload.c_str()) { mqttOutDropped++; return false; }
  SubT st("mqtt_pub");
  int len = payload.length();
  // nothing waiting: always take it, so one big state (many strips) can't be refused forever
  if (mqttOutBytes && mqttOutBytes + len > (retain ? MQTT_OUT_STATE_BYTES : MQTT_OUT_MAX_BYTES)) { mqttOutDropped++; return false; }
  MqttOut m;
  m.topic = strdup(topic.c_str());
  m.data = (char*)malloc(len + 1);
  if (!m.topic || !m.data) { free(m.topic); free(m.data); mqttOutDropped++; return false; }
  if (len) memcpy(m.data, payload.c_str(), len);
  m.data[len] = 0;
  m.len = len; m.qos = qos; m.retain = retain ? 1 : 0;
  portENTER_CRITICAL(&mqttOutMux);
  mqttOutBytes += len;
  portEXIT_CRITICAL(&mqttOutMux);
  if (xQueueSend(mqttOutQ, &m, 0) != pdTRUE) {
    portENTER_CRITICAL(&mqttOutMux);
    mqttOutBytes -= len;
    portEXIT_CRITICAL(&mqttOutMux);
    free(m.topic); free(m.data); mqttOutDropped++;
    return false;
  }
  return true;
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

// the cloud state is split. mttl/<hub>/state (members: mttl/<hub>/u/<id>/state) is a small head: everything but
// the strips, plus "strips":[MACs in order]. Each strip is its own retained message on mttl/<hub>/s/<MAC> (members:
// mttl/<hub>/u/<id>/s/<MAC>), sent only when that strip changed. With 10 strips the old single state was ~13 KB, more
// than the hub could build or queue, and it went out whole every 30 s and on every load change: far more EMQX traffic.
String mqttHead(const HubUser* u) {
  String h = u ? userStateHeadJson(*u) : stateHeadJson();
  if (!h.endsWith("\"devices\":[")) return String();
  h.remove(h.length() - 11);
  h += "\"strips\":[";
  bool first = true;
  for (int i = 0; i < MAX_STRIPS; i++) {
    if (!strips[i].used || !strips[i].identified || (u && !userHas(*u, strips[i].mac))) continue;
    if (!first) h += ",";
    h += "\"" + strips[i].mac + "\"";
    first = false;
  }
  for (int k = 0; k < knownCount; k++) {
    if (findStrip(known[k].mac) >= 0 || (u && !userHas(*u, known[k].mac))) continue;
    if (!first) h += ",";
    h += "\"" + known[k].mac + "\"";
    first = false;
  }
  h += "]}";
  return h;
}
void publishUserState(const HubUser& u) {
  String h = mqttHead(&u);
  if (h.length()) mqttPub("mttl/" + hubId + "/u/" + u.id + "/state", h, 0, true);   // "" would wipe the retained copy
}

// what must reach the cloud at once for one strip; numbers that drift (W, kWh, °C, V) follow their own pace
uint32_t sigMix(uint32_t h, const void* p, size_t n) {
  const uint8_t* b = (const uint8_t*)p;
  while (n--) h = (h ^ *b++) * 16777619u;
  return h;
}
uint32_t sigStr(uint32_t h, const String& v) { h = sigMix(h, v.c_str(), v.length()); return (h ^ 0x1F) * 16777619u; }
uint32_t stripSig(const String& mac) {
  uint32_t h = 2166136261u, flags = 0;
  for (int k = 0; k <= 4; k++) flags |= (hasSched(mac, k) ? 1u : 0u) << k | (hasRule(mac, k) ? 1u : 0u) << (8 + k);
  h = sigMix(h, &flags, 4);
  int i = findStrip(mac);
  if (i >= 0) {
    const Strip& s = strips[i];
    uint32_t bits = 1u << 31 | (s.masterLock ? 1u << 30 : 0) | (uint32_t)s.lockMask << 4 | (uint32_t)s.protMask << 8 |
                    (uint32_t)s.keepMask << 12 | (uint32_t)s.notifyMask << 16;
    for (int k = 0; k < 4; k++) bits |= (s.o[k].on ? 1u : 0u) << k | (s.autoOffAt[k] ? 1u : 0u) << (24 + k);
    h = sigMix(h, &bits, 4);
    h = sigMix(h, s.ampX2, sizeof s.ampX2);
    h = sigMix(h, s.autoOffMin, sizeof s.autoOffMin);
    h = sigStr(h, s.label);
    for (int k = 0; k < 4; k++) h = sigStr(h, s.olabel[k]);
    h = sigStr(h, s.fw);
    h = sigStr(h, s.ip);
    return h;
  }
  for (int k = 0; k < knownCount; k++) {
    if (known[k].mac != mac) continue;
    const Known& n = known[k];
    uint32_t bits = (uint32_t)n.lock | (uint32_t)n.prot << 8 | (uint32_t)n.keep << 16 | (uint32_t)n.notify << 24;
    h = sigMix(h, &bits, 4);
    h = sigMix(h, n.amp, sizeof n.amp);
    h = sigStr(h, n.label);
    for (int q = 0; q < 4; q++) h = sigStr(h, n.olabel[q]);
    return h;
  }
  return 0;
}
// one mark per strip the cloud has: the last thing sent and which copies (bit 0 owner, bit 1+u member u) still wait
struct PubMark { char mac[13]; uint32_t sig, at; float pw; uint16_t need, wipe; };   // wipe: member copies to clear
PubMark pubMarks[MAX_KNOWN];
void pubMarksReset() { for (int m = 0; m < MAX_KNOWN; m++) { pubMarks[m].at = 0; pubMarks[m].sig = 0; } }
float stripPower(const Strip& s) { float p = 0; for (int k = 0; k < 4; k++) p += s.o[k].on ? s.o[k].powerW : 0; return p; }
PubMark* pubMark(const String& mac) {
  PubMark* freeSlot = nullptr;
  for (int m = 0; m < MAX_KNOWN; m++) {
    if (!strcmp(pubMarks[m].mac, mac.c_str())) return &pubMarks[m];
    if (!pubMarks[m].mac[0] && !freeSlot) freeSlot = &pubMarks[m];
  }
  if (freeSlot) { *freeSlot = PubMark(); strlcpy(freeSlot->mac, mac.c_str(), sizeof freeSlot->mac); }
  return freeSlot;
}
// sends the strips that changed, a copy at a time while the send queue has room; the rest go on a later pass
void publishStrips() {
  if (!mqttUp) return;
  String base = "mttl/" + hubId + "/";
  uint32_t now = millis();
  // strips removed in the app: wipe their retained copies (owner and every member)
  for (int m = 0; m < MAX_KNOWN; m++) {
    PubMark& pm = pubMarks[m];
    if (!pm.mac[0] || macKnown(pm.mac)) continue;
    bool all = mqttPub(base + "s/" + pm.mac, "", 1, true);
    for (int u = 0; u < userCount && all; u++) all = mqttPub(base + "u/" + users[u].id + "/s/" + pm.mac, "", 1, true);
    if (!all) return;                              // queue full: the whole wipe again on a later pass
    pm = PubMark();
  }
  for (int pass = 0; pass < 2; pass++) {          // online strips, then the remembered (offline) ones
    int count = pass ? knownCount : MAX_STRIPS;
    for (int x = 0; x < count; x++) {
      String mac;
      int si = -1;
      if (!pass) { if (!strips[x].used || !strips[x].identified) continue; si = x; mac = strips[x].mac; }
      else { if (findStrip(known[x].mac) >= 0) continue; mac = known[x].mac; }
      PubMark* pm = pubMark(mac);
      if (!pm) continue;
      for (int u = 0; u < userCount && u < 15 && pm->wipe; u++) {   // a member lost this strip: clear its copy
        uint16_t bit = 1 << (u + 1);
        if (!(pm->wipe & bit)) continue;
        if (!userHas(users[u], mac) && !mqttPub(base + "u/" + users[u].id + "/s/" + mac, "", 1, true)) return;
        pm->wipe &= ~bit;
      }
      uint32_t sig = stripSig(mac);
      float pw = si >= 0 ? stripPower(strips[si]) : 0;
      bool due = !pm->at || pm->sig != sig ||
                 (si >= 0 && now - pm->at > 3000 && fabs(pw - pm->pw) > max(2.0f, pm->pw * 0.1f)) ||
                 (si >= 0 && now - pm->at > 60000);
      if (due) {
        pm->need = 1;
        for (int u = 0; u < userCount && u < 15; u++) if (userHas(users[u], mac)) pm->need |= 1 << (u + 1);
        pm->sig = sig; pm->at = now ? now : 1; pm->pw = pw;
      }
      if (!pm->need) continue;
      String body = si >= 0 ? stripJson(si) : offlineStripJson(known[x]);
      if (!body.length()) return;                  // out of memory: later
      if (pm->need & 1) { if (!mqttPub(base + "s/" + mac, body, 0, true)) return; pm->need &= ~1; }
      for (int u = 0; u < userCount && u < 15; u++) {
        uint16_t bit = 1 << (u + 1);
        if (!(pm->need & bit)) continue;
        if (!userHas(users[u], mac)) { pm->need &= ~bit; continue; }   // members changed since the mark was set
        if (!mqttPub(base + "u/" + users[u].id + "/s/" + mac, body, 0, true)) return;
        pm->need &= ~bit;
      }
    }
  }
}
// a member lost strips: their copies are wiped by publishStrips (paced, retried until the queue takes them).
// all = the member is being removed: wiped at once, as far as the queue takes them (their server login goes too).
void clearUserStrips(const HubUser& u, bool all) {
  if (all) {
    String base = "mttl/" + hubId + "/u/" + u.id + "/s/";
    for (int k = 0; k < knownCount; k++) mqttPub(base + known[k].mac, "", 1, true);
    return;
  }
  int ui = findUser(u.id);
  if (ui < 0 || ui >= 15) return;
  for (int k = 0; k < knownCount; k++) {
    if (userHas(u, known[k].mac)) continue;
    PubMark* pm = pubMark(known[k].mac);
    if (pm) pm->wipe |= 1 << (ui + 1);
  }
}
void mqttRestart() {
  mqttLock();
  if (mqtt) { esp_mqtt_client_stop(mqtt); esp_mqtt_client_destroy(mqtt); mqtt = nullptr; }
  mqttUp = false; mqttErrKind = 0; mqttErr = "";
  mqttUnlock();
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
  String h = mqttHead(nullptr);
  if (h.length()) mqttPub(tState, h, 0, true);
  h = String();
  for (int u = 0; u < userCount; u++) publishUserState(users[u]);
  mqttHeadDirty = false;
  lastStatePub = millis();
  lastRelaySig = relaySignature();
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
    pubMarksReset();                              // every strip again after a reconnect
    publishState();
    publishStrips();
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
  static uint32_t lastStripScan = 0;
  if (millis() - lastStripScan >= 500) {          // each strip on its own, when it changed (checked twice a second)
    lastStripScan = millis();
    publishStrips();
  }
  // the head: when something else changed (seen by the phones' stream), the timers moved, or every 30 s
  if (relaySignature() != lastRelaySig || provState != lastProvPub || (mqttHeadDirty && millis() - lastStatePub > 2000) ||
      millis() - lastStatePub > 30000)
    publishState();
}

