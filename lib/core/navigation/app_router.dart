import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/domain.dart';
import '../../features/customers/customers.dart';
import '../../features/dashboard/dashboard.dart';
import '../../features/entry/screens/add_entry_screen.dart';
import '../../features/entry/screens/edit_transaction_screen.dart';
import '../../features/entry/screens/loan_details_screen.dart';
import '../../features/payments/screens/add_payment_screen.dart';
import '../../features/reports/reports.dart';
import '../../features/settings/settings.dart';
import '../../presentation/app_shell.dart';
import 'app_routes.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// GoRouter configuration implementing StatefulShellRoute.indexedStack (§10.1).
///
/// Each bottom navigation tab keeps its own independent navigation stack
/// and scroll position when switching tabs.
final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/dashboard',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (BuildContext context, GoRouterState state, StatefulNavigationShell navigationShell) {
        return AppShell(navigationShell: navigationShell);
      },
      branches: [
        // Tab 0: Dashboard
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/dashboard',
              name: 'dashboard',
              builder: (BuildContext context, GoRouterState state) => const DashboardScreen(),
            ),
          ],
        ),
        // Tab 1: Customers
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/customers',
              name: 'customers',
              builder: (BuildContext context, GoRouterState state) => const CustomersScreen(),
            ),
          ],
        ),
        // Tab 2: Reports
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/reports',
              name: 'reports',
              builder: (BuildContext context, GoRouterState state) => const ReportsScreen(),
            ),
          ],
        ),
        // Tab 3: Settings
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              name: 'settings',
              builder: (BuildContext context, GoRouterState state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),

    // Overdue shortcut route (direct jump to Overdue tab in Reports)
    GoRoute(
      path: '/overdue',
      parentNavigatorKey: rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) =>
          const ReportsScreen(initialSubTab: 3),
    ),

    // Modal / Sub-routes
    GoRoute(
      path: '/entry/add',
      parentNavigatorKey: rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) {
        final extra = state.extra;
        if (extra is AddEntryRoute) {
          return AddEntryScreen(
            preselectedCustomerId: extra.customerId,
            initialType: extra.initialType ?? RecordType.GIVEN,
          );
        }
        return const AddEntryScreen();
      },
    ),

    GoRoute(
      path: '/entry/edit/:recordId',
      parentNavigatorKey: rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) {
        final extra = state.extra;
        if (extra is EditEntryRoute && extra.record != null) {
          return EditTransactionScreen(record: extra.record!);
        }
        return const SizedBox.shrink();
      },
    ),

    GoRoute(
      path: '/customer/:customerId',
      parentNavigatorKey: rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) {
        final customerId = state.pathParameters['customerId'] ?? '';
        return CustomerDetailScreen(customerId: customerId);
      },
    ),

    GoRoute(
      path: '/record/:recordId',
      parentNavigatorKey: rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) {
        final extra = state.extra;
        final recordId = state.pathParameters['recordId'] ?? '';
        final record = extra is RecordDetailRoute ? extra.record : null;
        return RecordDetailScreen(recordId: recordId, record: record);
      },
    ),


    GoRoute(
      path: '/payment/add/:recordId',
      parentNavigatorKey: rootNavigatorKey,
      builder: (BuildContext context, GoRouterState state) {
        final extra = state.extra;
        if (extra is AddPaymentRoute && extra.record != null) {
          return AddPaymentScreen(record: extra.record!);
        }
        return const SizedBox.shrink();
      },
    ),
  ],
);
