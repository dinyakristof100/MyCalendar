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
