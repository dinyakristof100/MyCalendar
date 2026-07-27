import 'package:flutter/material.dart';

import '../../core/app_scaffold.dart';
import '../../core/prefs.dart';

/// Első indításkor lefutott-e már a bemutató. Szándékosan CSAK helyben él (nem
/// szinkronizált kulcs): az útmutató a telepítéshez tartozik, új készüléken
/// nyugodtan induljon el újra.
const _seenKey = 'guideSeen';

bool get guideSeen => prefs.getString(_seenKey) == 'true';

Future<void> markGuideSeen() => prefs.setString(_seenKey, 'true');

/// Egy súgótéma. Ugyanaz az adat táplálja az első indításkori bemutatót és a
/// súgóképernyőt is — két helyen ugyanazt karbantartani felesleges.
class GuideTopic {
  const GuideTopic({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

const guideTopics = <GuideTopic>[
  GuideTopic(
    icon: Icons.waving_hand_outlined,
    title: 'Üdv a MyCalendarban!',
    body:
        'Négy fül van az alsó sávban: Események, Naptár, Edzésnapló és '
        'Beállítások. Az események a telefonod saját naptárából jönnek, az '
        'edzésnapló pedig a heti tervedet vezeti. Nézzük végig, mi hol van — '
        'egy percbe se telik.',
  ),
  GuideTopic(
    icon: Icons.event_outlined,
    title: 'Események: a következő két hét',
    body:
        'Az első fülön a következő 14 nap eseményei sorakoznak, napokra '
        'bontva. Koppints egy eseményre a részletekért — ott szerkesztheted és '
        'törölheted is. A listát lehúzva frissítheted.',
  ),
  GuideTopic(
    icon: Icons.add_circle_outline,
    title: 'Új esemény felvitele',
    body:
        'A jobb alsó + gombbal. Add meg a címet, a kezdést és a véget, és '
        'rögtön kategóriát is választhatsz hozzá — nem kell utólag megnyitni. '
        'Az órát alapból begépeled; ha inkább a grafikus órát tekernéd, a '
        'Beállítások → Események alatt átkapcsolhatod. A mentés a telefonod '
        'naptárába írja az eseményt, és emlékeztetőt is kapsz róla: egy '
        'nappal és egy órával előtte. Ezeket — és az esti edzés-kérdést — a '
        'Beállítások → Értesítések alatt külön-külön ki is kapcsolhatod.',
  ),
  GuideTopic(
    icon: Icons.calendar_month_outlined,
    title: 'Naptár: a hónap egyben',
    body:
        'A második fülön hónapos rács. Oldalra húzva lapozol a hónapok között, '
        'egy napra koppintva pedig alatta megjelennek annak a napnak az '
        'eseményei. Az ünnep- és munkaszüneti napok külön színnel látszanak.',
  ),
  GuideTopic(
    icon: Icons.label_outline,
    title: 'Kategóriák és színek',
    body:
        'A naptár fejlécében a címke ikon nyitja a kategóriákat: újat hozol '
        'létre névvel és színnel, a meglévőt a mellette lévő menüből '
        'átnevezed, átszínezed vagy törlöd. Az esemény kategóriáját a színes '
        'csipeszre koppintva állítod. A szín a listában és a naptárrácsban is '
        'megjelenik.',
  ),
  GuideTopic(
    icon: Icons.fitness_center_outlined,
    title: 'Edzésnapló: a heti terved',
    body:
        'Vidd fel a terved: sima heti vagy A és B hét, hány napot edzel, és mi '
        'kerül az egyes napokra. A terv neve melletti menüből bármikor '
        'szerkesztheted vagy törölheted, több terv között pedig a fenti '
        'gombokkal váltasz.',
  ),
  GuideTopic(
    icon: Icons.check_circle_outline,
    title: 'Edzésnapok lezárása',
    body:
        'Egy napot hosszan nyomva zársz le: „Megvolt”, vagy „Kihagyom”, ha '
        'tudatosan kihagyod. Félrenyomtad? Nyomd meg újra hosszan, és a '
        '„Visszaállítás” újra nyitottá teszi. Esténként rá is kérdezünk, hogy '
        'megvolt-e a mai edzés.',
  ),
  GuideTopic(
    icon: Icons.local_fire_department_outlined,
    title: 'Sorozat és átcsúsztatás',
    body:
        'Ha egy héten minden betervezett edzés megvan, elindul a heti '
        'sorozatod 🔥. A Beállításokban bekapcsolhatod, hogy a nyitva maradt '
        'napok átcsússzanak a következő hétre — a szándékosan kihagyottakat '
        'nem hozzuk át.',
  ),
  GuideTopic(
    icon: Icons.cloud_done_outlined,
    title: 'Fiók, szinkron, megjelenés',
    body:
        'A Beállításokban választhatsz színkészletet, és ott találod a '
        'fiókodat is. A kategóriáid, edzésterveid és a haladásod a '
        'Google-fiókodhoz kötve a felhőbe is mentődnek, így új telefonon '
        'visszaállnak. A naptáresemények magán a készüléken maradnak.',
  ),
  GuideTopic(
    icon: Icons.import_export,
    title: 'Import és export',
    body:
        'A Beállítások → Adatok alatt CSV-fájlból importálhatsz eseményeket — '
        'akár egy másik naptáralkalmazás mentéséből. Ami már szerepel a '
        'naptáradban, azt kihagyjuk, az újak a Google-naptáradba kerülnek, '
        'onnan a felhőbe is. Exportnál a bekapcsolt naptáraidból készül egy '
        'fájl, amit rögtön küldhetsz e-mailben, üzenetben vagy Bluetooth-on.',
  ),
  GuideTopic(
    icon: Icons.help_outline,
    title: 'Ezt bármikor újranézheted',
    body:
        'A Beállítások → Súgó és útmutató alatt előveheted ezt a bemutatót, és '
        'témánként is elolvashatod, mi hogyan működik. Kellemes tervezést!',
  ),
];

/// Az első indításkori bemutató. Lépésenként átléphető, bármikor kihagyható —
/// akárhogy zárul, utána nem jön elő magától.
Future<void> showGuide(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const _GuideDialog(),
);

class _GuideDialog extends StatefulWidget {
  const _GuideDialog();

  @override
  State<_GuideDialog> createState() => _GuideDialogState();
}

class _GuideDialogState extends State<_GuideDialog> {
  final _pages = PageController();
  int _index = 0;

  bool get _isLast => _index == guideTopics.length - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _close() {
    markGuideSeen();
    Navigator.pop(context);
  }

  void _go(int delta) => _pages.animateToPage(
    _index + delta,
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOutCubic,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Dialog.fullscreen(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                children: [
                  Text(
                    '${_index + 1} / ${guideTopics.length}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TextButton(onPressed: _close, child: const Text('Kihagyom')),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                onPageChanged: (i) => setState(() => _index = i),
                itemCount: guideTopics.length,
                itemBuilder: (_, i) => _GuidePage(topic: guideTopics[i]),
              ),
            ),
            // Pöttyök: mutatják, hol tartunk és hány lépés van hátra.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < guideTopics.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _index ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _index
                          ? scheme.primary
                          : scheme.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Row(
                children: [
                  if (_index > 0)
                    TextButton.icon(
                      onPressed: () => _go(-1),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Vissza'),
                    ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _isLast ? _close : () => _go(1),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                    ),
                    icon: Icon(
                      _isLast ? Icons.check_rounded : Icons.arrow_forward,
                      size: 18,
                    ),
                    label: Text(_isLast ? 'Kezdhetjük!' : 'Tovább'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuidePage extends StatelessWidget {
  const _GuidePage({required this.topic});

  final GuideTopic topic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(topic.icon, size: 38, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 26),
          Text(
            topic.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            topic.body,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// A súgó: minden téma egy lenyitható szakasz, a tetején a bemutató
/// újraindításával.
///
/// ponytail: [ExpansionTile] lista, nem kereshető súgó-adatbázis. Tíz témánál a
/// keresés több karbantartás, mint amennyit ér.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppScaffold(
      title: 'Súgó és útmutató',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              'Koppints egy témára, hogy kifejtse. Ha inkább végig szeretnéd '
              'nézni, indítsd újra a bemutatót.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: FilledButton.tonalIcon(
              onPressed: () => showGuide(context),
              icon: const Icon(Icons.slideshow_outlined),
              label: const Text('Bemutató újranézése'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const Divider(height: 8),
          for (final topic in guideTopics)
            ExpansionTile(
              leading: Icon(topic.icon, color: theme.colorScheme.primary),
              title: Text(
                topic.title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                  child: Text(
                    topic.body,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
