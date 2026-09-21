import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/core/data/backup/backup.dart';
import 'package:money_lending/domain/domain.dart';

void main() {
  group('7.1 JSON Backup & Restore - File Format & Serialization', () {
    // -------------------------------------------------------------------------
    // 1. migrate1_1To1_2 Unit Tests (Mandated in §7.1)
    // -------------------------------------------------------------------------
    group('migrate1_1To1_2 transforms', () {
      test('(1) date-only startDate "2026-04-23" becomes "2026-04-23T00:00:00"', () {
        const wrapper = BackupWrapper(
          version: '1.1',
          customers: [],
          records: [
            BackupRecord(
              id: 'rec-1',
              type: 'GIVEN',
              status: 'ACTIVE',
              customerId: 'cust-1',
              startDate: '2026-04-23',
              principalAmount: 10000,
              interestRate: 2.0,
            ),
          ],
        );

        final migrated = migrate1_1To1_2(wrapper);
        expect(migrated.records.first.startDate, equals('2026-04-23T00:00:00'));
        expect(migrated.version, equals(BackupSerializer.backupVersion));
      });

      test('(2) already-migrated datetime "2026-04-23T14:30:00" passes through unchanged', () {
        const wrapper = BackupWrapper(
          version: '1.1',
          customers: [],
          records: [
            BackupRecord(
              id: 'rec-2',
              type: 'GIVEN',
              status: 'ACTIVE',
              customerId: 'cust-1',
              startDate: '2026-04-23T14:30:00',
              principalAmount: 5000,
              interestRate: 1.5,
            ),
          ],
        );

        final migrated = migrate1_1To1_2(wrapper);
        expect(migrated.records.first.startDate, equals('2026-04-23T14:30:00'));
      });

      test('(3) all payments are migrated identically', () {
        const wrapper = BackupWrapper(
          version: '1.1',
          customers: [],
          records: [
            BackupRecord(
              id: 'rec-3',
              type: 'GIVEN',
              status: 'ACTIVE',
              customerId: 'cust-1',
              startDate: '2026-01-10',
              principalAmount: 8000,
              interestRate: 2.0,
              payments: [
                BackupPayment(
                  id: 'pay-1',
                  amount: 500,
                  date: '2026-02-10', // Date-only
                  interestPaid: 160,
                  principalPaid: 340,
                ),
                BackupPayment(
                  id: 'pay-2',
                  amount: 1000,
                  date: '2026-03-10T16:45:00', // Already datetime
                  interestPaid: 160,
                  principalPaid: 840,
                ),
              ],
            ),
          ],
        );

        final migrated = migrate1_1To1_2(wrapper);
        final payments = migrated.records.first.payments;
        expect(payments[0].date, equals('2026-02-10T00:00:00'));
        expect(payments[1].date, equals('2026-03-10T16:45:00'));
      });
    });

    // -------------------------------------------------------------------------
    // 2. Backup Versioning & Strict String Matching
    // -------------------------------------------------------------------------
    group('Backup versioning and policy for unknown versions', () {
      test('BackupSerializer.backupVersion is "1.4"', () {
        expect(BackupSerializer.backupVersion, equals('1.4'));
      });

      test('Decodes valid version 1.1 with migrate1_1To1_2 transform', () {
        final jsonStr = jsonEncode({
          'version': '1.1',
          'customers': [
            {'id': 'c1', 'name': 'John', 'phone': '9999999999', 'createdAt': '2026-04-01T10:00:00'},
          ],
          'records': [
            {
              'id': 'r1',
              'type': 'GIVEN',
              'status': 'ACTIVE',
              'customerId': 'c1',
              'startDate': '2026-04-01', // Date-only
              'principalAmount': 5000.0,
              'interestRate': 2.0,
            }
          ],
        });

        final decoded = BackupSerializer.decode(jsonStr);
        expect(decoded.version, equals(BackupSerializer.backupVersion));
        expect(decoded.records.first.startDate, equals('2026-04-01T00:00:00'));
        expect(decoded.records.first.transactionId.isNotEmpty, isTrue);
      });

      test('Decodes valid version 1.2, 1.3, 1.4 directly', () {
        for (final v in ['1.2', '1.3', '1.4']) {
          final jsonStr = jsonEncode({
            'version': v,
            'customers': [],
            'records': [
              {
                'id': 'r1',
                'type': 'GIVEN',
                'status': 'ACTIVE',
                'customerId': 'c1',
                'startDate': '2026-04-01T10:00:00',
                'principalAmount': 5000.0,
                'interestRate': 2.0,
              }
            ],
          });

          final decoded = BackupSerializer.decode(jsonStr);
          expect(decoded.records.first.id, equals('r1'));
        }
      });

      test('Rejects unknown versions with exact required message', () {
        final unknownVersions = ['1.5', '2.0', '1.3.1', 'v1.4', 'unknown'];

        for (final v in unknownVersions) {
          final jsonStr = jsonEncode({
            'version': v,
            'customers': [],
            'records': [],
          });

          expect(
            () => BackupSerializer.decode(jsonStr),
            throwsA(
              isA<UnsupportedBackupVersionException>().having(
                (UnsupportedBackupVersionException e) => e.message,
                'message',
                equals('This backup was created by a newer version of MoneyLending. Please update the app before importing.'),
              ),
            ),
          );
        }
      });

      test('Rejects Map without version field', () {
        final jsonStr = jsonEncode({
          'customers': [],
          'records': [],
        });

        expect(
          () => BackupSerializer.decode(jsonStr),
          throwsA(isA<UnsupportedBackupVersionException>()),
        );
      });

      test('Rejects non-object/non-array JSON root', () {
        expect(() => BackupSerializer.decode('"a string"'), throwsA(isA<FormatException>()));
        expect(() => BackupSerializer.decode('123'), throwsA(isA<FormatException>()));
      });
    });

    // -------------------------------------------------------------------------
    // 3. Legacy Bare-Array Lenient Decode & Migrations
    // -------------------------------------------------------------------------
    group('Legacy Bare-Array format handling', () {
      test('Leniently decodes bare List, defaults missing postdating fields, assigns IDs', () {
        final legacyJson = jsonEncode([
          {
            'id': 'legacy-rec-1',
            'type': 'GIVEN',
            'status': 'ACTIVE',
            'customerId': 'cust-old-1',
            'customerName': 'Old Customer',
            'startDate': '2026-05-15', // Date-only
            'principalAmount': 10000.0,
            'interestRate': 2.0,
            // Missing: transactionId, itemCategory, linkedRecordId, calculatedInterest, endDate
            'items': [
              {
                'id': 'item-1',
                'name': 'Gold Ring',
                // Missing: sourceItemId, itemCategory
                'weight': 10.0,
                'itemValue': 50000.0,
              }
            ],
            'payments': [
              {
                'id': 'pay-old-1',
                'amount': 200.0,
                'date': '2026-06-15', // Date-only
                // Missing: paymentId
              }
            ],
          }
        ]);

        final decoded = BackupSerializer.decode(legacyJson);
        expect(decoded.version, equals(BackupSerializer.backupVersion));
        expect(decoded.records.length, equals(1));

        final record = decoded.records.first;
        // Verify postdating defaults [FIX-BACKUPRECORD-DEFAULTS-1]
        expect(record.transactionId, startsWith('TRAN'));
        expect(record.itemCategory, equals('Unknown'));
        expect(record.linkedRecordId, isNull);
        expect(record.calculatedInterest, isNull);
        expect(record.customerName, equals('Old Customer'));
        expect(record.endDate, isNull);

        // Verify date coercion [FIX-TIMESTAMP-BACKUP-1]
        expect(record.startDate, equals('2026-05-15T00:00:00'));

        // Verify items
        expect(record.items.length, equals(1));
        expect(record.items.first.itemCategory, equals('Unknown'));
        expect(record.items.first.sourceItemId, isNull);

        // Verify payments
        expect(record.payments.length, equals(1));
        expect(record.payments.first.paymentId, startsWith('PAY'));
        expect(record.payments.first.date, equals('2026-06-15T00:00:00'));

        // Verify synthesized customer
        expect(decoded.customers.length, equals(1));
        final customer = decoded.customers.first;
        expect(customer.id, equals('cust-old-1'));
        expect(customer.name, equals('Old Customer'));
        expect(customer.displayId, startsWith('CUST'));
      });
    });

    // -------------------------------------------------------------------------
    // 4. Verbatim ID Preservation for Kotlin Exports
    // -------------------------------------------------------------------------
    group('Verbatim ID preservation (Kotlin exports compatibility)', () {
      test('Preserves existing CUST-, TXN-, and TRAN/PAY IDs unchanged', () {
        final jsonStr = jsonEncode({
          'version': '1.4',
          'customers': [
            {
              'id': 'c-1',
              'displayId': 'CUST-0001', // Kotlin verbatim ID
              'name': 'Ramesh',
              'phone': '9876543210',
              'createdAt': '2026-04-10T10:00:00',
            }
          ],
          'records': [
            {
              'id': 'r-1',
              'transactionId': 'TXN-9999', // Kotlin verbatim ID
              'type': 'GIVEN',
              'status': 'ACTIVE',
              'customerId': 'c-1',
              'startDate': '2026-04-10T10:00:00',
              'principalAmount': 10000.0,
              'interestRate': 2.0,
              'payments': [
                {
                  'id': 'p-1',
                  'paymentId': 'PAY042601',
                  'amount': 200.0,
                  'date': '2026-05-10T11:00:00',
                }
              ]
            }
          ],
        });

        final decoded = BackupSerializer.decode(jsonStr);
        expect(decoded.customers.first.displayId, equals('CUST-0001'));
        expect(decoded.records.first.transactionId, equals('TXN-9999'));
        expect(decoded.records.first.payments.first.paymentId, equals('PAY042601'));
      });
    });

    // -------------------------------------------------------------------------
    // 5. Enum Casing [FIX-ENUM-CASE-1]
    // -------------------------------------------------------------------------
    group('Enum Casing [FIX-ENUM-CASE-1]', () {
      test('Outputs UPPERCASE strings for type and status in JSON', () {
        final domainRecord = LedgerRecord(
          id: 'rec-1',
          transactionId: 'TRAN092601',
          type: RecordType.given,
          status: RecordStatus.active,
          customerId: 'cust-1',
          startDate: DateTime(2026, 9, 21, 10, 0),
          principalAmount: 15000,
          interestRate: 2.0,
        );

        final wrapper = BackupSerializer.fromDomain(
          customers: [],
          records: [domainRecord],
        );

        expect(wrapper.records.first.type, equals('GIVEN'));
        expect(wrapper.records.first.status, equals('ACTIVE'));

        final jsonString = BackupSerializer.encode(wrapper);
        expect(jsonString, contains('"type":"GIVEN"'));
        expect(jsonString, contains('"status":"ACTIVE"'));
      });

      test('Throws clear error on unknown RecordType or RecordStatus', () {
        const invalidTypeRecord = BackupRecord(
          id: 'r1',
          type: 'BORROWED_INVALID',
          status: 'ACTIVE',
          customerId: 'c1',
          startDate: '2026-04-01T10:00:00',
          principalAmount: 1000,
          interestRate: 1.0,
        );

        expect(
          () => BackupSerializer.toDomain(
            const BackupWrapper(
              version: '1.4',
              customers: [],
              records: [invalidTypeRecord],
            ),
          ),
          throwsA(isA<FormatException>().having((FormatException e) => e.message, 'message', contains('Unknown RecordType'))),
        );

        const invalidStatusRecord = BackupRecord(
          id: 'r1',
          type: 'GIVEN',
          status: 'CANCELLED_INVALID',
          customerId: 'c1',
          startDate: '2026-04-01T10:00:00',
          principalAmount: 1000,
          interestRate: 1.0,
        );

        expect(
          () => BackupSerializer.toDomain(
            const BackupWrapper(
              version: '1.4',
              customers: [],
              records: [invalidStatusRecord],
            ),
          ),
          throwsA(isA<FormatException>().having((FormatException e) => e.message, 'message', contains('Unknown RecordStatus'))),
        );
      });
    });

    // -------------------------------------------------------------------------
    // 6. [FIX-BACKUPRECORD-ENDDATE-1] & Field Preservation Round-Trip
    // -------------------------------------------------------------------------
    group('[FIX-BACKUPRECORD-ENDDATE-1] & Round-Trip Preservation', () {
      test('endDate: null maps to "" on export, "" and null map to null on import', () {
        // Open-ended loan (null endDate)
        final openEndedRecord = LedgerRecord(
          id: 'r-open',
          transactionId: 'TRAN092601',
          type: RecordType.given,
          status: RecordStatus.active,
          customerId: 'cust-1',
          startDate: DateTime(2026, 9, 21),
          endDate: null,
          principalAmount: 10000,
          interestRate: 2.0,
        );

        final exported = BackupSerializer.fromDomain(customers: [], records: [openEndedRecord]);
        expect(exported.records.first.endDate, equals(''));

        final importedFromEmpty = BackupSerializer.toDomain(exported);
        expect(importedFromEmpty.records.first.endDate, isNull);

        // Explicit null in BackupRecord
        const explicitNullRecord = BackupRecord(
          id: 'r-null',
          type: 'GIVEN',
          status: 'ACTIVE',
          customerId: 'c1',
          startDate: '2026-04-01T00:00:00',
          endDate: null,
          principalAmount: 5000,
          interestRate: 1.5,
        );
        final importedFromNull = BackupSerializer.toDomain(
          const BackupWrapper(version: '1.4', customers: [], records: [explicitNullRecord]),
        );
        expect(importedFromNull.records.first.endDate, isNull);

        // Non-null endDate
        final fixedTermRecord = LedgerRecord(
          id: 'r-fixed',
          transactionId: 'TRAN092602',
          type: RecordType.given,
          status: RecordStatus.active,
          customerId: 'cust-1',
          startDate: DateTime(2026, 9, 21),
          endDate: DateTime(2026, 12, 21),
          principalAmount: 10000,
          interestRate: 2.0,
        );
        final exportedFixed = BackupSerializer.fromDomain(customers: [], records: [fixedTermRecord]);
        expect(exportedFixed.records.first.endDate, equals(DateTime(2026, 12, 21).toIso8601String()));
        final importedFixed = BackupSerializer.toDomain(exportedFixed);
        expect(importedFixed.records.first.endDate, equals(DateTime(2026, 12, 21)));
      });

      test('Preserves customerName, linkedRecordId, and calculatedInterest through round-trip', () {
        final originalCustomer = Customer(
          id: 'cust-100',
          displayId: 'CUST26-27-01',
          name: 'Amit Patel',
          phone: '9898989898',
          address: 'Main Bazaar',
          createdAt: DateTime(2026, 4, 1, 10, 0),
        );

        final originalRecord = LedgerRecord(
          id: 'rec-100',
          transactionId: 'TRAN092601',
          type: RecordType.given,
          status: RecordStatus.settled,
          customerId: 'cust-100',
          customerName: 'Amit Patel', // backward-compat customerName
          startDate: DateTime(2026, 4, 1, 10, 0),
          endDate: DateTime(2026, 9, 1, 10, 0),
          settledDate: DateTime(2026, 9, 15, 14, 0),
          principalAmount: 50000,
          interestRate: 1.75,
          calculatedInterest: 4375.0, // settled snapshot
          linkedRecordId: 'rec-renewed-099', // linked record
          items: [
            const LedgerItem(
              id: 'item-100',
              recordId: 'rec-100',
              name: 'Gold Chain',
              itemCategory: 'Gold',
              weight: 25.5,
              purity: 91.6,
              rate: 7000.0,
              itemValue: 178500.0,
              lendPercentage: 70.0,
              lendableAmount: 124950.0,
              sourceItemId: 'source-item-001',
            ),
          ],
          payments: [
            Payment(
              id: 'pay-100',
              paymentId: 'PAY092601',
              recordId: 'rec-100',
              amount: 54375.0,
              date: DateTime(2026, 9, 15, 14, 0),
              interestPaid: 4375.0,
              principalPaid: 50000.0,
            ),
          ],
        );

        const retired = BackupRetiredId(
          kind: 'transaction',
          displayId: 'TRAN092600',
          retiredAt: '2026-09-01T10:00:00',
        );

        // 1. Domain -> DTO
        final dtoWrapper = BackupSerializer.fromDomain(
          customers: [originalCustomer],
          records: [originalRecord],
          retiredIds: [retired],
        );

        // 2. DTO -> JSON
        final jsonString = BackupSerializer.encode(dtoWrapper);

        // 3. JSON -> DTO
        final decodedWrapper = BackupSerializer.decode(jsonString);

        // 4. DTO -> Domain
        final restored = BackupSerializer.toDomain(decodedWrapper);

        expect(restored.customers.length, equals(1));
        expect(restored.customers.first.id, equals(originalCustomer.id));
        expect(restored.customers.first.displayId, equals(originalCustomer.displayId));
        expect(restored.customers.first.name, equals(originalCustomer.name));
        expect(restored.customers.first.phone, equals(originalCustomer.phone));
        expect(restored.customers.first.address, equals(originalCustomer.address));

        expect(restored.records.length, equals(1));
        final restoredRec = restored.records.first;
        expect(restoredRec.id, equals(originalRecord.id));
        expect(restoredRec.transactionId, equals(originalRecord.transactionId));
        expect(restoredRec.customerName, equals(originalRecord.customerName));
        expect(restoredRec.linkedRecordId, equals(originalRecord.linkedRecordId));
        expect(restoredRec.calculatedInterest, equals(originalRecord.calculatedInterest));
        expect(restoredRec.principalAmount, equals(originalRecord.principalAmount));
        expect(restoredRec.interestRate, equals(originalRecord.interestRate));
        expect(restoredRec.settledDate, equals(originalRecord.settledDate));

        // Items and payments
        expect(restoredRec.items.length, equals(1));
        expect(restoredRec.items.first.sourceItemId, equals('source-item-001'));
        expect(restoredRec.items.first.name, equals('Gold Chain'));
        expect(restoredRec.items.first.itemCategory, equals('Gold'));

        expect(restoredRec.payments.length, equals(1));
        expect(restoredRec.payments.first.paymentId, equals('PAY092601'));
        expect(restoredRec.payments.first.amount, equals(54375.0));

        // Retired IDs
        expect(restored.retiredIds.length, equals(1));
        expect(restored.retiredIds.first.displayId, equals('TRAN092600'));
      });
    });
  });
}
