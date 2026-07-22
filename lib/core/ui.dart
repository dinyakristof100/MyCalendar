import 'dart:async';

import 'package:flutter/material.dart';

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
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    // A késleltetést timer adja, nem Interval — így a lista hosszától
    // függetlenül minden elem ugyanolyan gyorsan úszik be.
    _delay = Timer(
      Duration(milliseconds: 45 * widget.index),
      _controller.forward,
    );
  }

  @override
  void dispose() {
    _delay?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;

    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}
