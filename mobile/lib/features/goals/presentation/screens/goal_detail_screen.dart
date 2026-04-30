// GoalDetailScreen — Inline-editable goal view (matches task detail pattern).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/progress_bar.dart';
import '../../../../models/quarterly_goal.dart';
import '../../../../services/providers.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final _goalDetailProvider =
    FutureProvider.autoDispose.family<QuarterlyGoal, String>(
  (ref, goalId) async {
    final api = ref.read(apiServiceProvider);
    final response = await api.get('/goals/$goalId');
    return QuarterlyGoal.fromJson(response.data as Map<String, dynamic>);
  },
);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({super.key, required this.goalId});

  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalAsync = ref.watch(_goalDetailProvider(goalId));

    return goalAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
            child: CircularProgressIndicator(color: AppColors.kiwi400)),
      ),
      error: (_, __) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.content),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(child: Text('Could not load goal.')),
      ),
      data: (goal) => _GoalDetailView(
        goal: goal,
        onUpdated: () => ref.invalidate(_goalDetailProvider(goalId)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail view — inline editable
// ---------------------------------------------------------------------------

class _GoalDetailView extends ConsumerStatefulWidget {
  const _GoalDetailView({required this.goal, required this.onUpdated});

  final QuarterlyGoal goal;
  final VoidCallback onUpdated;

  @override
  ConsumerState<_GoalDetailView> createState() => _GoalDetailViewState();
}

class _GoalDetailViewState extends ConsumerState<_GoalDetailView> {
  late TextEditingController _titleCtrl;
  late TextEditingController _whyCtrl;
  late int _progress;
  late DateTime _startDate;
  late DateTime _endDate;
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.goal.title);
    _whyCtrl = TextEditingController(text: widget.goal.why ?? '');
    _progress = widget.goal.progressPercent;
    _startDate = widget.goal.startDate;
    _endDate = widget.goal.endDate;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _whyCtrl.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  int get _weeksRemaining {
    final diff = _endDate.difference(DateTime.now()).inDays;
    return (diff / 7).ceil().clamp(0, 999);
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _saving = true);
    try {
      final api = ref.read(apiServiceProvider);
      await api.put('/goals/${widget.goal.id}', data: {
        'title': title,
        'why': _whyCtrl.text.trim().isEmpty ? null : _whyCtrl.text.trim(),
        'progress_percent': _progress,
        'start_date': DateFormat('yyyy-MM-dd').format(_startDate),
        'end_date': DateFormat('yyyy-MM-dd').format(_endDate),
      });
      widget.onUpdated();
      if (mounted) {
        setState(() {
          _saving = false;
          _dirty = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete goal?'),
        content: const Text('This will also remove all linked weekly plans and tasks.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child:
                const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final api = ref.read(apiServiceProvider);
      await api.delete('/goals/${widget.goal.id}');
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete goal.')),
        );
      }
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.kiwi400),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate.isBefore(_startDate)) _endDate = _startDate;
        } else {
          _endDate = picked;
        }
        _dirty = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.content),
          onPressed: () => context.pop(),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz,
                color: AppColors.contentSecondary),
            onSelected: (v) {
              if (v == 'delete') _delete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Delete goal',
                        style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Progress
            Row(
              children: [
                Text(
                  '$_progress%',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: AppColors.kiwi500,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$_weeksRemaining weeks left',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.contentSecondary,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ProgressBar(percent: _progress),
            const SizedBox(height: 4),
            SliderTheme(
              data: const SliderThemeData(
                activeTrackColor: AppColors.kiwi400,
                inactiveTrackColor: AppColors.surfaceAlt,
                thumbColor: AppColors.kiwi500,
                overlayColor: AppColors.kiwi100,
                trackHeight: 4,
                thumbShape:
                    RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                value: _progress.toDouble(),
                max: 100,
                divisions: 20,
                onChanged: (v) {
                  setState(() {
                    _progress = v.round();
                    _dirty = true;
                  });
                },
              ),
            ),

            const SizedBox(height: 12),

            // Title (inline editable, borderless)
            TextField(
              controller: _titleCtrl,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.content,
                    fontWeight: FontWeight.w600,
                  ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText: 'Goal title',
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              maxLines: null,
              onChanged: (_) => _markDirty(),
            ),

            const SizedBox(height: 8),

            // Why (inline editable)
            TextField(
              controller: _whyCtrl,
              maxLines: null,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.content,
                    height: 1.5,
                  ),
              decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText: 'Add why this goal matters...',
                hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.contentTertiary,
                    ),
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              onChanged: (_) => _markDirty(),
            ),

            const SizedBox(height: 20),

            // Dates row
            Row(
              children: [
                Expanded(
                  child: _DateChip(
                    label: 'Start',
                    date: _startDate,
                    onTap: () => _pickDate(isStart: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateChip(
                    label: 'End',
                    date: _endDate,
                    onTap: () => _pickDate(isStart: false),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: _dirty
          ? _GoalToolbar(
              onSave: _saving ? null : _save,
              onDismiss: () => FocusScope.of(context).unfocus(),
              isSaving: _saving,
            )
          : null,
    );
  }

}

// ---------------------------------------------------------------------------
// Goal toolbar — keyboard-aware save toolbar
// ---------------------------------------------------------------------------

class _GoalToolbar extends StatelessWidget {
  const _GoalToolbar({
    required this.onSave,
    required this.onDismiss,
    this.isSaving = false,
  });

  final VoidCallback? onSave;
  final VoidCallback onDismiss;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        8,
        6,
        8,
        6 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border(
          top: BorderSide(color: AppColors.borderSubtle, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onDismiss,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.keyboard_hide_outlined,
                  size: 22, color: AppColors.contentSecondary),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onSave,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: onSave != null
                    ? AppColors.kiwi400
                    : AppColors.borderSubtle,
                borderRadius: BorderRadius.circular(8),
              ),
              child: isSaving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check, size: 20, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Date chip
// ---------------------------------------------------------------------------

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.label,
    required this.date,
    required this.onTap,
  });

  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today,
                size: 14, color: AppColors.contentSecondary),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.contentTertiary,
                      ),
                ),
                Text(
                  DateFormat('MMM d, yyyy').format(date),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.content,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
