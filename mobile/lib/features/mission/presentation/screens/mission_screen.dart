// MissionScreen - "Why am I here? What roles do I serve?"
// Usage: Registered as /mission route (outside shell).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/kinwii_card.dart';
import '../../../../models/mission.dart';
import '../../../../models/role.dart';
import '../../../../features/auth/presentation/screens/login_screen.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final missionProvider =
    StateNotifierProvider.autoDispose<_MissionNotifier, AsyncValue<Mission?>>(
  (ref) => _MissionNotifier(ref),
);

class _MissionNotifier extends StateNotifier<AsyncValue<Mission?>> {
  _MissionNotifier(this._ref) : super(const AsyncValue.loading()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    state = const AsyncValue.loading();
    try {
      final api = _ref.read(apiServiceProvider);
      final response = await api.get('/mission');
      if (response.data == null) {
        state = const AsyncValue.data(null);
      } else {
        state = AsyncValue.data(
            Mission.fromJson(response.data as Map<String, dynamic>));
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> upsert(String statement) async {
    final api = _ref.read(apiServiceProvider);
    final response =
        await api.put('/mission', data: {'statement': statement});
    state = AsyncValue.data(
        Mission.fromJson(response.data as Map<String, dynamic>));
  }

  Future<void> refresh() => _load();
}

final rolesProvider =
    StateNotifierProvider.autoDispose<_RolesNotifier, AsyncValue<List<Role>>>(
  (ref) => _RolesNotifier(ref),
);

class _RolesNotifier extends StateNotifier<AsyncValue<List<Role>>> {
  _RolesNotifier(this._ref) : super(const AsyncValue.loading()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    state = const AsyncValue.loading();
    try {
      final api = _ref.read(apiServiceProvider);
      final response = await api.get('/mission/roles');
      final list = (response.data as List<dynamic>)
          .map((e) => Role.fromJson(e as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> addRole(String name, String? description) async {
    final api = _ref.read(apiServiceProvider);
    final response = await api.post('/mission/roles', data: {
      'name': name,
      if (description != null && description.isNotEmpty)
        'description': description,
    });
    final newRole = Role.fromJson(response.data as Map<String, dynamic>);
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([...current, newRole]);
  }

  Future<void> updateRole(String roleId, String name, String? description) async {
    final api = _ref.read(apiServiceProvider);
    await api.put('/mission/roles/$roleId', data: {
      'name': name,
      if (description != null) 'description': description,
    });
    await _load();
  }

  Future<void> deleteRole(String roleId) async {
    final api = _ref.read(apiServiceProvider);
    await api.delete('/mission/roles/$roleId');
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(current.where((r) => r.id != roleId).toList());
  }

  Future<void> refresh() => _load();
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class MissionScreen extends ConsumerWidget {
  const MissionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missionAsync = ref.watch(missionProvider);
    final rolesAsync = ref.watch(rolesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.content),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Mission & Roles',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.content,
              ),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.kiwi400,
        onRefresh: () async {
          await ref.read(missionProvider.notifier).refresh();
          await ref.read(rolesProvider.notifier).refresh();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          children: [
            // Mission section
            Text(
              'My mission',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.content,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'One sentence that captures your life direction.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.contentSecondary,
                  ),
            ),
            const SizedBox(height: 12),
            missionAsync.when(
              loading: () => const KinwiiCard(
                child: SizedBox(
                  height: 40,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppColors.kiwi400,
                      strokeWidth: 2,
                    ),
                  ),
                ),
              ),
              error: (_, __) => KinwiiCard(
                child: Text(
                  'Could not load mission.',
                  style: TextStyle(color: AppColors.contentSecondary),
                ),
              ),
              data: (mission) => _MissionCard(
                mission: mission,
                onSave: (statement) async {
                  await ref.read(missionProvider.notifier).upsert(statement);
                },
              ),
            ),

            const SizedBox(height: 32),

            // Roles section
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Life roles',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.content,
                        ),
                  ),
                ),
                IconButton(
                  onPressed: () => _showRoleSheet(context, ref),
                  icon: const Icon(
                    Icons.add_circle_outline,
                    color: AppColors.kiwi500,
                    size: 24,
                  ),
                  tooltip: 'Add role',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'The key areas of your life where you invest energy.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.contentSecondary,
                  ),
            ),
            const SizedBox(height: 12),
            rolesAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.kiwi400),
              ),
              error: (_, __) => Text(
                'Could not load roles.',
                style: TextStyle(color: AppColors.contentSecondary),
              ),
              data: (roles) {
                if (roles.isEmpty) {
                  return KinwiiCard(
                    color: AppColors.kiwi50,
                    onTap: () => _showRoleSheet(context, ref),
                    child: Row(
                      children: [
                        const Icon(Icons.person_outline,
                            color: AppColors.kiwi500, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Add your first role — e.g. Parent, Engineer, Leader',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppColors.kiwi700),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return Column(
                  children: roles
                      .map((role) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _RoleCard(
                              role: role,
                              onEdit: () =>
                                  _showRoleSheet(context, ref, role: role),
                              onDelete: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text('Delete role?'),
                                    content: Text(
                                        'This will remove "${role.name}" but keep any linked goals.'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('Delete',
                                            style:
                                                TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await ref
                                      .read(rolesProvider.notifier)
                                      .deleteRole(role.id);
                                }
                              },
                            ),
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRoleSheet(BuildContext context, WidgetRef ref, {Role? role}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _RoleSheet(
        existingRole: role,
        onSave: (name, description) async {
          if (role != null) {
            await ref
                .read(rolesProvider.notifier)
                .updateRole(role.id, name, description);
          } else {
            await ref
                .read(rolesProvider.notifier)
                .addRole(name, description);
          }
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mission card (editable)
// ---------------------------------------------------------------------------

class _MissionCard extends StatefulWidget {
  const _MissionCard({required this.mission, required this.onSave});

  final Mission? mission;
  final Future<void> Function(String) onSave;

  @override
  State<_MissionCard> createState() => _MissionCardState();
}

class _MissionCardState extends State<_MissionCard> {
  late final TextEditingController _controller;
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: widget.mission?.statement ?? '');
  }

  @override
  void didUpdateWidget(covariant _MissionCard old) {
    super.didUpdateWidget(old);
    if (!_editing && widget.mission?.statement != old.mission?.statement) {
      _controller.text = widget.mission?.statement ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(text);
      setState(() => _editing = false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return KinwiiCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 3,
              minLines: 2,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText:
                    'e.g. To build meaningful products that empower people to live with clarity.',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    _controller.text = widget.mission?.statement ?? '';
                    setState(() => _editing = false);
                  },
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (widget.mission == null) {
      return KinwiiCard(
        color: AppColors.kiwi50,
        onTap: () => setState(() => _editing = true),
        child: Row(
          children: [
            const Icon(Icons.edit_outlined,
                color: AppColors.kiwi500, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Tap to write your mission statement',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.kiwi700),
              ),
            ),
          ],
        ),
      );
    }

    return KinwiiCard(
      onTap: () => setState(() => _editing = true),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              widget.mission!.statement,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.content,
                    fontWeight: FontWeight.w500,
                    fontStyle: FontStyle.italic,
                    height: 1.5,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.edit_outlined,
              color: AppColors.contentTertiary, size: 16),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Role card
// ---------------------------------------------------------------------------

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.onEdit,
    required this.onDelete,
  });

  final Role role;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return KinwiiCard(
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.kiwi100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                role.name.isNotEmpty ? role.name[0].toUpperCase() : '?',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.kiwi600,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  role.name,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.content,
                        fontWeight: FontWeight.w500,
                      ),
                ),
                if (role.description != null &&
                    role.description!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    role.description!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.contentSecondary,
                        ),
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert,
                color: AppColors.contentTertiary, size: 20),
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Role create/edit sheet
// ---------------------------------------------------------------------------

class _RoleSheet extends StatefulWidget {
  const _RoleSheet({this.existingRole, required this.onSave});

  final Role? existingRole;
  final Future<void> Function(String name, String? description) onSave;

  @override
  State<_RoleSheet> createState() => _RoleSheetState();
}

class _RoleSheetState extends State<_RoleSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.existingRole?.name ?? '');
    _descController =
        TextEditingController(text: widget.existingRole?.description ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a role name.');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await widget.onSave(name, _descController.text.trim());
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to save role. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final isEditing = widget.existingRole != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEditing ? 'Edit role' : 'New role',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Role name',
              hintText: 'e.g. Parent, Engineer, Leader',
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _descController,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              hintText: 'e.g. Raising two kids with presence and patience',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submit,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(isEditing ? 'Save changes' : 'Add role'),
            ),
          ),
        ],
      ),
    );
  }
}
