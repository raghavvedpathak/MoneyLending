import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/calculations/calculations.dart';
import '../../../core/di/injection.dart';
import '../../../core/pdf/pdf.dart';
import '../../../core/ui/formatters/currency_formatter.dart';
import '../../../core/ui/theme/app_theme.dart';
import '../../../core/utils/app_date_formatter.dart';
import '../../../domain/domain.dart';
import '../viewmodels/reports_viewmodel.dart';

/// Tab 3: Reports Screen (:feature:reports).
///
/// Mandated by Specification Section 10.3 & §6.1:
/// • Overview tab — total principal, interest, due
/// • Monthly tab — interest received per month (cash-basis; label MUST say “Interest Received”)
/// • Overdue tab — records past 30-day activity threshold, plus GIVEN/TAKEN records
///   under-collateralized today or projected to be within 2 months at current live rate [FIX-OVERDUE-COLLATERAL-1]
/// • Customer tab — shows a scrollable list of all customers, each row displaying the
///   customer’s name, active record count, total principal out, total interest accrued, and
///   total due — all five CustomerReport fields (§5.1), matching the PDF’s Customer
///   Name / Active Records / Total Principal Out / Total Interest Accrued / Total Due
///   columns (§6.1) so the on-screen list and the exported statement never disagree
///   [FIX-CUSTOMERREPORT-COUNT-1]. Tapping a row selects that customer and updates
///   ReportsNotifier’s selectedCustomer field (controlling FAB visibility per §6.1).
///   The selected customer’s detailed report is shown as a navigation drill-down.
class ReportsScreen extends StatefulWidget {
  final int initialSubTab;

