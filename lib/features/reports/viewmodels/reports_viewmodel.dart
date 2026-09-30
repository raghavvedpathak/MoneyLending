import 'dart:async';
import '../../../core/di/injection.dart';
import '../../../core/pdf/pdf.dart';
import '../../../domain/domain.dart';

/// Available actions triggered by the Reports Screen Floating Action Button (§6.1).
enum ReportsFabAction {
  allCustomersReport,
  allBorrowersReport,
  allLendersReport,
  customerStatement,
  lenderStatement,
  none,
}

/// ViewModel for Reports Screen (:feature:reports) / ReportsNotifier (§6.1).
///
/// Mandated by Business Logic Spec §6.1 & [FIX-PDF-OVERDUEFLAG-1]:
/// - Tracks active sub-tab index as an int field (`activeSubTabIndex`).
/// - Tracks selected borrower as a nullable Customer? field named `selectedBorrower`.
/// - Tracks selected lender as a nullable Lender? field named `selectedLender`.
/// - Derives FAB visibility + tap handler:
///   * Borrowers tab (index 1) -> call generateCustomerStatement for selected borrower.
///     If no borrower selected (e.g. navigated directly without drill-down), FAB is HIDDEN, not just disabled!
///   * Lenders tab (index 2) -> call generateLenderStatement for selected lender.
///     Hidden if no lender selected!
///   * Overview tab (index 0) -> FAB is HIDDEN (combined Given/Taken totals; no single export spanning both tables).
///   * Monthly tab (index 3) -> FAB is HIDDEN (no PDF defined).
///   * Overdue tab (index 4) -> FAB is HIDDEN unless a filtered overdue report is explicitly implemented.
/// - The FAB must be hidden (not just disabled) on tabs where no PDF action is defined.
class ReportsViewModel {
  final CustomerRepository? _customerRepository;
  final LenderRepository? _lenderRepository;
  final RecordRepository? _recordRepository;
  final SettingsRepository? _settingsRepository;

  int _activeSubTabIndex = 0;
  Customer? _selectedBorrower;
  Lender? _selectedLender;

  final StreamController<int> _activeSubTabController =
      StreamController<int>.broadcast();
  final StreamController<Customer?> _selectedCustomerController =
      StreamController<Customer?>.broadcast();
  final StreamController<Lender?> _selectedLenderController =
      StreamController<Lender?>.broadcast();
  final StreamController<bool> _isFabVisibleController =
      StreamController<bool>.broadcast();
  final StreamController<ReportsFabAction> _fabActionController =
      StreamController<ReportsFabAction>.broadcast();

  ReportsViewModel({
    CustomerRepository? customerRepository,
    LenderRepository? lenderRepository,
    RecordRepository? recordRepository,
    SettingsRepository? settingsRepository,
    int initialTab = 0,
    Customer? initialCustomer,
    Customer? initialBorrower,
    Lender? initialLender,
  })  : _customerRepository = customerRepository ?? (sl.isRegistered<CustomerRepository>() ? sl<CustomerRepository>() : null),
        _lenderRepository = lenderRepository ?? (sl.isRegistered<LenderRepository>() ? sl<LenderRepository>() : null),
        _recordRepository = recordRepository ?? (sl.isRegistered<RecordRepository>() ? sl<RecordRepository>() : null),
        _settingsRepository = settingsRepository ?? (sl.isRegistered<SettingsRepository>() ? sl<SettingsRepository>() : null),
        _activeSubTabIndex = initialTab,
        _selectedBorrower = initialBorrower ?? initialCustomer,
        _selectedLender = initialLender;

  // ===========================================================================
  // REACTIVE STATE STREAMS
  // ===========================================================================

  /// Current active sub-tab index (§6.1):
  /// 0: Overview, 1: Borrowers, 2: Lenders, 3: Monthly, 4: Overdue
  Stream<int> get activeSubTabStream => _activeSubTabController.stream;
  int get activeSubTabIndex => _activeSubTabIndex;
  set activeSubTabIndex(int value) => setActiveSubTab(value);

  /// Selected borrower (§6.1)
  Stream<Customer?> get selectedBorrowerStream => _selectedCustomerController.stream;
  Customer? get selectedBorrower => _selectedBorrower;
  set selectedBorrower(Customer? value) => selectBorrower(value);

  /// Backwards-compatibility alias for [selectedBorrower]
  Stream<Customer?> get selectedCustomerStream => _selectedCustomerController.stream;
  Customer? get selectedCustomer => _selectedBorrower;
  set selectedCustomer(Customer? value) => selectBorrower(value);

  /// Selected lender (§6.1)
  Stream<Lender?> get selectedLenderStream => _selectedLenderController.stream;
  Lender? get selectedLender => _selectedLender;
  set selectedLender(Lender? value) => selectLender(value);

  /// Derived FAB visibility stream mandated by §6.1
  Stream<bool> get isFabVisibleStream => _isFabVisibleController.stream;
  bool get isFabVisible {
    switch (_activeSubTabIndex) {
      case 0: // Overview tab: FAB is hidden (§6.1)
        return false;
      case 1: // Borrowers tab: Visible ONLY when a borrower is in context (§6.1)
        return _selectedBorrower != null;
      case 2: // Lenders tab: Visible ONLY when a lender is in context (§6.1)
        return _selectedLender != null;
      case 3: // Monthly tab: FAB is hidden (§6.1)
        return false;
      case 4: // Overdue tab: FAB is hidden (§6.1)
        return false;
      default:
        return false;
    }
  }

