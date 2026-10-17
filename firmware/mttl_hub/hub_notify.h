// Fisha hub: phone notifications (ntfy). Part of mttl_hub.ino, included in order from there.
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
  // a safety cut always reaches the phone. These types have no switch in the app, and an old app could save
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

// the HTTPS call runs in its own task. On the loop it froze switching for 1-3 s per notification,
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

// an event made while the cloud link is down (Wi-Fi blip, MQTT reconnecting) used to be lost, so the phone
// never got its notification although the app's log showed it. It now waits here and goes out on reconnect.
const uint8_t EV_OUTBOX = 12;
String evOutJ[EV_OUTBOX], evOutMac[EV_OUTBOX];
uint8_t evOutN = 0;
// access requests are the owner's business only, not shown to family members
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

