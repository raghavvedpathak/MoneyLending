import 'dart:async';
import '../../../core/calculations/calculations.dart';
import '../../../core/di/injection.dart';
import '../../../domain/domain.dart';

/// Item in the customer ledger history pairing a record with its calculated financials
/// and resolved profit state.
class CustomerLedgerRecordItem {
  final LedgerRecord record;
  final Financials financials;
  final ProfitState profitState;

  const CustomerLedgerRecordItem({
    required this.record,
    required this.financials,
    required this.profitState,
  });
}

/// Reactive state for CustomerDetailScreen (§10.2).
class CustomerDetailState {
  final Customer? customer;
  final List<CustomerLedgerRecordItem> records;
  final double totalPrincipal;
  final double totalInterest;
  final double totalDue;
  final bool isLoading;
  final String? errorMessage;

  const CustomerDetailState({
    this.customer,
    this.records = const [],
    this.totalPrincipal = 0.0,
    this.totalInterest = 0.0,
    this.totalDue = 0.0,
    this.isLoading = false,
    this.errorMessage,
  });

  CustomerDetailState copyWith({
    Customer? customer,
    List<CustomerLedgerRecordItem>? records,
    double? totalPrincipal,
    double? totalInterest,
    double? totalDue,
    bool? isLoading,
    String? errorMessage,
  }) {
    return CustomerDetailState(
      customer: customer ?? this.customer,
      records: records ?? this.records,
      totalPrincipal: totalPrincipal ?? this.totalPrincipal,
      totalInterest: totalInterest ?? this.totalInterest,
      totalDue: totalDue ?? this.totalDue,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// CustomerDetail Notifier / ViewModel (:feature:customers).
///
/// Mandated by Business Architecture Spec §10.2:
/// - Resolves linked GIVEN records for TAKEN records and determines [ProfitState]:
///   * InterimProfit(amount): when the linked GIVEN record is ACTIVE.
///   * NetProfit(amount): when the linked GIVEN record is SETTLED.
///   * NoProfit(): when unlinked, not TAKEN, or on broken foreign key (never crash).
/// - Label selection belongs in the Notifier, not in the widget.
/// - Sorts ledger history rows descending by startDate (date, then time-of-day).
/// - Handles customer deletion with Addendum G / [FIX-ID-REUSE-1] guards.
class CustomerDetailNotifier {
  final String customerId;
  final CustomerRepository _customerRepository;
  final RecordRepository _recordRepository;
  final DateTime Function() _clock;

  final StreamController<CustomerDetailState> _stateController =
      StreamController<CustomerDetailState>.broadcast();

  CustomerDetailState _state = const CustomerDetailState(isLoading: true);
  StreamSubscription? _customerSub;
  StreamSubscription? _recordsSub;

  CustomerDetailNotifier({
    required this.customerId,
    CustomerRepository? customerRepository,
    RecordRepository? recordRepository,
    DateTime Function()? clock,
  })  : _customerRepository = customerRepository ?? sl<CustomerRepository>(),
        _recordRepository = recordRepository ?? sl<RecordRepository>(),
        _clock = clock ?? (() => DateTime.now().dateOnly) {
    loadData();
  }

  Stream<CustomerDetailState> get stateStream => _stateController.stream;
  CustomerDetailState get state => _state;

  void _emit(CustomerDetailState newState) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }

  Future<void> loadData() async {
    _emit(_state.copyWith(isLoading: true, errorMessage: null));

    try {
      // 1. Listen to customer changes
      _customerSub?.cancel();
      _customerSub = _customerRepository.getCustomerById(customerId).listen((customer) {
        _emit(_state.copyWith(customer: customer));
      });

      // 2. Listen to record changes
      _recordsSub?.cancel();
      _recordsSub = _recordRepository.getRecordsByCustomer(customerId).listen((records) async {
        await _processRecords(records);
      });
    } catch (e) {
      _emit(_state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _processRecords(List<LedgerRecord> rawRecords) async {
    try {
      final targetDate = _clock();
      final List<CustomerLedgerRecordItem> items = [];

      for (final r in rawRecords) {
        final financials = CalculationEngine.calculateRecordFinancials(r, targetDate);

        // Resolve ProfitState in Notifier (§10.2)
        ProfitState profitState = const NoProfit();
        if (r.isTaken && r.linkedRecordId != null && r.linkedRecordId!.isNotEmpty) {
          try {
            final linkedGiven = await _recordRepository.getRecordById(r.linkedRecordId!);
            if (linkedGiven != null) {
              final givenFin = CalculationEngine.calculateRecordFinancials(linkedGiven, targetDate);
              final profit = CalculationEngine.calculateNetProfit(givenFin, financials);

              if (linkedGiven.isActive) {
                profitState = InterimProfit(profit);
              } else if (linkedGiven.isSettled) {
                profitState = NetProfit(profit);
              }
            }
          } catch (_) {
            // Never crash on broken FK (§10.2)
            profitState = const NoProfit();
          }
        }

        items.add(CustomerLedgerRecordItem(
          record: r,
          financials: financials,
          profitState: profitState,
        ));
      }

      // Sort rows by startDate descending (date, then time-of-day) (§10.1 & §10.2)
      items.sort((a, b) {
        final cmp = b.record.startDate.compareTo(a.record.startDate);
        if (cmp != 0) return cmp;
        return b.record.transactionId.compareTo(a.record.transactionId);
      });

      // Calculate customer totals
      final totalPrincipal = items.fold(0.0, (acc, item) => acc + item.record.principalAmount);
      final totalInterest = items.fold(0.0, (acc, item) => acc + item.financials.totalInterest);
      final totalDue = items.fold(0.0, (acc, item) => acc + item.financials.totalDue);

      _emit(_state.copyWith(
        records: items,
        totalPrincipal: totalPrincipal,
        totalInterest: totalInterest,
        totalDue: totalDue,
        isLoading: false,
      ));
    } catch (e) {
      _emit(_state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  /// Deletes customer with Addendum G / FIX-ID-REUSE-1 guard.
  /// Throws CustomerHasRecordsException if customer has records.
  Future<void> deleteCustomer() async {
    await _customerRepository.deleteCustomer(customerId);
  }

  /// Deletes a record and reloads data.
  Future<void> deleteRecord(String recordId) async {
    await _recordRepository.forceDeleteRecord(recordId);
    await refresh();
  }

  Future<void> refresh() async {
    final raw = await _recordRepository.getRecordsByCustomer(customerId).first;
    await _processRecords(raw);
  }

  void dispose() {
    _customerSub?.cancel();
    _recordsSub?.cancel();
    _stateController.close();
  }
}

/// Architectural alias for CustomerDetailNotifier (§10.2).
typedef CustomerDetailViewModel = CustomerDetailNotifier;
