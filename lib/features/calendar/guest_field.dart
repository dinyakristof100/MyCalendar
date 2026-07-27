import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui.dart';
import 'calendar_service.dart';

/// A meghívottak mezője: e-mail címek vesszővel elválasztva, alatta a már ismert
/// címekből ajánlott csipeszek. Gépelés közben szűkül a felajánlott lista,
/// részegyezésre is (lásd [matchingGuests]).
///
/// ponytail: csipeszek a mező alatt, nem legördülő `Autocomplete`-réteg. A mező
/// TÖBB címet fogad, nem egyet választunk — a legördülő a teljes tartalmat
/// cserélné —, a felugró réteg pedig a felcsúszó lapon és a párbeszédben a
/// billentyűzet fölött kiszámíthatatlan helyre kerülne. A csipesz ujjbarát
/// célpont, és gépelés előtt is megmutatja a leggyakoribb címeket.
class GuestField extends ConsumerWidget {
  const GuestField({
    required this.controller,
    required this.label,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;

  /// A mező felirata — új eseménynél „Meghívottak", meglévőnél „További
  /// meghívottak".
  final String label;
  final bool autofocus;

  /// A hívó saját állapotához (mentés gomb, tájékoztató sáv) — a csipeszek
  /// frissítéséhez NEM kell, azt a mező értéke hajtja.
  final VoidCallback? onChanged;
  final VoidCallback? onSubmitted;

  /// A választott cím a gépelt rész helyére kerül, és a mező készen áll a
  /// következőre.
  void _pick(String email) {
    controller.text = withGuest(controller.text, email);
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    onChanged?.call();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Betöltés vagy hiba alatt üres: javaslat nélkül a mező sima beírómező.
    final known = ref.watch(knownGuestsProvider).value ?? const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          autofocus: autofocus,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onChanged: (_) => onChanged?.call(),
          onSubmitted: (_) => onSubmitted?.call(),
          decoration: InputDecoration(
            labelText: label,
            hintText: 'anna@pelda.hu, bela@pelda.hu',
            prefixIcon: const Icon(Icons.group_outlined),
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        // A mező értékére figyelünk, nem a szülő újraépítésére: így a javaslatok
        // minden leütésre frissülnek, akkor is, ha a hívó nem kér `setState`-et.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final matches = matchingGuests(known, value.text);
            if (matches.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final email in matches)
                    ActionChip(
                      avatar: const Icon(Icons.person_outline, size: 18),
                      // A hosszú címek zsugorodnak, nem futnak ki a csipeszből.
                      label: FitText(email),
                      onPressed: () => _pick(email),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
