import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../settings/settings_screen.dart';
import 'calendar_service.dart';
import 'event_categories.dart';
import 'event_groups.dart';

/// Esemény felvitele vagy szerkesztése. `true`-val záródik, ha az esemény be is
/// került / módosult a naptárban — a hívónak ilyenkor kell frissítenie a listát.
///
/// [initialDay]: erre a napra nyílik az űrlap új eseménynél (a naptárból a
/// kijelölt nap). Múltbeli vagy hiányzó nap esetén a következő egész óra.
/// [editing]: megadva a meglévő eseményt szerkeszti, nem újat hoz létre.
Future<bool?> showEventForm(
  BuildContext context, {
  DateTime? initialDay,
  CalendarEvent? editing,
}) => showModalBottomSheet<bool>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => _EventForm(initialDay: initialDay, editing: editing),
);

class _EventForm extends ConsumerStatefulWidget {
  const _EventForm({this.initialDay, this.editing});

  final DateTime? initialDay;
  final CalendarEvent? editing;

  @override
  ConsumerState<_EventForm> createState() => _EventFormState();
}

class _EventFormState extends ConsumerState<_EventForm> {
  final _title = TextEditingController();

  /// A meghívottak e-mail címei egy mezőben (lásd [parseGuestEmails]). Csak új
  /// eseménynél van itt: meglévőhöz a részletek lapján a „Meghívás" gomb visz a
  /// Naptárba (lásd [inviteToEvent]) — ott az `ACTION_EDIT` nem garantálja az
  /// előre kitöltött vendéglistát, ezért ott nem is kérjük be.
  final _guests = TextEditingController();

  late DateTime _start;
  late DateTime _end;

  /// A kiválasztott kategória — új eseménynél még nincs mihez rendelni, ezért
  /// az űrlapon várakozik, és a mentés köti rá a létrejött eseményre.
  String? _categoryId;
  bool _allDay = false;
  bool _saving = false;

