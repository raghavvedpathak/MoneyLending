import 'package:flutter_test/flutter_test.dart';
import 'package:money_lending/data/data.dart';

void main() {
  group('Data Layer Entity & Schema Tests (§4.1)', () {
    test('CustomerEntity serialization and displayId integrity [FIX-DEVCONCURRENCY-1]', () {
      const customer = CustomerEntity(
        id: 'cust-uuid-1',
        displayId: 'CUST-0001',
        name: 'Ramesh Kumar',
        phone: '9876543210',
        address: 'Bazaar Road',
        createdAt: '2026-04-23',
      );

      final map = customer.toMap();
      expect(map['displayId'], 'CUST-0001');
      expect(map['createdAt'], '2026-04-23');

      final deserialized = CustomerEntity.fromMap(map);
      expect(deserialized.id, customer.id);
      expect(deserialized.displayId, 'CUST-0001');
      expect(deserialized.name, 'Ramesh Kumar');
      expect(deserialized.formattedCreatedAt, '23 April 2026');
    });

    test('RecordEntity enforces ISO datetime [FIX-TIMESTAMPRECORD-1]', () {
      const record = RecordEntity(
        id: 'rec-uuid-1',
        transactionId: 'TXN-0001',
        type: 'GIVEN',
        customerId: 'cust-uuid-1',
        startDate: '2026-04-23T14:30:00',
        endDate: null,
        principalAmount: 50000.0,
        interestRate: 2.0,
        status: 'ACTIVE',
        settledDate: null,
        calculatedInterest: null,
        linkedRecordId: null,
      );

      final map = record.toMap();
      expect(map['startDate'], '2026-04-23T14:30:00');
      expect(map['endDate'], isNull);

      final fromMap = RecordEntity.fromMap(map);
      expect(fromMap.startDate, '2026-04-23T14:30:00');
      expect(fromMap.endDate, isNull);
      expect(fromMap.formattedStartDate, '23 April 2026');
      expect(fromMap.formattedStartDateTime, '23 April 2026, 02:30 PM');
    });

    test('LedgerItemEntity nullability guarantees [FIXLEDGERITEM-NULLABILITY-1]', () {
      const item = LedgerItemEntity(
        id: 'item-uuid-1',
        recordId: 'rec-uuid-1',
        name: 'Gold Ring with Ruby',
        itemCategory: 'Gold 22K',
        description: null, // Strictly nullable
        weight: 10.5,
        purity: 91.6,
        rate: 7200.0,
        itemValue: 69249.6,
        lendPercentage: 80.0,
        lendableAmount: 55399.68,
      );

      final map = item.toMap();
      expect(map['name'], 'Gold Ring with Ruby');
      expect(map['description'], isNull);

      final fromMap = LedgerItemEntity.fromMap(map);
      expect(fromMap.name, 'Gold Ring with Ruby');
      expect(fromMap.description, isNull);
    });

    test('PaymentEntity ISO datetime parsing with legacy fallback [FIX-TIMESTAMP-PAYMENT-1]', () {
      const paymentIso = PaymentEntity(
        id: 'pay-uuid-1',
        recordId: 'rec-uuid-1',
        amount: 1000.0,
        date: '2026-04-23T14:30:00',
        notes: 'Cash payment',
        interestPaid: 1000.0,
        principalPaid: 0.0,
      );

      expect(paymentIso.parsedDateTime.year, 2026);
      expect(paymentIso.parsedDateTime.hour, 14);
      expect(paymentIso.formattedDate, '23 April 2026');
      expect(paymentIso.formattedDateTime, '23 April 2026, 02:30 PM');

      // Legacy date-only fallback test
      const legacyPayment = PaymentEntity(
        id: 'pay-uuid-2',
        recordId: 'rec-uuid-1',
        amount: 1000.0,
        date: '2026-04-23',
        notes: 'Legacy record',
        interestPaid: 1000.0,
        principalPaid: 0.0,
      );

      expect(legacyPayment.parsedDateTime.year, 2026);
      expect(legacyPayment.parsedDateTime.month, 4);
      expect(legacyPayment.parsedDateTime.day, 23);
    });

    test('ItemRateEntity upsert mapping preserves market rate snapshot separation', () {
      const rate = ItemRateEntity(
        id: 'rate-uuid-1',
        itemCategory: 'Gold 22K',
        ratePerUnit: 7250.0,
        effectiveDate: '2026-04-23',
        updatedAt: '2026-04-23T10:00:00',
      );

      final map = rate.toMap();
      expect(map['itemCategory'], 'Gold 22K');
      expect(map['ratePerUnit'], 7250.0);

      final fromMap = ItemRateEntity.fromMap(map);
      expect(fromMap.ratePerUnit, 7250.0);
    });
  });
}
