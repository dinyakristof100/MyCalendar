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

/// A kézzel válogatott alapszínek + „egyedi szín" csúszkákkal (árnyalat,
/// telítettség, világosság). A kategóriák és a beosztás-csoportok ugyanezt
/// használják — egy app, egy színválasztó.
///
/// A világosság szándékosan szűk sávban mozog ([_minLightness]–[_maxLightness]):
/// ugyanaz a szín hol egész kártyányi háttér ([readableOn] szöveggel), hol
/// vékony akcentcsík egy világos VAGY sötét lapon. A koromfekete és a
/// hófehér valamelyik témában mindig eltűnne — a sáv ezt zárja ki.
class ColorField extends StatefulWidget {
  const ColorField({
    required this.colors,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final List<Color> colors;
  final Color value;
  final ValueChanged<Color> onChanged;

  @override
  State<ColorField> createState() => _ColorFieldState();
}

const _minLightness = 0.3;
const _maxLightness = 0.8;

class _ColorFieldState extends State<ColorField> {
  /// Nyitva van-e a csúszkás panel. Mentett egyedi színnél egyből nyitva:
  /// szerkesztéskor ott folytatod, ahol abbahagytad.
  late bool _custom = !_inPalette(widget.value);

  bool _inPalette(Color color) =>
      widget.colors.any((c) => c.toARGB32() == color.toARGB32());

  HSLColor get _hsl => HSLColor.fromColor(widget.value);

  void _setHsl(HSLColor hsl) => widget.onChanged(hsl.toColor());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hsl = _hsl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final color in widget.colors)
              _Swatch(
                color: color,
                selected:
                    !_custom && color.toARGB32() == widget.value.toARGB32(),
                onTap: () {
                  setState(() => _custom = false);
                  widget.onChanged(color);
                },
              ),
            Tooltip(
              message: 'Egyedi szín',
              child: _Swatch(
                color: _custom ? widget.value : null,
                selected: _custom,
                icon: Icons.colorize,
                onTap: () {
                  // Előbb a billentyűzetet tesszük el: a névmező fókuszban van
                  // (oda gépeltél), és a billentyűzet alá esnének a csúszkák.
                  FocusManager.instance.primaryFocus?.unfocus();
                  setState(() => _custom = true);
                  // A mostani szín a kiindulás — a világosságot a sávba húzzuk,
                  // hogy a csúszka ott is találja magát, ahol állhat.
                  _setHsl(
                    hsl.withLightness(
                      hsl.lightness.clamp(_minLightness, _maxLightness),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        if (_custom) ...[
          const SizedBox(height: 18),
          _ColorSlider(
            label: 'Árnyalat',
            value: hsl.hue,
            max: 360,
            track: [
              for (var hue = 0; hue <= 360; hue += 60)
                HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.55).toColor(),
            ],
            onChanged: (value) => _setHsl(hsl.withHue(value)),
          ),
          _ColorSlider(
            label: 'Telítettség',
            value: hsl.saturation,
            max: 1,
            track: [
              hsl.withSaturation(0).toColor(),
              hsl.withSaturation(1).toColor(),
            ],
            onChanged: (value) => _setHsl(hsl.withSaturation(value)),
          ),
          _ColorSlider(
            label: 'Világosság',
            value: hsl.lightness.clamp(_minLightness, _maxLightness),
            min: _minLightness,
            max: _maxLightness,
            track: [
              hsl.withLightness(_minLightness).toColor(),
              hsl.withLightness(_maxLightness).toColor(),
            ],
            onChanged: (value) => _setHsl(hsl.withLightness(value)),
          ),
          const SizedBox(height: 4),
          Text(
            'A választott szín világos és sötét témában is látszik.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Egy színkorong a választóban. [color] nélkül szivárvány — ez az „egyedi".
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final Color? color;
  final bool selected;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fill = color;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: fill,
          gradient: fill == null
              ? const SweepGradient(
                  colors: [
                    Color(0xFFCF7A72),
                    Color(0xFFD8AC5E),
                    Color(0xFF6FA97F),
                    Color(0xFF5FA8A3),
                    Color(0xFF7392C9),
                    Color(0xFF9B87C9),
                    Color(0xFFCF7A72),
                  ],
                )
              : null,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 3,
          ),
        ),
        child: selected
            ? Icon(
                Icons.check,
                color: readableOn(fill ?? Colors.white),
                size: 18,
              )
            : (icon == null ? null : Icon(icon, color: Colors.white, size: 18)),
      ),
    );
  }
}

/// Csúszka a saját gradiens sávján — ez mutatja, mit kapsz, ha arra húzod.
class _ColorSlider extends StatelessWidget {
  const _ColorSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.track,
    required this.onChanged,
    this.min = 0,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final List<Color> track;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(
          height: 34,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                // A hüvelykujj a sáv két végén félig kilógna: ennyivel húzzuk
                // beljebb a gradienst, hogy a szélein is fedje.
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: track),
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              ),
              SliderTheme(
                // A sávot a gradiens adja, a csúszka csak a hüvelykujjat rajzolja.
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 14,
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  thumbColor: Colors.white,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 9,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 18,
                  ),
                  trackShape: const RectangularSliderTrackShape(),
                ),
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  label: label,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
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
