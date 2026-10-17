std::vector<String> split(const String& s, char sep) {
  std::vector<String> out;
  int start = 0;
  for (int i = 0; i <= (int)s.length(); i++) {
    if (i == (int)s.length() || s[i] == sep) { out.push_back(s.substring(start, i)); start = i + 1; }
  }
  return out;
}
bool curValid(const Strip& s, int k, uint32_t now) {
  const Outlet& o = s.o[k];
  if (!o.on || !s.curAt[k] || (int32_t)(now - s.curAt[k]) > 45000) return false;
  float d = o.powerW - s.curPw[k];
  if (d < 0) d = -d;
  return d <= s.curPw[k] * 0.15f + 10.0f;
}
float outletAmps(const Strip& s, int k, float volts, uint32_t now) {
  if (!s.o[k].on) return 0;
  return curValid(s, k, now) ? s.curA[k] : s.o[k].powerW / volts;
}
float outletAmpsMax(const Strip& s, int k, float volts, uint32_t now) {
  if (!s.o[k].on) return 0;
  float est = s.o[k].powerW / volts;
  return curValid(s, k, now) && s.curA[k] > est ? s.curA[k] : est;
}
void handlePowerReport(Strip& s, const String& line) {
  std::vector<String> f = split(line.substring(16), ':');
  // the answer to a :current request (mA). It is told apart from a voltage (mV, >= 50000) by what was asked, and
  // a value in mV range is never taken as a voltage here: a strip that answered :current in another unit would
  // otherwise look like an under-voltage and cut its outlets.
  if (s.pwrKind == 2 && f.size() == 2 && f[0].toInt() == s.pwrCh) {
    s.pwrKind = 0;
    bool num = f[1].length() > 0 && f[1].length() <= 6;
    for (unsigned c = 0; num && c < f[1].length(); c++) if (f[1][c] < '0' || f[1][c] > '9') num = false;
    long mA = num ? f[1].toInt() : -1;
    if (mA >= 50000) { if (++s.curBadN >= 3) s.curBad = true; }
    else if (mA >= 0 && mA <= 20000 && s.pwrCh >= 1 && s.pwrCh <= 4) {
      int k = s.pwrCh - 1;
      s.curBadN = 0;
      s.curA[k] = mA / 1000.0f;
      s.curPw[k] = s.o[k].powerW;
      s.curAt[k] = millis() | 1;
      liveDirty = true;                      // numbers only
    }
    return;
  }
  if (f.size() == 2 && f[1].toInt() >= 50000) {
    if (s.pwrKind == 1) s.pwrKind = 0;
    s.voltage = f[1].toInt() / 1000.0f;
    if ((s.voltage < 200 || s.voltage > 250) && (!s.voltEventAt || millis() - s.voltEventAt > 600000)) {
      s.voltEventAt = millis();
      addEvent("voltage", s.mac, 0, String(s.voltage, 0) + " V");
    }
    voltCheck(s);
  }
}
void askCurrent(Strip& s) {
  uint32_t now = millis();
  if (s.curBad || (s.pwrKind && now - s.pwrAt < 3000)) return;
  for (int n = 0; n < 4; n++) {
    int k = (s.curNext + n) & 3;
    if (!s.o[k].on) continue;
    s.curNext = (k + 1) & 3;
    s.pwrKind = 2; s.pwrCh = k + 1; s.pwrAt = now;
    sendLine(s, "up:power_report:" + String(k + 1) + ":current");
    return;
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
    if (pollCount % DIAG_EVERY == 0) { s.pwrKind = 1; s.pwrCh = 1; s.pwrAt = millis(); sendLine(s, "up:power_report:1:vol"); sendLine(s, "up:query:wifirssi"); }
    else if (pollCount % DIAG_EVERY == 1) askCurrent(s);
  }
}
