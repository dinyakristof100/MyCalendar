import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cloud_sync.dart';
import '../../core/prefs.dart';
// Az A/B hét paritása ugyanaz a naptárszabály, mint az edzésterveknél — nincs
// belőle két változat.
import '../workouts/workout_plans.dart';

const scheduleKey = 'schedule';

/// A hét napjainak rövid neve (1 = hétfő), a heti rács fejlécéhez.
const scheduleWeekdays = ['H', 'K', 'Sze', 'Cs', 'P', 'Szo', 'V'];

/// Teljes név a tétel űrlapjához és a napi fejléchez.
const scheduleWeekdayNames = [
  'hétfő',
  'kedd',
  'szerda',
  'csütörtök',
  'péntek',
  'szombat',
  'vasárnap',
];

/// Perc éjféltől -> „8:00". Vezető nulla nélkül: magyarul így írjuk.
String hhmm(int minutes) =>
    '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';

/// Hossz emberi szóval: „45 perc", „3 óra", „1 óra 30 perc".
String spanLabel(int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$rest perc';
  if (rest == 0) return '$hours óra';
  return '$hours óra $rest perc';
}

/// Egy színcsoport: ezzel kötöd össze az összetartozó tételeket (pl. minden
/// előadás kék, minden gyakorlat zöld — vagy tantárgyanként, műszakonként egy).
class ScheduleGroup {
  const ScheduleGroup({
    required this.id,
    required this.name,
    required this.color,
  });

  final String id;
  final String name;
  final Color color;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'color': color.toARGB32(),
  };

  static ScheduleGroup fromJson(Map<String, Object?> json) => ScheduleGroup(
    id: json['id']! as String,
    name: json['name']! as String,
    color: Color(json['color']! as int),
  );
}

/// A beosztás egy tétele: egy adott napon, adott időben ismétlődő blokk
/// (tanóra, műszak, bármi, aminek fix helye van a hétben).
///
/// Az idő percben áll éjféltől: így a rácsban egyszerű a helyét kiszámolni, és
/// nincs időzóna, amit el lehetne rontani — a beosztás heti sablon, nem dátum.
class ScheduleEntry {
  const ScheduleEntry({
    required this.id,
    required this.weekday,
    required this.start,
    required this.end,
    required this.title,
    this.week,
    this.note = '',
    this.groupId,
  });

  final String id;
  final int weekday; // 1 = hétfő … 7 = vasárnap
  final int start; // perc éjféltől
  final int end;
  final String title;

  /// Melyik héten van: `null` = mindkettőn (sima heti beosztásnál mindig ez),
  /// 0 = A hét, 1 = B hét.
  final int? week;

  /// Terem, helyszín, oktató — ami segít eligazodni. Lehet üres.
  final String note;
  final String? groupId;

  int get minutes => end - start;

  /// Ott van-e ez a tétel a [weekday] napon, a [week] indexű héten.
  bool showsOn(int weekday, int week) =>
      this.weekday == weekday && (this.week == null || this.week == week);

  ScheduleEntry copyWith({
    int? weekday,
    int? start,
    int? end,
    String? title,
    Object? week = _keep,
    String? note,
    Object? groupId = _keep,
  }) => ScheduleEntry(
    id: id,
    weekday: weekday ?? this.weekday,
    start: start ?? this.start,
    end: end ?? this.end,
    title: title ?? this.title,
    week: week == _keep ? this.week : week as int?,
    note: note ?? this.note,
    groupId: groupId == _keep ? this.groupId : groupId as String?,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'weekday': weekday,
    'start': start,
    'end': end,
    'title': title,
    'week': week,
    'note': note,
    'groupId': groupId,
  };

  static ScheduleEntry fromJson(Map<String, Object?> json) => ScheduleEntry(
    id: json['id']! as String,
    weekday: json['weekday']! as int,
    start: json['start']! as int,
    end: json['end']! as int,
    title: json['title']! as String,
    week: json['week'] as int?,
    note: (json['note'] as String?) ?? '',
    groupId: json['groupId'] as String?,
  );
}

