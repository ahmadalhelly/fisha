// Fisha hub: helpers, JSON/String utilities, non-blocking socket writes. Part of mttl_hub.ino, included in order from there.
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
  if (body[p] == '"') {
    p++;
    while (p < (int)body.length()) {
      char c = body[p++];
      if (c == '\\') { if (p < (int)body.length()) p++; continue; }
      if (c == '"') return;
    }
    return;
  }
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

// {"8":3,"36":12}: how often each Wi-Fi drop reason happened since boot
String wifiReasonsJson() {
  String j = "{";
  for (int i = 0; i < 64; i++) {
    if (!wifiReasonCnt[i]) continue;
    if (j.length() > 1) j += ",";
    j += "\"" + (i < 48 ? String(i) : i < 63 ? String(i + 152) : String("other")) + "\":" + String(wifiReasonCnt[i]);
  }
  return j + "}";
}

// ---------- non-blocking socket writes ---------
// WiFiClient::write() waits up to 10 x 1 s for room in the send buffer. A phone that went to sleep with the
// live page open, or a strip that lost power, never drains it, so every write froze the whole hub for seconds:
// strips went stale and dropped, keep-on/lock reverts and schedules were late. These writes give up quickly.
bool sendNB(WiFiClient& c, const char* p, size_t len, uint32_t maxMs) {
  int fd = c.fd();
  if (fd < 0 || !c.connected()) return false;
  uint32_t t0 = millis();
  size_t piece = 536;                            // one small buffer at a time; a 1.5 KB one is what a fragmented heap cannot give
  while (len) {
    int r = lwip_send(fd, p, len < piece ? len : piece, MSG_DONTWAIT);
    if (r > 0) { p += r; len -= r; continue; }
    // ENOMEM = lwIP could not get a buffer this instant (a fragmented heap); the socket is fine: wait a little and
    // send smaller pieces, which need smaller buffers
    if (r < 0 && errno == ENOMEM && millis() - t0 < maxMs) { piece = 256; delay(5); continue; }
    if (r < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) && millis() - t0 < maxMs) { delay(1); continue; }
    return false;
  }
  return true;
}
bool sendStr(WiFiClient& c, const String& s, uint32_t maxMs) { return sendNB(c, s.c_str(), s.length(), maxMs); }
// like sendNB but reports how much went out (-1 = the socket is broken), so the rest can wait
int sendSome(WiFiClient& c, const char* p, size_t len, uint32_t maxMs) {
  int fd = c.fd();
  if (fd < 0 || !c.connected()) return -1;
  SubT st("sock_send");
  uint32_t t0 = millis();
  int sent = 0;
  size_t piece = 536;
  while (len) {
    int r = lwip_send(fd, p, len < piece ? len : piece, MSG_DONTWAIT);
    if (r > 0) { p += r; len -= r; sent += r; continue; }
    if (r < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == ENOMEM)) {   // ENOMEM: no buffer right now, not a broken socket
      if (errno == ENOMEM) piece = 256;                                          // smaller pieces need smaller buffers
      if (millis() - t0 < maxMs) { delay(errno == ENOMEM ? 5 : 1); continue; }
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

// a send that is slow for a moment (hub busy, Wi-Fi retry, low memory) no longer drops the strip.
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
  // another config command answers connect_ok too: from now on a connect_ok is not the answer to the time
  if (s.timePend && (line.startsWith("up:tz:") || line.startsWith("up:limits:") || line.startsWith("up:sched:") || line.startsWith("up:childlock:"))) s.timePend = false;
  if (!flushTx(s, 150) && !s.dead)
    Serial.printf("[tx %s] slow, %u bytes waiting\n", s.mac.length() ? s.mac.c_str() : s.ip.c_str(), s.txq.length());
  Serial.printf("[tx %s] %s\n", s.mac.length() ? s.mac.c_str() : s.ip.c_str(), line.c_str());
}

// like sendLine, but the serial log shows only the network name, never the password
// F1.0.82 keeps the physical-button locks in its own flash: bit0 = master button, bits1..4 = outlet buttons
// Extracts numeric revision after "F1.0." (e.g. "0.1.55-F1.0.90" -> 90, "0.1.55-F1.0.84" -> 84, "0.1.55-F1.0.82" -> 82)
int stripFwNum(const String& fw) {
  int p = fw.indexOf("F1.0.");
  if (p < 0) p = fw.indexOf("f1.0.");
  if (p < 0) return 0;
  return fw.substring(p + 5).toInt();
}

// the zones the app offers, with their POSIX rule (the daylight-saving switch dates are in it). Egypt: summer time from
// the last Friday of April 00:00 to the last Thursday of October 24:00.
struct TzZone { const char* id; const char* posix; };
const TzZone TZ_ZONES[] = {
  {"cairo", "EET-2EEST,M4.5.5/0,M10.5.4/24"}, {"riyadh", "<+03>-3"},   {"kuwait", "<+03>-3"},     {"doha", "<+03>-3"},
  {"baghdad", "<+03>-3"},                     {"amman", "<+03>-3"},    {"istanbul", "<+03>-3"},   {"dubai", "<+04>-4"},
  {"muscat", "<+04>-4"},                      {"delhi", "<+0530>-5:30"}, {"casablanca", "<+01>-1"}, {"tunis", "CET-1"},
  {"algiers", "CET-1"},                       {"khartoum", "CAT-2"},   {"london", "GMT0BST,M3.5.0/1,M10.5.0"},
  {"paris", "CET-1CEST,M3.5.0,M10.5.0/3"},    {"newyork", "EST5EDT,M3.2.0,M11.1.0"}, {"utc", "UTC0"},
};
const char* tzPosixFor(const char* id) {
  for (const TzZone& z : TZ_ZONES) if (!strcmp(z.id, id)) return z.posix;
  return nullptr;
}
// days since 1970-01-01 of a calendar date (no library call, no time zone involved)
static int64_t tzDays(int y, unsigned m, unsigned d) {
  y -= m <= 2;
  const int era = (y >= 0 ? y : y - 399) / 400;
  const unsigned yoe = (unsigned)(y - era * 400);
  const unsigned doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1;
  const unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  return (int64_t)era * 146097 + (int64_t)doe - 719468;
}
// the offset from UTC in force right now, in minutes (daylight saving included): the local clock read as if it were UTC,
// minus the real UTC time
int16_t tzNowMin() {
  time_t now = time(nullptr);
  struct tm l;
  localtime_r(&now, &l);
  int64_t loc = tzDays(l.tm_year + 1900, l.tm_mon + 1, l.tm_mday) * 86400 + l.tm_hour * 3600 + l.tm_min * 60 + l.tm_sec;
  return (int16_t)((loc - (int64_t)now) / 60);
}
bool tzNowDst() {
  time_t now = time(nullptr);
  struct tm l;
  localtime_r(&now, &l);
  return l.tm_isdst > 0;
}

void applyHubTimezone() {
  const char* posix = tzZone[0] ? tzPosixFor(tzZone) : nullptr;
  if (posix) {
    configTzTime(posix, "pool.ntp.org", "time.google.com");
    if (timeOk()) tzOffsetMin = tzNowMin();
    return;
  }
  // POSIX TZ sign is inverted relative to UTC offset: UTC+2 (+120 min) is "UTC-2"
  int16_t m = tzOffsetMin;
  char sign = (m >= 0) ? '-' : '+';
  int16_t absM = m >= 0 ? m : -m;
  int hh = absM / 60;
  int mm = absM % 60;
  char tzBuf[24];
  if (mm == 0) snprintf(tzBuf, sizeof(tzBuf), "UTC%c%d", sign, hh);
  else snprintf(tzBuf, sizeof(tzBuf), "UTC%c%d:%02d", sign, hh, mm);
  configTzTime(tzBuf, "pool.ntp.org", "time.google.com");
}

// every 30 s: with a zone chosen, the offset in force follows the daylight-saving rule; when it changes, every strip
// is sent the new offset (and the schedules that depend on it) through the normal paced sync
void tzTick() {
  static uint32_t last = 0;
  if (!tzZone[0] || !timeOk() || millis() - last < 30000) return;
  last = millis();
  int16_t o = tzNowMin();
  if (o == tzOffsetMin) return;
  tzOffsetMin = o;
  cfg.putShort("tzmin3", tzOffsetMin);
  for (int i = 0; i < MAX_STRIPS; i++)
    if (strips[i].used && strips[i].identified && stripFwNum(strips[i].fw) >= 90) strips[i].cfgSyncStep = 1;
  stateDirty = true;
}

void sendChildLock(Strip& s) {
  if (stripFwNum(s.fw) < 82) return;
  // the strip-level lock locks EVERY button on the strip (master + 4 outlets); the per-outlet locks stay saved
  // and come back when it is turned off
  sendLine(s, "up:childlock:" + String(s.masterLock ? 0x1F : ((s.lockMask & 0x0F) << 1)));
}
bool sendWifiTo(Strip& s, const String& ssid, const String& pass) {
  if (s.dead || !s.c.connected()) return false;
  s.connOk = false;
  s.wifiHandoverSent = true;
  s.txq += "up:connect:" + ssid + ":" + pass + "\r\n";
  flushTx(s, 150);
  Serial.printf("[tx %s] up:connect:%s:****\n", s.mac.c_str(), ssid.c_str());
  return true;
}

bool mqttPub(const String& topic, const String& payload, int qos, bool retain);
bool userHas(const HubUser& u, const String& macIn);
String userStateHeadJson(const HubUser& u);
void pubMarksReset();
void clearUserStrips(const HubUser& u, bool all);
bool stateStream(const HubUser* u, const std::function<bool(const String&)>& put);
void mqttLock();
void mqttUnlock();
extern uint32_t mqttOutDropped;
extern uint32_t mqttGateN, mqttPauseN;
extern volatile bool mqttPaused;
void sseSend(const char* ev, const String& data);
void sseEvent(const String& data, const String& mac);

