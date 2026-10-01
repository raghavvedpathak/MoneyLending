import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/calculations/calculations.dart';
import '../../../core/di/injection.dart';
import '../../../core/navigation/app_routes.dart';
import '../../../core/ui/formatters/id_formatter.dart';
import '../../../core/ui/theme/app_ui.dart';
import '../../../core/utils/app_date_formatter.dart';
import '../../../domain/domain.dart';
import '../../../presentation/widgets/add_edit_record_bottom_sheet.dart';
import '../viewmodels/lender_detail_viewmodel.dart';
import '../widgets/add_edit_lender_dialog.dart';

/// Full Lender Detail Screen (:feature:lenders) (§10.2).
///
/// Mandated by Business Architecture Spec §10.2:
/// - Header displays lender name + lender ID (e.g. LEND25-26-01) and lender type badge.
/// - AppBar overflow menu has "Delete lender" (Addendum G, FIX-ID-REUSE-1 guard).
/// - Per-lender ledger history is TAKEN-only:
///   * each record row shows its transactionId (TRAN…)
///   * each payment row shows its payment ID (PAY…)
///   * profit line for records with non-null linkedRecordId rendered directly from [ProfitState]
///     (InterimProfit | NetProfit | NoProfit) — the widget renders the label from ProfitState
///     and never inspects record.status directly.
///   * [FIX-TIMESTAMP-CUSTOMERHISTORY-1] (revised v1.15): formatDate() for all record rows and payment rows.
/// - Tapping a record row navigates to RecordDetailScreen via RecordDetailRoute.
class LenderDetailScreen extends StatefulWidget {
  final String lenderId;

  const LenderDetailScreen({
    super.key,
    required this.lenderId,
  });

  @override
  State<LenderDetailScreen> createState() => _LenderDetailScreenState();
}

class _LenderDetailScreenState extends State<LenderDetailScreen> {
  late final LenderDetailNotifier _notifier;
  List<ItemRate> _currentRates = [];
  StreamSubscription<List<ItemRate>>? _ratesSub;

  @override
  void initState() {
    super.initState();
    _notifier = LenderDetailNotifier(lenderId: widget.lenderId);
    _ratesSub = sl<ItemRateRepository>().watchCurrentRates().listen((rates) {
      if (mounted) setState(() => _currentRates = rates);
    });
  }

  @override
  void dispose() {
    _ratesSub?.cancel();
    _notifier.dispose();
    super.dispose();
  }

  Future<void> _editLender(Lender lender) async {
    final updated = await AddEditLenderDialog.show(
      context,
      existingLender: lender,
    );
    if (updated == true) {
      await _notifier.refresh();
    }
  }

