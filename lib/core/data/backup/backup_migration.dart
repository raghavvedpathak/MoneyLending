import 'backup_serializer.dart';
import 'models/backup_customer.dart';
import 'models/backup_lender.dart';
import 'models/backup_payment.dart';
import 'models/backup_record.dart';
import 'models/backup_wrapper.dart';

/// Pure migration and ID assignment functions for JSON Backup & Restore (§7.1, Addendum G, Addendum K.2).
///
/// Mandated by Business Logic Spec §7.1:
/// - Migration functions are pure (no DB calls) — they transform data structures only.
/// - [migrate1_1To1_2] coerces date-only strings to datetime strings by appending "T00:00:00".
/// - [splitCustomersIntoLenders] separates TAKEN counterparties into lenders when `lenders == null` ([FIX-LENDER-BACKUP-1]).
/// - [assignMissingDisplayIds] assigns missing prefix-scoped identifiers sequentially oldest-first.

/// Active Migration from v1.1 to v1.2 (and stamps current version) [FIX-TIMESTAMP-BACKUP-1, FIX-MIGRATION-NAMING-1].
BackupWrapper migrate1_1To1_2(BackupWrapper wrapper) {
  return wrapper.copyWith(
    version: BackupSerializer.backupVersion,
    records: wrapper.records.map((record) {
      return record.copyWith(
        startDate: record.startDate.contains('T')
            ? record.startDate
            : '${record.startDate}T00:00:00',
        payments: record.payments.map((payment) {
          return payment.copyWith(
            date: payment.date.contains('T')
                ? payment.date
                : '${payment.date}T00:00:00',
          );
        }).toList(),
      );
    }).toList(),
  );
}

/// Pure splitCustomersIntoLenders migration step ([FIX-LENDER-BACKUP-1], Addendum K.2).
///
/// Runs when `wrapper.lenders == null` (covers Kotlin exports, legacy bare arrays,
/// 1.1–1.3 files, and early 1.4 files which carried TAKEN records on a customerId).
///
/// Converts TAKEN record customer references into [BackupLender] entries, sets
/// record.lenderId = record.customerId and record.customerId = null.
/// Removes any customer from `customers` who only had TAKEN records (0 GIVEN records).
BackupWrapper splitCustomersIntoLenders(BackupWrapper wrapper) {
  final takenCustomerIds = <String>{};
  final givenCustomerIds = <String>{};

  for (final r in wrapper.records) {
    final typeUpper = r.type.toUpperCase();
    if (typeUpper == 'TAKEN' && r.customerId != null && r.customerId!.isNotEmpty) {
      takenCustomerIds.add(r.customerId!);
    } else if (typeUpper == 'GIVEN' && r.customerId != null && r.customerId!.isNotEmpty) {
      givenCustomerIds.add(r.customerId!);
    }
  }

  final customerMap = {for (final c in wrapper.customers) c.id: c};
  final newLenders = <BackupLender>[];
  final createdLenderIds = <String>{};

  for (final r in wrapper.records) {
    if (r.type.toUpperCase() == 'TAKEN' && r.customerId != null && r.customerId!.isNotEmpty) {
      final custId = r.customerId!;
      if (!createdLenderIds.contains(custId)) {
        createdLenderIds.add(custId);
        final existingCust = customerMap[custId];
        final rawCreatedAt = existingCust?.createdAt ?? (r.startDate.isNotEmpty ? r.startDate : DateTime.now().toIso8601String());
        final createdAtDateOnly = rawCreatedAt.length >= 10
            ? rawCreatedAt.substring(0, 10)
            : rawCreatedAt;
        final updatedAtIso = rawCreatedAt.contains('T')
            ? rawCreatedAt
            : '${rawCreatedAt}T00:00:00';

        newLenders.add(
          BackupLender(
            id: custId,
            displayId: '', // To be assigned sequentially by assignMissingDisplayIds()
            lenderType: 'individual',
            name: existingCust?.name ?? (r.customerName ?? 'Lender'),
            phone: existingCust?.phone ?? '',
            institutionDetails: null,
            notes: null,
            createdAt: createdAtDateOnly,
            updatedAt: updatedAtIso,
          ),
        );
      }
    }
  }

  // Customers who only had TAKEN records (and zero GIVEN records) are removed from customers
  final updatedCustomers = wrapper.customers
      .where((c) => !takenCustomerIds.contains(c.id) || givenCustomerIds.contains(c.id))
      .toList();

  // Switch TAKEN records from customerId to lenderId
  final updatedRecords = wrapper.records.map((r) {
    if (r.type.toUpperCase() == 'TAKEN' && (r.customerId != null && r.customerId!.isNotEmpty)) {
      return r.copyWith(
        lenderId: r.customerId,
        clearCustomerId: true,
      );
    }
    return r;
  }).toList();

  return wrapper.copyWith(
    customers: updatedCustomers,
    lenders: newLenders,
    records: updatedRecords,
  );
}

