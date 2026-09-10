import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_scaffold.dart';
import '../../core/ui.dart';
import '../calendar/event_groups.dart' show monthName;
import '../workouts/workout_plans.dart' show weekStartOf;
import 'entry_sheet.dart';
import 'schedule.dart';

/// A heti beosztás: napi és heti nézet ugyanarról a heti sablonról.
///
/// Egyetlen állapot mozgatja mindkét nézetet: a kiválasztott DÁTUM. Ebből jön a
/// nap (napi nézet), a hét (heti rács) és az A/B hét is — nincs külön
/// „melyik hetet nézem" kapcsoló, amit szinkronban kellene tartani.
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  late DateTime _day = _today();
  bool _weekView = false;
  int _slideDir = 1; // az utolsó lapozás iránya, a csúszó animációhoz
  Timer? _clock;

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    // A „most" vonal és a MOST jelvény különben beragadna: a fül a héjban
    // életben marad, magától nem épül újra. Percenként egy setState elég.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  void _shift(int steps) => setState(() {
    _slideDir = steps.sign;
    final days = (_weekView ? 7 : 1) * steps;
    _day = DateTime(_day.year, _day.month, _day.day + days);
  });

  void _goToday() {
    final today = _today();
    setState(() {
      _slideDir = _day.isAfter(today) ? -1 : 1;
      _day = today;
    });
  }

  /// Vízszintes húzás: jobbról balra előre, balról jobbra vissza — mint a
  /// naptárban a hónapok között. Napi nézetben napot, hetiben hetet lapoz.
  void _onSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 300) return;
    // Csak a tényleges lapozás rezeg — a küszöb alatti húzás nem.
    HapticFeedback.selectionClick();
    _shift(velocity < 0 ? 1 : -1);
  }

  /// Az új tétel oda kerül, ahol épp állsz: a látott napra, az aznapi utolsó
  /// tétel végétől — így egymás után felvinni egy napot nem időpont-vadászat.
  Future<void> _addEntry(ScheduleState state) {
    final day = state.dayEntries(_day.weekday, state.weekOf(_day));
    return showEntrySheet(
      context,
      weekday: _day.weekday,
      start: day.isEmpty ? 8 * 60 : math.min(day.last.end, 22 * 60),
    );
  }

  Future<void> _toggleAbWeeks(ScheduleState state) async {
    final controller = ref.read(scheduleProvider.notifier);
    if (state.abWeeks) {
      // Vissza sima hetire: a csak B héten élő tételeknek nem lenne hol
      // lenniük. Megkérdezzük, mielőtt elvinnénk őket.
      final bOnly = controller.bOnlyCount;
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Vissza sima heti beosztásra'),
          content: Text(
            bOnly == 0
                ? 'Minden tétel minden héten ott lesz.'
                : 'A csak B héten szereplő $bOnly tétel törlődik, a többi '
                      'minden héten ott lesz.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Mégsem'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Váltás'),
            ),
          ],
        ),
      );
      if (!(yes ?? false)) return;
    }
    await controller.setAbWeeks(!state.abWeeks);
  }

  Future<void> _clearAll() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Beosztás ürítése'),
        content: const Text(
          'Minden tétel törlődik — új félévhez, új munkarendhez tiszta lap. '
          'A színcsoportok megmaradnak.',
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
            child: const Text('Ürítés'),
          ),
        ],
      ),
    );
    if (yes ?? false) await ref.read(scheduleProvider.notifier).clearEntries();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scheduleProvider);
    final now = DateTime.now();
    final week = state.weekOf(_day);
    final weekStart = weekStartOf(_day);

    return AppScaffold(
      title: 'Beosztás',
      actions: [
        if (_day != _today())
          IconButton(
            icon: const Icon(Icons.today_outlined),
            tooltip: 'Ugrás a mai napra',
            onPressed: _goToday,
          ),
        IconButton(
          icon: const Icon(Icons.palette_outlined),
          tooltip: 'Színcsoportok',
          onPressed: () => showScheduleGroups(context),
        ),
        PopupMenuButton<int>(
          tooltip: 'A beosztás műveletei',
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 0,
              child: Text(
                state.abWeeks
                    ? 'Vissza sima heti beosztásra'
                    : 'Váltás A és B hetesre',
              ),
            ),
            const PopupMenuItem(value: 1, child: Text('Minden tétel törlése')),
          ],
          onSelected: (value) =>
              value == 0 ? _toggleAbWeeks(state) : _clearAll(),
        ),
      ],
      floatingActionButton: FloatingActionButton(
        tooltip: 'Új tétel',
        onPressed: () => _addEntry(state),
        child: const Icon(Icons.add),
      ),
      body: state.entries.isEmpty
          ? _Empty(onAdd: () => _addEntry(state))
          : GestureDetector(
              onHorizontalDragEnd: _onSwipe,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.view_day_outlined),
                          label: Text('Nap'),
                        ),
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.view_week_outlined),
                          label: Text('Hét'),
                        ),
                      ],
                      selected: {_weekView},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) =>
                          setState(() => _weekView = s.first),
                    ),
                  ),
                  _NavBar(
                    label: _weekView
                        ? _weekLabel(weekStart)
                        : _dayLabel(_day, now),
                    weekBadge: state.abWeeks
                        ? _WeekBadge(
                            week: week,
                            live: weekStart == weekStartOf(now),
                          )
                        : null,
                    onPrev: () => _shift(-1),
                    onNext: () => _shift(1),
                    isWeek: _weekView,
                  ),
                  Expanded(
                    child: _Paged(
                      // Lapozáskor a látott egység változik: napi nézetben a
                      // nap, hetiben a hét — csak ilyenkor animálunk.
                      pageKey: ValueKey(
                        '$_weekView|${(_weekView ? weekStart : _day).toIso8601String()}',
                      ),
                      direction: _slideDir,
                      child: _weekView
                          ? _WeekGrid(
                              state: state,
                              week: week,
                              weekStart: weekStart,
                              now: now,
                              onEntryTap: (entry) =>
                                  showEntrySheet(context, editing: entry),
                              onEmptyTap: (weekday, start) => showEntrySheet(
                                context,
                                weekday: weekday,
                                start: start,
                              ),
                              onDayTap: (weekday) => setState(() {
                                _day = weekStart.add(
                                  Duration(days: weekday - 1),
                                );
                                _weekView = false;
                              }),
                            )
                          : _DayView(
                              state: state,
                              day: _day,
                              week: week,
                              now: now,
                              onEntryTap: (entry) =>
                                  showEntrySheet(context, editing: entry),
                            ),
                    ),
                  ),
                  if (_weekView && state.groups.isNotEmpty)
                    _Legend(groups: state.groups),
                ],
              ),
            ),
    );
  }
}

