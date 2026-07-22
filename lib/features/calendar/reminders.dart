import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'calendar_service.dart';

final _plugin = FlutterLocalNotificationsPlugin();

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
  ),
  iOS: DarwinNotificationDetails(),
);

/// A `main()`-ből hívandó: plugin + időzóna-adatbázis felhúzása, és az Android
/// 13+ értesítési engedély elkérése.
Future<void> initReminders() async {
  tzdata.initializeTimeZones();
  await _plugin.initialize(
    settings: const InitializationSettings(
      // Sziluett-ikon, nem a launcher ikon: a status bar egyszínűre maszkolja,
      // a színes adaptive iconból fehér paca lenne.
      android: AndroidInitializationSettings('@drawable/ic_notification'),
      iOS: DarwinInitializationSettings(),
    ),
  );
  await _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.requestNotificationsPermission();
}

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

/// Újraütemezi az emlékeztetőket a kapott eseményekre.
///
/// Előbb mindent töröl: a naptárban azóta törölt vagy áthelyezett esemény így
/// nem hagy maga után árva emlékeztetőt, és nem kell helyi adatbázis a
/// duplikátumok kiszűréséhez. A már elmúlt időpontokat kihagyja.
Future<void> scheduleReminders(List<CalendarEvent> events) async {
  await _plugin.cancelAll();
  final now = DateTime.now();
  for (final event in events) {
    final when = reminderTime(event);
    // Ma vagy holnap kezdődő eseménynél az emlékeztető ideje már elmúlt.
    if (!when.isAfter(now)) continue;

    await _plugin.zonedSchedule(
      id: event.id.hashCode,
      title: event.title,
      body: 'Holnap — ${formatStart(event)}',
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
