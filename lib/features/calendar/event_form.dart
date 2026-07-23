import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'calendar_service.dart';
import 'event_groups.dart';

/// Új esemény felvitele. `true`-val záródik, ha az esemény be is került a
/// naptárba — a hívónak ilyenkor kell frissítenie a listát.
///
/// [initialDay]: erre a napra nyílik az űrlap (a naptárból a kijelölt nap).
/// Múltbeli vagy hiányzó nap esetén a következő egész óra az alapértelmezés.
Future<bool?> showEventForm(BuildContext context, {DateTime? initialDay}) =>
    showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _EventForm(initialDay: initialDay),
    );

class _EventForm extends StatefulWidget {
  const _EventForm({this.initialDay});

  final DateTime? initialDay;

  @override
  State<_EventForm> createState() => _EventFormState();
}

class _EventFormState extends State<_EventForm> {
  final _title = TextEditingController();

  late DateTime _start = _initialStart();
  late DateTime _end = _start.add(const Duration(hours: 1));
  bool _saving = false;

  /// Ma (vagy nap nélkül): a következő egész óra — a legtöbb esetben így elég
  /// a címet beírni. Jövőbeli napra: reggel 9. Múltbeli napra nem nyitunk,
  /// mert a dátumválasztó is a mai naptól enged választani.
  DateTime _initialStart() {
    final now = DateTime.now();
    final day = widget.initialDay;
    if (day != null) {
      final target = DateTime(day.year, day.month, day.day);
      if (target.isAfter(DateTime(now.year, now.month, now.day))) {
        return DateTime(target.year, target.month, target.day, 9);
      }
    }
    // Éjjel 11 után is jó: a DateTime magától átfordul a következő napra.
    return DateTime(now.year, now.month, now.day, now.hour + 1);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  /// A kezdés mozgatásakor a vége is megy vele — a hossz marad, amit
  /// beállítottak. Így a kezdés átállítása sosem hoz létre érvénytelen párost.
  void _setStart(DateTime value) => setState(() {
    _end = _end.add(value.difference(_start));
    _start = value;
  });

  void _setEnd(DateTime value) =>
      setState(() => _end = clampEnd(_start, value));

  Future<void> _pickDate({required bool end}) async {
    final current = end ? _end : _start;
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: current,
      // A vége legkorábban a kezdés napján lehet, a kezdés pedig ma.
      firstDate: end
          ? DateTime(_start.year, _start.month, _start.day)
          : DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );
    if (day == null) return;
    final picked = DateTime(
      day.year,
      day.month,
      day.day,
      current.hour,
      current.minute,
    );
    if (end) {
      _setEnd(picked);
    } else {
      _setStart(picked);
    }
  }

  Future<void> _pickTime({required bool end}) async {
    final current = end ? _end : _start;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null) return;
    final picked = DateTime(
      current.year,
      current.month,
      current.day,
      time.hour,
      time.minute,
    );
    if (end) {
      _setEnd(picked);
    } else {
      _setStart(picked);
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await createEvent(title: title, start: _start, end: _end);
      if (mounted) Navigator.pop(context, true);
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.code == permissionDeniedCode
                ? 'Engedélyezd a naptár írását, majd próbáld újra.'
                : 'Nem sikerült elmenteni: ${e.message}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = _title.text.trim().isNotEmpty && !_saving;

    return Padding(
      // A billentyűzet fölé emeli a lapot.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Új esemény',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _title,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                // A mentés gomb a cím ürességétől függ.
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Cím',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              _WhenRow(
                label: 'Kezdés',
                value: _start,
                onDate: () => _pickDate(end: false),
                onTime: () => _pickTime(end: false),
              ),
              const SizedBox(height: 8),
              _WhenRow(
                label: 'Vége',
                value: _end,
                onDate: () => _pickDate(end: true),
                onTime: () => _pickTime(end: true),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: ready ? _save : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _saving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Mentés a naptárba'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Egy időpont: dátum és óra, saját gombbal.
class _WhenRow extends StatelessWidget {
  const _WhenRow({
    required this.label,
    required this.value,
    required this.onDate,
    required this.onTime,
  });

  final String label;
  final DateTime value;
  final VoidCallback onDate;
  final VoidCallback onTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 58,
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onDate,
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text(
              dayLabel(value, today: DateTime.now()),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: onTime, child: Text(hhmm(value))),
      ],
    );
  }
}
