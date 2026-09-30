import 'dart:async';
import '../../../core/calculations/calculations.dart';
import '../../../core/di/injection.dart';
import '../../../domain/domain.dart';

/// Presentation state item wrapping a TAKEN ledger record for a Lender (§10.2).
class LenderLedgerRecordItem {
  final LedgerRecord record;
  final Financials financials;
  final ProfitState profitState;
  final LedgerRecord? linkedRecord;
  final String? linkedCustomerName;
  final String? linkedCustomerDisplayId;

  const LenderLedgerRecordItem({
    required this.record,
    required this.financials,
    required this.profitState,
    this.linkedRecord,
    this.linkedCustomerName,
    this.linkedCustomerDisplayId,
  });
}

/// State for [LenderDetailNotifier] (§10.2).
class LenderDetailState {
  final bool isLoading;
  final Lender? lender;
  final List<LenderLedgerRecordItem> records;
  final double totalPrincipal;
  final double totalInterest;
  final double totalDue;
  final String? errorMessage;

  const LenderDetailState({
    this.isLoading = false,
    this.lender,
    this.records = const [],
    this.totalPrincipal = 0.0,
    this.totalInterest = 0.0,
    this.totalDue = 0.0,
    this.errorMessage,
  });

  LenderDetailState copyWith({
    bool? isLoading,
    Lender? lender,
    List<LenderLedgerRecordItem>? records,
    double? totalPrincipal,
    double? totalInterest,
    double? totalDue,
    String? errorMessage,
  }) {
    return LenderDetailState(
      isLoading: isLoading ?? this.isLoading,
      lender: lender ?? this.lender,
      records: records ?? this.records,
      totalPrincipal: totalPrincipal ?? this.totalPrincipal,
      totalInterest: totalInterest ?? this.totalInterest,
      totalDue: totalDue ?? this.totalDue,
      errorMessage: errorMessage,
    );
  }
}

/// Lender Detail Notifier / ViewModel (:feature:lenders) (§10.2).
///
/// Mandated by Business Architecture Spec §10.2:
/// - Per-lender ledger history is TAKEN-only (each record row shows transactionId, each payment row its payment ID).
/// - Profit line for records with non-null linkedRecordId:
///   * InterimProfit(amount): when the linked GIVEN record is still ACTIVE.
///   * NetProfit(amount): when the linked GIVEN record is SETTLED.
///   * NoProfit(): when unlinked or on broken FK (never crash on broken FK).
/// - Label selection belongs in the Notifier, not the widget:
///   LenderDetailNotifier resolves the linked GIVEN record, checks its status,
///   and exposes a sealed ProfitState (InterimProfit(amount) | NetProfit(amount) | NoProfit)
///   to the screen; the widget renders the label from ProfitState and never inspects record.status directly.
/// - ProfitState lives in core/domain (shared with Borrowers, not duplicated).
/// - Rows are ordered by startDate descending (date, then time-of-day).
/// - Delete guard enforcing [LenderHasRecordsException] if records are active or settled.
class LenderDetailNotifier {
  final String lenderId;
  final LenderRepository _lenderRepository;
  final RecordRepository _recordRepository;
  final CustomerRepository _customerRepository;
  final DateTime Function() _clock;

  final StreamController<LenderDetailState> _stateController =
      StreamController<LenderDetailState>.broadcast();

  LenderDetailState _state = const LenderDetailState(isLoading: true);
  StreamSubscription? _lenderSub;
  StreamSubscription? _recordsSub;

  LenderDetailNotifier({
    required this.lenderId,
    LenderRepository? lenderRepository,
    RecordRepository? recordRepository,
    CustomerRepository? customerRepository,
    DateTime Function()? clock,
  })  : _lenderRepository = lenderRepository ?? sl<LenderRepository>(),
        _recordRepository = recordRepository ?? sl<RecordRepository>(),
        _customerRepository = customerRepository ?? sl<CustomerRepository>(),
        _clock = clock ?? (() => DateTime.now().dateOnly) {
    loadData();
  }

  Stream<LenderDetailState> get stateStream => _stateController.stream;
  LenderDetailState get state => _state;

