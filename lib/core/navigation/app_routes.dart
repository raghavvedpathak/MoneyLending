import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../domain/domain.dart';

/// Type-safe route definitions as a Dart 3 sealed class hierarchy (§2.4 [FIX-ARCH-NAV-1]).
///
/// This is the only place route strings exist; every feature imports from here.
sealed class AppRoute {
  const AppRoute();
  String get path;
  String get route => path.startsWith('/') ? path.substring(1) : path;
}

class DashboardRoute extends AppRoute {
  const DashboardRoute();
  @override
  String get path => '/dashboard';
}

class CustomersRoute extends AppRoute {
  const CustomersRoute();
  @override
  String get path => '/customers';
}

class ReportsRoute extends AppRoute {
  const ReportsRoute();
  @override
  String get path => '/reports';
}

class SettingsRoute extends AppRoute {
  const SettingsRoute();
  @override
  String get path => '/settings';
}

// Parametric routes — use the typed class, never concatenate strings in feature code
class CustomerDetailRoute extends AppRoute {
  const CustomerDetailRoute(this.customerId);
  final String customerId;

  @override
  String get path => '/customer/$customerId';

  static const String arg = 'customerId';
  @override
  String get route => 'customer/{$arg}';
  String resolve() => 'customer/$customerId';
}

class RecordDetailRoute extends AppRoute {
  const RecordDetailRoute(this.recordId, {this.record});
  final String recordId;
  final LedgerRecord? record;

  @override
  String get path => '/record/$recordId';

  static const String arg = 'recordId';
  @override
  String get route => 'record/{$arg}';
  String resolve() => 'record/$recordId';
}

/// Modal / Sub-routes for entry and payments
class AddEntryRoute extends AppRoute {
  final String? customerId;
  final RecordType? initialType;
  const AddEntryRoute({this.customerId, this.initialType});

  @override
  String get path => '/entry/add';
  @override
  String get route => 'entry/add';
}

class EditEntryRoute extends AppRoute {
  final String recordId;
  final LedgerRecord? record;
  const EditEntryRoute(this.recordId, {this.record});

  @override
  String get path => '/entry/edit/$recordId';
  static const String arg = 'recordId';
  @override
  String get route => 'entry/edit/{$arg}';
  String resolve() => 'entry/edit/$recordId';
}

class AddPaymentRoute extends AppRoute {
  final String recordId;
  final LedgerRecord? record;
  final String? customerId;
  const AddPaymentRoute({required this.recordId, this.record, this.customerId});

  @override
  String get path => '/payment/add/$recordId';
  static const String arg = 'recordId';
  @override
  String get route => 'payment/add/{$arg}';
  String resolve() => 'payment/add/$recordId';
}

/// Compatibility container for static route definitions
abstract final class AppRoutes {
  static const DashboardRoute dashboard = DashboardRoute();
  static const CustomersRoute customers = CustomersRoute();
  static const ReportsRoute reports = ReportsRoute();
  static const SettingsRoute settings = SettingsRoute();
}

// Type aliases for backwards-compatibility
typedef Dashboard = DashboardRoute;
typedef Customers = CustomersRoute;
typedef Reports = ReportsRoute;
typedef Settings = SettingsRoute;

/// Type-safe navigator helper for feature screens
class AppNavigator {
  AppNavigator._();

  static Future<T?> navigate<T extends Object?>(
    BuildContext context,
    AppRoute route, {
    Object? arguments,
  }) {
    // 1. Try GoRouter if mounted and available
    try {
      final goRouter = GoRouter.maybeOf(context);
      if (goRouter != null) {
        return context.push<T>(route.path, extra: arguments ?? route);
      }
    } catch (_) {}

    // 2. Fallback to standard Navigator
    final String resolvedPath = switch (route) {
      DashboardRoute() => 'dashboard',
      CustomersRoute() => 'customers',
      ReportsRoute() => 'reports',
      SettingsRoute() => 'settings',
      CustomerDetailRoute r => r.resolve(),
      RecordDetailRoute r => r.resolve(),
      AddEntryRoute _ => 'entry/add',
      EditEntryRoute r => r.resolve(),
      AddPaymentRoute r => r.resolve(),
    };

    return Navigator.of(context).pushNamed<T>(
      resolvedPath,
      arguments: arguments ?? route,
    );
  }

  static void pop<T extends Object?>(BuildContext context, [T? result]) {
    try {
      final goRouter = GoRouter.maybeOf(context);
      if (goRouter != null && goRouter.canPop()) {
        goRouter.pop(result);
        return;
      }
    } catch (_) {}
    Navigator.of(context).pop(result);
  }
}
