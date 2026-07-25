import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cloud_sync.dart';
import '../../core/prefs.dart';

const _categoriesKey = 'eventCategories';
const _assignmentsKey = 'eventCategoryAssignments';

/// A választható kategóriaszínek: kézzel válogatott, jól elkülönülő árnyalatok.
const categoryColors = [
  Color(0xFFE11D48), // piros
  Color(0xFFF97316), // narancs
  Color(0xFFF59E0B), // borostyán
  Color(0xFF16A34A), // zöld
  Color(0xFF0EA5A0), // türkiz
  Color(0xFF2563EB), // kék
  Color(0xFF7C3AED), // lila
  Color(0xFFDB2777), // rózsaszín
  Color(0xFF64748B), // pala
];

/// Egy eseménykategória: név és szín. A színt ARGB egészként tároljuk.
class EventCategory {
  const EventCategory({
    required this.id,
    required this.name,
    required this.color,
  });

  final String id;
  final String name;
  final Color color;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'color': color.toARGB32(),
  };

  static EventCategory fromJson(Map<String, Object?> json) => EventCategory(
    id: json['id']! as String,
    name: json['name']! as String,
    color: Color(json['color']! as int),
  );
}

/// A kategóriák és az esemény→kategória hozzárendelések együtt.
///
/// A hozzárendelés az esemény azonosítójára megy (nem a példányra), így egy
/// ismétlődő esemény minden előfordulása ugyanazt a kategóriát kapja — ami a
/// naptárban pont a kívánt viselkedés.
class CategoryState {
  const CategoryState({required this.categories, required this.assignments});

  final List<EventCategory> categories;
  final Map<String, String> assignments; // eseményId -> kategóriaId

  EventCategory? byId(String? id) {
    if (id == null) return null;
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Az eseményhez rendelt kategória, vagy `null`, ha nincs.
  EventCategory? of(String eventId) => byId(assignments[eventId]);
}

final categoriesProvider = NotifierProvider<CategoryController, CategoryState>(
  CategoryController.new,
);

class CategoryController extends Notifier<CategoryState> {
  @override
  CategoryState build() => CategoryState(
    categories: [
      for (final raw
          in jsonDecode(prefs.getString(_categoriesKey) ?? '[]') as List)
        EventCategory.fromJson((raw as Map).cast<String, Object?>()),
    ],
    assignments: {
      for (final e
          in (jsonDecode(prefs.getString(_assignmentsKey) ?? '{}') as Map)
              .entries)
        e.key as String: e.value as String,
    },
  );

  Future<EventCategory> addCategory(String name, Color color) async {
    final category = EventCategory(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      color: color,
    );
    state = CategoryState(
      categories: [...state.categories, category],
      assignments: state.assignments,
    );
    await _saveCategories();
    return category;
  }

  /// Név és szín felülírása. A hozzárendelések maradnak: ugyanaz a kategória,
  /// csak máshogy hívják vagy más a színe.
  Future<EventCategory> updateCategory(
    String id,
    String name,
    Color color,
  ) async {
    final updated = EventCategory(id: id, name: name, color: color);
    state = CategoryState(
      categories: [
        for (final c in state.categories)
          if (c.id == id) updated else c,
      ],
      assignments: state.assignments,
    );
    await _saveCategories();
    return updated;
  }

  /// Törléskor a rá mutató hozzárendelések is eltűnnek — különben egy esemény
  /// egy nem létező kategóriára hivatkozna.
  Future<void> deleteCategory(String id) async {
    state = CategoryState(
      categories: [
        for (final c in state.categories)
          if (c.id != id) c,
      ],
      assignments: {
        for (final e in state.assignments.entries)
          if (e.value != id) e.key: e.value,
      },
    );
    await _saveCategories();
    await _saveAssignments();
  }

  /// `null` kategóriával a hozzárendelés törlődik.
  Future<void> assign(String eventId, String? categoryId) async {
    final next = Map<String, String>.from(state.assignments);
    if (categoryId == null) {
      next.remove(eventId);
    } else {
      next[eventId] = categoryId;
    }
    state = CategoryState(categories: state.categories, assignments: next);
    await _saveAssignments();
  }

  Future<void> _saveCategories() => saveSetting(
    _categoriesKey,
    jsonEncode([for (final c in state.categories) c.toJson()]),
  );

  Future<void> _saveAssignments() =>
      saveSetting(_assignmentsKey, jsonEncode(state.assignments));
}

/// Színes pötty egy kategóriához — a listákban és a naptárban is ez jelöl.
class CategoryDot extends StatelessWidget {
  const CategoryDot({required this.color, this.size = 12, super.key});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// A kategóriaválasztó lap: itt lehet kategóriát választani, újat létrehozni,
/// meglévőt átnevezni/átszínezni vagy törölni.
///
/// A választást [onPick] kapja meg (`null` = nincs kategória), a lap maga nem
/// ír hozzárendelést: az esemény űrlapján még nincs azonosító, amihez kötni
/// lehetne — ott a mentés végzi el.
Future<void> showCategoryPicker(
  BuildContext context, {
  required String? selectedId,
  required ValueChanged<String?> onPick,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _CategoryPicker(selectedId: selectedId, onPick: onPick),
  );
}

/// Önálló kategória-kezelő: nincs eseményhez kötve, csak létrehozás,
/// szerkesztés és törlés — így nem kell előbb egy eseményt megnyitni ahhoz,
/// hogy kategóriát lehessen csinálni. A naptár fejlécéből nyílik.
Future<void> showCategoryManager(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _CategoryPicker(selectedId: null, onPick: null),
  );
}

class _CategoryPicker extends ConsumerWidget {
  const _CategoryPicker({required this.selectedId, required this.onPick});

