import 'package:drift/drift.dart';
import '../converters/date_converters.dart';

/// Drift Schema Table Definitions (§4.1 Table Mapping & §4.2 Key Decisions).
///
/// Direct 1:1 mapping from Domain Types to Drift tables.
/// Every constraint, generation rule, and nullability rule matches §4.1:
/// - CustomerEntity -> customers
/// - RecordEntity -> records
/// - LedgerItemEntity -> ledger_items
/// - PaymentEntity -> payments
/// - SettingsEntity -> settings
/// - ItemRateEntity -> item_rates
/// - RetiredIdEntity -> retired_ids

/// customers table (§4.1)
/// id (UUID TEXT), displayId (TEXT NOT NULL UNIQUE, CUST26-27-01 format)
/// createdAt stored as ISO date string YYYY-MM-DD (time truncated to midnight).
@DataClassName('CustomerEntityData')
class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get displayId => text().unique()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get createdAt => text().map(const DateOnlyConverter())();

  @override
  String get tableName => 'customers';

  @override
  Set<Column> get primaryKey => {id};
}

// DO NOT CHANGE TO INTEGER — switching to paise storage requires a Drift schema migration; money is a REAL rounded to 2 decimals with roundMoney(); see §4.2 and Addendum J.1.
/// records table (§4.1)
/// type (TEXT enum, stored as lowercase enum .name given/taken [FIX-ENUM-CASE-1])
/// startDate stored as full ISO-8601 datetime string YYYY-MM-DDTHH:MM:SS [FIX-TIMESTAMP-RECORD-1]
/// endDate nullable date-only string (null for open-ended loans)
/// status stored as lowercase active/settled
/// settledDate nullable date-only string
/// calculatedInterest nullable money snapshot
/// transactionId unique TRAN092601 format [FIX-ID-FORMAT-1]
@DataClassName('RecordEntityData')
class Records extends Table {
  TextColumn get id => text()();
  TextColumn get transactionId => text().unique()();
  TextColumn get type => text()();
  TextColumn get customerId => text().references(Customers, #id, onDelete: KeyAction.cascade)();
  TextColumn get customerName => text().nullable()();
  TextColumn get startDate => text().map(const LocalDateTimeConverter())();
  TextColumn get endDate => text().map(const DateOnlyConverter()).nullable()();
  RealColumn get principalAmount => real()();
  RealColumn get interestRate => real()();
  TextColumn get status => text()();
  TextColumn get settledDate => text().map(const DateOnlyConverter()).nullable()();
  RealColumn get calculatedInterest => real().nullable()();
  TextColumn get linkedRecordId => text().nullable()();

  @override
  String get tableName => 'records';

  @override
  Set<Column> get primaryKey => {id};
}

// DO NOT CHANGE TO INTEGER — switching to paise storage requires a Drift schema migration; money is a REAL rounded to 2 decimals with roundMoney(); see §4.2 and Addendum J.1.
/// ledger_items table (§4.1)
/// itemCategory: FK-equivalent join key to item_rates.itemCategory
/// description: strictly nullable in table & domain model [FIX-LEDGERITEM-NULLABILITY-1]
/// rate: snapshot from ItemRateEntity at time of lending
/// itemValue: roundMoney(weight * (purity/100) * rate)
/// lendableAmount: roundMoney(itemValue * (lendPercentage/100))
/// sourceItemId: self-referential FK to ledger_items.id, ON DELETE SET NULL [FIX-ITEM-CUSTODY-2]
@DataClassName('LedgerItemEntityData')
class LedgerItems extends Table {
  TextColumn get id => text()();
  TextColumn get recordId => text().references(Records, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  TextColumn get itemCategory => text()();
  TextColumn get description => text().nullable()();
  RealColumn get weight => real()();
  RealColumn get purity => real()();
  RealColumn get rate => real()();
  RealColumn get itemValue => real()();
  RealColumn get lendPercentage => real()();
  RealColumn get lendableAmount => real()();
  TextColumn get sourceItemId => text().nullable()();

  @override
  String get tableName => 'ledger_items';

  @override
  Set<Column> get primaryKey => {id};
}

// DO NOT CHANGE TO INTEGER — switching to paise storage requires a Drift schema migration; money is a REAL rounded to 2 decimals with roundMoney(); see §4.2 and Addendum J.1.
/// payments table (§4.1)
/// date: ISO datetime string YYYY-MM-DDTHH:MM:SS [FIX-TIMESTAMP-PAYMENT-1]
/// notes: nullable column, repository maps null -> ""
/// interestPaid, principalPaid: recalculated cache of interest-first split [FIX-REPLAY-1]
/// paymentId: PAY092601 format unique [FIX-ID-FORMAT-1]
@DataClassName('PaymentEntityData')
class Payments extends Table {
  TextColumn get id => text()();
  TextColumn get recordId => text().references(Records, #id, onDelete: KeyAction.cascade)();
  RealColumn get amount => real()();
  TextColumn get date => text().map(const LocalDateTimeConverter())();
  TextColumn get notes => text().nullable()();
  RealColumn get interestPaid => real()();
  RealColumn get principalPaid => real()();
  TextColumn get paymentId => text().unique()();

  @override
  String get tableName => 'payments';

  @override
  Set<Column> get primaryKey => {id};
}

// DO NOT CHANGE TO INTEGER — switching to paise storage requires a Drift schema migration; money is a REAL rounded to 2 decimals with roundMoney(); see §4.2 and Addendum J.1.
/// settings table (§4.1)
/// Single-row table (id = 1)
@DataClassName('SettingsEntityData')
class Settings extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  TextColumn get phone => text()();
  TextColumn get address => text()();
  RealColumn get defaultInterestRate => real()();

  @override
  String get tableName => 'settings';

  @override
  Set<Column> get primaryKey => {id};
}

// DO NOT CHANGE TO INTEGER — switching to paise storage requires a Drift schema migration; money is a REAL rounded to 2 decimals with roundMoney(); see §4.2 and Addendum J.1.
/// item_rates table (§4.1)
/// One row per category per date. Unique index on (itemCategory, effectiveDate).
/// Historical snapshots in LedgerItemEntity.rate are never modified.
@DataClassName('ItemRateEntityData')
class ItemRates extends Table {
  TextColumn get id => text()();
  TextColumn get itemCategory => text()();
  RealColumn get ratePerUnit => real()();
  TextColumn get effectiveDate => text().map(const DateOnlyConverter())();
  TextColumn get updatedAt => text().map(const LocalDateTimeConverter())();

  @override
  String get tableName => 'item_rates';

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {itemCategory, effectiveDate},
  ];
}

/// retired_ids table (§4.1 & Addendum G, FIX-ID-REUSE-1)
/// Bookkeeping only: composite primary key (kind, displayId).
/// kind: 'customer' | 'transaction' | 'payment'.
@DataClassName('RetiredIdEntityData')
class RetiredIds extends Table {
  TextColumn get kind => text()();
  TextColumn get displayId => text()();
  TextColumn get retiredAt => text().map(const LocalDateTimeConverter())();

  @override
  String get tableName => 'retired_ids';

  @override
  Set<Column> get primaryKey => {kind, displayId};
}