/// A `null` és a „nem adtam meg" megkülönböztetése a [ScheduleEntry.copyWith]-ben.
const _keep = Object();

/// A teljes beosztás: a hét típusa, a színcsoportok és a tételek.
class ScheduleState {
  const ScheduleState({
    required this.abWeeks,
    required this.groups,
    required this.entries,
  });

  static const empty = ScheduleState(abWeeks: false, groups: [], entries: []);

  /// Két hetes (A/B) beosztás-e. Sima heti beosztásnál minden tétel minden
  /// héten ott van.
  final bool abWeeks;
  final List<ScheduleGroup> groups;
  final List<ScheduleEntry> entries;

  int get weeks => abWeeks ? 2 : 1;

  ScheduleGroup? groupById(String? id) {
    if (id == null) return null;
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// A [day] dátumra eső hét indexe: sima beosztásnál mindig 0.
  int weekOf(DateTime day) => weekIndexOf(day, weeks: weeks);

  /// Egy nap tételei kezdés szerint rendezve — ez táplálja a napi listát és a
  /// heti rács egy oszlopát is.
  List<ScheduleEntry> dayEntries(int weekday, int week) {
    final day = [
      for (final e in entries)
        if (e.showsOn(weekday, week)) e,
    ];
    day.sort((a, b) => a.start == b.start ? a.end - b.end : a.start - b.start);
    return day;
  }

  Map<String, Object?> toJson() => {
    'abWeeks': abWeeks,
    'groups': [for (final g in groups) g.toJson()],
    'entries': [for (final e in entries) e.toJson()],
  };

  static ScheduleState fromJson(Map<String, Object?> json) => ScheduleState(
    abWeeks: (json['abWeeks'] as bool?) ?? false,
    groups: [
      for (final raw in (json['groups'] as List?) ?? const [])
        ScheduleGroup.fromJson((raw as Map).cast<String, Object?>()),
    ],
    entries: [
      for (final raw in (json['entries'] as List?) ?? const [])
        ScheduleEntry.fromJson((raw as Map).cast<String, Object?>()),
    ],
  );
}

/// Egy tétel helye a heti rács oszlopában: hányadik sávban áll, és hány sávra
/// osztozik a vele átfedő csoport.
typedef Lane = ({int lane, int lanes});

/// Sávkiosztás az átfedő tételeknek: az egymást átfedők egymás MELLÉ kerülnek,
/// nem egymásra. A [sorted] lista kezdés szerint rendezett (lásd
/// [ScheduleState.dayEntries]).
///
/// ponytail: mohó kiosztás (mindig az első szabad sáv), nem optimális pakolás.
/// Egy beosztásban ritka az átfedés; a lényeg, hogy egyik tétel se tűnjön el a
/// másik alatt. Ha valaha zsúfolt lesz, ide jön egy intervallum-gráf színezés.
List<Lane> laneLayout(List<ScheduleEntry> sorted) {
  final result = List<Lane>.filled(sorted.length, (lane: 0, lanes: 1));
  final laneEnd = <int>[]; // sávonként az eddigi utolsó vég
  final cluster = <int>[]; // az aktuális, egymást érő átfedő csoport
  var clusterEnd = -1;

  void flush() {
    for (final i in cluster) {
      result[i] = (lane: result[i].lane, lanes: laneEnd.length);
    }
    cluster.clear();
    laneEnd.clear();
  }

  for (var i = 0; i < sorted.length; i++) {
    final entry = sorted[i];
    // Ha ez a tétel már egyik korábbival sem fed át, a csoport lezárul.
    if (cluster.isNotEmpty && entry.start >= clusterEnd) flush();

    var lane = laneEnd.indexWhere((end) => end <= entry.start);
    if (lane < 0) {
      laneEnd.add(entry.end);
      lane = laneEnd.length - 1;
    } else {
      laneEnd[lane] = entry.end;
    }
    result[i] = (lane: lane, lanes: 1);
    cluster.add(i);
    if (entry.end > clusterEnd) clusterEnd = entry.end;
  }
  if (cluster.isNotEmpty) flush();
  return result;
}

final scheduleProvider = NotifierProvider<ScheduleController, ScheduleState>(
  ScheduleController.new,
);

class ScheduleController extends Notifier<ScheduleState> {
  @override
  ScheduleState build() {
    final raw = prefs.getString(scheduleKey);
    if (raw == null) return ScheduleState.empty;
    return ScheduleState.fromJson(
      (jsonDecode(raw) as Map).cast<String, Object?>(),
    );
  }

