import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class ReminderRow extends StatelessWidget {
  const ReminderRow({
    super.key,
    required this.label,
    required this.sublabel,
    this.onSublabelTap,
    required this.time,
    required this.enabled,
    required this.onToggle,
    required this.onTimeTap,
  });

  final String label;
  final String sublabel;
  final VoidCallback? onSublabelTap;
  final TimeOfDay time;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTimeTap;

  String _formatTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final min = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$min $period';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.content,
                      ),
                ),
                GestureDetector(
                  onTap: onSublabelTap,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        sublabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: onSublabelTap != null
                                  ? AppColors.kiwi600
                                  : AppColors.contentTertiary,
                            ),
                      ),
                      if (onSublabelTap != null) ...[
                        const SizedBox(width: 2),
                        Icon(Icons.unfold_more,
                            size: 14,
                            color: AppColors.kiwi600),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: enabled ? onTimeTap : null,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: enabled ? AppColors.kiwi50 : AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _formatTime(time),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: enabled
                          ? AppColors.kiwi700
                          : AppColors.contentTertiary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 24,
            child: FittedBox(
              child: Switch.adaptive(
                value: enabled,
                onChanged: onToggle,
                activeTrackColor: AppColors.kiwi400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
