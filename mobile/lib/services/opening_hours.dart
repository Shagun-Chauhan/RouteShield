/// Interpreter for the common subset of the OSM `opening_hours` tag.
///
/// Supported: `24/7`, day lists/ranges (`Mo-Fr`, `Sa,Su`, wrapping `Sa-Mo`), one or more time
/// ranges per rule (`09:00-13:00,14:00-18:00`), overnight ranges (`18:00-02:00`), `off`/`closed`,
/// `;`-separated rules where later rules override earlier ones for the same days.
/// `PH` (public holiday) rules are recognised but not evaluated: the result is flagged uncertain.
///
/// NOT supported (parse returns null => "hours unavailable", never a guess): months/dates,
/// week numbers, sunrise/sunset, `+` open-ended times, comments, `||` fallbacks, school holidays.
///
/// A missing, empty or unparseable tag never yields "open". The status describes the *published
/// schedule*; OSM cannot confirm that a place is physically operating right now.
enum OpenState { open, closed, unknown }

class OpenStatus {
  final OpenState state;
  final String label; // e.g. "Open now · closes 21:00"
  final bool uncertain; // true when public-holiday rules exist but were not evaluated
  const OpenStatus(this.state, this.label, {this.uncertain = false});
  static const unavailable = OpenStatus(OpenState.unknown, 'Opening hours unavailable');
}

class OpeningHours {
  OpeningHours._(this._days, this.uncertain);
  // Index 0 = Monday ... 6 = Sunday. Intervals are minutes from 00:00; end may exceed 1440 (overnight).
  final List<List<(int, int)>> _days;
  final bool uncertain;

  static const _dayNames = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
  static const _dayLong = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static final _unsupported = RegExp(
      r'''["\[\]+]|sunrise|sunset|dawn|dusk|week|easter|\|\||\bSH\b|\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\b|\b(19|20)\d\d\b|\bopen\b|\bunknown\b''',
      caseSensitive: false);
  static final _daySel = RegExp(
      r'^((?:Mo|Tu|We|Th|Fr|Sa|Su|PH)(?:-(?:Mo|Tu|We|Th|Fr|Sa|Su))?(?:\s*,\s*(?:Mo|Tu|We|Th|Fr|Sa|Su|PH)(?:-(?:Mo|Tu|We|Th|Fr|Sa|Su))?)*)\s*(.*)$');
  static final _time = RegExp(r'^(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})$');

  static OpeningHours? parse(String? raw) {
    if (raw == null) return null;
    final text = raw.trim();
    if (text.isEmpty || _unsupported.hasMatch(text)) return null;
    final days = List.generate(7, (_) => <(int, int)>[]);
    var uncertain = false;
    if (text == '24/7') {
      for (final d in days) {
        d.add((0, 1440));
      }
      return OpeningHours._(days, false);
    }

    for (final ruleRaw in text.split(';')) {
      final rule = ruleRaw.trim();
      if (rule.isEmpty) continue;
      var selector = '';
      var spec = rule;
      final m = _daySel.firstMatch(rule);
      if (m != null) {
        selector = m.group(1)!;
        spec = m.group(2)!.trim();
      }

      // Which weekdays does the rule cover?
      final target = <int>{};
      var hasPh = false;
      if (selector.isEmpty) {
        target.addAll(List.generate(7, (i) => i));
      } else {
        for (final part in selector.split(',')) {
          final p = part.trim();
          if (p == 'PH') {
            hasPh = true;
            continue;
          }
          final bits = p.split('-');
          final a = _dayNames.indexOf(bits[0]);
          final b = bits.length > 1 ? _dayNames.indexOf(bits[1]) : a;
          if (a < 0 || b < 0) return null;
          for (var i = a;; i = (i + 1) % 7) {
            target.add(i);
            if (i == b) break;
          }
        }
      }
      if (hasPh) uncertain = true;
      if (target.isEmpty) continue; // PH-only rule: noted as uncertain, otherwise ignored

      final lower = spec.toLowerCase();
      if (lower == 'off' || lower == 'closed') {
        for (final d in target) {
          days[d].clear();
        }
        continue;
      }
      if (lower == '24/7' || (spec == '00:00-24:00')) {
        for (final d in target) {
          days[d]
            ..clear()
            ..add((0, 1440));
        }
        continue;
      }
      if (spec.isEmpty) return null;
      final ranges = <(int, int)>[];
      for (final t in spec.split(',')) {
        final tm = _time.firstMatch(t.trim());
        if (tm == null) return null;
        final h1 = int.parse(tm.group(1)!), m1 = int.parse(tm.group(2)!);
        final h2 = int.parse(tm.group(3)!), m2 = int.parse(tm.group(4)!);
        if (h1 > 24 || h2 > 24 || m1 > 59 || m2 > 59) return null;
        final start = h1 * 60 + m1;
        var end = h2 * 60 + m2;
        if (start == end) return null;
        if (end < start) end += 1440; // overnight
        ranges.add((start, end));
      }
      ranges.sort((a, b) => a.$1.compareTo(b.$1));
      for (final d in target) {
        days[d]
          ..clear()
          ..addAll(ranges);
      }
    }
    return OpeningHours._(days, uncertain);
  }

  static String _fmt(int minutes) {
    final m = minutes % 1440;
    return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }

  /// [now] must already be expressed in the place's local time. The app only knows the device's
  /// timezone (no tz database is bundled), so callers pass device-local time and the UI says so.
  OpenStatus status(DateTime now) {
    final note = uncertain ? ' (public-holiday hours may differ)' : '';
    final wd = now.weekday - 1;
    final minute = now.hour * 60 + now.minute;

    // Currently open? Check today's intervals and last night's overnight spill.
    int? closesAt;
    for (final (s, e) in _days[wd]) {
      if (minute >= s && minute < e) {
        closesAt = e;
        break;
      }
    }
    if (closesAt == null) {
      for (final (_, e) in _days[(wd + 6) % 7]) {
        if (e > 1440 && minute < e - 1440) {
          closesAt = e - 1440;
          break;
        }
      }
    }
    if (closesAt != null) {
      // Follow continuous opening past midnight (e.g. 08:00-24:00 then 00:00-02:00 next day).
      var day = wd;
      var end = closesAt;
      var hops = 0;
      while (end >= 1440 && hops < 7) {
        final nextDay = (day + 1) % 7;
        final cont = _days[nextDay].where((r) => r.$1 == 0);
        if (cont.isEmpty) break;
        end = cont.first.$2;
        day = nextDay;
        hops++;
      }
      if (hops >= 7) return OpenStatus(OpenState.open, 'Open 24 hours$note', uncertain: uncertain);
      return OpenStatus(OpenState.open, 'Open now · closes ${_fmt(end)}$note', uncertain: uncertain);
    }

    for (var off = 0; off <= 7; off++) {
      final d = (wd + off) % 7;
      for (final (s, _) in _days[d]) {
        if (off == 0 && s <= minute) continue;
        final when = off == 0 ? '' : off == 1 ? 'tomorrow ' : '${_dayLong[d]} ';
        return OpenStatus(OpenState.closed, 'Closed now · opens $when${_fmt(s)}$note', uncertain: uncertain);
      }
    }
    return OpenStatus(OpenState.closed, 'Closed now$note', uncertain: uncertain);
  }

  /// Convenience: parse + evaluate. Missing or unreadable hours => unknown, never open.
  static OpenStatus statusOf(String? raw, DateTime now) => parse(raw)?.status(now) ?? OpenStatus.unavailable;
}
