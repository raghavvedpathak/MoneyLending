import 'dart:async';
import '../../../core/di/injection.dart';
import '../../../core/pdf/pdf.dart';
import '../../../domain/domain.dart';

/// Available actions triggered by the Reports Screen Floating Action Button (§6.1).
enum ReportsFabAction {
  allCustomersReport,
  customerStatement,
  none,
}

/// ViewModel for Reports Screen (:feature:reports).
///
/// Mandated by Business Logic Spec §6.1:
/// - Tracks active sub-tab index (0: Overview, 1: Customer, 2: Monthly, 3: Overdue).
/// - Tracks selected customer as reactive state (`Customer?`).
/// - Derives FAB visibility + click handler:
///   * Customer tab -> call generateCustomerStatement for selected customer. Hidden if null!
///   * Overview tab -> call generateAllCustomersReport.
///   * Monthly tab -> FAB is hidden.
///   * Overdue tab -> FAB is hidden.
/// - FAB must be hidden (not just disabled) on tabs where no PDF action is defined.
class ReportsViewModel {
  final CustomerRepository? _customerRepository;
  final RecordRepository? _recordRepository;
  final SettingsRepository? _settingsRepository;

  int _activeSubTabIndex = 0;
  Customer? _selectedCustomer;

  final StreamController<int> _activeSubTabController =
      StreamController<int>.broadcast();
  final StreamController<Customer?> _selectedCustomerController =
      StreamController<Customer?>.broadcast();
  final StreamController<bool> _isFabVisibleController =
      StreamController<bool>.broadcast();
  final StreamController<ReportsFabAction> _fabActionController =
      StreamController<ReportsFabAction>.broadcast();

  ReportsViewModel({
    CustomerRepository? customerRepository,
    RecordRepository? recordRepository,
    SettingsRepository? settingsRepository,
    int initialTab = 0,
    Customer? initialCustomer,
  })  : _customerRepository = customerRepository ?? (sl.isRegistered<CustomerRepository>() ? sl<CustomerRepository>() : null),
        _recordRepository = recordRepository ?? (sl.isRegistered<RecordRepository>() ? sl<RecordRepository>() : null),
        _settingsRepository = settingsRepository ?? (sl.isRegistered<SettingsRepository>() ? sl<SettingsRepository>() : null),
        _activeSubTabIndex = initialTab,
        _selectedCustomer = initialCustomer;

  // ===========================================================================
  // REACTIVE STATE STREAMS (StateFlow equivalents in Dart)
  // ===========================================================================

  /// Current active sub-tab index:
  /// 0: Overview, 1: Customer, 2: Monthly, 3: Overdue
  Stream<int> get activeSubTabStream => _activeSubTabController.stream;
  int get activeSubTabIndex => _activeSubTabIndex;
  set activeSubTabIndex(int value) => setActiveSubTab(value);

  /// Currently selected customer (if viewing customer statement or drilled-down tab)
  Stream<Customer?> get selectedCustomerStream => _selectedCustomerController.stream;
  Customer? get selectedCustomer => _selectedCustomer;
  set selectedCustomer(Customer? value) => selectCustomer(value);

  /// Derived FAB visibility stream mandated by §6.1
  Stream<bool> get isFabVisibleStream => _isFabVisibleController.stream;
  bool get isFabVisible {
    switch (_activeSubTabIndex) {
      case 0: // Overview tab: Always visible
        return true;
      case 1: // Customer tab: Visible ONLY when a customer is selected
        return _selectedCustomer != null;
      case 2: // Monthly tab: Hidden
        return false;
      case 3: // Overdue tab: Hidden
        return false;
      default:
        return false;
    }
  }

