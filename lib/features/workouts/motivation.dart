/// Motiváció a kipipált edzésekhez és „lite" gondolkodtató a kihagyás ellen.
///
/// Minden üzenet determinisztikusan, a naptári napból forog — nincs tárolt
/// állapot, nincs véletlen: ugyanaz a nap ugyanazt az üzenetet adja (így az
/// előre ütemezett esti értesítés és a képernyő nem mond mást), másnap viszont
/// mindenhol új szöveg jön.
library;

/// Dicséret egy kipipált edzés után.
const praiseMessages = [
  'Szép munka! Egy edzéssel közelebb a heti célhoz.',
  'Kipipálva — a jövőbeli éned ezt megköszöni.',
  'Ez az! Nem a motiváció számít, hanem hogy megcsináltad.',
  'Megvan! Az izom ma épül, a szokás már kész.',
  'Erős nap. A terv papíron volt, te valóra váltottad.',
  'Pipa! A folytatás mindig könnyebb, mint az újrakezdés.',
];

/// Külön ünneplés, amikor a hét utolsó edzése is megvan.
const weekCompleteMessages = [
  'A heti terv 100%! Ezt a hetet megnyerted.',
  'Minden edzés megvan erre a hétre — így néz ki a következetesség.',
  'Teljes hét! A pihenőt most már megérdemled.',
];

/// Miért rossz kihagyni — a „lite" gondolkodtató egyik fele.
const skipCosts = [
  'Egy kihagyott edzésből könnyen kettő lesz — a kihagyás is szokássá válik.',
  'Amit nem használsz, azt a tested lassan leépíti — a forma nem vár meg.',
  'A „majd holnap" a leggyakoribb út a jövő heti nullához.',
  'Kihagyva az edzés a fejedben marad, és estig nyomja a lelkiismeretet.',
];

/// Miért jó megcsinálni — a másik fele.
const doneGains = [
  'Edzés után jobb az alvás és több az energia — még ma érezni fogod.',
  'Fél óra mozgás órákkal jobb hangulatot ad.',
  'Minden befejezett edzés bizonyíték, hogy betartod, amit magadnak ígérsz.',
  'A haladást nem a tökéletes hetek adják, hanem a befejezett napok.',
  'A legrosszabb edzés is veri a kihagyottat.',
];

/// A nap sorszáma egy rögzített origótól — ez forgatja az üzeneteket.
int _dayIndex(DateTime day) =>
    DateTime(day.year, day.month, day.day).difference(DateTime(2024)).inDays;

/// A pipálás utáni üzenet. A hét utolsó edzése külön ünneplést kap; a többinél
/// a nap ÉS az aznapi sorszám is forgat, hogy egy napon belül se ismétlődjön.
/// Ha teljes lett a hét és van élő [streak] (legalább 2), a sorozatot is kiírja.
String praiseFor({
  required int done,
  required int total,
  required DateTime day,
  int streak = 0,
}) {
  final index = _dayIndex(day);
  if (done < total) {
    return praiseMessages[(index + done) % praiseMessages.length];
  }
  final base = weekCompleteMessages[index % weekCompleteMessages.length];
  return streak >= 2 ? '$base 🔥 $streak hét zsinórban!' : base;
}

/// A napi gondolkodtató páros: mit veszítesz kihagyva, mit nyersz megcsinálva.
/// A két lista hossza eltér, így a párosítás is napról napra más.
({String cost, String gain}) reflectionFor(DateTime day) {
  final index = _dayIndex(day);
  return (
    cost: skipCosts[index % skipCosts.length],
    gain: doneGains[index % doneGains.length],
  );
}

/// Az esti kérdés alá szánt egysoros. Ha van megvédhető [streak] (legalább 2
/// hét), a sorozat elvesztése az erősebb ösztönző — azt írjuk. Különben páros
/// napon a nyereség, páratlanon a veszteség, hogy ne mindig ugyanonnan szóljon.
String nudgeLineFor(DateTime day, {int streak = 0}) {
  if (streak >= 2) return 'Ne szakítsd meg a $streak hetes sorozatod!';
  final reflection = reflectionFor(day);
  return _dayIndex(day).isEven ? reflection.gain : reflection.cost;
}
