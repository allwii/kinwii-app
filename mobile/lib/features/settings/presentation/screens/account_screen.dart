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
              if (!hasEmail)
                _AccountRow(
                  icon: Icons.email_outlined,
                  label: 'Link email for backup',
                  onTap: () => _showLinkEmailSheet(context, ref),
                ),
            ],
          ),

          const SizedBox(height: 24),

          // Danger zone
          _AccountCard(
            children: [
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

  void _showLinkEmailSheet(BuildContext context, WidgetRef ref) {
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _LinkEmailSheet(
        emailCtrl: emailCtrl,
        passwordCtrl: passwordCtrl,
        api: ref.read(apiServiceProvider),
        onLinked: () => ref.invalidate(_accountProfileProvider),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Link email sheet
// ---------------------------------------------------------------------------

class _LinkEmailSheet extends StatefulWidget {
  const _LinkEmailSheet({
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.api,
    required this.onLinked,
  });

  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final dynamic api;
  final VoidCallback onLinked;

  @override
  State<_LinkEmailSheet> createState() => _LinkEmailSheetState();
}

class _LinkEmailSheetState extends State<_LinkEmailSheet> {
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    final email = widget.emailCtrl.text.trim();
    final password = widget.passwordCtrl.text;
    if (email.isEmpty || password.length < 8) {
      setState(
          () => _error = 'Please enter a valid email and password (8+ chars).');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.api.post('/auth/link-email', data: {
        'email': email,
        'password': password,
      });
      widget.onLinked();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not link email. It may already be in use.';
        });
      }
    }
  }

  @override
  void dispose() {
    widget.emailCtrl.dispose();
    widget.passwordCtrl.dispose();
    super.dispose();
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
            'Link email',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.content,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add an email and password so you can recover your data if you switch devices.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.contentSecondary,
                ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: widget.emailCtrl,
            decoration: const InputDecoration(labelText: 'Email'),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: widget.passwordCtrl,
            decoration: const InputDecoration(labelText: 'Password'),
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style:
                    const TextStyle(color: Color(0xFFDC2626), fontSize: 13)),
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
                  : const Text('Link email'),
            ),
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
