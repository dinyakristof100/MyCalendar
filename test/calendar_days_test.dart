import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar/features/calendar/calendar_days.dart';

void main() {
  test('húsvétvasárnap ismert évekre', () {
    // A húsvét-alapú munkaszüneti napok (nagypéntek, húsvét- és pünkösdhétfő)
    // ezen a számításon állnak.
    expect(easterSunday(2024), DateTime(2024, 3, 31));
    expect(easterSunday(2025), DateTime(2025, 4, 20));
    expect(easterSunday(2026), DateTime(2026, 4, 5));
    expect(easterSunday(2027), DateTime(2027, 3, 28));
  });

  test('naptípusok 2026-ra', () {
    // Nemzeti ünnepek.
    expect(dayKindOf(DateTime(2026, 8, 20)), DayKind.holiday);
    // Március 15. 2026-ban vasárnapra esik — az ünnep megelőzi a hétvégét.
    expect(dayKindOf(DateTime(2026, 3, 15)), DayKind.holiday);
    // Egyéb munkaszüneti napok.
    expect(dayKindOf(DateTime(2026, 1, 1)), DayKind.restDay); // újév
    expect(dayKindOf(DateTime(2026, 4, 6)), DayKind.restDay); // húsvéthétfő
    expect(dayKindOf(DateTime(2026, 12, 25)), DayKind.restDay); // karácsony
    // Hétvége és hétköznap.
    expect(dayKindOf(DateTime(2026, 7, 25)), DayKind.weekend); // szombat
    expect(dayKindOf(DateTime(2026, 7, 23)), DayKind.weekday); // csütörtök
  });
}