/// „Ma · szeptember 11." / „csütörtök · szeptember 11."
String _dayLabel(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day) == day;
  final name = today ? 'Ma' : scheduleWeekdayNames[day.weekday - 1];
  return '$name · ${monthName(day.month)} ${day.day}.';
}

/// „szeptember 8–14." — hónapfordulón mindkét hónap nevével.
String _weekLabel(DateTime weekStart) {
  final end = weekStart.add(const Duration(days: 6));
  if (end.month == weekStart.month) {
    return '${monthName(weekStart.month)} ${weekStart.day}–${end.day}.';
  }
  return '${monthName(weekStart.month)} ${weekStart.day}. – '
      '${monthName(end.month)} ${end.day}.';
}

/// Lapozósor: napi nézetben napot, heti nézetben hetet léptet.
class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.label,
    required this.weekBadge,
    required this.onPrev,
    required this.onNext,
    required this.isWeek,
  });

  final String label;
  final Widget? weekBadge;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final bool isWeek;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton(
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left),
          tooltip: isWeek ? 'Előző hét' : 'Előző nap',
        ),
        Expanded(
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (weekBadge != null) ...[const SizedBox(height: 4), weekBadge!],
            ],
          ),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
          tooltip: isWeek ? 'Következő hét' : 'Következő nap',
        ),
      ],
    );
  }
}