  Future<void> _confirmDeleteLender(Lender lender) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.borderDark),
        ),
        title: const Text('Delete Lender'),
        content: Text(
          'Are you sure you want to delete ${lender.name} (${AppIdFormatter.formatLenderId(lender.displayId)})?\n\n'
          'The lender ID will be permanently archived and cannot be reused.\n\n'
          'Lenders with active or settled records cannot be deleted.',
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
            child: const Text('Delete Lender'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _notifier.deleteLender();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            AppTheme.successSnackBar('Lender ${AppIdFormatter.formatLenderId(lender.displayId)} deleted'),
          );
          Navigator.of(context).pop(true);
        }
      } on LenderHasRecordsException catch (e) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppTheme.cardDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppTheme.borderDark),
              ),
              title: const Text('Cannot Delete Lender'),
              content: Text(
                'Cannot delete lender ${AppIdFormatter.formatLenderId(lender.displayId)} because ${e.recordCount} record(s) '
                'are still associated with this lender.\n\n'
                'Please settle or delete all transactions before deleting the lender.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            AppTheme.errorSnackBar('Failed to delete lender: $e'),
          );
        }
      }
    }
  }

  Future<void> _openAddTaken(Lender lender) async {
    final created = await AddEditRecordBottomSheet.show(
      context,
      initialType: RecordType.TAKEN,
    );
    if (created == true && mounted) {
      await _notifier.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LenderDetailState>(
      stream: _notifier.stateStream,
      initialData: _notifier.state,
      builder: (context, snapshot) {
        final state = snapshot.data ?? _notifier.state;

        if (state.isLoading && state.lender == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Lender Details')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final lender = state.lender;
        if (lender == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Lender Not Found')),
            body: const Center(child: Text('This lender could not be found.')),
          );
        }

        final isInstitution = lender.isInstitution;

        return Scaffold(
          appBar: AppBar(
            title: Text(lender.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Edit Lender',
                onPressed: () => _editLender(lender),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  if (value == 'delete') {
                    _confirmDeleteLender(lender);
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: AppTheme.rose, size: 20),
                        SizedBox(width: 8),
                        Text('Delete lender', style: TextStyle(color: AppTheme.rose)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'lender_detail_fab',
            onPressed: () => _openAddTaken(lender),
            icon: const Icon(Icons.add),
            label: const Text('New Borrowing'),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Header: Name + Lender ID (§10.2)
              AppCard(
                borderColor: AppTheme.gold.withValues(alpha: 0.35),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                lender.name,
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                AppIdFormatter.formatLenderId(lender.displayId),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.gold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        AppStatusBadge(
                          label: lender.lenderType.displayName,
                          color: isInstitution ? AppTheme.accentCyan : AppTheme.emerald,
                          icon: isInstitution ? Icons.business_outlined : Icons.person_outline,
                        ),
                      ],
                    ),
                    if (lender.phone != null && lender.phone!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.phone_outlined, size: 14, color: AppTheme.textMuted),
                          const SizedBox(width: 6),
                          Text(lender.phone!, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                        ],
                      ),
                    ],
                    if (lender.institutionDetails != null && lender.institutionDetails!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.account_balance_outlined, size: 14, color: AppTheme.textMuted),
                          const SizedBox(width: 6),
                          Text(lender.institutionDetails!, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                        ],
                      ),
                    ],
                    if (lender.notes != null && lender.notes!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.note_alt_outlined, size: 14, color: AppTheme.textMuted),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              lender.notes!,
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Summary Cards
              Row(
                children: [
                  Expanded(
                    child: AppStatCard(
                      title: 'Total Borrowed',
                      value: CurrencyFormatter.format(state.totalPrincipal),
                      accentColor: AppTheme.emerald,
                      icon: Icons.south_west,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppStatCard(
                      title: 'Interest Accrued',
                      value: CurrencyFormatter.format(state.totalInterest),
                      accentColor: AppTheme.gold,
                      icon: Icons.trending_up,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppStatCard(
                      title: 'Total Due',
                      value: CurrencyFormatter.format(state.totalDue),
                      accentColor: AppTheme.rose,
                      icon: Icons.payments_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Per-Lender Ledger History Header (§10.2: TAKEN-only)
              AppSectionHeader(
                title: 'Ledger History (${state.records.length})',
                trailing: const AppStatusBadge(
                  label: 'TAKEN ONLY',
                  color: AppTheme.emerald,
                ),
              ),
              const SizedBox(height: 12),

              if (state.records.isEmpty)
                const AppEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No TAKEN ledger records found for this lender.',
                  description: 'Tap "+ New Borrowing" below to record a loan taken from this lender.',
                )
              else
                ...state.records.map((item) {
                  return _LenderRecordLedgerCard(
                    item: item,
                    currentRates: _currentRates,
                    onTap: () async {
                      await AppNavigator.navigate(
                        context,
                        RecordDetailRoute(item.record.id, record: item.record),
                      );
                      if (mounted) {
                        await _notifier.refresh();
                      }
                    },
                  );
                }),
              const SizedBox(height: 64),
            ],
          ),
        );
      },
    );
  }
}

class _LenderRecordLedgerCard extends StatelessWidget {
  final LenderLedgerRecordItem item;
  final VoidCallback onTap;
  final List<ItemRate> currentRates;

  const _LenderRecordLedgerCard({
    required this.item,
    required this.onTap,
    this.currentRates = const [],
  });

  @override
  Widget build(BuildContext context) {
    final record = item.record;
    final financials = item.financials;
    final isActive = record.isActive;

    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: transactionId + Type & Status Badges
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  // transactionId header (§10.2: TRAN...)
                  AppStatusBadge(
                    label: AppIdFormatter.formatTransactionId(record.transactionId),
                    color: AppTheme.gold,
                  ),
                  const SizedBox(width: 8),
                  // Type Badge (always TAKEN for Lender)
                  const AppStatusBadge(
                    label: 'TAKEN',
                    color: AppTheme.emerald,
                  ),
                  if (record.linkedRecordId != null && record.linkedRecordId!.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    AppStatusBadge(
                      label: item.linkedRecord != null
                          ? 'LINKED: ${AppIdFormatter.formatTransactionId(item.linkedRecord!.transactionId)}'
                          : 'LINKED',
                      color: AppTheme.gold,
                      icon: Icons.link,
                    ),
                  ],
                ],
              ),
              AppStatusBadge(
                label: record.status.name.toUpperCase(),
                color: isActive ? AppTheme.emerald : AppTheme.accentCyan,
              ),
            ],
          ),
              const SizedBox(height: 8),

              // Row 2: Date with formatDate() [FIX-TIMESTAMP-CUSTOMERHISTORY-1] and duration
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Started ${AppDateFormatter.formatDate(record.startDate)} • ${AppDateFormatter.formatMonths(financials.months)}',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                  Text(
                    '${record.interestRate}% / month',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Row 3: Financial Summary for this record
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Principal', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                      Text(
                        CurrencyFormatter.format(record.principalAmount),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text('Accrued (${AppDateFormatter.formatMonths(financials.months)})', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                      Text(
                        CurrencyFormatter.format(financials.totalInterest),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.gold),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Total Due', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                      Text(
                        CurrencyFormatter.format(financials.totalDue),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.rose),
                      ),
                    ],
                  ),
                ],
              ),

              // Linked Given Loan Details
              if (record.linkedRecordId != null && record.linkedRecordId!.isNotEmpty) ...[
                const SizedBox(height: 10),
                if (item.linkedRecord != null) ...[
                  InkWell(
                    onTap: () {
                      AppNavigator.navigate(
                        context,
                        RecordDetailRoute(item.linkedRecord!.id, record: item.linkedRecord),
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.cardDark,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.link, size: 15, color: AppTheme.gold),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Backed by: ${AppIdFormatter.formatTransactionId(item.linkedRecord!.transactionId)}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.gold,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: AppTheme.badgeDecoration(
                                  item.linkedRecord!.isActive ? AppTheme.emerald : AppTheme.accentCyan,
                                ),
                                child: Text(
                                  item.linkedRecord!.status.name,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: item.linkedRecord!.isActive ? AppTheme.emerald : AppTheme.accentCyan,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'Borrower: ${item.linkedCustomerName ?? "Borrower"} (${AppIdFormatter.formatCustomerId(item.linkedCustomerDisplayId ?? item.linkedRecord?.customerId ?? "")})',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${CurrencyFormatter.format(item.linkedRecord!.principalAmount)} @ ${item.linkedRecord!.interestRate}%/mo',
                                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // Profit Line (§10.2):
                // Label selection belongs in the Notifier, not the widget:
                // The widget renders the label from ProfitState and never inspects record.status directly.
                if (item.profitState is InterimProfit || item.profitState is NetProfit) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: item.profitState is NetProfit
                          ? AppTheme.emerald.withValues(alpha: 0.12)
                          : AppTheme.accentCyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: item.profitState is NetProfit
                            ? AppTheme.emerald.withValues(alpha: 0.3)
                            : AppTheme.accentCyan.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          item.profitState.label ?? 'Profit',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: item.profitState is NetProfit ? AppTheme.emerald : AppTheme.accentCyan,
                          ),
                        ),
                        Text(
                          CurrencyFormatter.format(item.profitState.profitAmount ?? 0.0),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: item.profitState is NetProfit ? AppTheme.emerald : AppTheme.accentCyan,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],

              // Collateral / Pledged Items
              if (record.items.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                          Row(
                            children: [
                              const Icon(Icons.shield_outlined, size: 13, color: AppTheme.gold),
                              const SizedBox(width: 4),
                              Text(
                                'Collateral (${record.items.length})',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.gold,
                                ),
                              ),
                            ],
                          ),
                          Builder(
                            builder: (context) {
                              final lendingVal = record.items.fold(0.0, (s, i) => s + (i.itemValue > 0 ? i.itemValue : CalculationEngine.calculateItemValue(i)));
                              final liveVal = CalculationEngine.calculateTotalLiveCollateralValue(record.items, currentRates);
                              final hasDrift = liveVal > 0 && lendingVal > 0 && (liveVal != lendingVal);

                              return Text(
                                hasDrift
                                    ? 'Live Val: ${CurrencyFormatter.format(liveVal)}'
                                    : 'Val: ${CurrencyFormatter.format(lendingVal)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.emerald,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: record.items.map((it) {
                          final details = <String>[
                            if (it.weight > 0) '${it.weight}g',
                            if (it.purity > 0) '${it.purity}%',
                          ];
                          final detailStr = details.isNotEmpty ? ' (${details.join("@")})' : '';
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.cardDark,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppTheme.borderDark),
                            ),
                            child: Text(
                              '${it.name}$detailStr',
                              style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ],

              // Payments list drill-down (each payment shows payment ID PAY... and formatDate())
              if (record.payments.isNotEmpty) ...[
                const Divider(height: 16),
                Text(
                  'Payments (${record.payments.length})',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 6),
                ...record.payments.map((p) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: AppTheme.badgeDecoration(AppTheme.gold),
                              child: Text(
                                AppIdFormatter.formatPaymentId(p.paymentId),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.gold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            // [FIX-TIMESTAMP-CUSTOMERHISTORY-1] (revised v1.15) formatDate(payment.date)
                            Text(
                              AppDateFormatter.formatDate(p.date),
                              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                        Text(
                          CurrencyFormatter.format(p.amount),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.emerald),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        );
  }
}
