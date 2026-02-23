import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/today')) return 0;
    if (location.startsWith('/week')) return 1;
    if (location.startsWith('/goals')) return 2;
    if (location.startsWith('/reflect')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex(context),
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              context.go('/today');
            case 1:
              context.go('/week');
            case 2:
              context.go('/goals');
            case 3:
              context.go('/reflect');
          }
        },
        backgroundColor: Colors.white,
        indicatorColor: AppColors.kiwi100,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today, color: AppColors.kiwi600),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.view_week_outlined),
            selectedIcon: Icon(Icons.view_week, color: AppColors.kiwi600),
            label: 'Week',
          ),
          NavigationDestination(
            icon: Icon(Icons.flag_outlined),
            selectedIcon: Icon(Icons.flag, color: AppColors.kiwi600),
            label: 'Goals',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome, color: AppColors.kiwi600),
            label: 'Reflect',
          ),
        ],
      ),
    );
  }
}