  void _emit(LenderDetailState newState) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }

  Future<void> loadData() async {
    _emit(_state.copyWith(isLoading: true, errorMessage: null));

    try {
      // 1. Fetch initial lender or watch
      final lender = await _lenderRepository.getLenderById(lenderId);
      if (lender != null) {
        _emit(_state.copyWith(lender: lender));
      }

      // Also listen to watchAllLenders to keep lender profile synchronized
      _lenderSub?.cancel();
      _lenderSub = _lenderRepository.watchAllLenders().listen((allLenders) {
        final match = allLenders.where((l) => l.id == lenderId).firstOrNull;
        if (match != null) {
          _emit(_state.copyWith(lender: match));
        }
      });

      // 2. Listen to records belonging to this lender (TAKEN-side)
      _recordsSub?.cancel();
      _recordsSub = _recordRepository.getRecordsByLender(lenderId).listen((records) async {
        await _processRecords(records);
      });
    } catch (e) {
      _emit(_state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _processRecords(List<LedgerRecord> rawRecords) async {
    try {
      final targetDate = _clock();
      final List<LenderLedgerRecordItem> items = [];

      // Per-lender ledger history is TAKEN-only (§10.2)
      final takenRecords = rawRecords.where((r) => r.isTaken).toList();

      List<LedgerRecord> allRecords = [];
      List<Customer> allCustomers = [];
      try {
        allRecords = await _recordRepository.getAllRecordsOnce();
      } catch (_) {}
      try {
        allCustomers = await _customerRepository.getAllCustomersOnce();
      } catch (_) {}

      for (final r in takenRecords) {
        final financials = CalculationEngine.calculateRecordFinancials(r, targetDate);

        // Label selection belongs in the Notifier, not the widget (§10.2):
        // LenderDetailNotifier resolves the linked GIVEN record, checks its status,
        // and exposes a sealed ProfitState (InterimProfit(amount) | NetProfit(amount) | NoProfit)
        // to the screen; the widget renders the label from ProfitState and never inspects
        // record.status directly. ProfitState lives in core/domain (shared with Borrowers, not duplicated).
        ProfitState profitState = const NoProfit();
        LedgerRecord? linkedRecord;
        String? linkedCustName;
        String? linkedCustDisplayId;

        if (r.linkedRecordId != null && r.linkedRecordId!.isNotEmpty) {
          try {
            linkedRecord = allRecords.where((rec) => rec.id == r.linkedRecordId).firstOrNull;
            linkedRecord ??= await _recordRepository.getRecordById(r.linkedRecordId!);

            if (linkedRecord != null) {
              final givenFin = CalculationEngine.calculateRecordFinancials(linkedRecord, targetDate);
              final profit = CalculationEngine.calculateNetProfit(givenFin, financials);

              if (linkedRecord.isActive) {
                profitState = InterimProfit(profit);
              } else if (linkedRecord.isSettled) {
                profitState = NetProfit(profit);
              }

              final linkedCust = allCustomers.where((c) => c.id == linkedRecord!.customerId).firstOrNull;
              linkedCustName = linkedCust?.name;
              linkedCustDisplayId = linkedCust?.displayId;
            }
          } catch (_) {
            // Never crash on a broken FK (§10.2)
            profitState = const NoProfit();
          }
        }

        items.add(LenderLedgerRecordItem(
          record: r,
          financials: financials,
          profitState: profitState,
          linkedRecord: linkedRecord,
          linkedCustomerName: linkedCustName,
          linkedCustomerDisplayId: linkedCustDisplayId,
        ));
      }

      // Sort rows by startDate descending (date, then time-of-day) (§10.1 & §10.2)
      items.sort((a, b) {
        final cmp = b.record.startDate.compareTo(a.record.startDate);
        if (cmp != 0) return cmp;
        return b.record.transactionId.compareTo(a.record.transactionId);
      });

      // Calculate totals for this lender
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

  /// Deletes lender with Addendum G / FIX-ID-REUSE-1 guard.
  /// Throws [LenderHasRecordsException] if lender still has records.
  Future<void> deleteLender() async {
    await _lenderRepository.deleteLender(lenderId);
  }

  /// Deletes a record and reloads data.
  Future<void> deleteRecord(String recordId) async {
    await _recordRepository.forceDeleteRecord(recordId);
    await refresh();
  }

  Future<void> refresh() async {
    final raw = await _recordRepository.getRecordsByLender(lenderId).first;
    await _processRecords(raw);
  }

  void dispose() {
    _lenderSub?.cancel();
    _recordsSub?.cancel();
    _stateController.close();
  }
}

/// Architectural alias for LenderDetailNotifier (§10.2).
typedef LenderDetailViewModel = LenderDetailNotifier;
