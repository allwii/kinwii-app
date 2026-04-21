// Shared task detail bottom sheet used by Today and Week screens.
// Caller wires up onUpdate / onDelete / onToggleComplete callbacks so the
// sheet stays agnostic of the underlying provider/state.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../models/quarterly_goal.dart';
import '../../models/task.dart';

typedef TaskUpdateCallback = Future<void> Function(
    String taskId, Map<String, dynamic> fields);
typedef TaskIdCallback = Future<void> Function(String taskId);

class TaskDetailSheet extends StatefulWidget {
  const TaskDetailSheet({
    super.key,
    required this.task,
    required this.goals,
    required this.onUpdate,
    required this.onDelete,
    required this.onToggleComplete,
    this.currentGoalName,
  });

  final Task task;
  final List<QuarterlyGoal> goals;
  final String? currentGoalName;
  final TaskUpdateCallback onUpdate;
  final TaskIdCallback onDelete;
  final TaskIdCallback onToggleComplete;

  @override
  State<TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends State<TaskDetailSheet> {
  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late DateTime _date;
  String? _selectedGoalId;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _saving = false;
  bool _dirty = false;
  bool _descFullView = false;

  /// Resolve the goal name from the current `_selectedGoalId` against the
  /// goals list, falling back to `widget.currentGoalName` for legacy tasks
  /// that have no `quarter_id` of their own.
  String? get _selectedGoalName {
    if (_selectedGoalId != null) {
      final match =
          widget.goals.where((g) => g.id == _selectedGoalId).toList();
      if (match.isNotEmpty) return match.first.title;
    }
    return widget.currentGoalName;
  }

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.task.title);
    _descCtrl = TextEditingController(text: widget.task.description ?? '');
    _selectedGoalId = widget.task.quarterId;
    _date = widget.task.date;
    if (widget.task.startTime != null) {
      try {
        final parts = widget.task.startTime!.split(':');
        _startTime = TimeOfDay(
            hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      } catch (_) {}
    }
    if (widget.task.endTime != null) {
      try {
        final parts = widget.task.endTime!.split(':');
        _endTime = TimeOfDay(
            hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  bool get _isOverdue {
    if (_endTime == null && _startTime == null) return false;
    final now = DateTime.now();
    final checkTime = _endTime ?? _startTime!;
    final taskDateTime = DateTime(
        _date.year, _date.month, _date.day, checkTime.hour, checkTime.minute);
    return taskDateTime.isBefore(now) && !widget.task.completed;
  }

  String get _dateLabel {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final taskDay = DateTime(_date.year, _date.month, _date.day);
    final diff = taskDay.difference(today).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    return DateFormat('EEE, MMM d').format(_date);
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _saving = true);

    String? startStr;
    String? endStr;
    if (_startTime != null) {
      startStr =
          '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}:00';
    }
    if (_endTime != null) {
      endStr =
          '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}:00';
    }

    try {
      await widget.onUpdate(widget.task.id, {
        'title': title,
        'description':
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'date': DateFormat('yyyy-MM-dd').format(_date),
        if (startStr != null) 'start_time': startStr,
        if (endStr != null) 'end_time': endStr,
        'quarter_id': _selectedGoalId,
      });
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    await widget.onDelete(widget.task.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.kiwi400),
        ),
        child: child!,
      ),
    );
    if (pickedDate == null || !mounted) return;
    setState(() {
      _date = pickedDate;
      _dirty = true;
    });
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime ?? TimeOfDay.now(),
      helpText: 'Start time',
    );
    if (picked != null) {
      setState(() {
        _startTime = picked;
        _dirty = true;
      });
    }
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime ??
          _startTime?.replacing(hour: (_startTime!.hour + 1) % 24) ??
          TimeOfDay.now(),
      helpText: 'End time',
    );
    if (picked != null) {
      setState(() {
        _endTime = picked;
        _dirty = true;
      });
    }
  }

  String _formatTimeOfDay(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final p = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $p';
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    if (_descFullView) {
      return SizedBox(
        height: screenHeight * 0.92,
        child: _buildFullView(context, bottomPadding),
      );
    }

    return SizedBox(
      height: screenHeight * 0.6,
      child: _buildCompactView(context, bottomPadding),
    );
  }

  Widget _buildFullView(BuildContext context, double bottomPadding) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 16 + bottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTopSection(context),
          const SizedBox(height: 16),
          Text(
            _titleCtrl.text,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.content,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              controller: _descCtrl,
              autofocus: true,
              expands: true,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              textCapitalization: TextCapitalization.sentences,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.content,
                    height: 1.6,
                  ),
              decoration: InputDecoration(
                hintText: 'add details, deliverables, or notes...',
                hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.contentTertiary,
                    ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (_) => _markDirty(),
            ),
          ),
          SafeArea(
            child: Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() => _descFullView = false);
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.all(8),
                    minimumSize: Size.zero,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: AppColors.kiwi500,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: Goal chip + more menu
        Row(
          children: [
            GestureDetector(
              onTap: _showGoalPicker,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.kiwi50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.flag,
                        size: 14, color: AppColors.kiwi500),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(
                        _selectedGoalName ?? 'Select goal',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: _selectedGoalName != null
                                      ? AppColors.kiwi600
                                      : AppColors.contentTertiary,
                                  fontWeight: FontWeight.w500,
                                ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.unfold_more,
                        size: 14, color: AppColors.contentTertiary),
                  ],
                ),
              ),
            ),
            const Spacer(),
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
                      Icon(Icons.delete_outline,
                          size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Row 2: Checkmark + date + start/end time
        Row(
          children: [
            GestureDetector(
              onTap: () {
                widget.onToggleComplete(widget.task.id);
                Navigator.of(context).pop();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: widget.task.completed
                      ? AppColors.kiwi400
                      : Colors.white,
                  border: Border.all(
                    color: widget.task.completed
                        ? AppColors.kiwi400
                        : AppColors.borderSubtle,
                    width: 2,
                  ),
                ),
                child: widget.task.completed
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _pickDate,
              child: Text(
                _dateLabel,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _isOverdue ? Colors.red : AppColors.content,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
            if (_startTime != null || _endTime != null) ...[
              const SizedBox(width: 8),
              Text(
                ',',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.contentSecondary,
                    ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _pickStartTime,
                child: Text(
                  _startTime != null ? _formatTimeOfDay(_startTime!) : 'Start',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _isOverdue ? Colors.red : AppColors.content,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('–',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.contentTertiary,
                        )),
              ),
              GestureDetector(
                onTap: _pickEndTime,
                child: Text(
                  _endTime != null ? _formatTimeOfDay(_endTime!) : 'End',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _isOverdue ? Colors.red : AppColors.content,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => setState(() {
                  _startTime = null;
                  _endTime = null;
                  _dirty = true;
                }),
                child: const Icon(Icons.close,
                    size: 14, color: AppColors.contentTertiary),
              ),
            ] else ...[
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _pickStartTime,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.schedule,
                        size: 14, color: AppColors.contentTertiary),
                    const SizedBox(width: 4),
                    Text(
                      'Add time',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.contentTertiary,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildCompactView(BuildContext context, double bottomPadding) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 20 + bottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTopSection(context),
          const SizedBox(height: 16),
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
              hintText: 'Task title',
              contentPadding: EdgeInsets.zero,
              isDense: true,
            ),
            maxLines: null,
            onChanged: (_) => _markDirty(),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _descFullView = true),
              child: SingleChildScrollView(
                child: Text(
                  _descCtrl.text.isNotEmpty
                      ? _descCtrl.text
                      : 'add details, deliverables, or notes...',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _descCtrl.text.isNotEmpty
                            ? AppColors.contentSecondary
                            : AppColors.contentTertiary,
                        height: 1.5,
                      ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_dirty)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save'),
              ),
            ),
        ],
      ),
    );
  }

  void _showGoalPicker() {
    if (widget.goals.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Goal', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...widget.goals.map((g) => ListTile(
                  leading: const Icon(Icons.flag,
                      size: 16, color: AppColors.kiwi500),
                  title: Text(
                    g.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: g.id == _selectedGoalId
                      ? const Icon(Icons.check, color: AppColors.kiwi500)
                      : null,
                  onTap: () {
                    setState(() {
                      _selectedGoalId = g.id;
                      _dirty = true;
                    });
                    Navigator.of(context).pop();
                  },
                )),
          ],
        ),
      ),
    );
  }
}
