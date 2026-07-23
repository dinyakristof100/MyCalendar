import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

final categoriesProvider =
    NotifierProvider<CategoryController, CategoryState>(CategoryController.new);

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

  Future<void> _saveCategories() => prefs.setString(
    _categoriesKey,
    jsonEncode([for (final c in state.categories) c.toJson()]),
  );

  Future<void> _saveAssignments() =>
      prefs.setString(_assignmentsKey, jsonEncode(state.assignments));
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

/// A kategóriaválasztó lap: itt lehet kategóriát rendelni az eseményhez, újat
/// létrehozni, vagy törölni. Ez a "kategóriák az eseményeknél" felület.
Future<void> showCategoryPicker(BuildContext context, String eventId) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _CategoryPicker(eventId: eventId),
  );
}

class _CategoryPicker extends ConsumerWidget {
  const _CategoryPicker({required this.eventId});

  final String eventId;

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
    final current = state.of(eventId);

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Kategória',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            // "Nincs" — a hozzárendelés törlése.
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.block,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              title: const Text('Nincs kategória'),
              trailing: current == null
                  ? Icon(Icons.check, color: theme.colorScheme.primary)
                  : null,
              onTap: () async {
                await ref.read(categoriesProvider.notifier).assign(eventId, null);
                if (context.mounted) Navigator.pop(context);
              },
            ),
            for (final category in state.categories)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CategoryDot(color: category.color, size: 18),
                title: Text(category.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (category.id == current?.id)
                      Icon(Icons.check, color: theme.colorScheme.primary),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      color: theme.colorScheme.onSurfaceVariant,
                      tooltip: 'Törlés',
                      onPressed: () => _confirmDelete(context, ref, category),
                    ),
                  ],
                ),
                onTap: () async {
                  await ref
                      .read(categoriesProvider.notifier)
                      .assign(eventId, category.id);
                  if (context.mounted) Navigator.pop(context);
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
                final created = await _showCreateDialog(context, ref);
                // Az újat egyből rá is tesszük az eseményre — aki most hozta
                // létre, arra akarja tenni.
                if (created != null) {
                  await ref
                      .read(categoriesProvider.notifier)
                      .assign(eventId, created.id);
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

Future<EventCategory?> _showCreateDialog(BuildContext context, WidgetRef ref) {
  return showDialog<EventCategory>(
    context: context,
    builder: (_) => const _CreateCategoryDialog(),
  );
}

class _CreateCategoryDialog extends ConsumerStatefulWidget {
  const _CreateCategoryDialog();

  @override
  ConsumerState<_CreateCategoryDialog> createState() =>
      _CreateCategoryDialogState();
}

class _CreateCategoryDialogState extends ConsumerState<_CreateCategoryDialog> {
  final _name = TextEditingController();
  Color _color = categoryColors.first;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _saving) return;
    setState(() => _saving = true);
    final created = await ref
        .read(categoriesProvider.notifier)
        .addCategory(name, _color);
    if (mounted) Navigator.pop(context, created);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Új kategória'),
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
          child: const Text('Létrehozás'),
        ),
      ],
    );
  }
}