/// Lapozás-animáció: az új nap/hét a lapozás irányából úszik be, a régi
/// ellenkező irányba ki. Rövid és halk — csak annyit mond, hogy „lapoztál",
/// nem várakoztat. Ugyanaz a mozdulat, mint a naptár hónapváltásánál.
class _Paged extends StatelessWidget {
  const _Paged({
    required this.pageKey,
    required this.direction,
    required this.child,
  });

  final Key pageKey;
  final int direction;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 220),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    // A kimenő és a bejövő lap egymás mellett áll, nem egymás alatt — a
    // rács és a lista is a teljes helyet kéri.
    layoutBuilder: (current, previous) => Stack(
      alignment: Alignment.topLeft,
      children: [...previous, ?current],
    ),
    transitionBuilder: (child, animation) {
      final incoming = child.key == pageKey;
      final from = (incoming ? direction : -direction) * 0.14;
      return FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: Offset(from, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      );
    },
    child: KeyedSubtree(key: pageKey, child: child),
  );
}

/// „A HÉT" / „B HÉT" jelvény. A most futó hét kitöltve és „· MOST" felirattal
/// látszik — a lapozás közben ez mondja meg, hol vagy a valósághoz képest.
class _WeekBadge extends StatelessWidget {
  const _WeekBadge({required this.week, required this.live});

