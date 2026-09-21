import 'dart:async';
import '../../../core/calculations/calculations.dart';
import '../../../core/di/injection.dart';
import '../../../domain/domain.dart';

/// Extension for debouncing streams without external reactive libraries (§5.3).
extension StreamDebounceExtension<T> on Stream<T> {
  Stream<T> debounce(Duration duration) {
    Timer? timer;
    StreamController<T>? controller;
    StreamSubscription<T>? subscription;

    controller = StreamController<T>(
      sync: true,
      onListen: () {
        subscription = listen(
          (data) {
            timer?.cancel();
            timer = Timer(duration, () {
              if (!controller!.isClosed) {
                controller.add(data);
              }
            });
          },
          onError: (err, stack) {
            if (!controller!.isClosed) controller.addError(err, stack);
          },
          onDone: () {
            timer?.cancel();
            if (!controller!.isClosed) controller.close();
          },
          cancelOnError: false,
        );
      },
      onCancel: () {
        timer?.cancel();
        subscription?.cancel();
      },
    );
    return controller.stream;
  }
}

/// Representation of the Risk Summary header (§10.1).
class RiskSummary {
  final int atRiskCount;
  final double totalExposure;

  const RiskSummary({
    required this.atRiskCount,
    required this.totalExposure,
  });

  bool get allSafe => atRiskCount == 0;
}

/// Dashboard ViewModel / Notifier (:feature:dashboard).
///
/// Mandated by Business Logic Spec §5.3, §5.4, and §10.1:
/// - Combines Active Given records, debounced live rates (300ms), and total paid stream.
/// - [FIX-DEV-DEBOUNCE-1]: Rate flow debounced at 300ms to eliminate UI jitter during rapid edits.
/// - [FIX-DEV-COMBINESUSPEND-1]: Uses non-suspend getTotalPaidFlow() stream.
/// - H-4 FIX: alertsLoaded starts false and only becomes true upon first combine emission.
/// - [FIX-RISK-VIEWMODEL-1]: Exposes authoritative 5-group sorted `List<RecordRisk>`.
/// - §10.1: Derives Risk Summary and Stale-Rate banner status directly from the combined streams.
/// - §10.1: Handles Category Add (M-10 FIX & [FIX-RATE-USABLE-1]) and Rate Updates with inline validation.
class DashboardViewModel {
  final RecordRepository _recordRepository;
  final ItemRateRepository _itemRateRepository;
  final DateTime Function() _clock;

  final StreamController<List<CollectionAlert>> _collectionAlertsController =
      StreamController<List<CollectionAlert>>.broadcast();
  final StreamController<List<CollectionAlertCardData>> _collectionAlertCardsController =
      StreamController<List<CollectionAlertCardData>>.broadcast();
  final StreamController<List<RecordRisk>> _recordRisksController =
      StreamController<List<RecordRisk>>.broadcast();
  final StreamController<RiskSummary> _riskSummaryController =
      StreamController<RiskSummary>.broadcast();
  final StreamController<ItemRate?> _oldestStaleRateController =
      StreamController<ItemRate?>.broadcast();
  final StreamController<bool> _alertsLoadedController =
      StreamController<bool>.broadcast();

  bool _alertsLoaded = false;
  List<CollectionAlert> _currentAlerts = const [];
  List<CollectionAlertCardData> _currentAlertCards = const [];
  List<RecordRisk> _currentRecordRisks = const [];
  RiskSummary _currentRiskSummary = const RiskSummary(atRiskCount: 0, totalExposure: 0.0);
  ItemRate? _currentOldestStaleRate;

  StreamSubscription? _subRecords;
  StreamSubscription? _subRates;
  StreamSubscription? _subTotals;

  List<LedgerRecord>? _latestRecords;
  List<ItemRate>? _latestRates;
  List<RecordPaymentTotal>? _latestTotals;

