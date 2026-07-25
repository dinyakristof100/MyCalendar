import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar/core/notifications.dart';

void main() {
  test('gomb nélküli koppintás: csak navigáció', () {
    expect(notificationActionFor(null, '/workouts'), NotificationAction.open);
    expect(notificationActionFor('', '/'), NotificationAction.open);
    expect(
      notificationActionFor('ismeretlen_gomb', '/'),
      NotificationAction.open,
    );
  });

  test('a két gomb a saját műveletét kapja', () {
    expect(
      notificationActionFor(workoutDoneAction, '/workouts'),
      NotificationAction.workoutDone,
    );
    expect(
      notificationActionFor(snoozeAction, '/?t=Teszt&b=Holnap'),
      NotificationAction.snooze,
    );
  });

  test('payload nélkül a +10 percnek nincs mit újraütemeznie: csak nyit', () {
    expect(notificationActionFor(snoozeAction, null), NotificationAction.open);
    expect(notificationActionFor(snoozeAction, ''), NotificationAction.open);
  });
}
