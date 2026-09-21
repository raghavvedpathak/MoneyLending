import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/di/injection.dart';
import '../core/notifications/overdue_notification_service.dart';
import '../core/ui/theme/app_theme.dart';
import '../features/customers/customers.dart';
import '../features/dashboard/dashboard.dart';
import '../features/reports/reports.dart';
import '../features/settings/settings.dart';

class AppShell extends StatefulWidget {
  final int initialTabIndex;
  final int initialSubTab;
  final StatefulNavigationShell? navigationShell;

  const AppShell({
    super.key,
    this.initialTabIndex = 0,
    this.initialSubTab = 0,
    this.navigationShell,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _currentIndex;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTabIndex;
    _screens = [
      const DashboardScreen(),
      const CustomersScreen(),
      ReportsScreen(initialSubTab: widget.initialSubTab),
      const SettingsScreen(),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && sl.isRegistered<OverdueNotificationService>()) {
        sl<OverdueNotificationService>().checkPermissionsAndPrompt(context);
      }
    });
  }

  int get _selectedTab => widget.navigationShell?.currentIndex ?? _currentIndex;

  void _onDestinationSelected(int index) {
    if (widget.navigationShell != null) {
      widget.navigationShell!.goBranch(
        index,
        initialLocation: index == widget.navigationShell!.currentIndex,
      );
    } else {
      setState(() => _currentIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget bodyContent = widget.navigationShell ??
        IndexedStack(
          index: _currentIndex,
          children: _screens,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isTabletOrWide = constraints.maxWidth >= 720;

        if (isTabletOrWide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedTab,
                  onDestinationSelected: _onDestinationSelected,
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
                  child: bodyContent,
                ),
              ],
            ),
          );
        }

        return Scaffold(
          body: bodyContent,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedTab,
            onDestinationSelected: _onDestinationSelected,
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
