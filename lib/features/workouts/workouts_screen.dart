import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scaffold.dart';
import '../../core/ui.dart';
import 'motivation.dart';
import 'streak.dart';
import 'workout_plans.dart';
import 'workout_progress.dart';

/// A kipipált edzés jelzése. Fix zöld, nem a téma akcentszíne: a "kész" itt
/// nem díszítés, hanem állapot — ugyanazt kell jelentenie világos és sötét
/// témában is.
const _done = Color(0xFF2E7D32);

class WorkoutsScreen extends ConsumerWidget {
  const WorkoutsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workoutPlansProvider);
    final plan = state.active;

    return AppScaffold(
      title: 'Edzésnapló',
      floatingActionButton: plan == null
          ? null
          : FloatingActionButton(
              tooltip: 'Új edzésterv',
              onPressed: () => context.push('/workouts/new'),
              child: const Icon(Icons.add),
            ),
      body: plan == null
          ? const _NoPlanYet()
          : _PlanView(plans: state.plans, plan: plan),
    );
  }
}

/// Az első indulás: terv nélkül az edzésnaplónak nincs miről beszélnie.
class _NoPlanYet extends StatelessWidget {
  const _NoPlanYet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A görgetés a KÖZÉPRE igazítás alatt van: rövid tartalomnál a görgetőnézet
    // a tartalom méretét veszi fel, tehát középen marad; kis kijelzőn viszont
    // görgethetővé válik ahelyett, hogy kifutna. (Fordított sorrendben mindig a
    // képernyő tetejére tapadna.)
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(40, 24, 40, 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.fitness_center,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Még nincs edzésterved',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Add meg, hány napot edzel egy héten, és mi kerül az egyes '
              'napokra.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () => context.push('/workouts/new'),
              icon: const Icon(Icons.add),
              label: const Text('Edzésterv létrehozása'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanView extends ConsumerWidget {
  const _PlanView({required this.plans, required this.plan});

  final List<WorkoutPlan> plans;
  final WorkoutPlan plan;

  /// Terv törlése megerősítéssel. A heti haladás a tervhez tartozik, ezért vele
  /// együtt nullázódik — ezt előre meg is mondjuk.
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edzésterv törlése'),
        content: Text(
          '„${plan.name}" törlődik, a heti haladásával együtt. '
          'A többi terved megmarad.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Mégsem'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Törlés'),
          ),
        ],
      ),
    );
    if (yes ?? false) {
      await ref.read(workoutPlansProvider.notifier).remove(plan.id);
    }
  }

  /// Hosszú nyomásra kérdez: görgetés közben könnyű véletlenül eltalálni egy
  /// kártyát, ezért egy edzés lezárása mindig megerősítést kér. Kimenetek:
  /// megvolt, szándékosan kihagyva (nem húzzuk át), lezárt napnál visszaállítás
  /// nyitottra, vagy mégsem.
  ///
  /// A `null` kimenet (nyitott nap) és a „mégsem" nem ugyanaz, ezért a válasz
  /// egyelemű rekordba csomagolva jön: `null` = mégsem, `(null,)` = nyitottra.
  Future<(WorkoutOutcome?,)?> _ask(
    BuildContext context,
    String label,
    String content, {
    required bool resolved,
  }) {
    return showDialog<(WorkoutOutcome?,)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mi lett ezzel a nappal?'),
        content: Text('$label — $content'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Mégsem'),
          ),
          if (resolved)
            TextButton(
              onPressed: () => Navigator.pop(context, (null,)),
              child: const Text('Visszaállítás'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, (WorkoutOutcome.skipped,)),
            child: const Text('Kihagyom'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, (WorkoutOutcome.done,)),
            child: const Text('Megvolt'),
          ),
        ],
      ),
    );
  }

  /// Megkérdi a kimenetet, elmenti, majd visszajelez: leedzésre motiváció (a hét
  /// utolsó edzése külön ünneplést kap), kihagyásra és visszaállításra rövid
  /// nyugtázás.
  Future<void> _mark(
    BuildContext context,
    WidgetRef ref,
    String label,
    String content, {
    required bool resolved,
    required Future<void> Function(WorkoutOutcome?) apply,
  }) async {
    final answer = await _ask(context, label, content, resolved: resolved);
    if (answer == null) return;
    final outcome = answer.$1;
    // Egyetlen rezgés az egész appban: a leedzett nap az, ami megérdemli.
    if (outcome == WorkoutOutcome.done) HapticFeedback.mediumImpact();
    await apply(outcome);
    if (!context.mounted) return;

    // A sorozatot az `apply` már frissítette (ha teljes lett a hét) — a friss
    // értéket olvassuk, hogy a dicséret is kiírhassa.
    final now = DateTime.now();
    final week = ref.read(currentWeekProvider);
    final message = switch (outcome) {
      WorkoutOutcome.done => praiseFor(
        done: week.trainedCount(plan),
        total: week.targetCount(plan),
        day: now,
        streak: ref.read(streakProvider).live(now),
        spin: motivationSpin.value,
      ),
      WorkoutOutcome.skipped =>
        'Kihagyva — ezt a napot nem hozzuk át a jövő hétre.',
      null => 'Visszaállítva — a nap újra nyitott.',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final thisWeek = weekIndexOf(now, weeks: plan.weeks.length);
    final week = ref.watch(currentWeekProvider);
    final target = week.targetCount(plan);
    final trained = week.trainedCount(plan);
    final skipped = week.skippedCount(plan);
    final streakState = ref.watch(streakProvider);
    final streak = streakState.live(now);
    var slot = 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
      children: [
        // Tervválasztó csak akkor, ha van miből választani.
        if (plans.length > 1) ...[
          Wrap(
            spacing: 8,
            children: [
              for (final option in plans)
                ChoiceChip(
                  label: Text(option.name),
                  selected: option.id == plan.id,
                  onSelected: (_) => ref
                      .read(workoutPlansProvider.notifier)
                      .setActive(option.id),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        Appear(
          index: slot++,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  plan.name,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              PopupMenuButton<bool>(
                tooltip: 'A terv műveletei',
                itemBuilder: (_) => const [
                  PopupMenuItem(value: true, child: Text('Terv szerkesztése')),
                  PopupMenuItem(value: false, child: Text('Terv törlése')),
                ],
                onSelected: (edit) => edit
                    ? context.push('/workouts/edit/${plan.id}')
                    : _confirmDelete(context, ref),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${plan.hasBWeek ? 'A és B hét' : 'Sima heti terv'} · ezen a héten '
          '$trained/$target megvan'
          '${skipped > 0 ? ' · $skipped kihagyva' : ''}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: trained >= target
                ? _done
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (streak > 0) ...[
          const SizedBox(height: 10),
          _StreakPill(weeks: streak),
        ],
        if (streakState.completedWeeks.isNotEmpty) ...[
          const SizedBox(height: 10),
          _WeekDots(done: streakState.lastWeeks(now, 12), thisWeek: now),
        ],
        const SizedBox(height: 14),
        Appear(
          index: slot++,
          child: _MotivationCard(
            fullyTrained: week.fullyTrained(plan),
            resolved: week.resolvedAll(plan),
            skipped: skipped,
            streak: streak,
          ),
        ),
        for (var w = 0; w < plan.weeks.length; w++) ...[
          if (plan.hasBWeek)
            _WeekHeader(
              label: '${w == 0 ? 'A' : 'B'} HÉT',
              isThisWeek: w == thisWeek,
            )
          else
            const SizedBox(height: 14),
          for (var day = 0; day < plan.weeks[w].length; day++)
            Appear(
              index: slot++,
              child: _DayCard(
                label: '${day + 1}. NAP',
                content: plan.weeks[w][day],
                done: w == thisWeek && week.done.contains(day),
                skipped: w == thisWeek && week.skipped.contains(day),
                // Csak az aktuális hét pipálható — a lezárt nap is, hogy a
                // félrenyomott pipa visszavonható legyen.
                onLongPress: w == thisWeek
                    ? () => _mark(
                        context,
                        ref,
                        '${day + 1}. nap',
                        plan.weeks[w][day],
                        resolved:
                            week.done.contains(day) ||
                            week.skipped.contains(day),
                        apply: (outcome) => ref
                            .read(workoutProgressProvider.notifier)
                            .markBase(plan, day, outcome),
                      )
                    : null,
              ),
            ),
        ],
        if (week.carried.isNotEmpty) ...[
          const _CarriedHeader(),
          for (var i = 0; i < week.carried.length; i++)
            Appear(
              index: slot++,
              child: _DayCard(
                label: 'ÁTHOZOTT',
                content: week.carried[i].content,
                done: week.carried[i].done,
                skipped: week.carried[i].resolved && !week.carried[i].done,
                onLongPress: () => _mark(
                  context,
                  ref,
                  'Áthozott nap',
                  week.carried[i].content,
                  resolved: week.carried[i].resolved,
                  apply: (outcome) => ref
                      .read(workoutProgressProvider.notifier)
                      .markCarried(plan, i, outcome),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// A „lite" gondolkodtató, illetve a hét zárása. Amíg van nyitott nap, párban
/// mutatja, mit nyersz és mit veszítesz. Ha minden edzés megvan, zöld
/// gratuláció; ha a hét lezárt, de volt kihagyott nap, halkabb nyugtázás.
///
/// Mindhárom szöveg a [motivationSpin]-re van kötve: az edzésnapló minden
/// megnyitása másikat hoz elő. A fül a héjban életben marad, ezért a szülő
/// képernyő nem épül újra magától — a feliratkozás itt, a kártyában van.
class _MotivationCard extends StatelessWidget {
  const _MotivationCard({
    required this.fullyTrained,
    required this.resolved,
    required this.skipped,
    required this.streak,
  });

  final bool fullyTrained;
  final bool resolved;
  final int skipped;
  final int streak;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: motivationSpin,
    builder: (context, spin, _) => _build(context, spin),
  );

  Widget _build(BuildContext context, int spin) {
    final theme = Theme.of(context);
    final today = DateTime.now();

    if (fullyTrained) {
      return _Banner(
        color: _done,
        icon: Icons.emoji_events_outlined,
        text: weekCompleteFor(today, streak: streak, spin: spin),
      );
    }

    if (resolved) {
      return _Banner(
        color: theme.colorScheme.onSurfaceVariant,
        icon: Icons.check_circle_outline,
        text: weekClosedFor(today, skipped: skipped, spin: spin),
      );
    }

    final reflection = reflectionFor(today, spin: spin);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: cardSurface(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MIÉRT ÉRI MEG MA?',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          _ReflectionLine(
            icon: Icons.trending_up,
            color: _done,
            text: reflection.gain,
          ),
          const SizedBox(height: 8),
          _ReflectionLine(
            icon: Icons.trending_down,
            color: theme.colorScheme.error,
            text: reflection.cost,
          ),
        ],
      ),
    );
  }
}

/// A hét összegző sávja (kész / lezárva) — a helye ilyenkor sem tűnik el, hogy
/// a lista ne ugráljon.
class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.text});

  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A heti sorozat jelvénye a fejlécben — csak akkor látszik, ha van élő sorozat.
class _StreakPill extends StatelessWidget {
  const _StreakPill({required this.weeks});

  final int weeks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔥', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              '$weeks hét zsinórban',
              style: theme.textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Az utolsó hetek hőtérképe: egy pötty hetente, teljesült = akcentszín. A
/// [done] a mai héttel kezdve visszafelé jön, a sor jobb széle a mai hét.
class _WeekDots extends StatelessWidget {
  const _WeekDots({required this.done, required this.thisWeek});

  final List<bool> done;
  final DateTime thisWeek;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final monday = weekStartOf(thisWeek);
    return Row(
      children: [
        for (var i = done.length - 1; i >= 0; i--)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Tooltip(
              message: _label(
                DateTime(monday.year, monday.month, monday.day - 7 * i),
                done[i],
              ),
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done[i]
                      ? scheme.primary
                      : scheme.outlineVariant.withValues(alpha: 0.5),
                  border: i == 0
                      ? Border.all(color: scheme.onSurfaceVariant, width: 1.5)
                      : null,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _label(DateTime monday, bool done) =>
      '${monday.month.toString().padLeft(2, '0')}. '
      '${monday.day.toString().padLeft(2, '0')}. heti — '
      '${done ? 'megvolt' : 'kimaradt'}';
}

class _ReflectionLine extends StatelessWidget {
  const _ReflectionLine({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
          ),
        ),
      ],
    );
  }
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader({required this.label, required this.isThisWeek});

  final String label;
  final bool isThisWeek;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 22, 0, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isThisWeek
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            isThisWeek ? '$label · EZ A HÉT' : label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: isThisWeek
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Az áthozott napok szekció fejléce — a múlt hétről itt gyűlnek össze a
/// nyitva maradt edzések.
class _CarriedHeader extends StatelessWidget {
  const _CarriedHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 26, 0, 6),
      child: Row(
        children: [
          Icon(
            Icons.history,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            'ÁTHOZVA A MÚLT HÉTRŐL',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.label,
    required this.content,
    required this.done,
    required this.skipped,
    required this.onLongPress,
  });

  final String label;
  final String content;
  final bool done;
  final bool skipped;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: AppCard(
        decoration: done
            ? BoxDecoration(
                color: _done.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: _done.withValues(alpha: 0.55)),
              )
            : skipped
            ? BoxDecoration(
                color: muted.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: muted.withValues(alpha: 0.35)),
              )
            : cardSurface(theme),
        child: InkWell(
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 18, 17),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        skipped ? '$label · KIHAGYVA' : label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: done
                              ? _done
                              : skipped
                              ? muted
                              : theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        content,
                        style: theme.textTheme.titleMedium?.copyWith(
                          height: 1.25,
                          color: skipped ? muted : null,
                          decoration: skipped
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                if (done) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.check_circle, color: _done),
                ] else if (skipped) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.do_not_disturb_on_outlined, color: muted),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