/// Pure sequential display-ID assignment step (Addendum G, FIX-ID-BACKUP-1, FIX-LENDER-BACKUP-1).
///
/// Assigns:
/// - Customer displayId: CUST + FY + sequence (e.g. CUST26-27-01)
/// - Lender displayId: LEND + FY + sequence (e.g. LEND26-27-01)
/// - Record transactionId: TRAN + MMYY + sequence (e.g. TRAN092601)
/// - Payment paymentId: PAY + MMYY + sequence (e.g. PAY092601)
///
/// Rows are processed oldest-first based on their respective timestamps so sequences follow history.
BackupWrapper assignMissingDisplayIds(BackupWrapper wrapper) {
  // 1. Map existing Customer displayIds
  final customerPrefixCounters = <String, int>{};
  for (final r in wrapper.retiredIds) {
    if (r.kind == 'customer') {
      _recordMaxPrefixSeq(r.displayId, customerPrefixCounters, 11);
    }
  }
  for (final c in wrapper.customers) {
    if (c.displayId.isNotEmpty) {
      _recordMaxPrefixSeq(c.displayId, customerPrefixCounters, 11);
    }
  }

  // Assign missing customer displayIds
  final sortedCustomersWithIndices = wrapper.customers.asMap().entries.toList()
    ..sort((a, b) => a.value.createdAt.compareTo(b.value.createdAt));

  final updatedCustomers = List<BackupCustomer>.from(wrapper.customers);
  for (final entry in sortedCustomersWithIndices) {
    final c = entry.value;
    if (c.displayId.isEmpty) {
      final date = _parseDateOrFallback(c.createdAt);
      final prefix = _customerFyPrefix(date);
      final nextSeq = (customerPrefixCounters[prefix] ?? 0) + 1;
      customerPrefixCounters[prefix] = nextSeq;
      final assignedId = '$prefix${nextSeq.toString().padLeft(2, '0')}';
      updatedCustomers[entry.key] = c.copyWith(displayId: assignedId);
    }
  }

  // 1b. Map existing Lender displayIds
  final lenderPrefixCounters = <String, int>{};
  for (final r in wrapper.retiredIds) {
    if (r.kind == 'lender') {
      _recordMaxPrefixSeq(r.displayId, lenderPrefixCounters, 11);
    }
  }
  final currentLenders = wrapper.lenders ?? const <BackupLender>[];
  for (final l in currentLenders) {
    if (l.displayId.isNotEmpty) {
      _recordMaxPrefixSeq(l.displayId, lenderPrefixCounters, 11);
    }
  }

  // Assign missing lender displayIds
  final sortedLendersWithIndices = currentLenders.asMap().entries.toList()
    ..sort((a, b) => a.value.createdAt.compareTo(b.value.createdAt));

  final updatedLenders = List<BackupLender>.from(currentLenders);
  for (final entry in sortedLendersWithIndices) {
    final l = entry.value;
    if (l.displayId.isEmpty) {
      final date = _parseDateOrFallback(l.createdAt);
      final prefix = _lenderFyPrefix(date);
      final nextSeq = (lenderPrefixCounters[prefix] ?? 0) + 1;
      lenderPrefixCounters[prefix] = nextSeq;
      final assignedId = '$prefix${nextSeq.toString().padLeft(2, '0')}';
      updatedLenders[entry.key] = l.copyWith(displayId: assignedId);
    }
  }

  // 2. Map existing Transaction IDs
  final txnPrefixCounters = <String, int>{};
  for (final r in wrapper.retiredIds) {
    if (r.kind == 'transaction') {
      _recordMaxPrefixSeq(r.displayId, txnPrefixCounters, 8);
    }
  }
  for (final r in wrapper.records) {
    if (r.transactionId.isNotEmpty && r.transactionId.startsWith('TRAN')) {
      _recordMaxPrefixSeq(r.transactionId, txnPrefixCounters, 8);
    }
  }

  // 3. Map existing Payment IDs
  final payPrefixCounters = <String, int>{};
  for (final r in wrapper.retiredIds) {
    if (r.kind == 'payment') {
      _recordMaxPrefixSeq(r.displayId, payPrefixCounters, 7);
    }
  }
  for (final r in wrapper.records) {
    for (final p in r.payments) {
      if (p.paymentId.isNotEmpty && p.paymentId.startsWith('PAY')) {
        _recordMaxPrefixSeq(p.paymentId, payPrefixCounters, 7);
      }
    }
  }

  // Assign missing Transaction and Payment IDs
  final sortedRecordsWithIndices = wrapper.records.asMap().entries.toList()
    ..sort((a, b) => a.value.startDate.compareTo(b.value.startDate));

  final updatedRecords = List<BackupRecord>.from(wrapper.records);

  for (final entry in sortedRecordsWithIndices) {
    var record = entry.value;

    // Transaction ID: only assign if empty (preserves legacy CUST-/TXN- IDs verbatim per §7.1)
    if (record.transactionId.isEmpty) {
      final date = _parseDateOrFallback(record.startDate);
      final prefix = _txnPrefix(date);
      final nextSeq = (txnPrefixCounters[prefix] ?? 0) + 1;
      txnPrefixCounters[prefix] = nextSeq;
      final assignedTxnId = '$prefix${nextSeq.toString().padLeft(2, '0')}';
      record = record.copyWith(transactionId: assignedTxnId);
    }

    // Payments in this record
    if (record.payments.isNotEmpty) {
      final sortedPaymentsWithIndices = record.payments.asMap().entries.toList()
        ..sort((a, b) => a.value.date.compareTo(b.value.date));

      final updatedPayments = List<BackupPayment>.from(record.payments);
      for (final pEntry in sortedPaymentsWithIndices) {
        final p = pEntry.value;
        if (p.paymentId.isEmpty) {
          final pDate = _parseDateOrFallback(p.date);
          final pPrefix = _payPrefix(pDate);
          final nextPaySeq = (payPrefixCounters[pPrefix] ?? 0) + 1;
          payPrefixCounters[pPrefix] = nextPaySeq;
          final assignedPayId = '$pPrefix${nextPaySeq.toString().padLeft(2, '0')}';
          updatedPayments[pEntry.key] = p.copyWith(paymentId: assignedPayId);
        }
      }
      record = record.copyWith(payments: updatedPayments);
    }

    updatedRecords[entry.key] = record;
  }

  return wrapper.copyWith(
    customers: updatedCustomers,
    lenders: updatedLenders,
    records: updatedRecords,
  );
}

