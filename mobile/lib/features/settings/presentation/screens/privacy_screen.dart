// PrivacyScreen — Privacy promises, data export, device permissions.

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          'Privacy & Permissions',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.content,
              ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
        children: [
          // --- Privacy promise card ---
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.kiwi50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Icon(Icons.shield_outlined,
                    size: 48, color: AppColors.kiwi500),
                const SizedBox(height: 16),
                Text(
                  'Your privacy is important to us and we are committed to protecting your data. You are always in full control of your information and can choose what to share.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.contentSecondary,
                        height: 1.5,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // --- Our promises ---
          Text(
            'Our promises to you',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.content,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Column(
              children: [
                _PromiseRow(
                  icon: Icons.money_off_outlined,
                  title: "We don't sell your data!",
                  subtitle: 'We sell subscriptions to apps, not your data.',
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(height: 1),
                ),
                _PromiseRow(
                  icon: Icons.volume_off_outlined,
                  title: "We don't show ads!",
                  subtitle:
                      'You are here to focus, not get distracted.',
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(height: 1),
                ),
                _PromiseRow(
                  icon: Icons.location_off_outlined,
                  title: "We don't track you!",
                  subtitle:
                      'What you do elsewhere is none of our business.',
                ),
              ],
            ),
          ),



        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Promise row
// ---------------------------------------------------------------------------

class _PromiseRow extends StatelessWidget {
  const _PromiseRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.kiwi50,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, size: 18, color: AppColors.kiwi500),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.content,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.contentSecondary,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
