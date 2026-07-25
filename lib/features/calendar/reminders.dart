import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/notifications.dart';
import 'calendar_service.dart';

/// Egész napos eseménynél a kezdés helyi éjfél, így az „egy nappal korábban”
/// hajnali 0:00-t jelentene — használhatatlan. Helyette az előző nap estéjén
/// szólunk.
///
/// ponytail: fix érték. Ha kérni fogják, ez lesz az első felhasználói beállítás.
const _allDayReminderHour = 18;

/// Ennyivel tol el a „+10 perc" gomb. A gomb feliratába is ez megy.
const _snoozeMinutes = 10;

const _details = NotificationDetails(
  android: AndroidNotificationDetails(
    'event_reminders',
    'Naptár emlékeztetők',
    channelDescription:
        'Emlékeztető a naptáresemény előtt egy nappal és egy órával.',
    importance: Importance.high,
    priority: Priority.high,
    // Enélkül a „csak prioritásos” Ne zavarjanak mód elnyeli az értesítést, és
    // akkor az órára sem jut el. Eseményként a naptár-kivétel átengedi.
    category: AndroidNotificationCategory.event,
    actions: [
      AndroidNotificationAction(
        snoozeAction,
        '+$_snoozeMinutes perc',
        showsUserInterface: true,
      ),
    ],
  ),
  iOS: DarwinNotificationDetails(),
);

/// Egy esemény emlékeztetői: 24 órával előtte, és időpontos eseménynél egy
/// órával előtte is. A `slot` az azonosító-eltolás (0/1), hogy a két értesítés
/// ne írja felül egymást.
///
/// A 24 órás emlékeztető fali óra szerint számol (nap − 1), nem 24 óra
/// kivonásával — így a nyári időszámítás váltásának hetében sem csúszik el egy
/// órát. Az egyórásnál a fix időtartam-kivonás a helyes (abszolút idő).
List<({DateTime when, String body, int slot})> remindersFor(
  CalendarEvent event,
) {
  final at = event.at;
  final start = formatStart(event);
  if (event.allDay) {
    // ponytail: egész napos eseménynél nincs értelmes „egy órával előtte” — a
    // kezdés helyi éjfél. Marad az egyetlen előző esti emlékeztető.
    return [
      (
        when: DateTime(at.year, at.month, at.day - 1, _allDayReminderHour),
        body: 'Holnap — $start',
        slot: 0,
      ),
    ];
  }
  return [
    (
      when: DateTime(at.year, at.month, at.day - 1, at.hour, at.minute),
      body: 'Holnap — $start',
      slot: 0,
    ),
    (
      when: at.subtract(const Duration(hours: 1)),
      body: 'Egy óra múlva — $start',
      slot: 1,
    ),
  ];
}

/// Amit legutóbb kiütemeztünk. Lásd [remindersSignature].
String _scheduled = '';

/// Az ütemezést meghatározó adatok egy sorban: ha ez nem változott, nincs mit
/// újraütemezni.
String remindersSignature(List<CalendarEvent> events) => [
  for (final event in events)
    for (final r in remindersFor(event))
      '${event.id}|${event.title}|${r.when}|${r.body}',
].join(';');

/// Újraütemezi az emlékeztetőket a kapott eseményekre.
///
/// Előbb mindent töröl: a naptárban azóta törölt vagy áthelyezett esemény így
/// nem hagy maga után árva emlékeztetőt, és nem kell helyi adatbázis a
/// duplikátumok kiszűréséhez. A már elmúlt időpontokat kihagyja.
Future<void> scheduleReminders(List<CalendarEvent> events) async {
  // A lista minden frissítéskor megjön — előtérbe kerüléskor, lehúzáskor,
  // mentés után —, de többnyire ugyanaz. Változatlan listára a cancelAll + N
  // ütemezés csak terhelné az Android főszálát, amiről a Flutter a vsync-et
  // kapja: ettől akadna a UI.
  final signature = remindersSignature(events);
  if (signature == _scheduled) return;
  _scheduled = signature;

  // Az emlékeztető egy nappal előre szól, egy másodperc késés semmit nem
  // jelent rajta — a most záródó lap és a lista animációja viszont pont ezt a
  // szálat használja.
  await Future<void>.delayed(const Duration(seconds: 1));

  // Csak a saját azonosítótartományunkat töröljük: a cancelAll az esti
  // edzés-kérdéseket is levinné.
  for (final pending in await notifications.pendingNotificationRequests()) {
    if (pending.id < workoutIdBase) await notifications.cancel(id: pending.id);
  }

  final now = DateTime.now();
  for (final event in events) {
    // Két azonosító eseményenként (24h + 1h). A felezett tartományba képezve,
    // *2+slot-tal, hogy egymást ne írják felül és az edzés-azonosítókkal se
    // ütközzenek (base*2+1 < workoutIdBase marad).
    final base = event.id.hashCode.abs() % (workoutIdBase ~/ 2);
    for (final r in remindersFor(event)) {
      // Az emlékeztető ideje már elmúlhatott (ma kezdődő esemény 24h-ága, vagy
      // egy órán belüli kezdés) — azt kihagyjuk, a másik ág még mehet.
      if (!r.when.isAfter(now)) continue;

      await notifications.zonedSchedule(
        id: base * 2 + r.slot,
        title: event.title,
        body: r.body,
        // A koppintás (órán a „Megnyitás telefonon”) az eseménylistára visz. A
        // cím és a szöveg query-ként vele utazik: a „+10 perc" gombnak ebből
        // kell újraépítenie az értesítést, mert az akció-válaszból csak az
        // azonosító és a payload jön vissza. Az útvonal így is '/' marad.
        payload: Uri(
          path: '/',
          queryParameters: {'t': event.title, 'b': r.body},
        ).toString(),
        // ponytail: UTC-ben ütemezünk. A plugin az abszolút időpontot küldi a
        // platformnak (ISO8601, offsettel), így nem kell külön csomag a készülék
        // IANA időzónájának kiderítéséhez. Ismétlődő értesítéshez
        // (matchDateTimeComponents) ez már nem lenne elég.
        scheduledDate: tz.TZDateTime.from(r.when, tz.UTC),
        notificationDetails: _details,
        // Az emlékeztetőnek nem kell másodperc-pontosság (egy órás előjelzésen a
        // néhány perc doze-csúszás elfér), cserébe nem kell hozzá az Android 14+
        // exact alarm engedély sem.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}

/// A „+10 perc" gomb: ugyanazzal az [id]-vel ütemezi újra a most megszólalt
/// emlékeztetőt. Az azonosító a válaszból jön, tehát marad a `base * 2 + slot`
/// tartományban (`< workoutIdBase`) — a következő teljes újraütemezés így
/// megtalálja és eltakarítja, ha közben változik az esemény.
///
/// ponytail: az eredeti szöveg megy tovább, tehát az „Egy óra múlva" 10 perccel
/// pontatlanná válik. Pontos szöveghez az eseményt kellene visszakeresni az
/// azonosítóból (az `event.id.hashCode` viszont egyirányú).
Future<void> snoozeReminder(int id, String payload) async {
  final q = Uri.parse(payload).queryParameters;
  await notifications.zonedSchedule(
    id: id,
    title: q['t'],
    body: q['b'],
    payload: payload,
    scheduledDate: tz.TZDateTime.now(
      tz.UTC,
    ).add(const Duration(minutes: _snoozeMinutes)),
    notificationDetails: _details,
    // Mint a rendes emlékeztetőnél: a néhány perc doze-csúszás belefér, cserébe
    // nincs szükség az Android 14+ exact alarm engedélyre.
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
  );
}
