import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/data/backup/backup.dart';
import 'package:money_lending/data/datasources/database_helper.dart';
import 'package:money_lending/data/repositories/customer_repository_impl.dart';
import 'package:money_lending/data/repositories/item_rate_repository_impl.dart';
import 'package:money_lending/data/repositories/record_repository_impl.dart';
import 'package:money_lending/data/repositories/settings_repository_impl.dart';
import 'package:money_lending/domain/domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late DatabaseHelper dbHelper;
  late CustomerRepository customerRepo;
  late RecordRepository recordRepo;
  late SettingsRepository settingsRepo;
  late ItemRateRepository itemRateRepo;
  late BackupService backupService;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await DatabaseHelper.createTablesForTesting(db);
        },
      ),
    );
    dbHelper = DatabaseHelper.forTesting(db);

    customerRepo = CustomerRepositoryImpl(dbHelper);
    recordRepo = RecordRepositoryImpl(dbHelper);
    settingsRepo = SettingsRepositoryImpl(dbHelper);
    itemRateRepo = ItemRateRepositoryImpl(dbHelper);

    backupService = BackupService(
      dbHelper: dbHelper,
      customerRepository: customerRepo,
      recordRepository: recordRepo,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('7.2 Flutter File Access - Backup & Restore System', () {
    // -------------------------------------------------------------------------
    // 1. backupStamp and File Naming Specification
    // -------------------------------------------------------------------------
    group('backupStamp and filename formatting (§7.2)', () {
      test('backupStamp formats yyyyMMdd_HHmmss with padLeft (e.g. 20260920_101530)', () {
        final dt = DateTime(2026, 9, 20, 10, 15, 30);
        final stamp = BackupService.backupStamp(dt);

        expect(stamp, equals('20260920_101530'));
        expect(stamp, isNot(contains(':')));
        expect(stamp, isNot(contains('-')));
        expect(RegExp(r'^\d{8}_\d{6}$').hasMatch(stamp), isTrue);
      });

      test('backupStamp pads single-digit values correctly', () {
        final dt = DateTime(2026, 1, 5, 4, 3, 2);
        final stamp = BackupService.backupStamp(dt);

        expect(stamp, equals('20260105_040302'));
      });

      test('generateBackupFileName produces canonical moneylending_backup_YYYYMMDD_HHMMSS.json', () {
        final dt = DateTime(2026, 9, 20, 10, 15, 30);
        final fileName = BackupService.generateBackupFileName(dt);

        expect(fileName, equals('moneylending_backup_20260920_101530.json'));
      });
    });

    // -------------------------------------------------------------------------
    // 2. Pure Duplicate ID & Integrity Validation
    // -------------------------------------------------------------------------
    group('validateBackup duplicate ID detection', () {
      test('Identifies offending duplicate customer displayId', () {
        const wrapper = BackupWrapper(
          version: '1.4',
          customers: [
            BackupCustomer(id: 'c1', displayId: 'CUST26-27-01', name: 'Alice', createdAt: '2026-04-01T10:00:00'),
            BackupCustomer(id: 'c2', displayId: 'CUST26-27-01', name: 'Bob', createdAt: '2026-04-02T10:00:00'),
          ],
          records: [],
        );

        expect(
          () => BackupService.validateBackup(wrapper),
          throwsA(
            isA<BackupValidationException>().having(
              (e) => e.offendingId,
              'offendingId',
              equals('CUST26-27-01'),
            ),
          ),
        );
      });

      test('Identifies offending duplicate transactionId', () {
        const wrapper = BackupWrapper(
          version: '1.4',
          customers: [
            BackupCustomer(id: 'c1', displayId: 'CUST26-27-01', name: 'Alice', createdAt: '2026-04-01T10:00:00'),
          ],
          records: [
            BackupRecord(
              id: 'r1',
              transactionId: 'TRAN092601',
              type: 'GIVEN',
              status: 'ACTIVE',
              customerId: 'c1',
              startDate: '2026-09-01T10:00:00',
              principalAmount: 10000,
              interestRate: 2.0,
            ),
            BackupRecord(
              id: 'r2',
              transactionId: 'TRAN092601', // Duplicate!
              type: 'GIVEN',
              status: 'ACTIVE',
              customerId: 'c1',
              startDate: '2026-09-02T10:00:00',
              principalAmount: 5000,
              interestRate: 2.0,
            ),
          ],
        );

        expect(
          () => BackupService.validateBackup(wrapper),
          throwsA(
            isA<BackupValidationException>().having(
              (e) => e.offendingId,
              'offendingId',
              equals('TRAN092601'),
            ),
          ),
        );
      });

      test('Identifies offending duplicate paymentId', () {
        const wrapper = BackupWrapper(
          version: '1.4',
          customers: [
            BackupCustomer(id: 'c1', displayId: 'CUST26-27-01', name: 'Alice', createdAt: '2026-04-01T10:00:00'),
          ],
          records: [
            BackupRecord(
              id: 'r1',
              transactionId: 'TRAN092601',
              type: 'GIVEN',
              status: 'ACTIVE',
              customerId: 'c1',
              startDate: '2026-09-01T10:00:00',
              principalAmount: 10000,
              interestRate: 2.0,
              payments: [
                BackupPayment(id: 'p1', paymentId: 'PAY092601', amount: 500, date: '2026-09-10T10:00:00'),
                BackupPayment(id: 'p2', paymentId: 'PAY092601', amount: 200, date: '2026-09-15T10:00:00'),
              ],
            ),
          ],
        );

        expect(
          () => BackupService.validateBackup(wrapper),
          throwsA(
            isA<BackupValidationException>().having(
              (e) => e.offendingId,
              'offendingId',
              equals('PAY092601'),
            ),
          ),
        );
      });

      test('Identifies offending duplicate customer primary key ID', () {
        const wrapper = BackupWrapper(
          version: '1.4',
          customers: [
            BackupCustomer(id: 'duplicate-c-id', displayId: 'CUST26-27-01', name: 'Alice', createdAt: '2026-04-01T10:00:00'),
            BackupCustomer(id: 'duplicate-c-id', displayId: 'CUST26-27-02', name: 'Bob', createdAt: '2026-04-02T10:00:00'),
          ],
          records: [],
        );

        expect(
          () => BackupService.validateBackup(wrapper),
          throwsA(
            isA<BackupValidationException>().having(
              (e) => e.offendingId,
              'offendingId',
              equals('duplicate-c-id'),
            ),
          ),
        );
      });
    });

    // -------------------------------------------------------------------------
    // 3. Transactional Replace-All Restore (§7.2, Addendum G, FIX-ID-BACKUP-1)
    // -------------------------------------------------------------------------
    group('Transactional Replace-All Restore', () {
      test('Restores backup atomically, replacing existing data while preserving settings and rates', () async {
        // 1. Seed existing device data
        final existingCust = await customerRepo.insertCustomer(
          Customer(
            id: 'old-cust-1',
            displayId: 'CUST26-27-99',
            name: 'Old Existing Customer',
            phone: '1111111111',
            createdAt: DateTime(2026, 4, 1),
          ),
        );

        await recordRepo.insertRecord(
          LedgerRecord(
            id: 'old-rec-1',
            transactionId: 'TRAN092699',
            type: RecordType.given,
            status: RecordStatus.active,
            customerId: existingCust.id,
            startDate: DateTime(2026, 9, 1),
            principalAmount: 20000,
            interestRate: 2.0,
          ),
        );

        // Seed settings and item rate
        await settingsRepo.updateSettings(
          const Settings(
            name: 'Original Gold Shop',
            phone: '9988776655',
            address: 'Market Yard',
            defaultInterestRate: 2.5,
          ),
        );

        await itemRateRepo.upsertRate(
          ItemRate(
            id: 'rate-1',
            itemCategory: 'GOLD',
            ratePerUnit: 7500.0,
            effectiveDate: DateTime(2026, 9, 1),
            updatedAt: DateTime(2026, 9, 1),
          ),
        );

        // Verify initial state
        var currentCustomers = await customerRepo.getAllCustomersOnce();
        var currentRecords = await recordRepo.getAllRecordsOnce();
        expect(currentCustomers.length, equals(1));
        expect(currentRecords.length, equals(1));

        // 2. Prepare BackupWrapper to restore
        const backupWrapper = BackupWrapper(
          version: '1.4',
          customers: [
            BackupCustomer(
              id: 'restored-c1',
              displayId: 'CUST26-27-01',
              name: 'Restored New Customer',
              phone: '9999900000',
              address: 'Downtown',
              createdAt: '2026-05-01T10:00:00',
            ),
          ],
          records: [
            BackupRecord(
              id: 'restored-r1',
              transactionId: 'TRAN092601',
              type: 'GIVEN',
              status: 'ACTIVE',
              customerId: 'restored-c1',
              startDate: '2026-09-10T14:30:00',
              principalAmount: 35000,
              interestRate: 1.5,
              items: [
                BackupItem(
                  id: 'restored-item-1',
                  recordId: 'restored-r1',
                  name: 'Gold Bangle',
                  itemCategory: 'GOLD',
                  weight: 15.0,
                  purity: 91.6,
                  rate: 7200.0,
                  itemValue: 98928.0,
                  lendPercentage: 70.0,
                  lendableAmount: 69249.6,
                ),
              ],
              payments: [
                BackupPayment(
                  id: 'restored-p1',
                  paymentId: 'PAY092601',
                  recordId: 'restored-r1',
                  amount: 500.0,
                  date: '2026-09-20T11:00:00',
                  interestPaid: 500.0,
                  principalPaid: 0.0,
                ),
              ],
            ),
          ],
          retiredIds: [
            BackupRetiredId(
              kind: 'transaction',
              displayId: 'TRAN092600',
              retiredAt: '2026-09-01T10:00:00',
            ),
          ],
        );

        // 3. Execute transactional restore
        await backupService.restoreBackup(backupWrapper);

        // 4. Verify replace-all: old customer & record replaced completely
        currentCustomers = await customerRepo.getAllCustomersOnce();
        currentRecords = await recordRepo.getAllRecordsOnce();

        expect(currentCustomers.length, equals(1));
        expect(currentCustomers.first.id, equals('restored-c1'));
        expect(currentCustomers.first.displayId, equals('CUST26-27-01'));
        expect(currentCustomers.first.name, equals('Restored New Customer'));

        expect(currentRecords.length, equals(1));
        expect(currentRecords.first.id, equals('restored-r1'));
        expect(currentRecords.first.transactionId, equals('TRAN092601'));
        expect(currentRecords.first.principalAmount, equals(35000.0));
        expect(currentRecords.first.items.length, equals(1));
        expect(currentRecords.first.payments.length, equals(1));

        // Retired IDs present in database
        final retired = await dbHelper.getAllRetiredIds();
        expect(retired.length, equals(1));
        expect(retired.first['displayId'], equals('TRAN092600'));

        // 5. Verify settings and item rates were NEVER touched (§7.2, [FIX-ID-BACKUP-1])
        final settings = await settingsRepo.getSettingsOnce();
        expect(settings.name, equals('Original Gold Shop'));
        expect(settings.phone, equals('9988776655'));

        final goldRate = await itemRateRepo.getCurrentRateOnce('GOLD');
        expect(goldRate, isNotNull);
        expect(goldRate!.ratePerUnit, equals(7500.0));
      });

      test('Restores backup and replaces settings and itemRates when present [FIX-BACKUP-CONFIG-1]', () async {
        // 1. Initial settings and rates
        await settingsRepo.updateSettings(
          const Settings(
            name: 'Initial Shop',
            phone: '1111111111',
            address: 'Initial Address',
            defaultInterestRate: 2.0,
          ),
        );
        await itemRateRepo.upsertRate(
          ItemRate(
            id: 'rate-1',
            itemCategory: 'GOLD',
            ratePerUnit: 6000.0,
            effectiveDate: DateTime(2026, 9, 1),
            updatedAt: DateTime(2026, 9, 1),
          ),
        );

        // 2. Backup wrapper with new settings and new item rates
        const backupWrapper = BackupWrapper(
          version: '1.4',
          customers: [],
          records: [],
          settings: BackupSettings(
            name: 'Restored Shop Name',
            phone: '8888888888',
            address: 'Restored Address',
            defaultInterestRate: 3.0,
          ),
          itemRates: [
            BackupItemRate(
              id: 'restored-rate-1',
              itemCategory: 'GOLD',
              ratePerUnit: 7200.0,
              effectiveDate: '2026-09-20',
              updatedAt: '2026-09-20T10:00:00',
            ),
          ],
        );

        await backupService.restoreBackup(backupWrapper);

        final settings = await settingsRepo.getSettingsOnce();
        expect(settings.name, equals('Restored Shop Name'));
        expect(settings.phone, equals('8888888888'));
        expect(settings.defaultInterestRate, equals(3.0));

        final goldRate = await itemRateRepo.getCurrentRateOnce('GOLD');
        expect(goldRate, isNotNull);
        expect(goldRate!.ratePerUnit, equals(7200.0));
      });

      test('Rolls back full import on failure, leaving previous data 100% intact', () async {
        // 1. Seed existing data
        final existingCust = await customerRepo.insertCustomer(
          Customer(
            id: 'original-c1',
            displayId: 'CUST26-27-01',
            name: 'Original Preserved Customer',
            phone: '5555555555',
            createdAt: DateTime(2026, 4, 1),
          ),
        );

        await recordRepo.insertRecord(
          LedgerRecord(
            id: 'original-r1',
            transactionId: 'TRAN092601',
            type: RecordType.given,
            status: RecordStatus.active,
            customerId: existingCust.id,
            startDate: DateTime(2026, 9, 1),
            principalAmount: 15000,
            interestRate: 2.0,
          ),
        );

        // 2. Prepare an invalid backup containing a duplicate transactionId
        const invalidWrapper = BackupWrapper(
          version: '1.4',
          customers: [
            BackupCustomer(id: 'c1', displayId: 'CUST26-27-10', name: 'New 1', createdAt: '2026-05-01T10:00:00'),
          ],
          records: [
            BackupRecord(
              id: 'r1',
              transactionId: 'TRAN092602',
              type: 'GIVEN',
              status: 'ACTIVE',
              customerId: 'c1',
              startDate: '2026-09-01T10:00:00',
              principalAmount: 1000,
              interestRate: 2.0,
            ),
            BackupRecord(
              id: 'r2',
              transactionId: 'TRAN092602', // DUPLICATE transactionId!
              type: 'GIVEN',
              status: 'ACTIVE',
              customerId: 'c1',
              startDate: '2026-09-02T10:00:00',
              principalAmount: 2000,
              interestRate: 2.0,
            ),
          ],
        );

        // 3. Attempt restore -> Must throw BackupValidationException identifying offending ID
        expect(
          () => backupService.restoreBackup(invalidWrapper),
          throwsA(
            isA<BackupValidationException>().having(
              (e) => e.offendingId,
              'offendingId',
              equals('TRAN092602'),
            ),
          ),
        );

        // 4. Verify original data was 100% preserved (no partial deletion or insertion)
        final customers = await customerRepo.getAllCustomersOnce();
        final records = await recordRepo.getAllRecordsOnce();

        expect(customers.length, equals(1));
        expect(customers.first.id, equals('original-c1'));
        expect(customers.first.name, equals('Original Preserved Customer'));

        expect(records.length, equals(1));
        expect(records.first.id, equals('original-r1'));
        expect(records.first.transactionId, equals('TRAN092601'));
      });
    });

    // -------------------------------------------------------------------------
    // 4. End-to-End Export & Import Round-Trip
    // -------------------------------------------------------------------------
    group('End-to-End Export & Import Round-Trip', () {
      test('generateBackupJson exports complete database and parseAndValidate decodes it', () async {
        final cust = await customerRepo.insertCustomer(
          Customer(
            id: 'e2e-c1',
            displayId: 'CUST26-27-01',
            name: 'Sunita Sharma',
            phone: '9876500000',
            createdAt: DateTime(2026, 4, 1),
          ),
        );

        await recordRepo.insertRecord(
          LedgerRecord(
            id: 'e2e-r1',
            transactionId: 'TRAN092601',
            type: RecordType.given,
            status: RecordStatus.active,
            customerId: cust.id,
            startDate: DateTime(2026, 9, 1),
            principalAmount: 25000,
            interestRate: 2.0,
            items: [
              const LedgerItem(
                id: 'e2e-item-1',
                recordId: 'e2e-r1',
                name: 'Silver Anklets',
                itemCategory: 'SILVER',
                weight: 100.0,
                purity: 80.0,
                rate: 80.0,
                itemValue: 6400.0,
                lendPercentage: 75.0,
                lendableAmount: 4800.0,
              ),
            ],
          ),
        );

        // Export to JSON string
        final exportedJson = await backupService.generateBackupJson();
        expect(exportedJson, contains('"version":"1.4"'));
        expect(exportedJson, contains('"displayId":"CUST26-27-01"'));
        expect(exportedJson, contains('"transactionId":"TRAN092601"'));

        // Parse and validate exported JSON
        final decodedWrapper = BackupService.parseAndValidateBackup(exportedJson);
        expect(decodedWrapper.customers.length, equals(1));
        expect(decodedWrapper.records.length, equals(1));
        expect(decodedWrapper.records.first.items.length, equals(1));
        expect(decodedWrapper.records.first.items.first.name, equals('Silver Anklets'));
      });
    });
  });
}
