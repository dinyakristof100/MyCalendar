import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scaffold.dart';
import 'workout_plans.dart';

const _maxDays = 7;

/// Edzésterv felvitele vagy szerkesztése: típus → heti edzésnapok száma → mi
/// kerül az egyes napokra.
///
/// [planId] megadva a meglévő tervet írja felül (azonos azonosítóval), egyébként
/// újat hoz létre.
///
/// ponytail: egyetlen görgethető űrlap, nem lépésenkénti varázsló. A sorrend
/// ugyanaz, a kérdések egymás alatt látszanak, és nincs mögötte lépés-állapot,
/// amit karban kellene tartani.
class PlanFormScreen extends ConsumerStatefulWidget {
  const PlanFormScreen({this.planId, super.key});

  final String? planId;

  @override
  ConsumerState<PlanFormScreen> createState() => _PlanFormScreenState();
}

class _PlanFormScreenState extends ConsumerState<PlanFormScreen> {
  final _name = TextEditingController();
  bool _abWeeks = false;
  int _days = 3;
  bool _saving = false;

  /// A napok tartalma: `[hét][nap]`, mindig teljes 2 × [_maxDays] rácsban.
  /// Így a nap-szám és a hét-típus állítgatása nem dobja el a már beírt
  /// szövegeket, és nincs vezérlő-életciklus, amit el lehetne rontani.
  final _content = List.generate(2, (_) => List.filled(_maxDays, ''));

  int get _weeks => _abWeeks ? 2 : 1;

  /// A szerkesztett terv, vagy `null` új felvitelnél.
  WorkoutPlan? get _editing {
    for (final plan in ref.read(workoutPlansProvider).plans) {
      if (plan.id == widget.planId) return plan;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final plan = _editing;
    if (plan == null) return;
    _name.text = plan.name;
    _abWeeks = plan.hasBWeek;
    _days = plan.daysPerWeek;
    for (var week = 0; week < plan.weeks.length; week++) {
      for (var day = 0; day < plan.weeks[week].length; day++) {
        _content[week][day] = plan.weeks[week][day];
      }
    }
  }

  bool get _ready {
    if (_name.text.trim().isEmpty || _saving) return false;
    for (var week = 0; week < _weeks; week++) {
      for (var day = 0; day < _days; day++) {
        if (_content[week][day].trim().isEmpty) return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final plan = WorkoutPlan(
      // Az azonosítónak csak egyedinek kell lennie a készüléken belül.
      id: widget.planId ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim(),
      weeks: [
        for (var week = 0; week < _weeks; week++)
          [for (var day = 0; day < _days; day++) _content[week][day].trim()],
      ],
    );
    final controller = ref.read(workoutPlansProvider.notifier);
    await (widget.planId == null
        ? controller.add(plan)
        : controller.update(plan));
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: widget.planId == null ? 'Új edzésterv' : 'Edzésterv szerkesztése',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'A terv neve',
              hintText: 'pl. Erő – tavaszi',
              border: OutlineInputBorder(),
            ),
          ),
          const _Label('Milyen a terv?'),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Sima heti')),
              ButtonSegment(value: true, label: Text('A és B hét')),
            ],
            selected: {_abWeeks},
            onSelectionChanged: (selection) =>
                setState(() => _abWeeks = selection.first),
          ),
          const _Label('Hány napot edzel egy héten?'),
          _DayCount(
            days: _days,
            onChanged: (value) => setState(() => _days = value),
          ),
          for (var week = 0; week < _weeks; week++) ...[
            _Label(
              _abWeeks ? '${week == 0 ? 'A' : 'B'} hét napjai' : 'A napok',
            ),
            for (var day = 0; day < _days; day++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextFormField(
                  // A kulcs köti a beírt szöveget a naphoz akkor is, ha közben
                  // változik a napok száma vagy a hetek típusa.
                  key: ValueKey('$week-$day'),
                  initialValue: _content[week][day],
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (value) =>
                      setState(() => _content[week][day] = value),
                  decoration: InputDecoration(
                    labelText: '${day + 1}. nap',
                    hintText: 'pl. mell, tricepsz, vádli',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _ready ? _save : null,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    widget.planId == null
                        ? 'Edzésterv mentése'
                        : 'Módosítások mentése',
                  ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 10),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DayCount extends StatelessWidget {
  const _DayCount({required this.days, required this.onChanged});

  final int days;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          tooltip: 'Kevesebb nap',
          onPressed: days > 1 ? () => onChanged(days - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 72,
          child: Text(
            '$days',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Több nap',
          onPressed: days < _maxDays ? () => onChanged(days + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
