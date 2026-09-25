import 'package:flutter/material.dart';
import '../../../core/calculations/calculations.dart';
import '../../../core/di/injection.dart';
import '../../../core/navigation/app_routes.dart';
import '../../../core/ui/formatters/currency_formatter.dart';
import '../../../core/ui/formatters/id_formatter.dart';
import '../../../core/ui/theme/app_theme.dart';
import '../../../core/utils/app_date_formatter.dart';
import '../../../domain/domain.dart';
import '../../../presentation/widgets/collateral_item_tile.dart';
import 'edit_transaction_screen.dart';

/// Screen displaying complete details for a single loan transaction,
/// with options to edit/update the transaction or record payments.
class LoanDetailsScreen extends StatefulWidget {
  final LedgerRecord record;

  const LoanDetailsScreen({super.key, required this.record});

  @override
  State<LoanDetailsScreen> createState() => _LoanDetailsScreenState();
}

class _LoanDetailsScreenState extends State<LoanDetailsScreen> {
  final RecordRepository _recordRepository = sl<RecordRepository>();
  final CustomerRepository _customerRepository = sl<CustomerRepository>();

  late LedgerRecord _record;
  Customer? _customer;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _record = widget.record;
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() => _isLoading = true);
    try {
      final updated = await _recordRepository.getRecordById(_record.id);
      Customer? cust;
      if (updated != null) {
        final customers = await _customerRepository.getAllCustomers().first;
        cust = customers.where((c) => c.id == updated.customerId).firstOrNull;
      }

      if (mounted) {
        setState(() {
          if (updated != null) _record = updated;
          _customer = cust;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openEdit() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditTransactionScreen(record: _record),
      ),
    );
    if (result == true && mounted) {
      await _loadDetails();
    }
  }

  Future<void> _openAddPayment() async {
    final result = await AppNavigator.navigate<bool>(
      context,
      AddPaymentRoute(recordId: _record.id, record: _record),
    );
    if (result == true && mounted) {
      await _loadDetails();
    }
  }

  Future<void> _settleLoan() async {
    final financials = CalculationEngine.calculateRecordFinancials(_record, DateTime.now());
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Loan Settlement'),
        content: Text(
          'Mark this loan as SETTLED?\n\n'
          'Final Accrued Interest: ${CurrencyFormatter.format(financials.totalInterest)}\n'
          'Outstanding Due: ${CurrencyFormatter.format(financials.totalDue)}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Settle & Close'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _recordRepository.settleRecord(_record.id, financials.totalInterest);
      await _loadDetails();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppTheme.successSnackBar('Loan ${AppIdFormatter.formatTransactionId(_record.transactionId)} marked as SETTLED!'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _record;
    final isGiven = r.type == RecordType.GIVEN;
    final accentColor = isGiven ? AppTheme.accentCyan : AppTheme.emerald;
    final financials = CalculationEngine.calculateRecordFinancials(r, DateTime.now());

    double totalCollateralValue = 0.0;
    for (final item in r.items) {
      totalCollateralValue += (item.itemValue > 0 ? item.itemValue : calculateItemValue(item));
    }

    final totalPaid = r.payments.fold<double>(0.0, (sum, p) => sum + p.amount);

    return Scaffold(
      appBar: AppBar(
        title: Text(r.transactionId.isEmpty ? 'Loan Details' : AppIdFormatter.formatTransactionId(r.transactionId)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            tooltip: 'Edit Transaction',
            onPressed: _openEdit,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDetails,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                children: [
                  // 1. Transaction Type & Status Banner
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppTheme.cardDark,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: accentColor.withValues(alpha: 0.35), width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  isGiven ? Icons.arrow_outward_rounded : Icons.arrow_downward_rounded,
                                  color: accentColor,
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isGiven ? 'LOAN GIVEN (Lent)' : 'LOAN TAKEN (Borrowed)',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: accentColor,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: AppTheme.badgeDecoration(
                                r.isActive ? AppTheme.emerald : AppTheme.accentCyan,
                              ),
                              child: Text(
                                r.status.name.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: r.isActive ? AppTheme.emerald : AppTheme.accentCyan,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Principal Amount', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                                Text(
                                  CurrencyFormatter.format(r.principalAmount),
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text('Total Outstanding Due', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                                Text(
                                  CurrencyFormatter.format(financials.totalDue),
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.rose,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. Customer Information Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: AppTheme.metricCardDecoration,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Customer Information', style: AppTheme.sectionHeaderStyle),
                            if (_customer != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: AppTheme.badgeDecoration(AppTheme.gold),
                                child: Text(
                                  AppIdFormatter.formatCustomerId(_customer!.displayId),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.gold),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _customer?.name ?? r.customerName ?? 'Customer',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        if (_customer?.phone != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.phone_outlined, size: 14, color: AppTheme.textMuted),
                              const SizedBox(width: 6),
                              Text(_customer!.phone!, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                            ],
                          ),
                        ],
                        if (_customer?.address != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.textMuted),
                              const SizedBox(width: 6),
                              Text(_customer!.address!, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 3. Complete Financial Calculation Breakdown
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: AppTheme.metricCardDecoration,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Financial Intelligence & Ledger', style: AppTheme.sectionHeaderStyle),
                        const SizedBox(height: 14),
                        _DetailRow(label: 'Monthly Interest Rate', value: '${r.interestRate.toStringAsFixed(1)}% / month'),
                        _DetailRow(label: 'Started Date', value: AppDateFormatter.formatDate(r.startDate)),
                        _DetailRow(label: 'Duration / Tenure', value: AppDateFormatter.formatMonths(financials.months)),
                        if (r.endDate != null)
                          _DetailRow(label: 'Due / End Date', value: AppDateFormatter.formatDate(r.endDate!)),
                        if (r.settledDate != null)
                          _DetailRow(label: 'Settled Date', value: AppDateFormatter.formatDate(r.settledDate!)),
                        const Divider(height: 20, color: AppTheme.borderDark),
                        _DetailRow(label: 'Total Accrued Interest (${AppDateFormatter.formatMonths(financials.months)})', value: CurrencyFormatter.format(financials.totalInterest)),
                        _DetailRow(label: 'Total Amount Repaid', value: CurrencyFormatter.format(totalPaid)),
                        _DetailRow(label: 'Remaining Principal Due', value: CurrencyFormatter.format(financials.remainingPrincipal)),
                        _DetailRow(label: 'Remaining Interest Due', value: CurrencyFormatter.format(financials.outstandingInterest)),
                        const Divider(height: 20, color: AppTheme.borderDark),
                        _DetailRow(
                          label: 'Grand Total Outstanding Due',
                          value: CurrencyFormatter.format(financials.totalDue),
                          isHighlight: true,
                          valueColor: AppTheme.rose,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 4. Collateral / Mortgage Items (Girvi)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: AppTheme.metricCardDecoration,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Collateral Items (${r.items.length})',
                              style: AppTheme.sectionHeaderStyle,
                            ),
                            Text(
                              CurrencyFormatter.format(totalCollateralValue),
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.gold, fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (r.items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: Text(
                                'No collateral items pledged (Unsecured loan).',
                                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                              ),
                            ),
                          )
                        else
                          ...r.items.map((item) => CollateralItemTile(item: item)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 5. Payment History
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: AppTheme.metricCardDecoration,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Payment History (${r.payments.length})',
                              style: AppTheme.sectionHeaderStyle,
                            ),
                            Text(
                              'Paid: ${CurrencyFormatter.format(totalPaid)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.emerald, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (r.payments.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: Text(
                                'No payments recorded yet.',
                                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                              ),
                            ),
                          )
                        else
                          ...r.payments.map((p) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: AppTheme.subCardDecoration,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.paymentId.isNotEmpty
                                            ? '${AppIdFormatter.formatPaymentId(p.paymentId)} • ${AppDateFormatter.formatDate(p.date)}'
                                            : AppDateFormatter.formatDate(p.date),
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Interest: ${CurrencyFormatter.format(p.interestPaid)}  |  Principal: ${CurrencyFormatter.format(p.principalPaid)}',
                                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    CurrencyFormatter.format(p.amount),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.emerald),
                                  ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: const BoxDecoration(
          color: AppTheme.cardDark,
          border: Border(top: BorderSide(color: AppTheme.borderDark, width: 1)),
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openEdit,
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Edit Details'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _openAddPayment,
                  icon: const Icon(Icons.payment_rounded, size: 18),
                  label: const Text('Record Payment'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.emerald,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (r.isActive) ...[
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  icon: const Icon(Icons.check_circle_outline, size: 20),
                  tooltip: 'Mark as Settled',
                  onPressed: _settleLoan,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isHighlight;
  final Color? valueColor;

  const _DetailRow({
    required this.label,
    required this.value,
    this.isHighlight = false,
    this.valueColor,
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
              fontWeight: isHighlight ? FontWeight.w600 : FontWeight.normal,
              color: isHighlight ? AppTheme.textPrimary : AppTheme.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isHighlight ? 15 : 13,
              fontWeight: FontWeight.bold,
              color: valueColor ?? (isHighlight ? AppTheme.gold : AppTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
