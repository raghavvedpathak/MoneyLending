import 'dart:async';
import '../../core/utils/app_date_formatter.dart';
import '../../core/utils/uuid_generator.dart';
import '../../domain/models/item_rate.dart';
import '../../domain/repositories/item_rate_repository.dart';
import '../datasources/database_helper.dart';
import '../models/item_rate_entity.dart';

/// Concrete Data Layer implementation of ItemRateRepository.
///
/// Mandated by Data Spec §4.3 & §4.5 [FIX-ARCH-ITEMRATE-1]:
/// - Implements the ItemRateRepository interface defined in :core:domain.
/// - Concurrency safe via rateUpsertLock [FIX-DEVCONCURRENCY-1].
/// - Preserves existing UUID id on update (never uses REPLACE).
class ItemRateRepositoryImpl implements ItemRateRepository {
  final DatabaseHelper _dbHelper;
  late final StreamController<List<ItemRate>> _ratesStreamController =
      StreamController<List<ItemRate>>.broadcast(onListen: _refreshStream);

  ItemRateRepositoryImpl([DatabaseHelper? dbHelper])
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  Future<void> _refreshStream() async {
    final rates = await getCurrentRatesOnce();
    _ratesStreamController.add(rates);
  }

  ItemRate _toDomain(ItemRateEntity entity) {
    return ItemRate(
      id: entity.id,
      itemCategory: entity.itemCategory,
      ratePerUnit: entity.ratePerUnit,
      effectiveDate: AppDateFormatter.parseIso(entity.effectiveDate) ?? DateTime.now(),
      updatedAt: AppDateFormatter.parseIso(entity.updatedAt) ?? DateTime.now(),
    );
  }

  @override
  Stream<ItemRate?> getCurrentRate(String category) async* {
    yield await getCurrentRateOnce(category);
    yield* _ratesStreamController.stream.map((rates) {
      try {
        return rates.firstWhere((r) => r.itemCategory == category);
      } catch (_) {
        return null;
      }
    });
  }

  @override
  Future<ItemRate?> getCurrentRateOnce(String category) async {
    final entity = await _dbHelper.getLatestRateForCategory(category);
    if (entity == null) return null;
    return _toDomain(entity);
  }

  @override
  Stream<List<ItemRate>> getCurrentRates() {
    _refreshStream();
    return _ratesStreamController.stream;
  }

  @override
  Future<List<ItemRate>> getCurrentRatesOnce() async {
    final entities = await _dbHelper.getLatestRatesForEveryCategory();
    return entities.map(_toDomain).toList();
  }

  @override
  Stream<List<ItemRate>> getRatesForDate(String date) async* {
    yield await getRatesForDateOnce(date);
    yield* _ratesStreamController.stream.asyncMap((_) async {
      return await getRatesForDateOnce(date);
    });
  }

  @override
  Future<List<ItemRate>> getRatesForDateOnce(String date) async {
    final entities = await _dbHelper.getRatesForDate(date);
    return entities.map(_toDomain).toList();
  }

  @override
  Stream<List<ItemRate>> getRatesStream() => getCurrentRates();

  @override
  Future<void> upsertRate(ItemRate rate) async {
    final entity = ItemRateEntity(
      id: rate.id.isNotEmpty ? rate.id : AppUuid.generate(),
      itemCategory: rate.itemCategory,
      ratePerUnit: rate.ratePerUnit,
      effectiveDate: AppDateFormatter.toIsoDate(rate.effectiveDate),
      updatedAt: AppDateFormatter.toIsoDateTime(DateTime.now()),
    );
    await _dbHelper.upsertItemRate(entity);
    await _refreshStream();
  }
}
