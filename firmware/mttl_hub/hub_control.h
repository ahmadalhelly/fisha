// Fisha hub: strip control, energy, automations and protections. Part of mttl_hub.ino, included in order from there.
// ---------- strip control ----------
void dropStrip(Strip& s, const char* why) {
  Serial.printf("[-] %s %s\n", s.mac.length() ? s.mac.c_str() : s.ip.c_str(), why);
  if (s.identified && (!strcmp(why, "disconnected") || !strcmp(why, "stale") || !strcmp(why, "socket stuck"))) {
    String mac = s.mac;
    if (offlineMacs.indexOf(mac) < 0) offlineMacs += mac + ",";
    { SubT st("sock_close"); s.c.stop(); }
    s = Strip();
    stateDirty = true;
    linkDrop(mac);
    addEvent("offline", mac, 0, why);                 // why: "disconnected" (strip closed), "stale" (silent 45 s) or "socket stuck" (hub could not send,
    return;
  }
  { SubT st("sock_close"); s.c.stop(); }
  s = Strip();
  stateDirty = true;
}

void noteCommanded(Strip& s, int outlet, bool on) {
  uint8_t before = s.lockState;
  for (int ch = (outlet ? outlet : 1); ch <= (outlet ? outlet : 4); ch++) {
    s.cmdAt[ch - 1] = millis();
    if (on) s.lockState |= (1 << (ch - 1)); else s.lockState &= ~(1 << (ch - 1));
  }
  if (s.lockState != before && s.lockMask) saveLocks(s);
}

// fire-and-forget switch (used by schedules, timers, automations); the next poll confirms it
// keep-always-on outlets ignore "off" unless it is a safety cut (force), which holds them off until switched on again
bool keepSkip(Strip& s, int ch, bool on, bool force) {
  uint8_t bit = 1 << (ch - 1);
  if (on || !(s.keepMask & bit)) return false;
  if (!force) return true;
  s.keepHold |= bit;
  return false;
}

// fix: a master "all on/off" (outlet == 0) used to also re-command a child-locked outlet, which raced
// with the "keep a locked outlet where it belongs" resend (the lock enforcement loop) and could stall or confuse
// the whole batch for the strip, so the other (free) outlets did not respond properly either. A direct command to
// that one outlet (outlet == ch, from its own tile) still goes through — only the whole-strip master command skips
// locked channels now, the same way it already skips keep-always-on ones.
bool lockSkip(Strip& s, int ch, int outlet) { return outlet == 0 && (s.lockMask & (1 << (ch - 1))); }

void sendOnOffF(Strip& s, int outlet, bool on, bool force) {
  for (int ch = (outlet ? outlet : 1); ch <= (outlet ? outlet : 4); ch++) {
    if (on) s.tripMask &= ~(1 << (ch - 1));      // switched back on on purpose: stop chasing the safety cut
    if (lockSkip(s, ch, outlet) || keepSkip(s, ch, on, force)) continue;
    noteCommanded(s, ch, on);
    sendLine(s, "up:onoff:" + String(ch) + ":" + (on ? "on" : "off"));
    s.o[ch - 1].on = on;
  }
  sendLine(s, "up:getinfo:all");
  stateDirty = true;
}
void sendOnOff(Strip& s, int outlet, bool on) { sendOnOffF(s, outlet, on, false); }

