import 'package:flutter/material.dart';

/// Egy naptári nap típusa — ez adja a csempe színét a naptárban.
///
/// A magyar munkaszüneti napokat két csoportra bontjuk, mert a felhasználó is
/// külön színt kért rájuk: a három nemzeti ünnep (`holiday`: márc. 15., aug.
/// 20., okt. 23.) és a többi hivatalos pihenőnap (`restDay`: újév, húsvét- és
/// pünkösdhétfő, nagypéntek, május 1., mindenszentek, karácsony). Mind a négy
/// típus puszta naptárszabályból számolható — nincs szükség évente frissülő
/// kormányzati táblázatra.
///
/// ponytail: az áthelyezett munkanapok (dolgozós szombat, hídnap) kimaradnak —
/// azok évente rendeletből jönnek, szabályból nem levezethetők. Egy ilyen
/// szombat itt hétvégeként jelenik meg. Ha kell, ide jöhet egy évenkénti
/// felülíró tábla `{év: {plusz pihenőnapok}, {dolgozós szombatok}}` alakban.
enum DayKind { weekday, weekend, restDay, holiday }

/// Húsvétvasárnap dátuma az adott évben (Meeus/Jones/Butcher Gauss-algoritmus,
/// gregorián naptár). Ebből számoljuk a nagypénteket, húsvét- és pünkösdhétfőt.
DateTime easterSunday(int year) {
  final a = year % 19;
  final b = year ~/ 100;
  final c = year % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31;
  final day = ((h + l - 7 * m + 114) % 31) + 1;
  return DateTime(year, month, day);
}

/// A három nemzeti ünnep az adott évben.
Set<DateTime> _nationalHolidays(int year) => {
  DateTime(year, 3, 15),
  DateTime(year, 8, 20),
  DateTime(year, 10, 23),
};

/// A többi hivatalos munkaszüneti nap. A húsvéthoz kötött napokat a
/// [DateTime] konstruktor normalizálja (nap ± eltolás) — így nincs nyári
/// időszámítás-elcsúszás, ami a `Duration`-os számolást érné.
Set<DateTime> _restDays(int year) {
  final e = easterSunday(year);
  DateTime off(int days) => DateTime(e.year, e.month, e.day + days);
  return {
    DateTime(year, 1, 1),
    off(-2), // nagypéntek
    off(1), // húsvéthétfő
    DateTime(year, 5, 1),
    off(50), // pünkösdhétfő
    DateTime(year, 11, 1),
    DateTime(year, 12, 25),
    DateTime(year, 12, 26),
  };
}

// A 42 csempés rács ugyanabból az évből sokszor kérdez — évenként egyszer
// számolunk, utána a halmazból nézünk.
final _nationalCache = <int, Set<DateTime>>{};
final _restCache = <int, Set<DateTime>>{};

/// Egy nap típusa. Az ünnep megelőzi a hétvégét: a vasárnapra eső március 15.
/// is ünnep marad.
DayKind dayKindOf(DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  if (_nationalCache
      .putIfAbsent(d.year, () => _nationalHolidays(d.year))
      .contains(d)) {
    return DayKind.holiday;
  }
  if (_restCache.putIfAbsent(d.year, () => _restDays(d.year)).contains(d)) {
    return DayKind.restDay;
  }
  if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
    return DayKind.weekend;
  }
  return DayKind.weekday;
}

/// Rövid magyar címke a jelmagyarázathoz.
String dayKindLabel(DayKind kind) => switch (kind) {
  DayKind.weekday => 'Hétköznap',
  DayKind.weekend => 'Hétvége',
  DayKind.restDay => 'Munkaszüneti',
  DayKind.holiday => 'Ünnepnap',
};

/// Egy naptípus színkészlete: halvány háttér a csempének, telített akcent a
/// számnak és a jelmagyarázatnak.
class DayPalette {
  const DayPalette({required this.fill, required this.accent});

  final Color fill;
  final Color accent;
}

// Fix árnyalatok: a naptípus állapotot jelöl, nem díszít — ugyanazt kell
// jelentenie világos és sötét témában is, ezért nem a téma akcentszínéből jön.
const _weekendHue = Color(0xFF2563EB); // kék
const _restHue = Color(0xFF0EA5A0); // türkiz
const _holidayHue = Color(0xFFE11D48); // piros

DayPalette dayPalette(DayKind kind, ThemeData theme) {
  final scheme = theme.colorScheme;
  final dark = theme.brightness == Brightness.dark;
  Color tint(Color c) => c.withValues(alpha: dark ? 0.24 : 0.13);
  // Sötét témában a telített hue elveszne a sötét háttéren — világosítjuk.
  Color ink(Color c) => dark ? Color.lerp(c, Colors.white, 0.35)! : c;

  return switch (kind) {
    DayKind.weekday => DayPalette(
      fill: scheme.surfaceContainerHigh,
      accent: scheme.onSurface,
    ),
    DayKind.weekend => DayPalette(
      fill: tint(_weekendHue),
      accent: ink(_weekendHue),
    ),
    DayKind.restDay => DayPalette(fill: tint(_restHue), accent: ink(_restHue)),
    DayKind.holiday => DayPalette(
      fill: tint(_holidayHue),
      accent: ink(_holidayHue),
    ),
  };
}