void _recordMaxPrefixSeq(String fullId, Map<String, int> counters, int prefixLength) {
  if (fullId.length <= prefixLength) return;
  final prefix = fullId.substring(0, prefixLength);
  final seqStr = fullId.substring(prefixLength);
  final seq = int.tryParse(seqStr);
  if (seq != null) {
    final current = counters[prefix] ?? 0;
    if (seq > current) {
      counters[prefix] = seq;
    }
  }
}

DateTime _parseDateOrFallback(String s) {
  try {
    return DateTime.parse(s);
  } catch (_) {
    return DateTime.now();
  }
}

String _customerFyPrefix(DateTime dt) {
  final year = dt.year;
  final month = dt.month;
  final startYear = (month >= 4 ? year : year - 1) % 100;
  final endYear = (month >= 4 ? year + 1 : year) % 100;
  return 'CUST${startYear.toString().padLeft(2, '0')}-${endYear.toString().padLeft(2, '0')}-';
}

String _lenderFyPrefix(DateTime dt) {
  final year = dt.year;
  final month = dt.month;
  final startYear = (month >= 4 ? year : year - 1) % 100;
  final endYear = (month >= 4 ? year + 1 : year) % 100;
  return 'LEND${startYear.toString().padLeft(2, '0')}-${endYear.toString().padLeft(2, '0')}-';
}

String _txnPrefix(DateTime dt) {
  final month = dt.month.toString().padLeft(2, '0');
  final year = (dt.year % 100).toString().padLeft(2, '0');
  return 'TRAN$month$year';
}

String _payPrefix(DateTime dt) {
  final month = dt.month.toString().padLeft(2, '0');
  final year = (dt.year % 100).toString().padLeft(2, '0');
  return 'PAY$month$year';
}