  /// Új tétel felvitele vagy meglévő felülírása — az azonosító dönti el.
  Future<void> saveEntry(ScheduleEntry entry) => saveEntries([entry]);

  /// Több tétel egy menetben (egy űrlap több napra). Minden nap külön tétel
  /// saját azonosítóval: így egy nap törlése a többit nem viszi el.
  Future<void> saveEntries(Iterable<ScheduleEntry> entries) async {
    var next = state.entries;
    for (final entry in entries) {
      next = next.any((e) => e.id == entry.id)
          ? [
              for (final e in next)
                if (e.id == entry.id) entry else e,
            ]
          : [...next, entry];
    }
    state = _with(entries: next);
    await _save();
  }

  Future<void> removeEntry(String id) async {
    state = _with(
      entries: [
        for (final e in state.entries)
          if (e.id != id) e,
      ],
    );
    await _save();
  }

  Future<void> clearEntries() async {
    state = _with(entries: const []);
    await _save();
  }

  Future<ScheduleGroup> saveGroup(ScheduleGroup group) async {
    final exists = state.groups.any((g) => g.id == group.id);
    state = _with(
      groups: exists
          ? [
              for (final g in state.groups)
                if (g.id == group.id) group else g,
            ]
          : [...state.groups, group],
    );
    await _save();
    return group;
  }

  /// Csoport törlése: a rá hivatkozó tételek nem tűnnek el, csak elvesztik a
  /// színüket — különben egy nem létező csoportra mutatnának.
  Future<void> removeGroup(String id) async {
    state = _with(
      groups: [
        for (final g in state.groups)
          if (g.id != id) g,
      ],
      entries: [
        for (final e in state.entries)
          if (e.groupId == id) e.copyWith(groupId: null) else e,
      ],
    );
    await _save();
  }

  /// Váltás sima heti és A/B beosztás között.
  ///
  /// A/B-re váltva a meglévő tételek mindkét héten megmaradnak (`week == null`),
  /// tehát semmi nem vész el. Vissza sima hetire viszont a CSAK a B héten élő
  /// tételeknek nem lenne hol lenniük: azok törlődnek (a hívó előre megkérdezi,
  /// lásd [bOnlyCount]), az A-hetiek pedig mindkét hétre kerülnek.
  Future<void> setAbWeeks(bool value) async {
    state = _with(
      abWeeks: value,
      entries: value
          ? state.entries
          : [
              for (final e in state.entries)
                if (e.week != 1) e.copyWith(week: null),
            ],
    );
    await _save();
  }

  /// Hány tétel élne csak a B héten — ennyit vinne el a sima hetire váltás.
  int get bOnlyCount => state.entries.where((e) => e.week == 1).length;

  ScheduleState _with({
    bool? abWeeks,
    List<ScheduleGroup>? groups,
    List<ScheduleEntry>? entries,
  }) => ScheduleState(
    abWeeks: abWeeks ?? state.abWeeks,
    groups: groups ?? state.groups,
    entries: entries ?? state.entries,
  );

  Future<void> _save() => saveSetting(scheduleKey, jsonEncode(state.toJson()));
}
