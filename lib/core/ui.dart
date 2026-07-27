import 'dart:async';

import 'package:flutter/material.dart';

/// A [background] fölött biztosan olvasható szövegszín: fehér vagy fekete —
/// amelyiknek nagyobb a WCAG-kontrasztaránya az adott háttérrel. Így a
/// kategóriaszín BÁRMELY árnyalatán látszik a felirat: a világos háttér (pl.
/// borostyán) fekete, a sötét (pl. kék) fehér szöveget kap.
///
/// Kontrasztarány = (világosabb luminancia + 0.05) / (sötétebb + 0.05); a
/// fehérrel és feketével számolt közül a nagyobbat választjuk.
Color readableOn(Color background) {
  final lum = background.computeLuminance();
  final contrastWithWhite = 1.05 / (lum + 0.05); // (1.0 + 0.05) / (lum + 0.05)
  final contrastWithBlack = (lum + 0.05) / 0.05; // (lum + 0.05) / (0.0 + 0.05)
  return contrastWithWhite >= contrastWithBlack ? Colors.white : Colors.black;
}

/// Felirat, ami inkább arányosan kisebb lesz, mint hogy kifusson a helyéből.
///
/// Kis kijelzőn (és nagyobb rendszerbetűnél) egy hosszabb gomb- vagy
/// listaelem-felirat kifutna a sorából. A levágás (`…`) és a tördelés helyett
/// ilyenkor a szöveg zsugorodik, tehát egészben olvasható marad. Ott használjuk,
/// ahol a magasság kötött, a szélesség pedig szűk lehet: gombokon, csipeszeken,
/// legördülő elemeken.
///
/// Bőven elég helynél semmit nem tesz — a `scaleDown` csak lefelé méretez.
class FitText extends StatelessWidget {
  const FitText(this.text, {this.style, super.key});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    // Sor kezdetéhez igazítva: enélkül a zsugorított felirat elugrana a helyén
    // ahhoz képest, ahol elég helynél áll.
    alignment: AlignmentDirectional.centerStart,
    child: Text(text, style: style, maxLines: 1, softWrap: false),
  );
}

/// Kártyafelület árnyékkal.
///
/// Sötét témában az árnyék láthatatlan — ott a mélységet világosabb felület és
/// vékony kontúr adja. Enélkül a sötét téma laposnak látszana.
BoxDecoration cardSurface(ThemeData theme, {double radius = 22, Color? color}) {
  final dark = theme.brightness == Brightness.dark;
  return BoxDecoration(
    color: color ?? theme.colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(radius),
    border: dark
        ? Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          )
        : null,
    boxShadow: dark
        ? null
        : [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.07),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
  );
}

/// Kártya megbízhatóan kirajzolt háttérrel és koppintás-hullámmal.
///
/// NEM `Ink`-et használ: az `Ink` a hátterét az ős `Material`-re bízza, és a
/// beúszó (opacity-0 `FadeTransition` — lásd [Appear]) alatt induló kártyáknál a
/// Material nem rajzolja újra a hátteret, amíg egy koppintás vagy görgetés nem
/// kényszeríti. Így a kártya tartalma (szöveg) látszik, a háttere viszont
/// hiányzik a képernyő megérintéséig. A `DecoratedBox` maga festi a hátteret —
/// mindig az első képkockán —, a koppintás-hullámot pedig egy helyi átlátszó
/// `Material` adja. A `decoration`/`child` paraméter az `Ink`-ével egyezik, így
/// a hívás egy-az-egyben cserélhető.
class AppCard extends StatelessWidget {
  const AppCard({required this.decoration, required this.child, super.key});

  final Decoration decoration;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: decoration,
    child: Material(type: MaterialType.transparency, child: child),
  );
}

/// Beúszás lentről, sorszám szerint késleltetve.
///
/// A lépcsőzetes indítás egyetlen összefüggő mozdulatnak látszik ahelyett, hogy
/// minden elem külön ugrálna. A rendszerszintű „mozgás csökkentése” beállítást
/// tiszteletben tartja.
class Appear extends StatefulWidget {
  const Appear({required this.index, required this.child, super.key});

  final int index;
  final Widget child;

  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  );
  // Egyszer épül fel, nem buildenként: a görbe és a tween minden build-nél új
  // objektum volt, ráadásul a CurvedAnimation-t el is kell dobni.
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0, 0.12),
    end: Offset.zero,
  ).animate(_curve);
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    // A késleltetést timer adja, nem Interval — így a lista hosszától
    // függetlenül minden elem ugyanolyan gyorsan úszik be. A lépcsőt maximáljuk:
    // enélkül a hosszú lista utolsó kártyái másodpercekig 0 opacitáson (üres
    // háttéren) ragadnak, és görgetéskor csak üres helyet látni belőlük.
    _delay = Timer(
      Duration(milliseconds: 45 * widget.index.clamp(0, 6).toInt()),
      _controller.forward,
    );
  }

  @override
  void dispose() {
    _delay?.cancel();
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;

    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
