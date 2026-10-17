import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/strip_card.dart';

/// 2.0.27: everything the native strip widget draws, with the same colors the app uses
/// (load ring, temperature, volts, Wi-Fi arcs, the badges above each outlet).
String hexOf(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

List<List<Object>> _badges(AppState state, Strip s, Outlet? o) {
  final n = o?.n ?? 0;
  final out = <List<Object>>[];
  void add(IconData i, Color c) => out.add([i.codePoint, hexOf(c)]);
  if (o == null) {
    if (state.requiresBio(s.mac, 0)) add(Icons.fingerprint, C.accent);
    if (s.masterLock) add(Icons.lock, C.muted);
    return out;
  }
  if (o.hasSchedule) add(Icons.schedule, C.accent2);
  if (o.hasRule) add(Icons.bolt, C.warn);
  for (final x in state.timersFor(s.mac).where((x) => x.outlet == n)) {
    add(timerIcon(x), C.accent);
  }
  if (o.autoOffMin > 0) add(Icons.timer_outlined, C.accent);
  if (o.protected) add(Icons.shield, C.accent);
  if (o.keepOn) add(Icons.push_pin_outlined, C.accent);
  if (state.requiresBio(s.mac, o.n)) add(Icons.fingerprint, C.accent);
  if (o.locked) add(Icons.lock, C.muted);
  return out;
}

Map<String, dynamic> stripWidgetJson(AppState state, Strip s) {
  final online = s.online;
  final can = state.canControl;
  final canProt = state.can(Perm.prot);
  final stripLevel = s.maxTemp >= 60 ? 3 : loadLevel(s.livePower, kStripMaxW);
  final tone = stripLevel == 0 ? C.accent : levelColor(stripLevel);
  int? wifiLvl;
  Color wifiC = C.faint;
  final r = s.rssi;
  if (r != null) {
    if (r >= -55) {
      wifiLvl = 3;
      wifiC = levelColor(0);
    } else if (r >= -67) {
      wifiLvl = 2;
      wifiC = levelColor(1);
    } else if (r >= -75) {
      wifiLvl = 1;
      wifiC = levelColor(2);
    } else {
      wifiLvl = 0;
      wifiC = levelColor(3);
    }
  }
  final allOn = s.onCount == 4, allOff = s.onCount == 0;
  final mixed = !allOn && !allOff;
  final mOn = online && (allOn || mixed);
  final mLevel = loadLevel(s.livePower, kStripMaxW);
  final mHot = s.maxTemp >= 60;
  final mRing = mHot ? C.danger : levelColor(mLevel);
  return {
    'tone': hexOf(online && s.onCount > 0 ? tone : C.cardEdge),
    'toneA': online && s.onCount > 0 ? 0.30 : 1.0,
    'wifi': wifiLvl ?? -1,
    'wifiC': hexOf(wifiC),
    'sub': online ? t('n_of_4', {'a': s.onCount, 'b': s.outlets.length}) : t('offline_kept'),
    'subC': hexOf(online ? C.textSoft : C.danger),
    'tc': hexOf(tempColor(s.maxTemp)),
    'v': online && s.voltage != null ? '${s.voltage!.toStringAsFixed(0)} V' : '',
    'vc': hexOf(s.voltage != null ? voltColor(s.voltage!) : C.faint),
    'wc': hexOf(online ? loadColor(s.livePower, kStripMaxW) : C.faint),
    'amps': online && s.voltage != null && s.voltage! > 0 ? '${s.liveAmps(s.voltage!).toStringAsFixed(2)}A' : '',
    'pwr': Icons.power_settings_new.codePoint,
    'm': {
      'on': mOn,
      'mixed': mixed,
      'load': mOn ? (s.livePower / kStripMaxW).clamp(0.0, 1.0) : 0.0,
      'rc': hexOf(mRing),
      'halo': hexOf(mLevel == 0 && !mHot ? C.accent : mRing),
      'lbl': allOn ? t('master_all_on') : (allOff ? t('master_all_off') : t('master_n_of_4', {'a': s.onCount})),
      'b': _badges(state, s, null),
      'lock': !can || state.requiresBio(s.mac, 0),
    },
    'outs': [
      for (final o in s.outlets) _outlet(state, s, o, can, canProt),
    ],
  };
}

Map<String, dynamic> _outlet(AppState state, Strip s, Outlet o, bool can, bool canProt) {
  final on = s.online && o.on;
  final amps = o.amps(s.voltage);
  final ampWarn = o.ampLimit > 0 && amps >= o.ampLimit * 0.85;
  final tempWarn = o.tempC >= 55;
  final base = loadLevel(o.powerW, kOutletMaxW);
  final lvl = (ampWarn || tempWarn) ? math.max(base, 2) : base;
  final hot = o.tempC >= 60 || (o.ampLimit > 0 && amps >= o.ampLimit);
  final bio = state.requiresBio(s.mac, o.n);
  final blocked = !can || (o.protected && !canProt) || bio;
  return {
    'n': o.n,
    'name': state.outletName(s, o.n),
    'on': on,
    'w': o.powerW,
    'load': on ? (o.powerW / kOutletMaxW).clamp(0.0, 1.0) : 0.0,
    'rc': hexOf(hot ? C.danger : levelColor(lvl)),
    'wc': hexOf(loadColor(o.powerW, kOutletMaxW)),
    't': o.tempC,
    'tc': hexOf(tempColor(o.tempC)),
    'b': _badges(state, s, o),
    // the widget switches it only when the app would without asking anything
    'lockOn': blocked,
    'lockOff': blocked || o.keepOn || o.protected,
  };
}

String widgetWord(String ar, String en) => Tr.isAr ? ar : en;