  /// Derived FAB routing action stream mandated by §6.1
  Stream<ReportsFabAction> get fabActionStream => _fabActionController.stream;
  ReportsFabAction get currentFabAction {
    if (!isFabVisible) return ReportsFabAction.none;
    if (_activeSubTabIndex == 0) return ReportsFabAction.allCustomersReport;
    if (_activeSubTabIndex == 1 && _selectedCustomer != null) {
      return ReportsFabAction.customerStatement;
    }
    return ReportsFabAction.none;
  }

  /// Direct tap handler function derived from active sub-tab and customer context (§6.1).
  Future<void> Function()? getFabTapHandler({
    required Future<void> Function() onAllCustomersReport,
    required Future<void> Function(Customer customer) onCustomerStatement,
  }) {
    if (!isFabVisible) return null;
    if (_activeSubTabIndex == 0) {
      return onAllCustomersReport;
    }
    if (_activeSubTabIndex == 1 && _selectedCustomer != null) {
      return () => onCustomerStatement(_selectedCustomer!);
    }
    return null;
  }

  // ===========================================================================
  // STATE MUTATION ACTIONS
  // ===========================================================================

  /// Switches active sub-tab and updates derived FAB state (§6.1).
  void setActiveSubTab(int index) {
    if (_activeSubTabIndex == index) return;
    _activeSubTabIndex = index;
    if (!_activeSubTabController.isClosed) {
      _activeSubTabController.add(_activeSubTabIndex);
    }
    _emitDerivedFabUpdates();
  }

  /// Selects or contextually sets a customer for statement generation (§6.1).
  void selectCustomer(Customer? customer) {
    if (_selectedCustomer == customer) return;
    _selectedCustomer = customer;
    if (!_selectedCustomerController.isClosed) {
      _selectedCustomerController.add(_selectedCustomer);
    }
    _emitDerivedFabUpdates();
  }

  /// Clears selected customer (e.g. when navigating back to customer list).
  void clearSelectedCustomer() {
    selectCustomer(null);
  }

  void _emitDerivedFabUpdates() {
    if (!_isFabVisibleController.isClosed) {
      _isFabVisibleController.add(isFabVisible);
    }
    if (!_fabActionController.isClosed) {
      _fabActionController.add(currentFabAction);
    }
  }

  // ===========================================================================
  // PDF GENERATION ACTIONS
  // ===========================================================================

  /// Triggers All Customers Summary Report PDF generation (§6.1).
  Future<AllCustomersReport> generateAllCustomersPdf({DateTime? today}) async {
    final customerRepo = _customerRepository ?? sl<CustomerRepository>();
    final recordRepo = _recordRepository ?? sl<RecordRepository>();
    final settingsRepo = _settingsRepository ?? sl<SettingsRepository>();

    final customers = await customerRepo.getAllCustomers().first;
    final records = await recordRepo.getAllActiveRecordsOnce();
    final settings = await settingsRepo.getSettingsOnce();
    final businessInfo = BusinessInfo.fromSettings(settings);

    return generateAllCustomersReport(
      customers,
      records,
      businessInfo,
      today,
    );
  }

  /// Triggers Single Customer Statement PDF generation (§6.1).
  Future<CustomerStatementReport?> generateCustomerStatementPdf({DateTime? today}) async {
    final customer = _selectedCustomer;
    if (customer == null) return null;

    final recordRepo = _recordRepository ?? sl<RecordRepository>();
    final settingsRepo = _settingsRepository ?? sl<SettingsRepository>();

    final records = await recordRepo.getRecordsByCustomer(customer.id).first;
    final settings = await settingsRepo.getSettingsOnce();
    final businessInfo = BusinessInfo.fromSettings(settings);

    return generateCustomerStatement(
      customer,
      records,
      businessInfo,
      today,
    );
  }

  /// Cleanly closes all broadcast stream controllers.
  void dispose() {
    _activeSubTabController.close();
    _selectedCustomerController.close();
    _isFabVisibleController.close();
    _fabActionController.close();
  }
}

/// Architectural alias mandated by §6.1 (`ReportsNotifier`).
typedef ReportsNotifier = ReportsViewModel;