  const ReportsScreen({
    super.key,
    this.initialSubTab = 0,
  });

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with SingleTickerProviderStateMixin {
  late final ReportsViewModel _viewModel;
  late final TabController _tabController;
  final CustomerRepository _customerRepository = sl<CustomerRepository>();
  final RecordRepository _recordRepository = sl<RecordRepository>();
  final ItemRateRepository _itemRateRepository = sl<ItemRateRepository>();
  final PdfShareService _pdfShareService = sl<PdfShareService>();

  StreamSubscription<List<Customer>>? _customerSub;
  StreamSubscription<Customer?>? _selectedCustomerSub;
  List<Customer> _customers = [];

  @override
  void initState() {
    super.initState();
    _viewModel = ReportsViewModel(initialTab: widget.initialSubTab);
    _tabController = TabController(length: 4, vsync: this, initialIndex: widget.initialSubTab);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _viewModel.setActiveSubTab(_tabController.index);
      }
    });

    _customerSub = _customerRepository.getAllCustomers().listen((customers) {
      if (mounted) {
        setState(() {
          _customers = customers;
        });
      }
    });

    _selectedCustomerSub = _viewModel.selectedCustomerStream.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _customerSub?.cancel();
    _selectedCustomerSub?.cancel();
    _tabController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _handleFabAction(ReportsFabAction action) async {
    try {
      if (action == ReportsFabAction.allCustomersReport) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Generating All Customers Report PDF...')),
        );
        final report = await _viewModel.generateAllCustomersPdf();
        final fonts = await loadPdfFonts();
        final records = await _recordRepository.getAllActiveRecordsOnce();
        final bytes = await compute(
          buildAllCustomersBytes,
          AllCustomersJob(
            report.customerReports.map((c) => c.customer).toList(),
            records,
            report.businessInfo,
            fonts,
            report.generatedDate,
          ),
        );
        await _pdfShareService.sharePdf(
          bytes: bytes,
          fileName: 'all_customers_report_${DateTime.now().millisecondsSinceEpoch}',
          subject: 'All Customers Loan Ledger Report',
          chooserTitle: 'Share All Customers Report',
        );
      } else if (action == ReportsFabAction.customerStatement) {
        final customer = _viewModel.selectedCustomer;
        if (customer == null) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Generating statement for ${customer.name}...')),
        );
        final records = await _recordRepository.getRecordsByCustomer(customer.id).first;
        final settings = await sl<SettingsRepository>().getSettingsOnce();
        final businessInfo = BusinessInfo.fromSettings(settings);
        final fonts = await loadPdfFonts();
        final bytes = await compute(
          buildStatementBytes,
          StatementJob(customer, records, businessInfo, fonts),
        );
        await _pdfShareService.shareCustomerStatement(
          customer: customer,
          bytes: bytes,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppTheme.errorSnackBar('Error generating PDF: $e'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _viewModel.selectedCustomer == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _viewModel.selectedCustomer != null) {
          _viewModel.clearSelectedCustomer();
        }
      },
      child: StreamBuilder<bool>(
        stream: _viewModel.isFabVisibleStream,
        initialData: _viewModel.isFabVisible,
        builder: (context, fabVisibleSnap) {
          final isFabVisible = fabVisibleSnap.data ?? false;
          final currentFabAction = _viewModel.currentFabAction;

          return Scaffold(
            appBar: AppBar(
              title: const Text('Financial Reports'),
              bottom: TabBar(
                controller: _tabController,
                indicatorWeight: 3,
                tabs: const [
                  Tab(text: 'Overview'),
                  Tab(text: 'Customer'),
                  Tab(text: 'Monthly'),
                  Tab(text: 'Overdue'),
                ],
              ),
            ),
            floatingActionButton: isFabVisible
                ? FloatingActionButton.extended(
                    heroTag: 'reports_fab',
                    onPressed: () => _handleFabAction(currentFabAction),
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: Text(
                      currentFabAction == ReportsFabAction.allCustomersReport
                          ? 'Export All PDF'
                          : 'Export Statement PDF',
                    ),
                  )
                : null,
            body: TabBarView(
              controller: _tabController,
              children: [
                _OverviewTab(recordRepository: _recordRepository),
                _CustomerReportsTab(
                  customers: _customers,
                  selectedCustomer: _viewModel.selectedCustomer,
                  onCustomerChanged: (c) => _viewModel.selectCustomer(c),
                  recordRepository: _recordRepository,
                ),
                _MonthlyEarningsTab(recordRepository: _recordRepository),
                _OverdueLoansTab(
                  recordRepository: _recordRepository,
                  itemRateRepository: _itemRateRepository,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Overview tab — total principal, interest, due (§10.3).
class _OverviewTab extends StatefulWidget {
  final RecordRepository recordRepository;

  const _OverviewTab({required this.recordRepository});

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> with AutomaticKeepAliveClientMixin {
  late Future<List<LedgerRecord>> _recordsFuture;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _recordsFuture = widget.recordRepository.getAllActiveRecordsOnce();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<LedgerRecord>>(
      future: _recordsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final records = snapshot.data!;
        final dashboard = CalculationEngine.getDashboard(records, today: DateTime.now().dateOnly);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Executive Financial Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    _ReportRow(label: 'Total Principal Lent (Given)', value: CurrencyFormatter.format(dashboard.totalPrincipalGiven)),
                    _ReportRow(label: 'Total Principal Borrowed (Taken)', value: CurrencyFormatter.format(dashboard.totalPrincipalTaken)),
                    _ReportRow(label: 'Total Interest Accrued', value: CurrencyFormatter.format(dashboard.totalInterestAccruedGiven)),
                    const Divider(height: 24),
                    _ReportRow(
                      label: 'Grand Total Outstanding Due',
                      value: CurrencyFormatter.format(dashboard.totalDueGiven),
                      isHighlight: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Portfolio Health', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _ReportRow(label: 'Total Active Loans', value: '${records.where((r) => r.status == RecordStatus.ACTIVE).length}'),
                    _ReportRow(label: 'Total Settled Loans', value: '${records.where((r) => r.status == RecordStatus.SETTLED).length}'),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Customer tab — shows a scrollable list of all customers, each row displaying
/// Customer Name, Active Records, Total Principal Out, Total Interest Accrued, Total Due.
/// Tapping a row selects that customer and shows the detailed report drill-down (§10.3, [FIX-CUSTOMERREPORT-COUNT-1]).
class _CustomerReportsTab extends StatefulWidget {
  final List<Customer> customers;
  final Customer? selectedCustomer;
  final ValueChanged<Customer?> onCustomerChanged;
  final RecordRepository recordRepository;

  const _CustomerReportsTab({
    required this.customers,
    required this.selectedCustomer,
    required this.onCustomerChanged,
    required this.recordRepository,
  });

  @override
  State<_CustomerReportsTab> createState() => _CustomerReportsTabState();
}

class _CustomerReportsTabState extends State<_CustomerReportsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.selectedCustomer != null) {
      return _CustomerDetailDrillDown(
        customer: widget.selectedCustomer!,
        recordRepository: widget.recordRepository,
        onBack: () => widget.onCustomerChanged(null),
      );
    }

    return _CustomerSummaryList(
      customers: widget.customers,
      recordRepository: widget.recordRepository,
      onCustomerSelected: widget.onCustomerChanged,
    );
  }
}

/// Scrollable list of all customers with 5 CustomerReport fields (§5.1, §6.1, [FIX-CUSTOMERREPORT-COUNT-1]).
class _CustomerSummaryList extends StatefulWidget {
  final List<Customer> customers;
  final RecordRepository recordRepository;
  final ValueChanged<Customer> onCustomerSelected;

  const _CustomerSummaryList({
    required this.customers,
    required this.recordRepository,
    required this.onCustomerSelected,
  });

  @override
  State<_CustomerSummaryList> createState() => _CustomerSummaryListState();
}

class _CustomerSummaryListState extends State<_CustomerSummaryList> {
  late Future<List<LedgerRecord>> _recordsFuture;

  @override
  void initState() {
    super.initState();
    _recordsFuture = widget.recordRepository.getAllActiveRecordsOnce();
  }

  @override
  void didUpdateWidget(covariant _CustomerSummaryList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.customers.length != oldWidget.customers.length) {
      setState(() {
        _recordsFuture = widget.recordRepository.getAllActiveRecordsOnce();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LedgerRecord>>(
      future: _recordsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final records = snapshot.data!;
        final today = DateTime.now().dateOnly;
        final reports = CalculationEngine.getCustomerReport(
          widget.customers,
          records,
          today: today,
        );

        if (reports.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people_outline, size: 64, color: AppTheme.textMuted.withValues(alpha: 0.5)),
                const SizedBox(height: 16),
                const Text(
                  'No customers found',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: reports.length,
          itemBuilder: (context, index) {
            final report = reports[index];
            return _CustomerReportCard(
              report: report,
              onTap: () => widget.onCustomerSelected(report.customer),
            );
          },
        );
      },
    );
  }
}

/// Interactive customer card rendering all 5 CustomerReport fields (§5.1, §6.1, [FIX-CUSTOMERREPORT-COUNT-1]).
class _CustomerReportCard extends StatelessWidget {
  final CustomerReport report;
  final VoidCallback onTap;

  const _CustomerReportCard({
    required this.report,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final customer = report.customer;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          customer.displayId,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.gold,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.accentCyan.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.accentCyan.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      '${report.activeRecordCount} Active',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accentCyan,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, color: AppTheme.textMuted),
                ],
              ),
              const Divider(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _FieldColumn(
                      label: 'Total Principal Out',
                      value: CurrencyFormatter.format(report.totalPrincipal),
                    ),
                  ),
                  Expanded(
                    child: _FieldColumn(
                      label: 'Total Interest Accrued',
                      value: CurrencyFormatter.format(report.totalInterestAccrued),
                    ),
                  ),
                  Expanded(
                    child: _FieldColumn(
                      label: 'Total Due',
                      value: CurrencyFormatter.format(report.totalDue),
                      isHighlight: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldColumn extends StatelessWidget {
  final String label;
  final String value;
  final bool isHighlight;

  const _FieldColumn({
    required this.label,
    required this.value,
    this.isHighlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.textSecondary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isHighlight ? AppTheme.gold : AppTheme.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Navigation drill-down displaying selected customer's detailed report (§10.3).
class _CustomerDetailDrillDown extends StatefulWidget {
  final Customer customer;
  final RecordRepository recordRepository;
  final VoidCallback onBack;

  const _CustomerDetailDrillDown({
    required this.customer,
    required this.recordRepository,
    required this.onBack,
  });

  @override
  State<_CustomerDetailDrillDown> createState() => _CustomerDetailDrillDownState();
}

class _CustomerDetailDrillDownState extends State<_CustomerDetailDrillDown> {
  late Future<List<LedgerRecord>> _recordsFuture;

  @override
  void initState() {
    super.initState();
    _recordsFuture = _loadRecords();
  }

  @override
  void didUpdateWidget(covariant _CustomerDetailDrillDown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.customer.id != oldWidget.customer.id) {
      setState(() {
        _recordsFuture = _loadRecords();
      });
    }
  }

  Future<List<LedgerRecord>> _loadRecords() async {
    final allRecords = await widget.recordRepository.getAllRecordsOnce();
    return allRecords.where((r) => r.customerId == widget.customer.id).toList();
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.customer;
    final onBack = widget.onBack;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            IconButton(
              key: const Key('reports_drilldown_back_button'),
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back to all customers',
              onPressed: onBack,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${customer.displayId}${customer.phone != null && customer.phone!.isNotEmpty ? " • ${customer.phone}" : ""}',
                    style: const TextStyle(color: AppTheme.gold, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<LedgerRecord>>(
          future: _recordsFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              debugPrint('DRILL DOWN ERROR: ${snapshot.error}\n${snapshot.stackTrace}');
            }
            if (!snapshot.hasData) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final records = snapshot.data!;
            final customerReports = CalculationEngine.getCustomerReport(
              [customer],
              records,
              today: DateTime.now().dateOnly,
            );
            final report = customerReports.isNotEmpty
                ? customerReports.first
                : CustomerReport(
                    customer: customer,
                    activeRecordCount: 0,
                    totalPrincipal: 0.0,
                    totalInterestAccrued: 0.0,
                    totalDue: 0.0,
                  );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  color: AppTheme.subCardDark,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _ReportRow(label: 'Customer ID', value: customer.displayId),
                        _ReportRow(label: 'Customer Name', value: customer.name),
                        if (customer.phone != null && customer.phone!.isNotEmpty)
                          _ReportRow(label: 'Phone', value: customer.phone!),
                        if (customer.address != null && customer.address!.isNotEmpty)
                          _ReportRow(label: 'Address', value: customer.address!),
                        const Divider(height: 16),
                        _ReportRow(label: 'Active Records', value: '${report.activeRecordCount}'),
                        _ReportRow(label: 'Total Principal Out', value: CurrencyFormatter.format(report.totalPrincipal)),
                        _ReportRow(label: 'Total Interest Accrued', value: CurrencyFormatter.format(report.totalInterestAccrued)),
                        const Divider(height: 20),
                        _ReportRow(label: 'Total Due', value: CurrencyFormatter.format(report.totalDue), isHighlight: true),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Record History',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (records.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No loan records found for this customer.',
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
                    ),
                  )
                else
                  ...records.map((r) {
                    final isGiven = r.type == RecordType.GIVEN;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          backgroundColor: isGiven ? AppTheme.accentCyan.withValues(alpha: 0.15) : AppTheme.emerald.withValues(alpha: 0.15),
                          child: Icon(
                            isGiven ? Icons.arrow_outward_rounded : Icons.arrow_downward_rounded,
                            color: isGiven ? AppTheme.accentCyan : AppTheme.emerald,
                          ),
                        ),
                        title: Text('${r.transactionId} • ${CurrencyFormatter.format(r.principalAmount)}'),
                        subtitle: Text(
                          'Started: ${AppDateFormatter.formatDate(r.startDate)} • Rate: ${r.interestRate}%/mo',
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: r.status == RecordStatus.ACTIVE
                                ? AppTheme.gold.withValues(alpha: 0.15)
                                : AppTheme.cardDark,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            r.status.name.toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: r.status == RecordStatus.ACTIVE ? AppTheme.gold : AppTheme.textMuted,
                            ),
                          ),
                        ),
                        children: [
                          if (r.payments.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text('No payments recorded', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                            )
                          else
                            ...r.payments.map((p) => ListTile(
                              dense: true,
                              leading: const Icon(Icons.payment, size: 20, color: AppTheme.emerald),
                              title: Text('${p.paymentId ?? "PAY"} • ${CurrencyFormatter.format(p.amount)}'),
                              subtitle: Text(
                                '${AppDateFormatter.formatDate(p.date)} (Interest: ${CurrencyFormatter.format(p.interestPaid)}, Principal: ${CurrencyFormatter.format(p.principalPaid)})',
                                style: const TextStyle(fontSize: 11),
                              ),
                            )),
                        ],
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Monthly tab — interest received per month (cash-basis; label MUST say “Interest Received”) (§10.3).
class _MonthlyEarningsTab extends StatefulWidget {
  final RecordRepository recordRepository;

  const _MonthlyEarningsTab({required this.recordRepository});

  @override
  State<_MonthlyEarningsTab> createState() => _MonthlyEarningsTabState();
}

class _MonthlyEarningsTabState extends State<_MonthlyEarningsTab> with AutomaticKeepAliveClientMixin {
  late Future<List<LedgerRecord>> _recordsFuture;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _recordsFuture = widget.recordRepository.getAllRecordsOnce();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<LedgerRecord>>(
      future: _recordsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final records = snapshot.data!;
        final earnings = CalculationEngine.getMonthlyInterest(records);

        if (earnings.isEmpty) {
          return const Center(
            child: Text(
              'No interest payments recorded yet.',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Cash-Basis Interest Received (§5.1)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...earnings.map((e) {
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.calendar_month, color: AppTheme.gold),
                  title: Text(e.formattedMonth, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text(
                    'Interest Received',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                  trailing: Text(
                    CurrencyFormatter.format(e.interestReceived),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.emerald),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

/// Overdue tab — records past 30-day activity threshold, plus GIVEN/TAKEN records
/// under-collateralized today or projected to be within 2 months at the current live rate [FIX-OVERDUE-COLLATERAL-1] (§10.3).
class _OverdueLoansTab extends StatefulWidget {
  final RecordRepository recordRepository;
  final ItemRateRepository itemRateRepository;

  const _OverdueLoansTab({
    required this.recordRepository,
    required this.itemRateRepository,
  });

  @override
  State<_OverdueLoansTab> createState() => _OverdueLoansTabState();
}

class _OverdueLoansTabState extends State<_OverdueLoansTab> with AutomaticKeepAliveClientMixin {
  late Future<List<OverdueRecord>> _overdueFuture;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _overdueFuture = _fetchOverdues();
  }

  Future<List<OverdueRecord>> _fetchOverdues() async {
    final records = await widget.recordRepository.getAllActiveRecordsOnce();
    final activityMap = await widget.recordRepository.getActiveRecordLastActivityMap();
    final rates = await widget.itemRateRepository.getCurrentRatesOnce();
    final today = DateTime.now().dateOnly;

    // Activity-based overdue: gap >= 30 days (§8)
    final activityBased = CalculationEngine.getOverdue(
      records: records,
      latestPaymentDates: activityMap,
      today: today,
      thresholdDays: 30,
    );

    // Collateral live-rate overdue ([FIX-OVERDUE-COLLATERAL-1] & [FIX-OVERDUE-RATES-1])
    final collateralBased = CalculationEngine.computeCollateralOverdue(
      records: records,
      rates: rates,
      today: today,
    );

    // Merged unified overdue records
    return CalculationEngine.mergeOverdueRecords(activityBased, collateralBased);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<OverdueRecord>>(
      future: _overdueFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final overdues = snapshot.data!;

        if (overdues.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 64, color: AppTheme.emerald),
                SizedBox(height: 16),
                Text('No loans currently overdue!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: overdues.length,
          itemBuilder: (context, index) {
            final o = overdues[index];
            final reasons = <String>[];
            if (o.reasons.contains(OverdueReason.noActivity)) {
              reasons.add('Inactive: ${o.daysSinceActivity} days');
            }
            if (o.reasons.contains(OverdueReason.collateralBreachedNow)) {
              reasons.add('Collateral breached');
            }
            if (o.reasons.contains(OverdueReason.collateralProjected2Months)) {
              reasons.add('Projected breach in 2 mos');
            }

            final isGiven = o.record.type == RecordType.GIVEN;

            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.rose.withValues(alpha: 0.15),
                  child: const Icon(Icons.timer_outlined, color: AppTheme.rose),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${o.record.customerName ?? "Customer"} • ${o.record.transactionId}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isGiven ? AppTheme.accentCyan.withValues(alpha: 0.15) : AppTheme.emerald.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        o.record.type.name,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isGiven ? AppTheme.accentCyan : AppTheme.emerald,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Principal: ${CurrencyFormatter.format(o.record.principalAmount)} • ${reasons.join(" • ")}',
                  ),
                ),
                trailing: Text(
                  o.lastActivityDate != null
                      ? 'Last: ${o.formattedLastActivityDate}'
                      : (o.currentCollateralValue != null
                          ? 'Collateral: ${CurrencyFormatter.format(o.currentCollateralValue!)}'
                          : ''),
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ReportRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isHighlight;

  const _ReportRow({
    required this.label,
    required this.value,
    this.isHighlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: isHighlight ? 15 : 13,
                fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
                color: isHighlight ? AppTheme.textPrimary : AppTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: isHighlight ? 17 : 14,
              fontWeight: FontWeight.bold,
              color: isHighlight ? AppTheme.gold : AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
