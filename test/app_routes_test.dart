import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/navigation/app_routes.dart';

void main() {
  group('AppRoute & AppRoutes tests [FIX-ARCH-NAV-1]', () {
    test('AppRoute sealed class exact paths match §2.4 specification', () {
      const dashboard = DashboardRoute();
      const customers = CustomersRoute();
      const reports = ReportsRoute();
      const settings = SettingsRoute();

      expect(dashboard.path, '/dashboard');
      expect(customers.path, '/customers');
      expect(reports.path, '/reports');
      expect(settings.path, '/settings');
    });

    test('Top-level tab routes match specification', () {
      expect(AppRoutes.dashboard.route, 'dashboard');
      expect(AppRoutes.customers.route, 'customers');
      expect(AppRoutes.reports.route, 'reports');
      expect(AppRoutes.settings.route, 'settings');
    });

    test('CustomerDetail resolves parametric route cleanly', () {
      const route = CustomerDetailRoute('cust_123');
      expect(CustomerDetailRoute.arg, 'customerId');
      expect(route.path, '/customer/cust_123');
      expect(route.route, 'customer/{customerId}');
      expect(route.resolve(), 'customer/cust_123');
    });

    test('RecordDetail resolves parametric route cleanly', () {
      const route = RecordDetailRoute('rec_456');
      expect(RecordDetailRoute.arg, 'recordId');
      expect(route.path, '/record/rec_456');
      expect(route.route, 'record/{recordId}');
      expect(route.resolve(), 'record/rec_456');
    });

    test('Sub-routes provide type-safe paths', () {
      const addEntry = AddEntryRoute();
      const editEntry = EditEntryRoute('rec_789');
      const addPayment = AddPaymentRoute(recordId: 'rec_789');

      expect(addEntry.path, '/entry/add');
      expect(editEntry.path, '/entry/edit/rec_789');
      expect(addPayment.path, '/payment/add/rec_789');
    });
  });
}
