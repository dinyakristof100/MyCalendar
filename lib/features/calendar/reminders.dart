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

const _details = NotificationDetails(
  android: AndroidNotificationDetails(
    'event_reminders',
    'Naptár emlékeztetők',
    channelDescription: 'Emlékeztető a naptáresemény előtt egy nappal.',
    importance: Importance.high,
    priority: Priority.high,
    // Enélkül a „csak prioritásos” Ne zavarjanak mód elnyeli az értesítést, és
    // akkor az órára sem jut el. Eseményként a naptár-kivétel átengedi.
    category: AndroidNotificationCategory.event,
  ),
  iOS: DarwinNotificationDetails(),
);

/// Az emlékeztető időpontja: pontosan egy nappal a kezdés előtt, egész napos
/// eseménynél az előző nap [_allDayReminderHour] órakor.
///
/// Fali óra szerint számol (nap − 1), nem 24 óra kivonásával — így a nyári
/// időszámítás váltásának hetében sem csúszik el egy órát.
DateTime reminderTime(CalendarEvent event) {
  final at = event.at;
  return event.allDay
      ? DateTime(at.year, at.month, at.day - 1, _allDayReminderHour)
      : DateTime(at.year, at.month, at.day - 1, at.hour, at.minute);
}

/// Amit legutóbb kiütemeztünk. Lásd [remindersSignature].
String _scheduled = '';

/// Az ütemezést meghatározó adatok egy sorban: ha ez nem változott, nincs mit
/// újraütemezni.
String remindersSignature(List<CalendarEvent> events) => [
  for (final event in events)
    '${event.id}|${event.title}|${reminderTime(event)}|${formatStart(event)}',
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
    final when = reminderTime(event);
    // Ma vagy holnap kezdődő eseménynél az emlékeztető ideje már elmúlt.
    if (!when.isAfter(now)) continue;

    await notifications.zonedSchedule(
      // A tartományon belülre képezve, hogy az edzés-azonosítókkal ne ütközzön.
      id: event.id.hashCode.abs() % workoutIdBase,
      title: event.title,
      body: 'Holnap — ${formatStart(event)}',
      // A koppintás (órán a „Megnyitás telefonon”) az eseménylistára visz.
      payload: '/',
      // ponytail: UTC-ben ütemezünk. A plugin az abszolút időpontot küldi a
      // platformnak (ISO8601, offsettel), így nem kell külön csomag a készülék
      // IANA időzónájának kiderítéséhez. Ismétlődő értesítéshez
      // (matchDateTimeComponents) ez már nem lenne elég.
      scheduledDate: tz.TZDateTime.from(when, tz.UTC),
      notificationDetails: _details,
      // Egy nappal korábbi emlékeztetőnek nem kell másodperc-pontosság, cserébe
      // nem kell hozzá az Android 14+ exact alarm engedély sem.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}
