import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/calculations/calculations.dart';
import '../../../core/di/injection.dart';
import '../../../core/navigation/app_routes.dart';
import '../../../core/ui/formatters/currency_formatter.dart';
import '../../../core/ui/theme/app_theme.dart';
import '../../../core/utils/app_date_formatter.dart';
import '../../../domain/domain.dart';
import '../../../presentation/widgets/add_edit_record_bottom_sheet.dart';

/// Full Record Detail Screen (:feature:customers) (§10.2).
///
/// Mandated by Business Architecture Spec §10.2:
/// - Reached by tapping a ledger-history row in CustomerDetailScreen via RecordDetailRoute (§2.4).
/// - Header shows customer ID + transactionId (e.g. CUST26-27-01 • TRAN092601).
/// - AppBar Edit action opens AddEditRecordBottomSheet pre-populated, hidden when settled (Addendum v1.2).
/// - AppBar overflow menu has "Delete" action (v1.13 / Addendum G, FIX-ID-REUSE-1).
/// - Every payment-history row shows its payment ID (PAY…) and formatDate() timestamp.
class RecordDetailScreen extends StatefulWidget {
  final String recordId;
  final LedgerRecord? record;

  const RecordDetailScreen({
    super.key,
    required this.recordId,
    this.record,
  });

  @override
  State<RecordDetailScreen> createState() => _RecordDetailScreenState();
}

class _RecordDetailScreenState extends State<RecordDetailScreen> {
  final RecordRepository _recordRepository = sl<RecordRepository>();
  final CustomerRepository _customerRepository = sl<CustomerRepository>();
  final ItemRateRepository _itemRateRepository = sl<ItemRateRepository>();