  final int week;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: live ? 0.16 : 0),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: live ? 0.6 : 0.3)),
      ),
      child: Text(
        '${week == 0 ? 'A' : 'B'} HÉT${live ? ' · MOST' : ''}',
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

// ─── Heti rács ──────────────────────────────────────────────────────────────

const _gutter = 44.0; // az óratengely szélessége
const _pxPerMin = 1.0; // egy óra = 60 px

/// A rács órahatárai: a legkorábbi kezdéstől a legkésőbbi végig, de legalább
/// hat óra magasan. MINDEN tételből számoljuk (nem csak a látott hétből), hogy
/// az A és B hét között lapozva ne ugráljon a rács.
({int from, int to}) _hourRange(List<ScheduleEntry> entries) {
  if (entries.isEmpty) return (from: 7, to: 20);
  var from = 24;
  var to = 0;
  for (final e in entries) {
    from = math.min(from, e.start ~/ 60);
    to = math.max(to, (e.end + 59) ~/ 60);
  }
  if (to - from < 6) {
    to = math.min(24, from + 6);
    from = math.max(0, to - 6);
  }
  return (from: from, to: to);
}

class _WeekGrid extends StatelessWidget {
  const _WeekGrid({
    required this.state,
    required this.week,
    required this.weekStart,
    required this.now,
    required this.onEntryTap,
    required this.onEmptyTap,
    required this.onDayTap,
  });

  final ScheduleState state;
  final int week;
  final DateTime weekStart;
  final DateTime now;
  final ValueChanged<ScheduleEntry> onEntryTap;
  final void Function(int weekday, int start) onEmptyTap;
  final ValueChanged<int> onDayTap;

  /// Hétfőtől péntekig mindig, hétvége csak akkor, ha van rajta tétel — a
  /// diáknak ne foglaljon helyet két üres oszlop, a műszakos mégis lássa.
  int get _lastDay {
    var last = 5;
    for (final e in state.entries) {
      last = math.max(last, e.weekday);
    }
    return last;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final range = _hourRange(state.entries);
    final days = _lastDay;
    final height = (range.to - range.from) * 60 * _pxPerMin;
    final thisWeek = weekStart == weekStartOf(now);

    return LayoutBuilder(
      builder: (context, constraints) {
        // A napok MINDIG kiférnek a képernyőre — vízszintesen nem görgetünk.
        // A görgetés elnyelné az oldalra húzást, amivel a heteket lapozzuk, és
        // egy telefonnyi „heti áttekintés", amiben oldalra kell tolni, nem
        // áttekintés. Hét oszlopnál az oszlop keskeny lesz: a részletekért a
        // nap fejlécére koppintva ott a napi nézet.
        final column = (constraints.maxWidth - _gutter) / days;
        final width = constraints.maxWidth;

        return SizedBox(
          width: width,
          child: Column(
            children: [
              _DayHeaderRow(
                days: days,
                column: column,
                weekStart: weekStart,
                today: DateTime(now.year, now.month, now.day),
                onTap: onDayTap,
              ),
              Expanded(
                child: SingleChildScrollView(
                  // A lapozás új rácsot épít (az animációhoz kulcsolt), ez
                  // pedig megőrzi a függőleges pozíciót — különben minden
                  // héten visszaugrana a nap elejére.
                  key: const PageStorageKey('scheduleGrid'),
                  child: SizedBox(
                    // Alul hely a lebegő gombnak: enélkül az utolsó tétel
                    // alsó sarka a gomb alá kerül.
                    height: height + 72,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _GridLines(
                              hours: range.to - range.from,
                              column: column,
                              days: days,
                              height: height,
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                        _HourAxis(range: range, theme: theme),
                        for (var day = 1; day <= days; day++)
                          Positioned(
                            left: _gutter + (day - 1) * column,
                            top: 0,
                            width: column,
                            height: height,
                            child: _DayColumn(
                              entries: state.dayEntries(day, week),
                              state: state,
                              from: range.from * 60,
                              width: column,
                              onEntryTap: onEntryTap,
                              onEmptyTap: (start) => onEmptyTap(day, start),
                              nowMinutes: thisWeek && now.weekday == day
                                  ? now.hour * 60 + now.minute
                                  : null,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DayHeaderRow extends StatelessWidget {
  const _DayHeaderRow({
    required this.days,
    required this.column,
    required this.weekStart,
    required this.today,
    required this.onTap,
  });

  final int days;
  final double column;
  final DateTime weekStart;
  final DateTime today;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          const SizedBox(width: _gutter),
          for (var day = 1; day <= days; day++)
            SizedBox(
              width: column,
              child: InkWell(
                onTap: () => onTap(day),
                child: Builder(
                  builder: (context) {
                    final date = weekStart.add(Duration(days: day - 1));
                    final isToday = date == today;
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FitText(
                          scheduleWeekdays[day - 1],
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          width: 26,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: isToday
                              ? BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  borderRadius: BorderRadius.circular(9),
                                )
                              : null,
                          child: Text(
                            '${date.day}',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isToday
                                  ? theme.colorScheme.onPrimary
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Az óratengely feliratai a bal szélen — a vonalak alatt, hogy az órasáv
/// tetejét jelöljék.
class _HourAxis extends StatelessWidget {
  const _HourAxis({required this.range, required this.theme});

  final ({int from, int to}) range;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      for (var hour = range.from; hour < range.to; hour++)
        Positioned(
          top: (hour - range.from) * 60 * _pxPerMin + 2,
          left: 0,
          width: _gutter - 6,
          child: Text(
            '$hour:00',
            textAlign: TextAlign.right,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
    ],
  );
}

class _GridLines extends CustomPainter {
  const _GridLines({
    required this.hours,
    required this.column,
    required this.days,
    required this.height,
    required this.color,
  });

  final int hours;
  final double column;
  final int days;
  final double height;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var hour = 0; hour <= hours; hour++) {
      final y = hour * 60 * _pxPerMin;
      canvas.drawLine(Offset(_gutter, y), Offset(size.width, y), paint);
    }
    for (var day = 0; day <= days; day++) {
      final x = _gutter + day * column;
      canvas.drawLine(Offset(x, 0), Offset(x, height), paint);
    }
  }

  @override
  bool shouldRepaint(_GridLines old) =>
      old.hours != hours ||
      old.column != column ||
      old.days != days ||
      old.height != height ||
      old.color != color;
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.entries,
    required this.state,
    required this.from,
    required this.width,
    required this.onEntryTap,
    required this.onEmptyTap,
    required this.nowMinutes,
  });

  final List<ScheduleEntry> entries;
  final ScheduleState state;
  final int from; // a rács teteje percben
  final double width; // az oszlop szélessége
  final ValueChanged<ScheduleEntry> onEntryTap;
  final ValueChanged<int> onEmptyTap;
  final int? nowMinutes;

  @override
  Widget build(BuildContext context) {
    final lanes = laneLayout(entries);
    final now = nowMinutes;

    return Stack(
      children: [
        // Üres helyre koppintva új tétel indul — negyedórára kerekítve oda,
        // ahova nyomtál. A blokkok ez FÖLÖTT vannak, így ők kapják a saját
        // koppintásukat.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final minute = from + details.localPosition.dy ~/ _pxPerMin;
              onEmptyTap(((minute / 15).round() * 15).clamp(0, 23 * 60 + 45));
            },
          ),
        ),
        for (var i = 0; i < entries.length; i++)
          Positioned(
            top: (entries[i].start - from) * _pxPerMin,
            height: entries[i].minutes * _pxPerMin,
            // Az átfedő tételek egymás mellé kerülnek: a sáv szélessége az
            // oszlopszélesség osztva az átfedők számával.
            left: lanes[i].lane * (width / lanes[i].lanes) + 1.5,
            width: width / lanes[i].lanes - 3,
            child: _Block(
              entry: entries[i],
              group: state.groupById(entries[i].groupId),
              onTap: () => onEntryTap(entries[i]),
            ),
          ),
        if (now != null)
          Positioned(
            top: (now - from) * _pxPerMin - 1,
            left: 0,
            right: 0,
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: _nowColor,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(child: Container(height: 2, color: _nowColor)),
              ],
            ),
          ),
      ],
    );
  }
}

/// A „most" vonal színe: fix piros mindkét témában.
const _nowColor = Color(0xFFE11D48);

/// Egy tétel a heti rácsban. A tartalom a blokk magasságához igazodik: a
/// negyedórás blokkban csak a cím fér el, a hosszabban az idő és a megjegyzés
/// is. Amit így sem tudunk kiírni, azt levágjuk — kifutó szöveg helyett.
class _Block extends StatelessWidget {
  const _Block({required this.entry, required this.group, required this.onTap});

  final ScheduleEntry entry;
  final ScheduleGroup? group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = group?.color ?? theme.colorScheme.surfaceContainerHighest;
    final ink = group == null ? theme.colorScheme.onSurface : readableOn(color);
    final height = entry.minutes * _pxPerMin;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          border: group == null
              ? Border.all(color: theme.colorScheme.outlineVariant)
              : null,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: 5,
          vertical: height < 28 ? 1 : 4,
        ),
        // A doboz magassága kötött, a szöveg mérete a rendszerbetűtől függ:
        // korlátlan magasságot adunk a tartalomnak, és levágjuk a kilógót.
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxHeight: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.title,
                  maxLines: height < 34 ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                if (height >= 46)
                  // Keskeny oszlopban az idő levágva („8:00–9:…") semmit nem
                  // mond — inkább zsugorodjon, és maradjon egészben olvasható.
                  FitText(
                    '${hhmm(entry.start)}–${hhmm(entry.end)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ink.withValues(alpha: 0.8),
                    ),
                  ),
                if (height >= 66 && entry.note.isNotEmpty)
                  Text(
                    entry.note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ink.withValues(alpha: 0.8),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A színcsoportok jelmagyarázata a heti rács alatt: keskeny oszlopban a
/// blokkra nem fér ki minden, a szín viszont ott is beszél.
class _Legend extends StatelessWidget {
  const _Legend({required this.groups});

  final List<ScheduleGroup> groups;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Wrap(
        spacing: 14,
        runSpacing: 6,
        children: [
          for (final group in groups)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: group.color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 5),
                Text(group.name, style: theme.textTheme.labelSmall),
              ],
            ),
        ],
      ),
    );
  }
}

// ─── Napi nézet ─────────────────────────────────────────────────────────────

class _DayView extends StatelessWidget {
  const _DayView({
    required this.state,
    required this.day,
    required this.week,
    required this.now,
    required this.onEntryTap,
  });

  final ScheduleState state;
  final DateTime day;
  final int week;
  final DateTime now;
  final ValueChanged<ScheduleEntry> onEntryTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = state.dayEntries(day.weekday, week);
    final isToday = DateTime(now.year, now.month, now.day) == day;
    final nowMinutes = now.hour * 60 + now.minute;

    if (entries.isEmpty) {
      final weekend = day.weekday >= DateTime.saturday;
      return _Placeholder(
        icon: weekend ? Icons.weekend_outlined : Icons.free_breakfast_outlined,
        title: weekend ? 'Szabad hétvége' : 'Ezen a napon nincs semmid',
        detail: 'A + gombbal veheted fel az első tételt erre a napra.',
      );
    }

    final total = entries.fold(0, (sum, e) => sum + e.minutes);
    // A legkésőbbi vég nem feltétlenül az utolsó tételé: egy hosszú délelőtti
    // blokk túlnyúlhat a nála később kezdődőn.
    final last = entries.fold(0, (end, e) => math.max(end, e.end));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            '${entries.length} tétel · ${spanLabel(total)} · '
            '${hhmm(entries.first.start)}-tól ${hhmm(last)}-ig',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (var i = 0; i < entries.length; i++) ...[
          // Két tétel közti üres idő: a napi lista ettől lesz idővonal, nem
          // csak felsorolás.
          if (i > 0 && entries[i].start - entries[i - 1].end >= 15)
            _Gap(minutes: entries[i].start - entries[i - 1].end),
          Appear(
            index: i,
            child: _DayCard(
              entry: entries[i],
              group: state.groupById(entries[i].groupId),
              onTap: () => onEntryTap(entries[i]),
              nowMinutes: isToday ? nowMinutes : null,
            ),
          ),
        ],
      ],
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.entry,
    required this.group,
    required this.onTap,
    required this.nowMinutes,
  });

  final ScheduleEntry entry;
  final ScheduleGroup? group;
  final VoidCallback onTap;

  /// A mai nap aktuális perce — más napon `null` (ott nincs se „most", se múlt).
  final int? nowMinutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = group?.color ?? scheme.surfaceContainerHighest;
    final now = nowMinutes;
    final running = now != null && now >= entry.start && now < entry.end;
    // A kártya ugyanaz a tömör csoportszín, mint a heti rács blokkja — egy
    // tétel ugyanúgy nézzen ki mindkét nézetben, akkor is, ha ma már elmúlt.
    // A szöveg fehér vagy fekete, amelyik olvasható rajta.
    //
    // ponytail: nincs külön „letudott" állapot. Áttetszőre halványítva a
    // beállított háttérkép ütne át a kártyán, szürkére váltva pedig pont a
    // heti nézettől térne el. Ami most van, azt a MOST jelvény mutatja.
    final plain = group == null;
    final fill = plain ? scheme.surfaceContainerHighest : color;
    final ink = plain ? scheme.onSurface : readableOn(color);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(18),
          // Színes kártyán a keret elveszne — a most futó tételt a piros
          // kontúr és a MOST jelvény emeli ki, a szürkét egy halk vonal.
          border: running
              ? Border.all(color: _nowColor, width: 2)
              : (plain ? Border.all(color: scheme.outlineVariant) : null),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 52,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FitText(
                        hhmm(entry.start),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      FitText(
                        hhmm(entry.end),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ink.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: ink,
                              ),
                            ),
                          ),
                          if (running) const _NowPill(),
                        ],
                      ),
                      if (entry.note.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          entry.note,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: ink.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        [
                          spanLabel(entry.minutes),
                          if (group != null) group!.name,
                        ].join(' · '),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: ink.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NowPill extends StatelessWidget {
  const _NowPill();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 6),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: _nowColor,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      'MOST',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    ),
  );
}

/// Két tétel közti szünet jelzése a napi listában.
class _Gap extends StatelessWidget {
  const _Gap({required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = theme.colorScheme.outlineVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
      child: Row(
        children: [
          Expanded(child: Divider(color: line, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '${spanLabel(minutes)} szünet',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Divider(color: line, height: 1)),
        ],
      ),
    );
  }
}

// ─── Üres állapotok ─────────────────────────────────────────────────────────

/// Az első indulás: tételek nélkül a beosztásnak nincs miről beszélnie.
class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                Icons.view_timeline_outlined,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Még üres a beosztásod',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Ide kerül, ami minden héten ugyanakkor van: tanórák, műszakok, '
              'edzések. Színcsoporttal jelölheted, mi tartozik össze — és '
              'kérhetsz A/B hetes beosztást is a jobb felső menüben.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const FitText('Első tétel felvétele'),
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

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(40, 20, 40, 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