  /// Csak új eseménynél állítható. Meglévő sorozatnál a szabályt változatlanul
  /// visszaírjuk — az „ismétlődés átállítása" külön szerkesztő lenne.
  Recurrence _recurrence = Recurrence.none;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    if (editing != null) {
      _title.text = editing.title;
      _categoryId = ref.read(categoriesProvider).of(editing.id)?.id;
      _allDay = editing.allDay;
      _start = editing.at;
      // Egész naposnak nincs vége a modellben (a kezdés helyi éjfél). A mentés
      // ezt úgyis a nap végére számolja — a +1 óra csak arra kell, hogy a
      // kapcsolót kikapcsolva legyen értelmes időpontos vég.
      _end = editing.end ?? editing.at.add(const Duration(hours: 1));
    } else {
      _start = _initialStart();
      _end = _start.add(const Duration(hours: 1));
    }
  }

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
    _guests.dispose();
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
    final today = DateTime(now.year, now.month, now.day);
    // A vége legkorábban a kezdés napján lehet, a kezdés pedig ma — de egy
    // szerkesztett, már elmúlt esemény kezdete a múltban van, és a picker
    // elszáll, ha az induló dátum a firstDate elé esne. Ezért a padlót
    // sosem visszük az aktuális érték napja fölé.
    final startFloor = _start.isBefore(today)
        ? DateTime(_start.year, _start.month, _start.day)
        : today;
    final day = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: end
          ? DateTime(_start.year, _start.month, _start.day)
          : startFloor,
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
      // Beállításban választható, hogy gépelve vagy a mutatókat húzva induljon
      // (a választón belül a felhasználó így is válthat).
      initialEntryMode: ref.read(timeKeyboardProvider)
          ? TimePickerEntryMode.input
          : TimePickerEntryMode.dial,
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
      final editing = widget.editing;
      final categories = ref.read(categoriesProvider.notifier);
      // Az űrlap nyitva léte alatt a kategória törölhető is — a már nem létezőt
      // nem rendeljük hozzá.
      final categoryId = ref.read(categoriesProvider).byId(_categoryId)?.id;
      if (editing != null) {
        await updateEvent(
          id: editing.id,
          title: title,
          start: _start,
          end: _end,
          allDay: _allDay,
          // Változatlanul vissza: enélkül a natív oldal DTEND-et írna a sorozat
          // DURATION-je helyett, és a naptár elutasítaná a mentést.
          rrule: editing.rrule,
        );
        await categories.assign(editing.id, categoryId);
      } else if (parseGuestEmails(_guests.text) case final guests
          when guests.isNotEmpty) {
        // Meghívottakkal a Naptár szerkesztője veszi át — ő küldi a meghívót.
        // Nem kapunk vissza azonosítót, tehát kategóriát sem tudunk kötni rá; a
        // részletek lapján utólag megadható.
        await createEventWithGuests(
          title: title,
          start: _start,
          end: _end,
          allDay: _allDay,
          rrule: rruleFor(_recurrence, _start),
          guests: guests,
        );
      } else {
        final id = await createEvent(
          title: title,
          start: _start,
          end: _end,
          allDay: _allDay,
          rrule: rruleFor(_recurrence, _start),
          // A bejelentkezett fiók naptárába — a natív oldal magától a készülék
          // első írható naptárát venné, ami több fióknál másé is lehet. A
          // naptárlistát a lista- és a naptárnézet már betöltötte; ha mégsem,
          // marad a natív választás.
          calendarId: writeTargetId(
            ref.read(deviceCalendarsProvider).value ?? const [],
            ref.read(currentUserProvider).value?.email,
          ),
        );
        // Kategória nélkül nincs mit menteni; azonosító nélkül nincs mire.
        if (id != null && categoryId != null) {
          await categories.assign(id, categoryId);
        }
      }
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
    final scheme = theme.colorScheme;
    final ready = _title.text.trim().isNotEmpty && !_saving;
    final category = ref.watch(categoriesProvider).byId(_categoryId);

    return Padding(
      // A billentyűzet fölé emeli a lapot.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _isEdit ? Icons.edit_calendar_outlined : Icons.event,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _isEdit ? 'Esemény szerkesztése' : 'Új esemény',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              // Az id a sorozat sora, nem az előfordulásé: a mentés minden
              // előfordulást átír. Ezt előre kell tudni, ezért van legfelül.
              if (widget.editing?.recurring ?? false) ...[
                const _Warning(
                  icon: Icons.repeat_rounded,
                  text:
                      'Ismétlődő esemény: a módosítás a sorozat minden '
                      'előfordulására érvényes, és a sorozat kezdete erre a '
                      'napra kerül.',
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _title,
                autofocus: !_isEdit,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                // A mentés gomb a cím ürességétől függ.
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Cím',
                  hintText: 'Mi kerüljön a naptárba?',
                  prefixIcon: const Icon(Icons.title_rounded),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Kategória már itt, a felvitelnél — nem kell utólag megnyitni az
              // eseményt hozzá.
              Align(
                alignment: Alignment.centerLeft,
                child: _PickerChip(
                  icon: category == null ? Icons.label_outline : Icons.label,
                  label: category?.name ?? 'Kategória',
                  color: category?.color,
                  onTap: () => showCategoryPicker(
                    context,
                    selectedId: _categoryId,
                    onPick: (id) => setState(() => _categoryId = id),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: _allDay,
                        onChanged: (value) => setState(() => _allDay = value),
                        title: const Text('Egész napos'),
                        secondary: const Icon(Icons.today_outlined),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                      const SizedBox(height: 6),
                      // Egész naposnál nincs időpont és nincs külön vég: a nap
                      // maga az esemény.
                      if (_allDay)
                        _WhenRow(
                          label: 'Nap',
                          value: _start,
                          onDate: () => _pickDate(end: false),
                        )
                      else ...[
                        _WhenRow(
                          label: 'Kezdés',
                          value: _start,
                          onDate: () => _pickDate(end: false),
                          onTime: () => _pickTime(end: false),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Divider(
                                  height: 1,
                                  color: scheme.outlineVariant.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.hourglass_bottom_rounded,
                                      size: 14,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _durationLabel(_end.difference(_start)),
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Divider(
                                  height: 1,
                                  color: scheme.outlineVariant.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _WhenRow(
                          label: 'Vége',
                          value: _end,
                          onDate: () => _pickDate(end: true),
                          onTime: () => _pickTime(end: true),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Meglévő eseménynél nincs itt: az ismétlődés átállítása a
              // sorozat átírása lenne, nem ugyanaz a művelet.
              if (!_isEdit) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<Recurrence>(
                  initialValue: _recurrence,
                  onChanged: (value) =>
                      setState(() => _recurrence = value ?? Recurrence.none),
                  decoration: InputDecoration(
                    labelText: 'Ismétlődés',
                    prefixIcon: const Icon(Icons.repeat_rounded),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: [
                    for (final option in Recurrence.values)
                      DropdownMenuItem(
                        value: option,
                        child: Text(_recurrenceLabels[option]!),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _guests,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  // A figyelmeztető sáv megjelenése a mező tartalmán múlik.
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Meghívottak',
                    hintText: 'anna@pelda.hu, bela@pelda.hu',
                    prefixIcon: const Icon(Icons.group_outlined),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                // Csak akkor szólunk, ha tényleg lesz meghívott: a mentés
                // ilyenkor a Naptár szerkesztőjében folytatódik, ami látható
                // váltás — ne érje váratlanul a felhasználót.
                if (parseGuestEmails(_guests.text).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const _Warning(
                    icon: Icons.group_outlined,
                    text:
                        'Meghívottakkal a mentés a telefon Naptár '
                        'alkalmazásában fejeződik be — a meghívót az küldi ki. '
                        'Ott érdemes bekapcsolva hagyni, hogy a meghívottak '
                        'szerkeszthessék az eseményt: így mindenki '
                        'módosításait látni fogod.',
                  ),
                ],
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: ready ? _save : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_isEdit ? Icons.check_rounded : Icons.add_rounded),
                label: Text(
                  _isEdit ? 'Módosítások mentése' : 'Mentés a naptárba',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _recurrenceLabels = {
  Recurrence.none: 'Nem ismétlődik',
  Recurrence.daily: 'Naponta',
  Recurrence.weekly: 'Hetente ugyanezen a napon',
  Recurrence.yearly: 'Évente',
};

/// Figyelmeztető sáv: a sorozat-szerkesztésnél és a meghívottas mentésnél.
class _Warning extends StatelessWidget {
  const _Warning({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.tertiary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Emberi hossz-címke: „1 óra 30 perc", „45 perc", több napra „2 nap 3 óra".
String _durationLabel(Duration d) {
  final days = d.inDays;
  final hours = d.inHours % 24;
  final minutes = d.inMinutes % 60;
  final parts = [
    if (days > 0) '$days nap',
    if (hours > 0) '$hours óra',
    if (minutes > 0) '$minutes perc',
  ];
  return parts.isEmpty ? '0 perc' : parts.join(' ');
}

/// Egy időpont sora: fent a címke, alatta a dátum és az óra tonális chipként.
class _WhenRow extends StatelessWidget {
  const _WhenRow({
    required this.label,
    required this.value,
    required this.onDate,
    this.onTime,
  });

  final String label;
  final DateTime value;
  final VoidCallback onDate;

  /// Az órachip elhagyható — egész napos eseménynél nincs időpont.
  final VoidCallback? onTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _PickerChip(
                icon: Icons.event_outlined,
                label: dayLabel(value, today: DateTime.now()),
                onTap: onDate,
              ),
            ),
            if (onTime != null) ...[
              const SizedBox(width: 10),
              _PickerChip(
                icon: Icons.schedule_outlined,
                label: hhmm(value),
                onTap: onTime!,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Koppintható tonális pötty: ikon + felirat, az akcentszín halvány hátterén.
class _PickerChip extends StatelessWidget {
  const _PickerChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// A chip színe — megadva a kategória saját színét viseli, egyébként az
  /// akcentszínt.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;
    return Material(
      color: accent.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
