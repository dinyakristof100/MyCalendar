import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cloud_sync.dart';
import '../../core/prefs.dart';

const _plansKey = 'workoutPlans';
const _activeKey = 'activeWorkoutPlan';

/// A [day]-t tartalmazó hét hétfője, éjfélkor. A hét a teljesítések
/// nyilvántartásának egysége: vasárnap éjfélkor minden pipa lenullázódik.
DateTime weekStartOf(DateTime day) =>
    DateTime(day.year, day.month, day.day - (day.weekday - 1));

/// 2024. január 1. hétfő volt — innen számoljuk a hetek paritását.
final _epochMonday = DateTime(2024);

/// Melyik hét van soron [weeks] darab hétből: sima tervnél mindig a 0., A/B
/// tervnél a naptári hetek felváltva.
///
/// ponytail: a paritás a naptárból jön, nem tárolt állapotból — így nincs mit
/// elrontani vagy szinkronban tartani. Ha valakinek pont fordítva kell az A és
/// a B hét, majd kap egy cserélő gombot.
int weekIndexOf(DateTime day, {required int weeks}) => weeks == 1
    ? 0
    : (weekStartOf(day).difference(_epochMonday).inDays ~/ 7) % weeks;

/// Egy heti edzésterv.
///
/// A napok nincsenek a hét napjaihoz kötve: `weeks[hét][n]` az n+1. edzésnap
/// tartalma ("mell, tricepsz, vádli"). Ha valaki csúszik egy napot, a terv
/// attól még ugyanaz — ezért nem hétfő/szerda, hanem 1./2. nap.
///
/// Egy hét = sima heti terv, két hét = A és B hét.
class WorkoutPlan {
  const WorkoutPlan({
    required this.id,
    required this.name,
    required this.weeks,
  });

  final String id;
  final String name;
  final List<List<String>> weeks;

  bool get hasBWeek => weeks.length > 1;
  int get daysPerWeek => weeks.first.length;

  /// A [day] hetére eső napok (A/B tervnél a soron következő hét napjai).
  List<String> daysOfWeekAt(DateTime day) =>
      weeks[weekIndexOf(day, weeks: weeks.length)];

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'weeks': weeks};

  static WorkoutPlan fromJson(Map<String, Object?> json) => WorkoutPlan(
    id: json['id']! as String,
    name: json['name']! as String,
    weeks: [
      for (final week in json['weeks']! as List)
        [for (final day in week as List) day as String],
    ],
  );
}

/// A mentett tervek és az, hogy melyik az aktív.
class WorkoutPlans {
  const WorkoutPlans({required this.plans, this.activeId});

  final List<WorkoutPlan> plans;
  final String? activeId;

  /// Az aktív terv. Ha a mentett azonosítóhoz nincs terv (pl. törölték), az
  /// első tervre esik vissza — így sosem marad üres a képernyő fölöslegesen.
  WorkoutPlan? get active {
    for (final plan in plans) {
      if (plan.id == activeId) return plan;
    }
    return plans.isEmpty ? null : plans.first;
  }
}

final workoutPlansProvider =
    NotifierProvider<WorkoutPlansController, WorkoutPlans>(
      WorkoutPlansController.new,
    );

class WorkoutPlansController extends Notifier<WorkoutPlans> {
  @override
  WorkoutPlans build() => WorkoutPlans(
    plans: [
      for (final raw in jsonDecode(prefs.getString(_plansKey) ?? '[]') as List)
        WorkoutPlan.fromJson((raw as Map).cast<String, Object?>()),
    ],
    activeId: prefs.getString(_activeKey),
  );

  /// Az új terv egyből az aktív lesz — aki most vitte fel, arra kíváncsi.
  Future<void> add(WorkoutPlan plan) async {
    state = WorkoutPlans(plans: [...state.plans, plan], activeId: plan.id);
    await _save();
    await saveSetting(_activeKey, plan.id);
  }

  /// Meglévő terv felülírása (név, hetek típusa, napok). Az azonosító marad, így
  /// a heti haladás is a tervnél marad — a napok számának változását a
  /// `settleWeek` kezeli.
  Future<void> update(WorkoutPlan plan) async {
    state = WorkoutPlans(
      plans: [
        for (final p in state.plans)
          if (p.id == plan.id) plan else p,
      ],
      activeId: state.activeId,
    );
    await _save();
  }

  /// Terv törlése. Ha az aktívat törlik, a maradék első terve lép a helyére —
  /// üres listánál nincs aktív.
  Future<void> remove(String id) async {
    final plans = [
      for (final p in state.plans)
        if (p.id != id) p,
    ];
    final active = state.activeId == id
        ? (plans.isEmpty ? null : plans.first.id)
        : state.activeId;
    state = WorkoutPlans(plans: plans, activeId: active);
    await _save();
    await saveSetting(_activeKey, active ?? '');
  }

  Future<void> setActive(String id) async {
    state = WorkoutPlans(plans: state.plans, activeId: id);
    await saveSetting(_activeKey, id);
  }

  Future<void> _save() => saveSetting(
    _plansKey,
    jsonEncode([for (final p in state.plans) p.toJson()]),
  );
}