  LedgerRecord? _record;
  Customer? _customer;
  LedgerRecord? _linkedRecord;
  List<LedgerRecord> _linkedTakenRecords = [];
  List<ItemRate> _currentRates = [];
  StreamSubscription<List<ItemRate>>? _ratesSub;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _record = widget.record;
    _ratesSub = _itemRateRepository.watchCurrentRates().listen((rates) {
      if (mounted) {
        setState(() => _currentRates = rates);
      }
    });
    _loadRecord();
  }

  @override
  void dispose() {
    _ratesSub?.cancel();
    super.dispose();
  }

  Future<void> _loadRecord() async {
    try {
      final rec = await _recordRepository.getRecordById(widget.recordId);
      Customer? cust;
      LedgerRecord? linkedGiven;
      List<LedgerRecord> linkedTakens = [];
      if (rec != null) {
        final customers = await _customerRepository.getAllCustomersOnce();
        cust = customers.where((c) => c.id == rec.customerId).firstOrNull;
        if (rec.isTaken && rec.linkedRecordId != null && rec.linkedRecordId!.isNotEmpty) {
          linkedGiven = await _recordRepository.getRecordById(rec.linkedRecordId!);
        } else if (rec.isGiven) {
          final allRecords = await _recordRepository.getAllRecordsOnce();
          linkedTakens = allRecords.where((r) => r.isTaken && r.linkedRecordId == rec.id).toList();
        }
      }

      if (mounted) {
        setState(() {
          _record = rec ?? _record;
          _customer = cust;
          _linkedRecord = linkedGiven;
          _linkedTakenRecords = linkedTakens;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openEdit() async {
    if (_record == null) return;

    final updated = await AddEditRecordBottomSheet.show(
      context,
      initialType: _record!.type,
      existingRecord: _record,
    );

    if (updated == true && mounted) {
      await _loadRecord();
    }
  }

  Future<void> _confirmDelete() async {
    if (_record == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Record'),
        content: Text(
          'Are you sure you want to delete transaction ${_record!.transactionId}?\n\n'
          'This will permanently delete the record and its payments. '
          'The transaction ID and payment IDs will be permanently retired (FIX-ID-REUSE-1).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.rose,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _recordRepository.forceDeleteRecord(_record!.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            AppTheme.successSnackBar('Record ${_record!.transactionId} deleted'),
          );
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            AppTheme.errorSnackBar('Failed to delete record: $e'),
          );
        }
      }
    }
  }

  Future<void> _settleRecord() async {
    if (_record == null) return;

    final today = DateTime.now().dateOnly;
    final financials = CalculationEngine.calculateRecordFinancials(_record!, today);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Settlement'),
        content: Text(
          'Settle transaction ${_record!.transactionId}?\n\n'
          'Final Accrued Interest: ${CurrencyFormatter.format(financials.totalInterest)}\n'
          'Outstanding Balance Due: ${CurrencyFormatter.format(financials.totalDue)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Settle Record'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _recordRepository.settleRecord(_record!.id, financials.totalInterest);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            AppTheme.successSnackBar('Record ${_record!.transactionId} settled successfully'),
          );
          await _loadRecord();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            AppTheme.errorSnackBar('Failed to settle record: $e'),
          );
        }
      }
    }
  }

  Future<void> _openAddPayment() async {
    if (_record == null) return;

    final added = await AppNavigator.navigate<bool>(
      context,
      AddPaymentRoute(recordId: _record!.id, record: _record),
    );

    if (added == true && mounted) {
      await _loadRecord();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Record Details')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_record == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Record Not Found')),
        body: const Center(child: Text('This transaction could not be loaded.')),
      );
    }

    final record = _record!;
    final customer = _customer;
    final isSettled = record.status == RecordStatus.SETTLED;
    final financials = CalculationEngine.calculateRecordFinancials(record, DateTime.now().dateOnly);

    return Scaffold(
      appBar: AppBar(
        title: Text(record.transactionId),
        actions: [
          // Edit action: hidden when settled (Addendum v1.2 items A–C)
          if (!isSettled)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit Record',
              onPressed: _openEdit,
            ),

          // Overflow menu with Delete action (v1.13 / Addendum G, FIX-ID-REUSE-1)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'delete') {
                _confirmDelete();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, color: AppTheme.rose, size: 20),
                    SizedBox(width: 8),
                    Text('Delete Record', style: TextStyle(color: AppTheme.rose)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header: Customer ID + Transaction ID (§10.2)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.gold.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${customer?.displayId ?? 'Customer'} • ${record.transactionId}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.gold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: AppTheme.badgeDecoration(
                        record.isGiven ? AppTheme.accentCyan : AppTheme.emerald,
                      ),
                      child: Text(
                        record.type.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: record.isGiven ? AppTheme.accentCyan : AppTheme.emerald,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  customer?.name ?? 'Customer #${record.customerId}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                if (customer?.phone != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    customer!.phone!,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Status & Dates
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderDark),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Status', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: AppTheme.badgeDecoration(
                        isSettled ? AppTheme.accentCyan : AppTheme.emerald,
                      ),
                      child: Text(
                        record.status.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isSettled ? AppTheme.accentCyan : AppTheme.emerald,
                        ),
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Start Date', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    const SizedBox(height: 4),
                    Text(
                      AppDateFormatter.formatDate(record.startDate),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    if (record.settledDate != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Settled ${AppDateFormatter.formatDate(record.settledDate!)}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.accentCyan),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Linked Loan Given (for TAKEN record)
          if (record.isTaken && _linkedRecord != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.cardDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.gold.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.link, size: 18, color: AppTheme.gold),
                          SizedBox(width: 8),
                          Text('Backed by Given Loan', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: AppTheme.badgeDecoration(AppTheme.gold),
                        child: Text(_linkedRecord!.status.name, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.gold)),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_linkedRecord!.transactionId, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.gold)),
                          const SizedBox(height: 2),
                          Text('Customer: ${_linkedRecord!.customerName ?? "Customer"}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(CurrencyFormatter.format(_linkedRecord!.principalAmount), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('${_linkedRecord!.interestRate}% / mo', style: const TextStyle(fontSize: 12, color: AppTheme.accentCyan)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: Text('View Linked Customer Loan (${_linkedRecord!.transactionId})'),
                      onPressed: () {
                        AppNavigator.navigate(context, RecordDetailRoute(_linkedRecord!.id, record: _linkedRecord));
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Linked Borrowings (for GIVEN record with child TAKEN records)
          if (record.isGiven && _linkedTakenRecords.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.cardDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.emerald.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.link, size: 18, color: AppTheme.emerald),
                          SizedBox(width: 8),
                          Text('Linked Borrowings (${_linkedTakenRecords.length})', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: AppTheme.badgeDecoration(AppTheme.emerald),
                        child: const Text('RE-PLEDGED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.emerald)),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  ..._linkedTakenRecords.map((tk) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tk.transactionId, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.emerald)),
                              Text('Lender: ${tk.customerName ?? "Lender"} • ${tk.interestRate}%/mo', style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                            ],
                          ),
                          Row(
                            children: [
                              Text(CurrencyFormatter.format(tk.principalAmount), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.open_in_new, size: 16, color: AppTheme.emerald),
                                tooltip: 'View Taken Loan',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  AppNavigator.navigate(context, RecordDetailRoute(tk.id, record: tk));
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Financial Summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderDark),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Financial Summary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Divider(height: 20),
                _FinRow(label: 'Principal Amount', value: CurrencyFormatter.format(record.principalAmount)),
                _FinRow(label: 'Interest Rate', value: '${record.interestRate}% / month'),
                _FinRow(
                  label: 'Total Interest Accrued',
                  value: CurrencyFormatter.format(financials.totalInterest),
                  highlightColor: AppTheme.gold,
                ),
                _FinRow(
                  label: 'Total Paid',
                  value: CurrencyFormatter.format(financials.totalPaid),
                  highlightColor: AppTheme.emerald,
                ),
                const Divider(height: 16),
                _FinRow(
                  label: isSettled ? 'Final Settlement Balance' : 'Outstanding Balance Due',
                  value: CurrencyFormatter.format(financials.totalDue),
                  highlightColor: isSettled ? AppTheme.textSecondary : AppTheme.rose,
                  isBold: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Collateral Items (if any)
          if (record.items.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.cardDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderDark),
              ),
              child: Builder(
                builder: (context) {
                  final lendingTotal = record.items.fold(0.0, (s, i) => s + (i.itemValue > 0 ? i.itemValue : CalculationEngine.calculateItemValue(i)));
                  final liveTotal = CalculationEngine.calculateTotalLiveCollateralValue(record.items, _currentRates);
                  final hasMarketDrift = liveTotal > 0 && lendingTotal > 0 && (liveTotal != lendingTotal);
                  final totalDiff = liveTotal - lendingTotal;
                  final totalDiffPct = lendingTotal > 0 ? (totalDiff / lendingTotal) * 100.0 : 0.0;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.shield_outlined, size: 18, color: AppTheme.gold),
                              const SizedBox(width: 8),
                              Text(
                                'Pledged Collateral (${record.items.length})',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (hasMarketDrift) ...[
                                Text(
                                  'Live: ${CurrencyFormatter.format(liveTotal)}',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.emerald),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Lent: ${CurrencyFormatter.format(lendingTotal)}',
                                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                    ),
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: (totalDiff >= 0 ? AppTheme.emerald : AppTheme.rose).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(
                                        '${totalDiff >= 0 ? "+" : ""}${CurrencyFormatter.format(totalDiff)} (${totalDiff >= 0 ? "+" : ""}${totalDiffPct.toStringAsFixed(1)}%)',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: totalDiff >= 0 ? AppTheme.emerald : AppTheme.rose,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                Text(
                                  CurrencyFormatter.format(lendingTotal),
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.gold),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      ...record.items.map((item) {
                        final itemLiveRate = CalculationEngine.getUsableRate(_currentRates, item.itemCategory);
                        final liveVal = CalculationEngine.calculateLiveItemValue(item, _currentRates);
                        final lendingVal = item.itemValue > 0 ? item.itemValue : CalculationEngine.calculateItemValue(item);
                        final itemDiff = liveVal - lendingVal;
                        final hasItemDrift = itemLiveRate != null && itemLiveRate > 0 && liveVal != lendingVal && lendingVal > 0;
                        final itemDiffPct = lendingVal > 0 ? (itemDiff / lendingVal) * 100.0 : 0.0;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.subCardDark,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.borderDark),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.name,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: AppTheme.badgeDecoration(AppTheme.gold),
                                    child: Text(
                                      item.itemCategory,
                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.gold),
                                    ),
                                  ),
                                ],
                              ),
                              if (item.description != null && item.description!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  item.description!,
                                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontStyle: FontStyle.italic),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                children: [
                                  Text(
                                    '${item.weight}g @ ${item.purity}% (${item.fineWeight.toStringAsFixed(2)}g fine)',
                                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                  ),
                                  if (item.rate > 0)
                                    Text(
                                      '• Lent @ ₹${item.rate.toStringAsFixed(0)}/g',
                                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                    ),
                                  if (itemLiveRate != null && itemLiveRate > 0)
                                    Text(
                                      '• Live: ₹${itemLiveRate.toStringAsFixed(0)}/g',
                                      style: const TextStyle(fontSize: 12, color: AppTheme.emerald, fontWeight: FontWeight.w600),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  if (lendingVal > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: AppTheme.badgeDecoration(AppTheme.gold),
                                      child: Text(
                                        'Valuation at Lending: ${CurrencyFormatter.format(lendingVal)}',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.gold),
                                      ),
                                    ),
                                  if (hasItemDrift) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: AppTheme.badgeDecoration(AppTheme.emerald),
                                      child: Text(
                                        'Live Market Val: ${CurrencyFormatter.format(liveVal)}',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.emerald),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: (itemDiff >= 0 ? AppTheme.emerald : AppTheme.rose).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: (itemDiff >= 0 ? AppTheme.emerald : AppTheme.rose).withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: Text(
                                        '${itemDiff >= 0 ? "▲ +" : "▼ "}${CurrencyFormatter.format(itemDiff.abs())} (${itemDiff >= 0 ? "+" : ""}${itemDiffPct.toStringAsFixed(1)}%)',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: itemDiff >= 0 ? AppTheme.emerald : AppTheme.rose,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (item.lendableAmount > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: AppTheme.badgeDecoration(AppTheme.accentCyan),
                                      child: Text(
                                        'Max Lendable (${item.lendPercentage.toStringAsFixed(0)}%): ${CurrencyFormatter.format(item.lendableAmount)}',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.accentCyan),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Payment History (§10.2)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderDark),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Payment History (${record.payments.length})',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    if (!isSettled)
                      TextButton.icon(
                        onPressed: _openAddPayment,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Payment'),
                      ),
                  ],
                ),
                const Divider(height: 16),
                if (record.payments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'No payments recorded yet.',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ),
                  )
                else
                  ...record.payments.map((p) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.subCardDark,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: AppTheme.badgeDecoration(AppTheme.gold),
                                    child: Text(
                                      p.paymentId,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.gold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    AppDateFormatter.formatDate(p.date),
                                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Interest: ${CurrencyFormatter.format(p.interestPaid)}  •  Principal: ${CurrencyFormatter.format(p.principalPaid)}',
                                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                              ),
                            ],
                          ),
                          Text(
                            CurrencyFormatter.format(p.amount),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.emerald,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Actions
          if (!isSettled) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openAddPayment,
                    icon: const Icon(Icons.payment),
                    label: const Text('Add Payment'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentCyan,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: _settleRecord,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Settle Loan'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FinRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? highlightColor;
  final bool isBold;

  const _FinRow({
    required this.label,
    required this.value,
    this.highlightColor,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: isBold ? Colors.white : AppTheme.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: highlightColor ?? Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
