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

/// A színcsoportok kezelője: létrehozás, átnevezés, átszínezés, törlés.
Future<void> showScheduleGroups(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: _sheetHeight(context),
    builder: (_) => const _GroupManager(),
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
  String? _groupId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final entry = widget.editing;
    if (entry == null) return;
    _title.text = entry.title;
    _note.text = entry.note;
    _groupId = entry.groupId;
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
          groupId: _groupId,
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
              const _Label('Színcsoport'),
              _GroupPicker(
                groups: state.groups,
                selectedId: _groupId,
                onPick: (id) => setState(() => _groupId = id),
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

/// Csoportválasztó csipeszek + „új csoport" — a lapról nem kell kilépni ahhoz,
/// hogy legyen mihez rendelni a tételt.
class _GroupPicker extends ConsumerWidget {
  const _GroupPicker({
    required this.groups,
    required this.selectedId,
    required this.onPick,
  });

  final List<ScheduleGroup> groups;
  final String? selectedId;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      ChoiceChip(
        label: const Text('Nincs'),
        selected: selectedId == null,
        onSelected: (_) => onPick(null),
      ),
      for (final group in groups)
        ChoiceChip(
          avatar: CircleAvatar(backgroundColor: group.color, radius: 8),
          label: Text(group.name),
          selected: group.id == selectedId,
          onSelected: (_) => onPick(group.id),
        ),
      ActionChip(
        avatar: const Icon(Icons.add, size: 18),
        label: const Text('Új csoport'),
        onPressed: () async {
          final created = await showGroupDialog(context, ref);
          // Aki most hozta létre, arra akarja tenni a tételt.
          if (created != null) onPick(created.id);
        },
      ),
    ],
  );
}

class _GroupManager extends ConsumerWidget {
  const _GroupManager();

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ScheduleGroup group,
  ) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Csoport törlése'),
        content: Text(
          '„${group.name}" törlődik. A hozzá tartozó tételek megmaradnak, '
          'csak elvesztik a színüket.',
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
      await ref.read(scheduleProvider.notifier).removeGroup(group.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(scheduleProvider);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Színcsoportok',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Az összetartozó tételek kapjanak közös színt — előadás, '
              'gyakorlat, éjszakás műszak, vagy akár tantárgyanként egy.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            if (state.groups.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Még nincs egyetlen csoportod sem. Hozd létre az elsőt lent.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final group in state.groups)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(backgroundColor: group.color, radius: 12),
                title: Text(group.name),
                subtitle: Text(
                  '${state.entries.where((e) => e.groupId == group.id).length} tétel',
                ),
                trailing: PopupMenuButton<bool>(
                  icon: Icon(
                    Icons.more_vert,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  tooltip: 'Műveletek',
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: true, child: Text('Szerkesztés')),
                    PopupMenuItem(value: false, child: Text('Törlés')),
                  ],
                  onSelected: (edit) => edit
                      ? showGroupDialog(context, ref, editing: group)
                      : _confirmDelete(context, ref, group),
                ),
                onTap: () => showGroupDialog(context, ref, editing: group),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Új csoport'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () => showGroupDialog(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}

/// Új csoport felvitele, vagy [editing] átnevezése/átszínezése. A mentett
/// csoporttal tér vissza, elvetve `null`-lal.
Future<ScheduleGroup?> showGroupDialog(
  BuildContext context,
  WidgetRef ref, {
  ScheduleGroup? editing,
}) {
  return showDialog<ScheduleGroup>(
    context: context,
    builder: (_) => _GroupDialog(editing: editing),
  );
}

class _GroupDialog extends ConsumerStatefulWidget {
  const _GroupDialog({this.editing});

  final ScheduleGroup? editing;

  @override
  ConsumerState<_GroupDialog> createState() => _GroupDialogState();
}

class _GroupDialogState extends ConsumerState<_GroupDialog> {
  final _name = TextEditingController();
  late Color _color = widget.editing?.color ?? _nextFreeColor();
  bool _saving = false;

  /// Új csoport annak a színnek indul, amit még nem használ senki — így nem
  /// kell színt keresgélni ahhoz, hogy elkülönüljenek.
  Color _nextFreeColor() {
    final used = {
      for (final g in ref.read(scheduleProvider).groups) g.color.toARGB32(),
    };
    for (final color in categoryColors) {
      if (!used.contains(color.toARGB32())) return color;
    }
    return categoryColors.first;
  }

  @override
  void initState() {
    super.initState();
    _name.text = widget.editing?.name ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _saving) return;
    setState(() => _saving = true);
    final saved = await ref
        .read(scheduleProvider.notifier)
        .saveGroup(
          ScheduleGroup(
            id:
                widget.editing?.id ??
                DateTime.now().microsecondsSinceEpoch.toString(),
            name: name,
            color: _color,
          ),
        );
    if (mounted) Navigator.pop(context, saved);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.editing == null ? 'Új csoport' : 'Csoport szerkesztése',
      ),
      // Görgethető: az egyedi szín csúszkáival a tartalom kis kijelzőn (vagy
      // nagy rendszerbetűnél) magasabb lehet, mint a párbeszéd.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Név',
                hintText: 'pl. Előadás',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ColorField(
              colors: categoryColors,
              value: _color,
              onChanged: (color) => setState(() => _color = color),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Mégsem'),
        ),
        FilledButton(
          onPressed: _name.text.trim().isEmpty || _saving ? null : _save,
          child: Text(widget.editing == null ? 'Létrehozás' : 'Mentés'),
        ),
      ],
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