  DashboardViewModel({
    RecordRepository? recordRepository,
    ItemRateRepository? itemRateRepository,
    DateTime Function()? clock,
    Duration debounceDuration = const Duration(milliseconds: 300),
  })  : _recordRepository = recordRepository ?? sl<RecordRepository>(),
        _itemRateRepository = itemRateRepository ?? sl<ItemRateRepository>(),
        _clock = clock ?? DateTime.now {
    _initCombinePipeline(debounceDuration);
  }

  /// Reactive stream of collection alerts.
  Stream<List<CollectionAlert>> get collectionAlerts =>
      _collectionAlertsController.stream;

  /// Reactive stream of unified collection alert card models (§5.4).
  Stream<List<CollectionAlertCardData>> get collectionAlertCards =>
      _collectionAlertCardsController.stream;

  /// Authoritative stream of RecordRisk models in 5-group sort order (§5.3 & [FIX-RISK-VIEWMODEL-1]).
  Stream<List<RecordRisk>> get recordRisks => _recordRisksController.stream;

  /// Reactive stream of the Risk Summary header (§10.1).
  Stream<RiskSummary> get riskSummary => _riskSummaryController.stream;

  /// Reactive stream of the oldest stale rate, or null if all rates are up-to-date today (§10.1).
  Stream<ItemRate?> get oldestStaleRate => _oldestStaleRateController.stream;

  /// Stream of all current item rates for the Rate Management Card (§10.1).
  Stream<List<ItemRate>> watchCurrentRates() => _itemRateRepository.watchCurrentRates();

  /// Current cached collection alerts snapshot.
  List<CollectionAlert> get currentAlerts => _currentAlerts;

  /// Current cached unified cards snapshot.
  List<CollectionAlertCardData> get currentAlertCards => _currentAlertCards;

  /// Current cached RecordRisks snapshot.
  List<RecordRisk> get currentRecordRisks => _currentRecordRisks;

  /// Current cached RiskSummary snapshot.
  RiskSummary get currentRiskSummary => _currentRiskSummary;

  /// Current cached oldest stale rate snapshot.
  ItemRate? get currentOldestStaleRate => _currentOldestStaleRate;

  /// Companion stream mandated by H-4 FIX.
  /// Initial value is false; emits true once first combined alert list has been computed.
  Stream<bool> get alertsLoaded => _alertsLoadedController.stream;

  /// Synchronous value for H-4 FIX: UI must only show "All records safe today" if alertsLoaded == true.
  bool get isAlertsLoaded => _alertsLoaded;

  void _initCombinePipeline(Duration debounceDuration) {
    _subRecords = _recordRepository.getActiveGivenRecords().listen((records) {
      _latestRecords = records;
      _evaluateCombine();
    });

    _subRates = _itemRateRepository
        .getCurrentRates()
        .debounce(debounceDuration)
        .listen((rates) {
      _latestRates = rates;
      _evaluateCombine();
    });

    _subTotals = _recordRepository.getTotalPaidFlow().listen((totals) {
      _latestTotals = totals;
      _evaluateCombine();
    });
  }

  void _evaluateCombine() {
    if (_latestRecords == null || _latestRates == null || _latestTotals == null) {
      return;
    }

    final today = _clock().dateOnly;

    final totalPaidMap = {
      for (final t in _latestTotals!) t.recordId: t.totalPaid,
    };

    // 1. Authoritative RecordRisk list (§5.3)
    final risks = computeRecordRisks(
      records: _latestRecords!,
      rates: _latestRates!,
      today: today,
      totalPaidMap: totalPaidMap,
    );

    // 2. Legacy / Compatibility alert views
    final alerts = alertsFromRisks(risks);
    final cards = computeCollectionAlertCards(
      _latestRecords!,
      _latestRates!,
      totalPaidMap,
    );

    // 3. Derive Risk Summary header (§10.1)
    int atRiskCount = 0;
    double totalExposure = 0.0;
    for (final r in risks) {
      if (r.atRisk) {
        atRiskCount++;
        totalExposure += r.totalDue;
      }
    }
    final summary = RiskSummary(atRiskCount: atRiskCount, totalExposure: totalExposure);

    // 4. Derive Stale-rate banner (§10.1)
    final staleRate = _findOldestStaleRate(_latestRates!, today);

    _currentRecordRisks = risks;
    _currentAlerts = alerts;
    _currentAlertCards = cards;
    _currentRiskSummary = summary;
    _currentOldestStaleRate = staleRate;

    _recordRisksController.add(risks);
    _collectionAlertsController.add(alerts);
    _collectionAlertCardsController.add(cards);
    _riskSummaryController.add(summary);
    _oldestStaleRateController.add(staleRate);

    if (!_alertsLoaded) {
      _alertsLoaded = true;
      _alertsLoadedController.add(true);
    }
  }

