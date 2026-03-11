// GoalDetailScreen - Full detail view for a single QuarterlyGoal.
// Usage: Registered as /goals/:id route. Receives goalId as a path parameter.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/kinwii_card.dart';
import '../../../../core/widgets/progress_bar.dart';
import '../../../../models/quarterly_goal.dart';
import '../../../../models/role.dart';
import '../../../../features/auth/presentation/screens/login_screen.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final _goalDetailProvider =
    FutureProvider.autoDispose.family<QuarterlyGoal, String>(
  (ref, goalId) async {
    final api = ref.read(apiServiceProvider);
    final response = await api.get('/goals/$goalId');
    return QuarterlyGoal.fromJson(response.data as Map<String, dynamic>);
  },
);

final _rolesProvider = FutureProvider.autoDispose<List<Role>>((ref) async {
  final api = ref.read(apiServiceProvider);
  try {
    final response = await api.get('/mission/roles');
    return (response.data as List<dynamic>)
        .map((e) => Role.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return [];
  }
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({super.key, required this.goalId});

  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalAsync = ref.watch(_goalDetailProvider(goalId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
          color: AppColors.content,
        ),
        title: const Text('Goal detail'),
        actions: [
          goalAsync.maybeWhen(
            data: (goal) => IconButton(
              icon: const Icon(Icons.edit_outlined, size: 22),
              color: AppColors.kiwi500,
              tooltip: 'Edit goal',
              onPressed: () => _showEditSheet(context, ref, goal),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: goalAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.kiwi400),
        ),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: AppColors.contentTertiary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Could not load goal.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.contentSecondary,
                      ),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () =>
                      ref.invalidate(_goalDetailProvider(goalId)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (goal) => _GoalDetailBody(goal: goal, goalId: goalId),
      ),
    );
  }

  void _showEditSheet(
      BuildContext context, WidgetRef ref, QuarterlyGoal goal) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _EditGoalSheet(
        goal: goal,
        onSaved: () => ref.invalidate(_goalDetailProvider(goal.id)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------

class _GoalDetailBody extends ConsumerWidget {
  const _GoalDetailBody({required this.goal, required this.goalId});

  final QuarterlyGoal goal;
  final String goalId;

  int _weeksRemaining() {
    final now = DateTime.now();
    final diff = goal.endDate.difference(now).inDays;
    return (diff / 7).ceil().clamp(0, 999);
  }

  int _totalWeeks() {
    final diff = goal.endDate.difference(goal.startDate).inDays;
    return ((diff / 7).ceil()).clamp(1, 999);
  }

  String _quarterLabel() {
    final q = ((goal.startDate.month - 1) ~/ 3) + 1;
    return 'Q$q ${goal.startDate.year}';
  }

  List<_MonthBreakdown> _monthBreakdowns() {
    final months = <_MonthBreakdown>[];
    var cursor = DateTime(goal.startDate.year, goal.startDate.month, 1);
    final end = DateTime(goal.endDate.year, goal.endDate.month + 1, 1);
    while (cursor.isBefore(end)) {
      months.add(_MonthBreakdown(month: cursor));
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
    return months;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = DateFormat('MMM d, yyyy');
    final weeksLeft = _weeksRemaining();
    final totalWeeks = _totalWeeks();
    final weeksElapsed = (totalWeeks - weeksLeft).clamp(0, totalWeeks);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quarter badge + role
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.kiwi100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _quarterLabel(),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppColors.kiwi700,
                      ),
                ),
              ),
              if (goal.roleName != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.energyCreative,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    goal.roleName!,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: const Color(0xFF7C3AED),
                        ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // Title
          Text(
            goal.title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.content,
                ),
          ),
          const SizedBox(height: 20),

          // Progress card with inline update
          _ProgressCard(goal: goal, goalId: goalId),
          const SizedBox(height: 16),

          // Dates card
          KinwiiCard(
            child: Row(
              children: [
                _InfoItem(
                  label: 'Start',
                  value: fmt.format(goal.startDate),
                ),
                const SizedBox(width: 1),
                Container(
                    width: 1, height: 36, color: AppColors.borderSubtle),
                const SizedBox(width: 1),
                _InfoItem(
                  label: 'End',
                  value: fmt.format(goal.endDate),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Week tracker
          KinwiiCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Week $weeksElapsed of $totalWeeks',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.content,
                      ),
                ),
                Text(
                  weeksLeft == 0
                      ? 'Goal ended'
                      : '$weeksLeft wk${weeksLeft == 1 ? '' : 's'} remaining',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.contentSecondary,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Why it matters
          if (goal.why != null && goal.why!.isNotEmpty) ...[
            Text(
              'Why it matters',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.content,
                  ),
            ),
            const SizedBox(height: 8),
            KinwiiCard(
              child: Text(
                goal.why!,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.contentSecondary,
                      height: 1.6,
                    ),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Monthly breakdown
          Text(
            'Monthly breakdown',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.content,
                ),
          ),
          const SizedBox(height: 8),
          ..._monthBreakdowns().map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _MonthBreakdownTile(breakdown: m, goal: goal),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Progress card with inline slider
// ---------------------------------------------------------------------------

class _ProgressCard extends ConsumerStatefulWidget {
  const _ProgressCard({required this.goal, required this.goalId});

  final QuarterlyGoal goal;
  final String goalId;

  @override
  ConsumerState<_ProgressCard> createState() => _ProgressCardState();
}

class _ProgressCardState extends ConsumerState<_ProgressCard> {
  late int _progress;
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _progress = widget.goal.progressPercent;
  }

  @override
  void didUpdateWidget(_ProgressCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.goal.progressPercent != widget.goal.progressPercent) {
      _progress = widget.goal.progressPercent;
    }
  }

  Future<void> _saveProgress() async {
    if (_progress == widget.goal.progressPercent) {
      setState(() => _editing = false);
      return;
    }
    setState(() => _saving = true);
    try {
      final api = ref.read(apiServiceProvider);
      await api.put('/goals/${widget.goalId}', data: {
        'progress_percent': _progress,
      });
      ref.invalidate(_goalDetailProvider(widget.goalId));
      if (mounted) setState(() => _editing = false);
    } catch (_) {
      if (mounted) {
        setState(() => _progress = widget.goal.progressPercent);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KinwiiCard(
      color: AppColors.kiwi50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Progress',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.kiwi600,
                    ),
              ),
              if (_editing)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$_progress%',
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: AppColors.kiwi600,
                              ),
                    ),
                    const SizedBox(width: 8),
                    _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.kiwi400,
                            ),
                          )
                        : GestureDetector(
                            onTap: _saveProgress,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.kiwi400,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Save',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: Colors.white),
                              ),
                            ),
                          ),
                  ],
                )
              else
                GestureDetector(
                  onTap: () => setState(() => _editing = true),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$_progress%',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: AppColors.kiwi600,
                                ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: AppColors.kiwi500,
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_editing) ...[
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: AppColors.kiwi400,
                inactiveTrackColor: AppColors.kiwi100,
                thumbColor: AppColors.kiwi500,
                overlayColor: AppColors.kiwi400.withValues(alpha: 0.15),
                trackHeight: 6,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                value: _progress.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                onChanged: (v) =>
                    setState(() => _progress = v.round()),
              ),
            ),
          ] else ...[
            ProgressBar(percent: _progress, height: 8),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit goal bottom sheet
// ---------------------------------------------------------------------------

class _EditGoalSheet extends ConsumerStatefulWidget {
  const _EditGoalSheet({required this.goal, required this.onSaved});

  final QuarterlyGoal goal;
  final VoidCallback onSaved;

  @override
  ConsumerState<_EditGoalSheet> createState() => _EditGoalSheetState();
}

class _EditGoalSheetState extends ConsumerState<_EditGoalSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _whyController;
  late int _progress;
  String? _selectedRoleId;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.goal.title);
    _whyController = TextEditingController(text: widget.goal.why ?? '');
    _progress = widget.goal.progressPercent;
    _selectedRoleId = widget.goal.roleId;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _whyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.length < 5) {
      setState(() => _error = 'Goal title must be at least 5 characters.');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiServiceProvider);
      await api.put('/goals/${widget.goal.id}', data: {
        'title': title,
        'why': _whyController.text.trim(),
        'progress_percent': _progress,
        if (_selectedRoleId != null) 'role_id': _selectedRoleId,
      });
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to update goal. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Edit goal', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 20),
          TextField(
            controller: _titleController,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Goal title',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _whyController,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Why it matters (optional)',
            ),
          ),
          const SizedBox(height: 14),
          // Role dropdown
          ref.watch(_rolesProvider).when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (roles) {
                  if (roles.isEmpty) return const SizedBox.shrink();
                  return DropdownButtonFormField<String?>(
                    initialValue: _selectedRoleId,
                    decoration: const InputDecoration(
                      labelText: 'Life role (optional)',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('No role'),
                      ),
                      ...roles.map((r) => DropdownMenuItem(
                            value: r.id,
                            child: Text(r.name),
                          )),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedRoleId = value),
                  );
                },
              ),
          const SizedBox(height: 18),
          // Progress slider
          Text(
            'Progress: $_progress%',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.contentSecondary,
                ),
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppColors.kiwi400,
              inactiveTrackColor: AppColors.kiwi100,
              thumbColor: AppColors.kiwi500,
              overlayColor: AppColors.kiwi400.withValues(alpha: 0.15),
              trackHeight: 6,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: _progress.toDouble(),
              min: 0,
              max: 100,
              divisions: 20,
              onChanged: (v) => setState(() => _progress = v.round()),
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
                  : const Text('Save changes'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Supporting widgets
// ---------------------------------------------------------------------------

class _InfoItem extends StatelessWidget {
  const _InfoItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.contentTertiary,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.content,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}

class _MonthBreakdown {
  const _MonthBreakdown({required this.month});

  final DateTime month;
}

class _MonthBreakdownTile extends StatelessWidget {
  const _MonthBreakdownTile({
    required this.breakdown,
    required this.goal,
  });

  final _MonthBreakdown breakdown;
  final QuarterlyGoal goal;

  String _status() {
    final now = DateTime.now();
    final monthEnd = DateTime(
      breakdown.month.year,
      breakdown.month.month + 1,
      0,
    );
    if (monthEnd.isBefore(now)) return 'Past';
    if (breakdown.month.month == now.month &&
        breakdown.month.year == now.year) {
      return 'Current';
    }
    return 'Upcoming';
  }

  @override
  Widget build(BuildContext context) {
    final monthName = DateFormat('MMMM yyyy').format(breakdown.month);
    final status = _status();
    final isCurrent = status == 'Current';

    return KinwiiCard(
      color: isCurrent ? AppColors.kiwi50 : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              monthName,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.content,
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                  ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isCurrent ? AppColors.kiwi100 : AppColors.borderSubtle,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              status,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color:
                        isCurrent ? AppColors.kiwi700 : AppColors.contentTertiary,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
