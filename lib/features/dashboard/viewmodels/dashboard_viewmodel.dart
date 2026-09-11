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

/// Dashboard ViewModel (:feature:dashboard).
///
/// Mandated by Business Logic Spec §5.3:
/// - Combines Active Given records, debounced live rates (300ms), and total paid stream.
/// - [FIX-DEV-DEBOUNCE-1]: Rate flow debounced at 300ms to eliminate UI jitter during rapid edits.
/// - [FIX-DEV-COMBINESUSPEND-1]: Uses non-suspend getTotalPaidFlow() stream.
/// - H-4 FIX: alertsLoaded starts false and only becomes true upon first combine emission.
class DashboardViewModel {
  final RecordRepository _recordRepository;
  final ItemRateRepository _itemRateRepository;

  final StreamController<List<CollectionAlert>> _collectionAlertsController =
      StreamController<List<CollectionAlert>>.broadcast();
  final StreamController<List<CollectionAlertCardData>> _collectionAlertCardsController =
      StreamController<List<CollectionAlertCardData>>.broadcast();
  final StreamController<bool> _alertsLoadedController =
      StreamController<bool>.broadcast();

  bool _alertsLoaded = false;
  List<CollectionAlert> _currentAlerts = const [];
  List<CollectionAlertCardData> _currentAlertCards = const [];

  StreamSubscription? _subRecords;
  StreamSubscription? _subRates;
  StreamSubscription? _subTotals;

  List<LedgerRecord>? _latestRecords;
  List<ItemRate>? _latestRates;
  List<RecordPaymentTotal>? _latestTotals;

  DashboardViewModel({
    RecordRepository? recordRepository,
    ItemRateRepository? itemRateRepository,
    Duration debounceDuration = const Duration(milliseconds: 300),
  })  : _recordRepository = recordRepository ?? sl<RecordRepository>(),
        _itemRateRepository = itemRateRepository ?? sl<ItemRateRepository>() {
    _initCombinePipeline(debounceDuration);
  }

  /// Reactive stream of collection alerts.
  Stream<List<CollectionAlert>> get collectionAlerts =>
      _collectionAlertsController.stream;

  /// Reactive stream of unified collection alert card models (§5.4).
  Stream<List<CollectionAlertCardData>> get collectionAlertCards =>
      _collectionAlertCardsController.stream;

  /// Current cached collection alerts snapshot.
  List<CollectionAlert> get currentAlerts => _currentAlerts;

  /// Current cached unified cards snapshot.
  List<CollectionAlertCardData> get currentAlertCards => _currentAlertCards;

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

    final totalPaidMap = {
      for (final t in _latestTotals!) t.recordId: t.totalPaid,
    };

    final alerts = computeCollectionAlerts(
      _latestRecords!,
      _latestRates!,
      totalPaidMap,
    );

    final cards = computeCollectionAlertCards(
      _latestRecords!,
      _latestRates!,
      totalPaidMap,
    );

    _currentAlerts = alerts;
    _currentAlertCards = cards;
    _collectionAlertsController.add(alerts);
    _collectionAlertCardsController.add(cards);

    if (!_alertsLoaded) {
      _alertsLoaded = true;
      _alertsLoadedController.add(true);
    }
  }

  void dispose() {
    _subRecords?.cancel();
    _subRates?.cancel();
    _subTotals?.cancel();
    _collectionAlertsController.close();
    _collectionAlertCardsController.close();
    _alertsLoadedController.close();
  }
}
