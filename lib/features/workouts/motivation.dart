/// Motiváció a kipipált edzésekhez és „lite" gondolkodtató a kihagyás ellen.
///
/// Minden üzenet a naptári napból ÉS egy „forgatóból" ([spin]) áll elő — nincs
/// véletlen, tehát ugyanaz a hívás mindig ugyanazt adja. A forgatót az
/// edzésnapló megnyitása lépteti ([motivationSpin]), így minden megnyitáskor
/// más szöveg jön; a napi eltolás pedig azt adja, hogy két egymás utáni nap se
/// ugyanonnan induljon.
///
/// Az esti értesítés forgató nélkül (0-val) kérdez: azt előre kell ütemezni,
/// tehát a szövegének a nap alapján kiszámíthatónak kell lennie.
library;

import 'package:flutter/foundation.dart';

/// Hányadszor nyitották meg az edzésnaplót ebben a futásban.
///
/// Az edzésnapló füle a héjban életben marad (IndexedStack), tehát a képernyő
/// nem épül újra attól, hogy visszalépnek rá — ezért nem elég egy sima
/// számláló: a motivációs kártya erre iratkozik fel, az [AppShell] pedig lépteti
/// a fülre lépéskor.
final motivationSpin = ValueNotifier(0);

/// Dicséret egy kipipált edzés után.
const praiseMessages = [
  'Szép munka! Egy edzéssel közelebb a heti célhoz.',
  'Kipipálva — a jövőbeli éned ezt megköszöni.',
  'Ez az! Nem a motiváció számít, hanem hogy megcsináltad.',
  'Megvan! Az izom ma épül, a szokás már kész.',
  'Erős nap. A terv papíron volt, te valóra váltottad.',
  'Pipa! A folytatás mindig könnyebb, mint az újrakezdés.',
  'Ledolgozva. Ezt a napot már senki nem veheti el tőled.',
  'Kész! A kifogás lett volna a könnyebb — mégsem azt választottad.',
  'Egy újabb tégla a formádban. A fal nem egy nap alatt épül.',
  'Megcsináltad — pedig reggel még nem volt hozzá kedved.',
  'Ez a nap bekerült a statisztikába. A többi már erre épül.',
  'Jó munka! Az eredményt nem ma látod, de ma alapoztad meg.',
  'Pipa. Nem kellett hozzá tökéletes nap, csak egy elkezdett edzés.',
  'Megvan! Aki hetente ennyit tesz, az fél év múlva más ember.',
  'Kész van. A tested akkor is emlékszik rá, ha te holnap már nem.',
  'Egy edzéssel közelebb. A haladás pont ilyen unalmasan néz ki.',
];

/// Külön ünneplés, amikor a hét utolsó edzése is megvan. A képernyő tetején a
/// zöld sávban és a pipálás utáni visszajelzésben is ez jelenik meg.
const weekCompleteMessages = [
  'A heti terv 100%! Ezt a hetet megnyerted.',
  'Minden edzés megvan erre a hétre — így néz ki a következetesség.',
  'Teljes hét! A pihenőt most már megérdemled.',
  'Hibátlan hét. Nem véletlen volt: te csináltad végig.',
  'A heti terv kész. Ilyen hetekből áll össze egy egész év.',
  'Minden nap letudva — most a pihenés is a terv része.',
  'Nulla kihagyás ezen a héten. Ez az a szint, amit tartani kell.',
  'Kész a hét, és a következő már erre a formára épül.',
];

/// A lezárt, de nem hibátlan hét nyugtázása: minden nap eldőlt, de volt köztük
/// szándékosan kihagyott. A `%d` helyére a kihagyott napok száma kerül.
const weekClosedMessages = [
  'A hét lezárva — %d nap kihagyva, a többi megvolt. '
      'A kihagyottat nem hozzuk át.',
  'Ennyi volt a hét: %d nap kimaradt, a többit letudtad. '
      'Jövő héten tiszta lap.',
  'Lezárva. %d kihagyott nap — nem hibátlan hét, de nem is elveszett.',
  'A hét kész: %d napot szándékosan kihagytál, a többi megvan. '
      'Ez is döntés volt.',
];

