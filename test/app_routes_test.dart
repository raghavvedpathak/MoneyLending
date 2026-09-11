import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/navigation/app_routes.dart';

void main() {
  group('AppRoutes tests [FIX-ARCH-NAV-1]', () {
    test('Top-level tab routes match specification', () {
      expect(AppRoutes.dashboard.route, 'dashboard');
      expect(AppRoutes.customers.route, 'customers');
      expect(AppRoutes.reports.route, 'reports');
      expect(AppRoutes.settings.route, 'settings');
    });

    test('CustomerDetail resolves parametric route cleanly', () {
      const route = CustomerDetailRoute('cust_123');
      expect(CustomerDetailRoute.arg, 'customerId');
      expect(route.route, 'customer/{customerId}');
      expect(route.resolve(), 'customer/cust_123');
    });

    test('RecordDetail resolves parametric route cleanly', () {
      const route = RecordDetailRoute('rec_456');
      expect(RecordDetailRoute.arg, 'recordId');
      expect(route.route, 'record/{recordId}');
      expect(route.resolve(), 'record/rec_456');
    });
  });
}
