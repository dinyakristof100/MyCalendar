import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar/features/workouts/motivation.dart';

void main() {
  test('a hét utolsó edzése ünneplő üzenetet kap, a többi dicséretet', () {
    final day = DateTime(2026, 7, 23);
    expect(
      weekCompleteMessages,
      contains(praiseFor(done: 3, total: 3, day: day)),
    );
    expect(praiseMessages, contains(praiseFor(done: 1, total: 3, day: day)));
    // Egy napon belül a második pipa is más üzenetet kap.
    expect(
      praiseFor(done: 1, total: 3, day: day),
      isNot(praiseFor(done: 2, total: 3, day: day)),
    );
  });

  test('a gondolkodtató determinisztikus, de naponta forog', () {
    final today = DateTime(2026, 7, 23, 20, 15); // a napszak nem számít
    final sameDay = DateTime(2026, 7, 23, 8);
    final tomorrow = DateTime(2026, 7, 24);

    expect(reflectionFor(today), reflectionFor(sameDay));
    expect(reflectionFor(today).cost, isNot(reflectionFor(tomorrow).cost));
    expect(reflectionFor(today).gain, isNot(reflectionFor(tomorrow).gain));
    expect(skipCosts, contains(reflectionFor(today).cost));
    expect(doneGains, contains(reflectionFor(today).gain));
  });

  test('a forgató minden lépése más szöveget hoz elő', () {
    final day = DateTime(2026, 7, 23);

    // Az edzésnapló minden megnyitása léptet egyet: a szomszédos forgatók sosem
    // adhatják ugyanazt a szöveget — ez a kérés lényege.
    for (var spin = 0; spin < 5; spin++) {
      expect(
        reflectionFor(day, spin: spin).gain,
        isNot(reflectionFor(day, spin: spin + 1).gain),
      );
      expect(
        reflectionFor(day, spin: spin).cost,
        isNot(reflectionFor(day, spin: spin + 1).cost),
      );
      expect(
        praiseFor(done: 1, total: 3, day: day, spin: spin),
        isNot(praiseFor(done: 1, total: 3, day: day, spin: spin + 1)),
      );
      expect(
        weekCompleteFor(day, spin: spin),
        isNot(weekCompleteFor(day, spin: spin + 1)),
      );
      expect(
        weekClosedFor(day, skipped: 1, spin: spin),
        isNot(weekClosedFor(day, skipped: 1, spin: spin + 1)),
      );
    }

    // Forgató nélkül minden a régi marad — ezt ütemezzük előre az értesítésbe.
    expect(reflectionFor(day), reflectionFor(day, spin: 0));
  });

  test('a lezárt hét szövegébe a kihagyott napok száma kerül', () {
    final day = DateTime(2026, 7, 23);
    expect(weekClosedFor(day, skipped: 2), contains('2'));
    expect(weekClosedFor(day, skipped: 2), isNot(contains('%d')));
    for (final message in weekClosedMessages) {
      expect(message, contains('%d'));
    }
  });

  test('az esti egysoros felváltva mutat nyereséget és veszteséget', () {
    final today = DateTime(2026, 7, 23);
    final tomorrow = DateTime(2026, 7, 24);
    final lines = {...skipCosts, ...doneGains};
    expect(lines, contains(nudgeLineFor(today)));
    expect(lines, contains(nudgeLineFor(tomorrow)));
    // Szomszédos napokon más irányból szól (páros nap: nyereség, páratlan:
    // veszteség).
    expect(
      skipCosts.contains(nudgeLineFor(today)),
      isNot(skipCosts.contains(nudgeLineFor(tomorrow))),
    );
  });
}
