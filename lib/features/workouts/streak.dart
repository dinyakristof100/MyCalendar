import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cloud_sync.dart';
import '../../core/prefs.dart';
import 'workout_plans.dart';

const _key = 'workoutStreak';

/// Az előző hét hétfője. Napkonstruktorral, NEM `subtract(Duration)`-rel: a
/// nyári időszámítás váltásakor a Duration-kivonás 23:00-ra csúszna, és a
/// hétfő-éjfél összehasonlítás elhasalna (ugyanaz a DST-csapda, mint az egész
/// napos eseményeknél).
DateTime _prevWeek(DateTime weekStart) =>
    DateTime(weekStart.year, weekStart.month, weekStart.day - 7);

/// A heti sorozat tárolt állapota: hány hét zsinórban, és melyik hét (hétfője)
/// volt az utolsó beszámított. Csak nő (hét teljesítésekor); a megszakadást nem
/// tároljuk 0-ként, hanem a [live] számolja ki olvasáskor a mai héthez képest —
/// így egy hét kihagyása nem igényel „takarító" írást.
class Streak {
  const Streak({this.weeks = 0, this.lastWeek});

  final int weeks;
  final DateTime? lastWeek;

  /// Egy teljesített hetet ([weekStart] hétfővel) beszámít. Idempotens: ha ez a
  /// hét már benne van, ugyanezt adja vissza. Ha az előző hét volt az utolsó
  /// beszámított, folytatja a sorozatot; különben újat kezd 1-től.
  Streak advance(DateTime weekStart) {
    if (lastWeek == weekStart) return this;
    return Streak(
      weeks: lastWeek == _prevWeek(weekStart) ? weeks + 1 : 1,
      lastWeek: weekStart,
    );
  }

  /// Egy korábban beszámított hét visszavonása (a felhasználó visszavont egy
  /// pipát, így a hét már nem teljes). Csak az utoljára beszámított hetet lehet
  /// visszavonni — régebbire nyúlni nincs mihez, azt a [live] úgyis lezárja.
  Streak revoke(DateTime weekStart) {
    if (lastWeek != weekStart) return this;
    return weeks > 1
        ? Streak(weeks: weeks - 1, lastWeek: _prevWeek(weekStart))
        : const Streak();
  }

  /// A ténylegesen élő sorozat [now]-kor. Ha a legutóbb beszámított hét nem a
  /// mai vagy a közvetlen előző hét, akkor egy teljes hét kimaradt → 0.
  int live(DateTime now) {
    final last = lastWeek;
    if (last == null) return 0;
    final thisWeek = weekStartOf(now);
    return (last == thisWeek || last == _prevWeek(thisWeek)) ? weeks : 0;
  }

  Map<String, Object?> toJson() => {
    'weeks': weeks,
    'lastWeek': lastWeek?.toIso8601String(),
  };

  static Streak fromJson(Map<String, Object?> json) => Streak(
    weeks: (json['weeks'] as int?) ?? 0,
    lastWeek: DateTime.tryParse(json['lastWeek'] as String? ?? ''),
  );
}

final streakProvider = NotifierProvider<StreakController, Streak>(
  StreakController.new,
);

class StreakController extends Notifier<Streak> {
  @override
  Streak build() {
    final raw = prefs.getString(_key);
    return raw == null
        ? const Streak()
        : Streak.fromJson(jsonDecode(raw) as Map<String, Object?>);
  }

  /// Egy hét teljesült ([weekStart] hétfővel) — beszámítja a sorozatba és menti
  /// (helyben + a `saveSetting`-en át a felhőbe is). Idempotens: ha nem változik
  /// semmi (ugyanaz a hét újra), nem ír.
  Future<void> recordCompletion(DateTime weekStart) async {
    final next = state.advance(weekStart);
    if (identical(next, state)) return;
    state = next;
    await saveSetting(_key, jsonEncode(next.toJson()));
  }

  /// A [weekStart] hét visszavonása: ha ez a hét volt az utolsó beszámított, de
  /// egy nap pipáját visszavonták, a hét már nem teljes — lekerül a sorozatból.
  /// Más hétre nem nyúl.
  Future<void> revokeCompletion(DateTime weekStart) async {
    final next = state.revoke(weekStart);
    if (identical(next, state)) return;
    state = next;
    await saveSetting(_key, jsonEncode(next.toJson()));
  }
}