  /// A most kijelölt kategória — kezelő módban mindig `null`.
  final String? selectedId;

  /// `null` esetén önálló kezelő mód: nincs „Nincs kategória" sor és nincs
  /// kiválasztás, csak a kategóriák listája + létrehozás/szerkesztés/törlés.
  final ValueChanged<String?>? onPick;

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    EventCategory category,
  ) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kategória törlése'),
        content: Text(
          '„${category.name}" törlődik, és lekerül minden hozzárendelt '
          'eseményről. A naptáresemények maguk megmaradnak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Mégsem'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Törlés'),
          ),
        ],
      ),
    );
    if (yes ?? false) {
      await ref.read(categoriesProvider.notifier).deleteCategory(category.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(categoriesProvider);
    final pick = onPick;
    final managing = pick == null;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              managing ? 'Naptárkategóriák' : 'Kategória',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (managing) ...[
              const SizedBox(height: 6),
              Text(
                'Hozz létre kategóriákat névvel és színnel. Egy eseményt '
                'megnyitva rendelheted hozzá valamelyiket; a szín a naptárban '
                'és az eseménylistában is megjelenik.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 12),
            // "Nincs" — a hozzárendelés törlése (csak eseménynél).
            if (!managing)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.block,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                title: const Text('Nincs kategória'),
                trailing: selectedId == null
                    ? Icon(Icons.check, color: theme.colorScheme.primary)
                    : null,
                onTap: () {
                  pick(null);
                  Navigator.pop(context);
                },
              ),
            if (managing && state.categories.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Még nincs egyetlen kategóriád sem. Hozd létre az elsőt lent.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final category in state.categories)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CategoryDot(color: category.color, size: 18),
                title: Text(category.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (category.id == selectedId)
                      Icon(Icons.check, color: theme.colorScheme.primary),
                    PopupMenuButton<bool>(
                      icon: Icon(
                        Icons.more_vert,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      tooltip: 'Műveletek',
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: true, child: Text('Szerkesztés')),
                        PopupMenuItem(value: false, child: Text('Törlés')),
                      ],
                      onSelected: (edit) => edit
                          ? _showCategoryDialog(context, editing: category)
                          : _confirmDelete(context, ref, category),
                    ),
                  ],
                ),
                // Kezelő módban a sor koppintása is a szerkesztést nyitja — ott
                // nincs mit kiválasztani.
                onTap: managing
                    ? () => _showCategoryDialog(context, editing: category)
                    : () {
                        pick(category.id);
                        Navigator.pop(context);
                      },
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Új kategória'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () async {
                final created = await _showCategoryDialog(context);
                // Választó módban az újat egyből rátesszük (aki most hozta
                // létre, arra akarja); kezelő módban csak létrejön, a lap
                // nyitva marad.
                if (created != null && pick != null) {
                  pick(created.id);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Új kategória felvitele, vagy [editing] átnevezése/átszínezése. A létrejött
/// (illetve módosított) kategóriával tér vissza, elvetve `null`-lal.
Future<EventCategory?> _showCategoryDialog(
  BuildContext context, {
  EventCategory? editing,
}) {
  return showDialog<EventCategory>(
    context: context,
    builder: (_) => _CategoryDialog(editing: editing),
  );
}

class _CategoryDialog extends ConsumerStatefulWidget {
  const _CategoryDialog({this.editing});

  final EventCategory? editing;

  @override
  ConsumerState<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends ConsumerState<_CategoryDialog> {
  final _name = TextEditingController();
  late Color _color = widget.editing?.color ?? categoryColors.first;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name.text = widget.editing?.name ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _saving) return;
    setState(() => _saving = true);
    final controller = ref.read(categoriesProvider.notifier);
    final editing = widget.editing;
    final saved = editing == null
        ? await controller.addCategory(name, _color)
        : await controller.updateCategory(editing.id, name, _color);
    if (mounted) Navigator.pop(context, saved);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.editing == null ? 'Új kategória' : 'Kategória szerkesztése',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Név',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final color in categoryColors)
                GestureDetector(
                  onTap: () => setState(() => _color = color),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color == color
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: _color == color
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Mégsem'),
        ),
        FilledButton(
          onPressed: _name.text.trim().isEmpty || _saving ? null : _save,
          child: Text(widget.editing == null ? 'Létrehozás' : 'Mentés'),
        ),
      ],
    );
  }
}
