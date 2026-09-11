import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui.dart';
// A színpaletta közös a naptárkategóriákkal: egy app, egy színvilág.
import '../calendar/event_categories.dart' show categoryColors;
import '../settings/settings_screen.dart';
import 'schedule.dart';

/// Új tétel felvitele vagy [editing] szerkesztése.
///
/// Új tételnél [weekday] (1–7) és [start] (perc éjféltől) adja a kiindulást — a
/// heti rácsban oda, ahova koppintottál.
Future<void> showEntrySheet(
  BuildContext context, {
  ScheduleEntry? editing,
  int weekday = DateTime.monday,
  int start = 8 * 60,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: _sheetHeight(context),
    builder: (_) => _EntrySheet(
      editing: editing,
      weekday: editing?.weekday ?? weekday,
      start: editing?.start ?? start,
    ),
  );
}

/// A lap sosem ér fel a kijelző tetejéig: marad fölötte egy csík, amiből
/// látszik, hogy egy lapot húztál fel, nem egy új képernyőt nyitottál. Ami így
/// nem fér ki, azt a lap belül görgeti.
BoxConstraints _sheetHeight(BuildContext context) =>
    BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9);

class _EntrySheet extends ConsumerStatefulWidget {
  const _EntrySheet({
    required this.editing,
    required this.weekday,
    required this.start,
  });

  final ScheduleEntry? editing;
  final int weekday;
  final int start;

  @override
  ConsumerState<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends ConsumerState<_EntrySheet> {
  final _title = TextEditingController();
  final _note = TextEditingController();

  /// A kipipált napok. Egy űrlapból több nap is lehet — mindegyikre külön
  /// tétel készül, hogy az egyiket törölve a többi megmaradjon.
  late final Set<int> _weekdays = {widget.weekday};
  late int _start = widget.start;
  late int _end = widget.editing?.end ?? (widget.start + 90);

  /// A hét választója: -1 = mindkettő (ez a tárolt `null`), 0 = A, 1 = B.
  late int _week = widget.editing?.week ?? -1;

  /// A tétel színe — csak szín, név nélkül. A régi, szín nélküli tételek
  /// szerkesztéskor kapják meg az alapszínt.
  late Color _color = widget.editing?.color ?? categoryColors.first;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final entry = widget.editing;
    if (entry == null) return;
    _title.text = entry.title;
    _note.text = entry.note;
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _valid =>
      _title.text.trim().isNotEmpty && _end > _start && _weekdays.isNotEmpty;

  Future<void> _pickTime({required bool end}) async {
    final current = end ? _end : _start;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
      // Ugyanaz a beállítás dönt, mint az esemény űrlapján: gépelve vagy a
      // mutatókat húzva induljon.
      initialEntryMode: ref.read(timeKeyboardProvider)
          ? TimePickerEntryMode.input
          : TimePickerEntryMode.dial,
    );
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    setState(() {
      if (end) {
        _end = minutes;
      } else {
        // A kezdés mozgatása viszi magával a véget: a hossz marad, amit
        // beállítottál. (Éjfélen túl nem lóghat ki.)
        final length = _end - _start;
        _start = minutes;
        _end = (minutes + length).clamp(minutes, 24 * 60);
      }
    });
  }

  Future<void> _save() async {
    if (!_valid || _saving) return;
    setState(() => _saving = true);
    final editing = widget.editing;
    final days = _weekdays.toList()..sort();
    // Szerkesztésnél a szerkesztett tétel marad a saját napján (ha még ki van
    // pipálva), a többi kipipált nap ÚJ tételként jön létre. Így minden nap
    // önálló: az egyiket törölve a többi a helyén marad.
    final keep = editing != null && days.contains(editing.weekday)
        ? editing.weekday
        : days.first;
    final base = DateTime.now().microsecondsSinceEpoch;

    await ref.read(scheduleProvider.notifier).saveEntries([
      for (final day in days)
        ScheduleEntry(
          id: editing != null && day == keep ? editing.id : '${base + day}',
          weekday: day,
          start: _start,
          end: _end,
          title: _title.text.trim(),
          week: _week < 0 ? null : _week,
          note: _note.text.trim(),
          color: _color,
        ),
    ]);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final entry = widget.editing!;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tétel törlése'),
        // A törlés CSAK erről a napról szól: ugyanaz a cím más napokon önálló
        // tétel, az ott marad.
        content: Text(
          '„${entry.title}" törlődik erről a napról '
          '(${scheduleWeekdayNames[entry.weekday - 1]}). A többi nap marad.',
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
    if (!(yes ?? false)) return;
    await ref.read(scheduleProvider.notifier).removeEntry(entry.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(scheduleProvider);

    return SafeArea(
      child: Padding(
        // A billentyűzet elől feljebb csúszik a lap, hogy a mentés gomb is
        // elérhető maradjon.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.editing == null ? 'Új tétel' : 'Tétel szerkesztése',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                autofocus: widget.editing == null,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Mi ez?',
                  hintText: 'pl. Közgazdaságtan előadás',
                  border: OutlineInputBorder(),
                ),
              ),
              const _Label('Mely napokon?'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var day = 1; day <= 7; day++)
                    FilterChip(
                      label: Text(scheduleWeekdays[day - 1]),
                      selected: _weekdays.contains(day),
                      onSelected: (on) => setState(
                        () => on ? _weekdays.add(day) : _weekdays.remove(day),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _weekdays.isEmpty
                      ? 'Válassz legalább egy napot.'
                      : 'Több napot is bejelölhetsz — mindegyikre külön tétel '
                            'kerül, és külön is törölhetők.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _weekdays.isEmpty
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const _Label('Mettől meddig?'),
              Row(
                children: [
                  Expanded(
                    child: _TimeButton(
                      label: 'Kezdés',
                      minutes: _start,
                      onTap: () => _pickTime(end: false),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward, size: 18),
                  ),
                  Expanded(
                    child: _TimeButton(
                      label: 'Vége',
                      minutes: _end,
                      onTap: () => _pickTime(end: true),
                      error: _end <= _start,
                    ),
                  ),
                ],
              ),
              if (_end <= _start)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'A vége legyen a kezdés után.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    spanLabel(_end - _start),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (state.abWeeks) ...[
                const _Label('Melyik héten?'),
                SegmentedButton<int>(
                  // A három felirat szűk kijelzőn épp hogy kifér: inkább
                  // zsugorodjanak, mint hogy levágódjanak.
                  segments: const [
                    ButtonSegment(value: -1, label: FitText('Mindkettő')),
                    ButtonSegment(value: 0, label: FitText('A hét')),
                    ButtonSegment(value: 1, label: FitText('B hét')),
                  ],
                  selected: {_week},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _week = s.first),
                ),
              ],
              const _Label('Szín'),
              ColorField(
                colors: categoryColors,
                value: _color,
                onChanged: (color) => setState(() => _color = color),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Megjegyzés',
                  hintText: 'pl. B/2 terem',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (widget.editing != null) ...[
                    OutlinedButton(
                      onPressed: _delete,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Icon(Icons.delete_outline),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: FilledButton(
                      onPressed: _valid && !_saving ? _save : null,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const FitText('Mentés'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.minutes,
    required this.onTap,
    this.error = false,
  });

  final String label;
  final int minutes;
  final VoidCallback onTap;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
        side: error ? BorderSide(color: theme.colorScheme.error) : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          FitText(
            hhmm(minutes),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
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
      padding: const EdgeInsets.fromLTRB(0, 22, 0, 10),
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
