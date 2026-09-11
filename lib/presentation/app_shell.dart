import 'package:flutter/material.dart';
import '../core/ui/theme/app_theme.dart';
import '../features/customers/customers.dart';
import '../features/dashboard/dashboard.dart';
import '../features/reports/reports.dart';
import '../features/settings/settings.dart';

class AppShell extends StatefulWidget {
  final int initialTabIndex;

  const AppShell({
    super.key,
    this.initialTabIndex = 0,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _currentIndex;

  final List<Widget> _screens = const [
    DashboardScreen(),
    CustomersScreen(),
    ReportsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTabIndex;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTabletOrWide = constraints.maxWidth >= 720;

        if (isTabletOrWide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: (index) {
                    setState(() => _currentIndex = index);
                  },
                  backgroundColor: AppTheme.cardDark,
                  indicatorColor: AppTheme.gold.withValues(alpha: 0.18),
                  labelType: NavigationRailLabelType.all,
                  leading: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Icon(
                      Icons.account_balance_wallet_rounded,
                      color: AppTheme.gold,
                      size: 32,
                    ),
                  ),
                  selectedIconTheme: const IconThemeData(color: AppTheme.gold, size: 24),
                  unselectedIconTheme: const IconThemeData(color: AppTheme.textMuted, size: 24),
                  selectedLabelTextStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.gold,
                  ),
                  unselectedLabelTextStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textMuted,
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard_rounded),
                      label: Text('Dashboard'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.people_outline),
                      selectedIcon: Icon(Icons.people_alt_rounded),
                      label: Text('Customers'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.analytics_outlined),
                      selectedIcon: Icon(Icons.analytics_rounded),
                      label: Text('Reports'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings_rounded),
                      label: Text('Settings'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1, thickness: 1, color: AppTheme.borderDark),
                Expanded(
                  child: IndexedStack(
                    index: _currentIndex,
                    children: _screens,
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          body: IndexedStack(
            index: _currentIndex,
            children: _screens,
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() => _currentIndex = index);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard_rounded),
                label: 'Dashboard',
              ),
              NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people_alt_rounded),
                label: 'Customers',
              ),
              NavigationDestination(
                icon: Icon(Icons.analytics_outlined),
                selectedIcon: Icon(Icons.analytics_rounded),
                label: 'Reports',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: 'Settings',
              ),
            ],
          ),
        );
      },
    );
  }
}
