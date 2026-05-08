// AccountScreen — Edit name, link email, delete account.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../services/providers.dart';
import '../widgets/edit_name_modal.dart';

// ---------------------------------------------------------------------------
// User profile provider
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
    final hasEmail = profileAsync.valueOrNull?.email != null;

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

          if (!hasEmail) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Your data is saved on this device only.\nCreate an account to back it up.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.contentSecondary,
                      height: 1.4,
                    ),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Account actions
          _AccountCard(
            children: [
              if (hasEmail) ...[
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
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      useRootNavigator: true,
                      backgroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      builder: (_) => _ChangePasswordModal(
                        api: ref.read(apiServiceProvider),
                      ),
                    );
                  },
                ),
              ] else
                _AccountRow(
                  icon: Icons.person_add_outlined,
                  label: 'Create account',
                  onTap: () => context.push('/sign-in').then((_) {
                    ref.invalidate(_accountProfileProvider);
                  }),
                ),
            ],
          ),

          const SizedBox(height: 24),

          // Log out + delete
          _AccountCard(
            children: [
              if (hasEmail)
                _AccountRow(
                  icon: Icons.logout,
                  label: 'Log out',
                  showChevron: false,
                  onTap: () async {
                    await ref.read(authServiceProvider).logout();
                    if (context.mounted) context.go('/onboarding');
                  },
                ),
              _AccountRow(
                icon: Icons.delete_outline,
                label: 'Delete all data',
                showChevron: false,
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Delete all data?'),
                      content: Text(
                        hasEmail
                            ? 'This will permanently delete your account and all data. This cannot be undone.'
                            : 'This will permanently delete all your data. Since you don\'t have an email linked, this cannot be recovered.',
                      ),
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
          name ?? 'Me',
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
    this.showChevron = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.contentSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.content,
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

// ---------------------------------------------------------------------------
// Change password modal
// ---------------------------------------------------------------------------

class _ChangePasswordModal extends StatefulWidget {
  const _ChangePasswordModal({required this.api});
  final dynamic api;

  @override
  State<_ChangePasswordModal> createState() => _ChangePasswordModalState();
}

class _ChangePasswordModalState extends State<_ChangePasswordModal> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _currentCtrl.text;
    final newPw = _newCtrl.text;
    final confirm = _confirmCtrl.text;

    if (current.isEmpty) {
      setState(() => _error = 'Please enter your current password.');
      return;
    }
    if (newPw.length < 8) {
      setState(() => _error = 'New password must be at least 8 characters.');
      return;
    }
    if (newPw != confirm) {
      setState(() => _error = 'New passwords do not match.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });

    try {
      await widget.api.post('/auth/change-password', data: {
        'current_password': current,
        'new_password': newPw,
      });
      if (mounted) {
        setState(() {
          _loading = false;
          _success = 'Password updated!';
        });
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        final is401 = e.toString().contains('401');
        setState(() {
          _loading = false;
          _error = is401
              ? 'Current password is incorrect.'
              : 'Could not update password. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Change password',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.content,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _currentCtrl,
            decoration: InputDecoration(
              labelText: 'Current password',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureCurrent
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                  color: AppColors.contentTertiary,
                ),
                onPressed: () =>
                    setState(() => _obscureCurrent = !_obscureCurrent),
              ),
            ),
            obscureText: _obscureCurrent,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _newCtrl,
            decoration: InputDecoration(
              labelText: 'New password',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureNew
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                  color: AppColors.contentTertiary,
                ),
                onPressed: () => setState(() => _obscureNew = !_obscureNew),
              ),
            ),
            obscureText: _obscureNew,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmCtrl,
            decoration: InputDecoration(
              labelText: 'Confirm new password',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                  color: AppColors.contentTertiary,
                ),
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
            obscureText: _obscureConfirm,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style:
                    const TextStyle(color: Color(0xFFDC2626), fontSize: 13)),
          ],
          if (_success != null) ...[
            const SizedBox(height: 10),
            Text(_success!,
                style: TextStyle(color: AppColors.kiwi600, fontSize: 13)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Update password'),
            ),
          ),
        ],
      ),
    );
  }
}