/// Miért rossz kihagyni — a „lite" gondolkodtató egyik fele.
const skipCosts = [
  'Egy kihagyott edzésből könnyen kettő lesz — a kihagyás is szokássá válik.',
  'Amit nem használsz, azt a tested lassan leépíti — a forma nem vár meg.',
  'A „majd holnap" a leggyakoribb út a jövő heti nullához.',
  'Kihagyva az edzés a fejedben marad, és estig nyomja a lelkiismeretet.',
  'A kihagyott nap nem tűnik el: átcsúszik a jövő hétre, ahol már kettő vár.',
  'Két hét szünet után az első edzés megint olyan nehéz, mint a legelső volt.',
  'A forma hetekig épül, és pár nap alatt kezd visszacsúszni.',
  'Ma még elég egy kifogás. Egy hónap múlva már magyarázat kell.',
  'A ma elmaradt fél óra este alvásban és energiában jön vissza — mínuszban.',
  'Nem egy edzés fog hiányozni, hanem a lendület, amit vele veszítesz.',
  'Aki csak a jó napokon edz, annak kevés napja marad.',
  'A sorozat egyetlen napon szakad meg, utána viszont nincs mit védeni.',
];

/// Miért jó megcsinálni — a másik fele.
const doneGains = [
  'Edzés után jobb az alvás és több az energia — még ma érezni fogod.',
  'Fél óra mozgás órákkal jobb hangulatot ad.',
  'Minden befejezett edzés bizonyíték, hogy betartod, amit magadnak ígérsz.',
  'A haladást nem a tökéletes hetek adják, hanem a befejezett napok.',
  'A legrosszabb edzés is veri a kihagyottat.',
  'Az első öt perc után már nem a kedvedről szól, hanem a lendületről.',
  'Egy edzés után a mai stressz feleannyit nyom.',
  'A mai fél óra a holnapi kedvet is megalapozza — a lendület nem jön magától.',
  'Ma nem rekordot kell dönteni. Elég megjelenni.',
  'Edzés után te leszel az, aki büszke rá — nem más.',
  'Egy megcsinált nap többet ér, mint egy tökéletesre tervezett hét.',
  'A tested minden edzésnél megjegyzi: ez az ember nem áll le.',
];

/// A nap sorszáma egy rögzített origótól — ez forgatja az üzeneteket.
int _dayIndex(DateTime day) =>
    DateTime(day.year, day.month, day.day).difference(DateTime(2024)).inDays;

/// A [messages] listából a [day] + [offset] szerinti elem. Az összes választás
/// ezen megy át: egy hellyel arrébb lépve mindig MÁSIK üzenet jön (a lista
/// hossza mindenhol nagyobb egynél).
String _pick(List<String> messages, DateTime day, int offset) =>
    messages[(_dayIndex(day) + offset) % messages.length];

/// A teljes hét ünneplése. Ha van élő [streak] (legalább 2 hét), a sorozatot is
/// kiírja.
String weekCompleteFor(DateTime day, {int streak = 0, int spin = 0}) {
  final base = _pick(weekCompleteMessages, day, spin);
  return streak >= 2 ? '$base 🔥 $streak hét zsinórban!' : base;
}

/// A lezárt hét nyugtázása [skipped] kihagyott nappal.
String weekClosedFor(DateTime day, {required int skipped, int spin = 0}) =>
    _pick(weekClosedMessages, day, spin).replaceFirst('%d', '$skipped');

/// A pipálás utáni üzenet. A hét utolsó edzése külön ünneplést kap; a többinél
/// az aznapi sorszám is beleszámít, hogy egy napon belül se ismétlődjön.
String praiseFor({
  required int done,
  required int total,
  required DateTime day,
  int streak = 0,
  int spin = 0,
}) => done < total
    ? _pick(praiseMessages, day, done + spin)
    : weekCompleteFor(day, streak: streak, spin: spin);

/// A gondolkodtató páros: mit veszítesz kihagyva, mit nyersz megcsinálva.
/// A két lista hossza eltér, így a párosítás is napról napra más.
({String cost, String gain}) reflectionFor(DateTime day, {int spin = 0}) =>
    (cost: _pick(skipCosts, day, spin), gain: _pick(doneGains, day, spin));

/// Az esti kérdés alá szánt egysoros. Ha van megvédhető [streak] (legalább 2
/// hét), a sorozat elvesztése az erősebb ösztönző — azt írjuk. Különben páros
/// napon a nyereség, páratlanon a veszteség, hogy ne mindig ugyanonnan szóljon.
///
/// Forgató nélkül számol: az értesítés napokkal előre ütemeződik.
String nudgeLineFor(DateTime day, {int streak = 0}) {
  if (streak >= 2) return 'Ne szakítsd meg a $streak hetes sorozatod!';
  final reflection = reflectionFor(day);
  return _dayIndex(day).isEven ? reflection.gain : reflection.cost;
}