// safety cut: switch the outlet off and keep checking the strip's next reports. If it still says "on", send
// the off again (up to 4 more times), then raise "trip_fail" so the user knows the cut did not take.
void protectCut(Strip& s, int k) {
  sendOnOffF(s, k + 1, false, true);
  s.tripMask |= 1 << k;
  s.tripTries[k] = 0;
  s.tripAt = millis();
  s.tripSeq = s.infoSeq;
}
void tripVerify(Strip& s) {
  if (!s.tripMask) return;
  uint32_t now = millis();
  if (s.infoSeq == s.tripSeq || now - s.tripAt < 1500) return;   // wait for a report made after the last off
  for (int k = 0; k < 4; k++) {
    uint8_t bit = 1 << k;
    if (!(s.tripMask & bit)) continue;
    if (!s.o[k].on) { s.tripMask &= ~bit; continue; }             // confirmed off
    if (s.tripTries[k] >= 4) {
      s.tripMask &= ~bit;
      addEvent("trip_fail", s.mac, k + 1, String((int)s.o[k].powerW) + " W");
      continue;
    }
    s.tripTries[k]++;
    Serial.printf("[trip] %s outlet %d still on, off again (%u)\n", s.mac.c_str(), k + 1, s.tripTries[k]);
    sendOnOffF(s, k + 1, false, true);
    s.tripAt = now;
    s.tripSeq = s.infoSeq;
  }
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
  for (int ch = (outlet ? outlet : 1); ch <= (outlet ? outlet : 4); ch++) {
    if (on) s.tripMask &= ~(1 << (ch - 1));
    if (lockSkip(s, ch, outlet) || keepSkip(s, ch, on, false)) continue;
    noteCommanded(s, ch, on);
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
  if (!timeOk() || !histHeads(i)) return;
  Strip& s = strips[i];
  const ElogHead& h = elogs[i];
  int32_t today = localDay();
  bool changed = h.day == 0 || today != h.day;
  for (int k = 0; k < 4; k++) changed |= s.o[k].energyWh < h.base[k];   // counter reset
  if (!changed) return;
  ELog* elp = elogGet(i);
  if (!elp) return;                                // no memory now: next report tries again
  ELog& el = *elp;
  if (el.day == 0) {
    el.day = today;
    for (int k = 0; k < 4; k++) el.base[k] = s.o[k].energyWh;
  } else if (today != el.day) {
    int idx = ((el.day % ELOG_DAYS) + ELOG_DAYS) % ELOG_DAYS;
    for (int k = 0; k < 4; k++) {
      uint32_t c = s.o[k].energyWh;
      el.wh[idx][k] = c >= el.base[k] ? c - el.base[k] : 0;
      el.base[k] = c;
    }
    el.dayOf[idx] = el.day;
    el.day = today;
  } else {
    for (int k = 0; k < 4; k++) if (s.o[k].energyWh < el.base[k]) el.base[k] = s.o[k].energyWh;
  }
  elogPut(i, elp);
}


// over-voltage + under-voltage protection for the whole strip
void voltCheck(Strip& s) {
  if (isnan(s.voltage)) return;
  uint32_t now = millis();
  // over-voltage is always enforced ; vProt only switches the under-voltage cut
  bool underOn = vProt && vMin > 0;
  bool badV = s.voltage > vMax || (underOn && s.voltage < vMin);
  if (badV) {
    s.vOkSince = 0;
    if (s.ovCount < 255) s.ovCount++;
    bool far = s.voltage > vMax + 15 || (underOn && s.voltage < vMin - 15);
    if (s.vCutMask || (s.ovCount < protHoldS && !far)) return;   // two readings in a row, or one far outside
    bool over = s.voltage > vMax;
    uint8_t cut = 0;
    for (int k = 0; k < 4; k++)                       // over-voltage cuts protected outlets too
      if (s.o[k].on && (over || !(s.protMask & (1 << k)))) { protectCut(s, k); cut |= 1 << k; }
    s.vCutMask = cut ? cut : 0x80;                     // 0x80 = tripped with nothing to cut
    addEvent(over ? "overvolt" : "undervolt", s.mac, 0, String(s.voltage, 0) + " V");
    stateDirty = true;
    return;
  }
  s.ovCount = 0;
  if (!s.vCutMask) return;
  // back inside the window the owner chose (5 V inside the limits by default), for as long as the owner chose
  int hi = vBackHi ? ((int)vBackHi < (int)vMax - 1 ? (int)vBackHi : (int)vMax - 1) : (int)vMax - 5;
  int lo = vBackLo ? ((int)vBackLo > (int)vMin + 1 ? (int)vBackLo : (int)vMin + 1) : (int)vMin + 5;
  if (lo >= hi) { lo = (int)vMin + 1; hi = (int)vMax - 1; }   // an empty window would keep the strips off for good
  if (s.voltage > hi || (underOn && s.voltage < lo)) { s.vOkSince = 0; return; }
  if (!s.vOkSince) { s.vOkSince = now ? now : 1; return; }
  if (now - s.vOkSince < (uint32_t)vBackS * 1000UL) return;
  if (vRestore)
    for (int k = 0; k < 4; k++) if (s.vCutMask & (1 << k)) sendOnOff(s, k + 1, true);
  addEvent("voltage", s.mac, 0, String(s.voltage, 0) + " V ok");
  s.vCutMask = 0;
  s.vOkSince = 0;
  stateDirty = true;
}

// ---------- real per-outlet current ----------
// A real reading (mA from the strip) counts only while it is fresh and the load has not changed since it was read.
// Without one the estimate (W / V) is used, as before.
bool curValid(const Strip& s, int k, uint32_t now) {
  const Outlet& o = s.o[k];
  if (!o.on || !s.curAt[k]) return false;
  int32_t age = (int32_t)(now - s.curAt[k]);       // a reading a few ms newer than 'now' is fine; one older than 45 s (or from before a 24-day wrap) is not
  if (age < 0 && age > -1000) age = 0;
  if (age < 0 || age > 45000) return false;
  float d = o.powerW - s.curPw[k];
  if (d < 0) d = -d;
  return d <= s.curPw[k] * 0.15f + 10.0f;
}
// shown to the user and used by rules: the real current when there is one, else the estimate
float outletAmps(const Strip& s, int k, float volts, uint32_t now) {
  if (!s.o[k].on) return 0;
  return curValid(s, k, now) ? s.curA[k] : s.o[k].powerW / volts;
}
// used by the protections: never lower than the estimate
float outletAmpsMax(const Strip& s, int k, float volts, uint32_t now) {
  if (!s.o[k].on) return 0;
  float est = s.o[k].powerW / volts;
  // one reading never decides alone (it may be an inrush spike or a bad sample): the lower of the last two counts
  if (!curValid(s, k, now) || !s.preAt[k] || s.curAt[k] - s.preAt[k] > 60000UL) return est;
  float real = s.curA[k] < s.preA[k] ? s.curA[k] : s.preA[k];
  return real > est ? real : est;
}

// ---------- automations / protections (evaluated after every poll) ----------
void evalStrip(int i) {
  Strip& s = strips[i];
  uint32_t now = millis();
  tripVerify(s);
  float total = 0;
  float volts = (!isnan(s.voltage) && s.voltage > 50) ? s.voltage : 220.0f;
  for (int k = 0; k < 4; k++) {
    Outlet& o = s.o[k];
    total += o.on ? o.powerW : 0;
    float oAmpsEst = o.on ? (o.powerW / volts) : 0;
    float oAmps = o.on ? outletAmpsMax(s, k, volts, now) : 0;        // protections: the real current counts only when it is higher

    // over-temperature protection & near-limit warning
    // 10 °C past the limit cuts on the first reading instead of waiting 30 s
    if (tempProtect && o.on && o.tempC >= tempMax) {
      if (!s.hotSince[k]) s.hotSince[k] = now ? now : 1;
      if (o.tempC >= tempMax + 10 || now - s.hotSince[k] > 30000) {
        protectCut(s, k);
        addEvent("temp", s.mac, k + 1, String(o.tempC) + "°C");
        s.hotSince[k] = 0;
      }
    } else {
      s.hotSince[k] = 0;
    }
    // near temperature limit: 5 °C before tempMax (orange band)
    if (tempProtect && o.on && o.tempC >= tempMax - 5 && o.tempC < tempMax) {
      if (!(s.warnT & (1 << k))) { s.warnT |= (1 << k); addEvent("warn", s.mac, k + 1, String(o.tempC) + "°C (near " + String(tempMax) + "°C)"); }
    } else if (!o.on || o.tempC < tempMax - 8) s.warnT &= ~(1 << k);

    // per-outlet current limit (ampX2 in 0.5 A steps) & near-limit warning
    float oMaxA = s.ampX2[k] ? (s.ampX2[k] * 0.5f) : 0;
    if (oMaxA > 0 && o.on) {
      if (oAmps >= oMaxA) {
        if (!s.ocoSince[k]) s.ocoSince[k] = now ? now : 1;
        if (oAmpsEst >= oMaxA * 1.25f || now - s.ocoSince[k] > (uint32_t)protHoldS * 1000UL) {   // 25 % over cuts at once (estimate only: one reading never cuts alone)
          protectCut(s, k);
          addEvent("overcurrent", s.mac, k + 1, String(oAmps, 1) + " A (max " + String(oMaxA, 1) + " A)");
          s.ocoSince[k] = 0;
        }
      } else s.ocoSince[k] = 0;
      // near current limit (>= 85 %)
      if (oAmps >= oMaxA * 0.85f && oAmps < oMaxA) {
        if (!(s.warnA & (1 << k))) { s.warnA |= (1 << k); addEvent("warn", s.mac, k + 1, String(oAmps, 1) + " A (near " + String(oMaxA, 1) + " A)"); }
      } else if (!o.on || oAmps < oMaxA * 0.75f) s.warnA &= ~(1 << k);
    } else { s.ocoSince[k] = 0; s.warnA &= ~(1 << k); }

    // auto-off
    if (s.autoOffAt[k] && (int32_t)(now - s.autoOffAt[k]) >= 0) {
      s.autoOffAt[k] = 0;
      if (o.on && !(s.keepMask & (1 << k))) {
        sendOnOff(s, k + 1, false);
        addEvent("auto_off", s.mac, k + 1, String(s.autoOffMin[k]) + " min");
      }
    }
  }

  // over-current on the whole strip
  float amps = total / volts;
  float ampsHold = amps, ampsShown = 0, ampsMaxShown = 0;
  { float sumMax = 0; for (int k = 0; k < 4; k++) { sumMax += outletAmpsMax(s, k, volts, now); ampsShown += outletAmps(s, k, volts, now); }
    ampsMaxShown = sumMax;
    if (sumMax > ampsHold) ampsHold = sumMax; }
  if (aProt && ampsHold > aMax) {
    if (!s.ocSince) s.ocSince = now ? now : 1;
    if (amps > aMax * 1.15f || now - s.ocSince > (uint32_t)protHoldS * 1000UL) {            // 15 % over cuts at once (estimate only)
      for (int k = 0; k < 4; k++) if (s.o[k].on && !(s.protMask & (1 << k))) protectCut(s, k);
      addEvent("overcurrent", s.mac, 0, String(ampsHold, 1) + " A");
      s.ocSince = 0;
    }
  } else s.ocSince = 0;

  // strip load limit: one strip never carries more than 3500 W (the stock firmware only warns at 3000 W and
  // cuts at 16 A). After 3 s over (at once when 15 % over), the biggest unprotected loads go first until the rest
  // fits; protected outlets are cut only if they alone keep the strip over the limit.
  if (total > STRIP_MAX_W) {
    if (!s.olSince) s.olSince = now ? now : 1;
    if (total > STRIP_MAX_W * 1.15f || now - s.olSince > (uint32_t)protHoldS * 1000UL) {
      float left = 0;                              // what is still on now (the current cut above may have run)
      String cuts;                                 // the outlets cut, for the event ("2,4")
      for (int k = 0; k < 4; k++) left += s.o[k].on ? s.o[k].powerW : 0;
      for (int pass = 0; pass < 2 && left > STRIP_MAX_W; pass++)
        while (left > STRIP_MAX_W) {
          int big = -1;
          for (int k = 0; k < 4; k++)
            if (s.o[k].on && s.o[k].powerW > 0 && (pass == 1 || !(s.protMask & (1 << k))) && (big < 0 || s.o[k].powerW > s.o[big].powerW)) big = k;
          if (big < 0) break;
          left -= s.o[big].powerW;
          protectCut(s, big);
          cuts += (cuts.length() ? "," : "") + String(big + 1);
        }
      addEvent("overload", s.mac, 0, String((int)total) + " W > " + String((int)STRIP_MAX_W) + " W" + (cuts.length() ? " · o:" + cuts : String("")));
      s.olSince = 0;
    }
  } else s.olSince = 0;
  if (total > 3300 && now - s.loadEventAt > 300000) {
    s.loadEventAt = now;
    addEvent("load", s.mac, 0, String((int)total) + " W");
  }
  int hottest = 0;
  bool anyOn = false;
  for (int k = 0; k < 4; k++) { hottest = max(hottest, s.o[k].tempC); anyOn |= s.o[k].on; }

  // automations: metric 0 W, 1 °C, 2 W or °C, 3 A, 4 V (whole strip only)
  for (int a = 0; a < autoCount; a++) {
    Autom& r = autos[a];
    if (!r.enabled || !s.mac.equalsIgnoreCase(r.mac) || r.outlet > 4) continue;
    float pw, tc, cur;
    bool on;
    if (r.outlet == 0) { pw = total; tc = hottest; cur = r.above ? max(ampsShown, ampsMaxShown) : ampsShown; on = anyOn; }
    else { Outlet& o = s.o[r.outlet - 1]; pw = o.on ? o.powerW : 0; tc = o.tempC; cur = r.above ? max(outletAmps(s, r.outlet - 1, volts, now), outletAmpsMax(s, r.outlet - 1, volts, now)) : outletAmps(s, r.outlet - 1, volts, now); on = o.on; }
    float p = r.metric == 1 ? tc : (r.metric == 3 ? cur : (r.metric == 4 ? s.voltage : pw));
    if (r.metric == 4 && (isnan(s.voltage) || s.voltage < 50)) continue;   // no reading yet (NAN until the first one)
    // a rule is armed from the moment it is saved (and after every reboot), so a load that is already
    // past the limit counts. It fires once, then re-arms when the condition clears or the outlet is switched off.
    // Before, it only armed after the load crossed back first: a heater already above, or an outlet already in
    // standby, never tripped, and every hub reboot (firmware update) disarmed all rules.
    bool clear;
    if (r.metric == 2) { clear = pw < r.watts && tc < r.limit2; if (tc >= r.limit2) p = tc; }   // either limit (watts or temp)
    else clear = r.above ? p < r.watts : p > r.watts;
    if (clear || !on) { autoArmed[a] = true; autoWarned[a] = false; autoSince[a] = 0; autoFiredAt[a] = 0; autoSaid[a] = false; continue; }
    // a rule that switches off keeps acting for as long as its condition holds, with no need to switch it off and on:
    // after it fired it is armed again once its hold time has passed (at least 10 s), so a cut that did not take (a locked
    // or protected outlet, protected outlets that keep a whole-strip load up) is tried again. The alert goes out once per
    // crossing, with the first run; a notify-only rule has nothing to retry and stays once per crossing.
    if (!autoArmed[a] && autoFiredAt[a] && (r.act & 2) && now - autoFiredAt[a] > (uint32_t)max((int)r.holdS * 1000, 10000)) { autoArmed[a] = true; autoSince[a] = 0; }
    bool cond = autoArmed[a];
    // near-threshold warning (color-code alert) before the countdown trips
    if (r.above && autoArmed[a] && on && !autoWarned[a]) {
      float warnAt = r.watts * 0.85f;
      if (r.metric == 1) warnAt = max(r.watts - 5.0f, 40.0f);
      if (r.metric == 4) warnAt = r.watts - 5.0f;
      if (p >= warnAt && p < r.watts) {
        autoWarned[a] = true;
        addEvent("warn", s.mac, r.outlet, String(p, (r.metric == 1 || r.metric == 4) ? 0 : 1) + (r.metric == 1 ? "°C" : (r.metric == 3 ? " A" : (r.metric == 4 ? " V" : " W"))) + " (near " + String(r.watts, (r.metric == 1 || r.metric == 4) ? 0 : 1) + ")");
      }
    }
    if (!cond) { autoSince[a] = 0; continue; }
    if (!autoSince[a]) autoSince[a] = now ? now : 1;
    if (now - autoSince[a] >= (uint32_t)r.holdS * 1000) {
      autoArmed[a] = false;
      autoWarned[a] = false;
      autoSince[a] = 0;
      autoFiredAt[a] = now ? now : 1;
      String cuts;                                 // whole strip: the outlets it switched off ("1,3")
      if (r.act & 2) {
        if (r.outlet == 0) {                       // whole strip: never cut protected outlets (router)
          for (int k = 0; k < 4; k++)
            if (s.o[k].on && !(s.protMask & (1 << k))) { sendOnOffF(s, k + 1, false, true); cuts += (cuts.length() ? "," : "") + String(k + 1); }
        } else sendOnOffF(s, r.outlet, false, true);
      }
      String unit = (r.metric == 1 || (r.metric == 2 && p == tc)) ? " C" : (r.metric == 3 ? " A" : (r.metric == 4 ? " V" : " W"));
      // what was read and the limit it passed ("692 W > 500 W"), the rule's name in front when it has one
      String what = String(p, (unit == " C" || unit == " V") ? 0 : 1) + unit + (r.above ? " > " : " < ") + String(r.metric == 1 ? r.watts : (r.metric == 2 && p == tc ? r.limit2 : r.watts), unit == " A" ? 1 : 0) + unit;
      if (!autoSaid[a]) addEvent("automation", s.mac, r.outlet, (String(r.label).length() ? String(r.label) + " · " : String("")) + what + (cuts.length() ? " · o:" + cuts : String("")));
      autoSaid[a] = true;
    }
  }
}