  /// Derived FAB routing action stream mandated by §6.1
  Stream<ReportsFabAction> get fabActionStream => _fabActionController.stream;
  ReportsFabAction get currentFabAction {
    if (!isFabVisible) return ReportsFabAction.none;
    if (_activeSubTabIndex == 1 && _selectedBorrower != null) {
      return ReportsFabAction.customerStatement;
    }
    if (_activeSubTabIndex == 2 && _selectedLender != null) {
      return ReportsFabAction.lenderStatement;
    }
    return ReportsFabAction.none;
  }

  /// Direct tap handler function derived from active sub-tab and party context (§6.1).
  Future<void> Function()? getFabTapHandler({
    Future<void> Function()? onAllCustomersReport,
    required Future<void> Function(Customer customer) onCustomerStatement,
    Future<void> Function(Lender lender)? onLenderStatement,
  }) {
    if (!isFabVisible) return null;
    if (_activeSubTabIndex == 1 && _selectedBorrower != null) {
      return () => onCustomerStatement(_selectedBorrower!);
    }
    if (_activeSubTabIndex == 2 && _selectedLender != null && onLenderStatement != null) {
      return () => onLenderStatement(_selectedLender!);
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

  /// Selects a borrower for statement generation (§6.1).
  void selectBorrower(Customer? borrower) {
    if (_selectedBorrower == borrower) return;
    _selectedBorrower = borrower;
    if (!_selectedCustomerController.isClosed) {
      _selectedCustomerController.add(_selectedBorrower);
    }
    _emitDerivedFabUpdates();
  }

  /// Backwards-compatibility alias for [selectBorrower].
  void selectCustomer(Customer? customer) => selectBorrower(customer);

  /// Clears selected borrower (e.g. when navigating back to borrower list).
  void clearSelectedBorrower() {
    selectBorrower(null);
  }

  /// Backwards-compatibility alias for [clearSelectedBorrower].
  void clearSelectedCustomer() => clearSelectedBorrower();

  /// Selects a lender for statement generation (§6.1).
  void selectLender(Lender? lender) {
    if (_selectedLender == lender) return;
    _selectedLender = lender;
    if (!_selectedLenderController.isClosed) {
      _selectedLenderController.add(_selectedLender);
    }
    _emitDerivedFabUpdates();
  }

  /// Clears selected lender (e.g. when navigating back to lender list).
  void clearSelectedLender() {
    selectLender(null);
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

  /// Triggers Single Borrower/Customer Statement PDF generation (§6.1).
  Future<CustomerStatementReport?> generateCustomerStatementPdf({DateTime? today}) async {
    final customer = _selectedBorrower;
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

  /// Triggers Single Lender Statement PDF generation (§6.1 & §6.2b).
  Future<LenderStatementReport?> generateLenderStatementPdf({DateTime? today}) async {
    final lender = _selectedLender;
    if (lender == null) return null;

    final recordRepo = _recordRepository ?? sl<RecordRepository>();
    final settingsRepo = _settingsRepository ?? sl<SettingsRepository>();

    final records = await recordRepo.getRecordsByLender(lender.id).first;
    final settings = await settingsRepo.getSettingsOnce();
    final businessInfo = BusinessInfo.fromSettings(settings);

    return generateLenderStatement(
      lender,
      records,
      businessInfo,
      today,
    );
  }

  /// Triggers All Borrowers Summary Report PDF generation (§6.1).
  Future<AllBorrowersReport> generateAllBorrowersPdf({
    DateTime? today,
    Set<String>? overdueRecordIds,
  }) async {
    final customerRepo = _customerRepository ?? sl<CustomerRepository>();
    final recordRepo = _recordRepository ?? sl<RecordRepository>();
    final settingsRepo = _settingsRepository ?? sl<SettingsRepository>();

    final customers = await customerRepo.getAllCustomers().first;
    final records = await recordRepo.getAllActiveRecordsOnce();
    final settings = await settingsRepo.getSettingsOnce();
    final businessInfo = BusinessInfo.fromSettings(settings);

    return generateAllBorrowersReport(
      customers,
      records,
      overdueRecordIds ?? const <String>{},
      businessInfo,
      today,
    );
  }

  /// Backwards-compatibility alias for [generateAllBorrowersPdf].
  Future<AllCustomersReport> generateAllCustomersPdf({DateTime? today}) =>
      generateAllBorrowersPdf(today: today);

  /// Triggers All Lenders Summary Report PDF generation (§6.1).
  Future<AllLendersReport> generateAllLendersPdf({
    DateTime? today,
    Set<String>? overdueRecordIds,
  }) async {
    final lenderRepo = _lenderRepository ?? sl<LenderRepository>();
    final recordRepo = _recordRepository ?? sl<RecordRepository>();
    final settingsRepo = _settingsRepository ?? sl<SettingsRepository>();

    final lenders = await lenderRepo.watchAllLenders().first;
    final records = await recordRepo.getAllActiveRecordsOnce();
    final settings = await settingsRepo.getSettingsOnce();
    final businessInfo = BusinessInfo.fromSettings(settings);

    return generateAllLendersReport(
      lenders,
      records,
      overdueRecordIds ?? const <String>{},
      businessInfo,
      today,
    );
  }

  /// Cleanly closes all broadcast stream controllers.
  void dispose() {
    _activeSubTabController.close();
    _selectedCustomerController.close();
    _selectedLenderController.close();
    _isFabVisibleController.close();
    _fabActionController.close();
  }
}

/// Architectural alias mandated by §6.1 (`ReportsNotifier`).
typedef ReportsNotifier = ReportsViewModel;
