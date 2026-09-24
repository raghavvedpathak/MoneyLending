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

  LedgerRecord? _record;
  Customer? _customer;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _record = widget.record;
    _loadRecord();
  }

  Future<void> _loadRecord() async {
    try {
      final rec = await _recordRepository.getRecordById(widget.recordId);
      Customer? cust;
      if (rec != null) {
        final customers = await _customerRepository.getAllCustomersOnce();
        cust = customers.where((c) => c.id == rec.customerId).firstOrNull;
      }

      if (mounted) {
        setState(() {
          _record = rec ?? _record;
          _customer = cust;
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pledged Items (${record.items.length})',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Divider(height: 20),
                  ...record.items.map((item) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text(
                                '${item.itemCategory} • ${item.purity} • ${item.weight}g (${item.fineWeight}g fine)',
                                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                          Text(
                            CurrencyFormatter.format(item.itemValue),
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.gold),
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
