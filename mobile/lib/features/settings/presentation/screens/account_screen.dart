// AccountScreen — Edit name, change password, delete account, sign out.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../features/auth/presentation/screens/login_screen.dart';
import '../widgets/edit_name_modal.dart';
import '../widgets/password_reset_modal.dart';

// ---------------------------------------------------------------------------
// User profile provider (shared with settings screen)
// ---------------------------------------------------------------------------

class AccountProfile {
  final String? email;
  final String? name;

  const AccountProfile({this.email, this.name});
}

final _accountProfileProvider =
    FutureProvider.autoDispose<AccountProfile>((ref) async {
  final api = ref.read(apiServiceProvider);
  final resp = await api.get('/auth/me');
  final data = resp.data as Map<String, dynamic>;
  return AccountProfile(
    email: data['email'] as String?,
    name: data['name'] as String?,
  );
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(_accountProfileProvider);

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
          'Account',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: AppColors.content),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        children: [
          // Profile header
          profileAsync.when(
            data: (profile) => _ProfileHeader(
              name: profile.name,
              email: profile.email,
            ),
            loading: () => _ProfileHeader(name: null, email: null),
            error: (_, __) => _ProfileHeader(name: null, email: null),
          ),

          const SizedBox(height: 24),

          // Account actions
          _AccountCard(
            children: [
              _AccountRow(
                icon: Icons.person_outline,
                label: 'Edit name',
                onTap: () {
                  final name = profileAsync.valueOrNull?.name;
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    builder: (_) => EditNameModal(
                      api: ref.read(apiServiceProvider),
                      currentName: name,
                      onSaved: () => ref.invalidate(_accountProfileProvider),
                    ),
                  );
                },
              ),
              _AccountRow(
                icon: Icons.lock_outline,
                label: 'Change password',
                onTap: () {
                  final email = profileAsync.valueOrNull?.email;
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    builder: (_) => PasswordResetModal(
                      api: ref.read(apiServiceProvider),
                      initialEmail: email,
                    ),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Danger zone
          _AccountCard(
            children: [
              _AccountRow(
                icon: Icons.delete_outline,
                label: 'Delete account',
                showChevron: false,
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Delete account?'),
                      content: const Text(
                          'This will permanently delete your account and all data. This cannot be undone.'),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          child: const Text('Delete',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true && context.mounted) {
                    try {
                      await ref.read(apiServiceProvider).delete('/auth/me');
                    } catch (_) {}
                    await ref.read(authServiceProvider).logout();
                    if (context.mounted) context.go('/onboarding');
                  }
                },
              ),
              _AccountRow(
                icon: Icons.logout,
                label: 'Sign out',
                showChevron: false,
                onTap: () async {
                  await ref.read(authServiceProvider).logout();
                  if (context.mounted) context.go('/auth/login');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile header
// ---------------------------------------------------------------------------

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({this.name, this.email});

  final String? name;
  final String? email;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.kiwi100,
            borderRadius: BorderRadius.circular(36),
          ),
          child: const Icon(Icons.person, color: AppColors.kiwi600, size: 32),
        ),
        const SizedBox(height: 12),
        Text(
          name ?? 'Kinwii member',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.content,
                fontWeight: FontWeight.w600,
              ),
        ),
        if (email != null) ...[
          const SizedBox(height: 4),
          Text(
            email!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.contentSecondary,
                ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.icon,
    required this.label,
    this.onTap,
    this.iconColor,
    this.labelColor,
    this.showChevron = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? labelColor;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon,
                size: 20, color: iconColor ?? AppColors.contentSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: labelColor ?? AppColors.content,
                    ),
              ),
            ),
            if (showChevron && onTap != null)
              const Icon(Icons.chevron_right,
                  size: 20, color: AppColors.contentTertiary),
          ],
        ),
      ),
    );
  }
}
