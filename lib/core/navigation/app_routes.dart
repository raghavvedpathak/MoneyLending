import 'package:flutter/material.dart';

/// Type-safe route definitions as a sealed class hierarchy.
///
/// Mandated by Architecture Spec §2.4 and [FIX-ARCH-NAV-1]:
/// This is the ONLY place route strings exist; every feature module imports from here.
/// Parametric routes are used by name with resolve(), never string concatenation in feature code.
sealed class AppRoutes {
  final String route;
  const AppRoutes(this.route);

  // Top-level BottomNav tab destinations
  static const Dashboard dashboard = Dashboard._();
  static const Customers customers = Customers._();
  static const Reports reports = Reports._();
  static const Settings settings = Settings._();
}

/// Top-level tab routes
class Dashboard extends AppRoutes {
  const Dashboard._() : super('dashboard');
}

class Customers extends AppRoutes {
  const Customers._() : super('customers');
}

class Reports extends AppRoutes {
  const Reports._() : super('reports');
}

class Settings extends AppRoutes {
  const Settings._() : super('settings');
}

/// Parametric Route: Customer Detail
/// Used by name; never concatenate strings in feature code.
class CustomerDetailRoute extends AppRoutes {
  final String customerId;

  const CustomerDetailRoute(this.customerId) : super('customer/{$arg}');

  String resolve() => 'customer/$customerId';

  static const String arg = 'customerId';
}

/// Parametric Route: Record Detail
/// Used by name; never concatenate strings in feature code.
class RecordDetailRoute extends AppRoutes {
  final String recordId;

  const RecordDetailRoute(this.recordId) : super('record/{$arg}');

  String resolve() => 'record/$recordId';

  static const String arg = 'recordId';
}

/// Modal / Sub-routes for entry and payments
class AddEntryRoute extends AppRoutes {
  final String? customerId;
  const AddEntryRoute({this.customerId}) : super('entry/add');
}

class EditEntryRoute extends AppRoutes {
  final String recordId;
  const EditEntryRoute(this.recordId) : super('entry/edit/{$arg}');
  String resolve() => 'entry/edit/$recordId';
  static const String arg = 'recordId';
}

class AddPaymentRoute extends AppRoutes {
  final String recordId;
  final String? customerId;
  const AddPaymentRoute({required this.recordId, this.customerId}) : super('payment/add/{$arg}');
  String resolve() => 'payment/add/$recordId';
  static const String arg = 'recordId';
}

/// Type-safe navigator helper for feature screens
class AppNavigator {
  AppNavigator._();

  static Future<T?> navigate<T extends Object?>(
    BuildContext context,
    AppRoutes route, {
    Object? arguments,
  }) {
    final String resolvedPath = switch (route) {
      Dashboard() => 'dashboard',
      Customers() => 'customers',
      Reports() => 'reports',
      Settings() => 'settings',
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
    Navigator.of(context).pop(result);
  }
}