  /// Stale-rate detection: compare OLDEST effectiveDate in emitted list against today.
  /// (a 0.0 "not set" row counts as stale).
  ItemRate? _findOldestStaleRate(List<ItemRate> rates, DateTime today) {
    if (rates.isEmpty) return null;

    bool anyStale = false;
    ItemRate? oldest;

    for (final rate in rates) {
      final isStale = rate.ratePerUnit == 0.0 || rate.effectiveDate.dateOnly.isBefore(today.dateOnly);
      if (isStale) {
        anyStale = true;
      }
      if (oldest == null || rate.effectiveDate.isBefore(oldest.effectiveDate)) {
        oldest = rate;
      }
    }

    if (anyStale && oldest != null) {
      return oldest;
    }
    return null;
  }

  /// M-10 FIX: Adds a new category with ratePerUnit = 0.0 (the "not set yet" marker).
  ///
  /// Validation:
  /// - Category name cannot be blank -> returns "Category name cannot be blank"
  /// - Duplicate name check (case-insensitive) -> returns "Category already exists"
  /// Returns null on success.
  Future<String?> addCategory(String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      return 'Category name cannot be blank';
    }

    final currentRates = _latestRates ?? await _itemRateRepository.getCurrentRatesOnce();
    final isDuplicate = currentRates.any(
      (r) => r.itemCategory.trim().toLowerCase() == trimmedName.toLowerCase(),
    );

    if (isDuplicate) {
      return 'Category already exists';
    }

    final today = _clock().dateOnly;
    await _itemRateRepository.upsertRate(
      ItemRate(
        id: '',
        itemCategory: trimmedName.toUpperCase(),
        ratePerUnit: 0.0,
        effectiveDate: today,
        updatedAt: DateTime.now(),
      ),
    );

    return null;
  }

  /// Updates the ratePerUnit for an existing or new category for today's date (§10.1).
  ///
  /// Validation:
  /// - ratePerUnit must be > 0.0 (0.0 is reserved for "not set yet")
  /// - Returns "Rate must be greater than zero" if invalid.
  /// Returns null on success.
  Future<String?> updateCategoryRate(String category, double ratePerUnit) async {
    if (ratePerUnit <= 0.0) {
      return 'Rate must be greater than zero';
    }

    final today = _clock().dateOnly;
    await _itemRateRepository.upsertRate(
      ItemRate(
        id: '',
        itemCategory: category.trim().toUpperCase(),
        ratePerUnit: ratePerUnit,
        effectiveDate: today,
        updatedAt: DateTime.now(),
      ),
    );

    return null;
  }

  void dispose() {
    _subRecords?.cancel();
    _subRates?.cancel();
    _subTotals?.cancel();
    _collectionAlertsController.close();
    _collectionAlertCardsController.close();
    _recordRisksController.close();
    _riskSummaryController.close();
    _oldestStaleRateController.close();
    _alertsLoadedController.close();
  }
}

/// Type alias for spec equivalence (§10.1)
typedef DashboardNotifier = DashboardViewModel;
