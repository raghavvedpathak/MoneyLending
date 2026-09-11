import 'package:flutter/material.dart';
import '../../../core/calculations/calculations.dart';
import '../../../core/di/injection.dart';
import '../../../core/pdf/pdf.dart';
import '../../../core/ui/formatters/currency_formatter.dart';
import '../../../core/ui/theme/app_theme.dart';
import '../../../core/utils/app_date_formatter.dart';
import '../../../domain/domain.dart';
import '../viewmodels/reports_viewmodel.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with SingleTickerProviderStateMixin {
  late final ReportsViewModel _viewModel;
  late final TabController _tabController;
  final CustomerRepository _customerRepository = sl<CustomerRepository>();
  final RecordRepository _recordRepository = sl<RecordRepository>();
  final PdfShareService _pdfShareService = sl<PdfShareService>();

  List<Customer> _customers = [];

  @override
  void initState() {
    super.initState();
    _viewModel = ReportsViewModel();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _viewModel.setActiveSubTab(_tabController.index);
      }
    });
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    final customers = await _customerRepository.getAllCustomers().first;
    if (mounted) {
      setState(() {
        _customers = customers;
      });
    }
  }

  @override
  void dispose() {
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
        final bytes = await report.buildPdf();
        await _pdfShareService.sharePdf(
          bytes: bytes,
          fileName: 'all_customers_report_${DateTime.now().millisecondsSinceEpoch}',
          subject: 'All Customers Loan Ledger Report',
          chooserTitle: 'Share All Customers Report',
        );
      } else if (action == ReportsFabAction.customerStatement) {
        if (_viewModel.selectedCustomer == null) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Generating statement for ${_viewModel.selectedCustomer!.name}...')),
        );
        final statement = await _viewModel.generateCustomerStatementPdf();
        if (statement == null) return;
        final bytes = await statement.buildPdf();
        await _pdfShareService.sharePdf(
          bytes: bytes,
          fileName: 'customer_statement_${_viewModel.selectedCustomer!.displayId}',
          subject: 'Customer Loan Statement - ${_viewModel.selectedCustomer!.name}',
          chooserTitle: 'Share Customer Statement',
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
    return StreamBuilder<bool>(
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
              isScrollable: true,
              indicatorWeight: 3,
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Customer Statement'),
                Tab(text: 'Monthly Earnings'),
                Tab(text: 'Overdue Loans'),
              ],
            ),
          ),
          floatingActionButton: isFabVisible
              ? FloatingActionButton.extended(
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
              _CustomerStatementTab(
                customers: _customers,
                selectedCustomer: _viewModel.selectedCustomer,
                onCustomerChanged: (c) => _viewModel.selectCustomer(c),
                recordRepository: _recordRepository,
              ),
              _MonthlyEarningsTab(recordRepository: _recordRepository),
              _OverdueLoansTab(recordRepository: _recordRepository),
            ],
          ),
        );
      },
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final RecordRepository recordRepository;

  const _OverviewTab({required this.recordRepository});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LedgerRecord>>(
      future: recordRepository.getAllActiveRecordsOnce(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final records = snapshot.data!;
        final dashboard = CalculationEngine.getDashboard(records, DateTime.now());

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

class _CustomerStatementTab extends StatelessWidget {
  final List<Customer> customers;
  final Customer? selectedCustomer;
  final ValueChanged<Customer?> onCustomerChanged;
  final RecordRepository recordRepository;

  const _CustomerStatementTab({
    required this.customers,
    required this.selectedCustomer,
    required this.onCustomerChanged,
    required this.recordRepository,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<Customer>(
          initialValue: selectedCustomer,
          decoration: const InputDecoration(
            labelText: 'Select Customer for Statement',
            prefixIcon: Icon(Icons.person_search),
          ),
          items: customers.map((c) {
            return DropdownMenuItem(
              value: c,
              child: Text('${c.name} (${c.displayId})'),
            );
          }).toList(),
          onChanged: onCustomerChanged,
        ),
        const SizedBox(height: 16),
        if (selectedCustomer == null)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: Text('Select a customer above to preview and export their statement.'),
            ),
          )
        else
          FutureBuilder<List<LedgerRecord>>(
            future: recordRepository.getRecordsByCustomer(selectedCustomer!.id).first,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

              final records = snapshot.data!;
              final customerReports = CalculationEngine.getCustomerReport([selectedCustomer!], records, DateTime.now());
              final report = customerReports.isNotEmpty
                  ? customerReports.first
                  : CustomerReport(
                      customer: selectedCustomer!,
                      activeRecordCount: 0,
                      totalPrincipal: 0.0,
                      totalInterestAccrued: 0.0,
                      totalDue: 0.0,
                    );

              return Column(
                children: [
                  Card(
                    color: AppTheme.subCardDark,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _ReportRow(label: 'Customer ID', value: selectedCustomer!.displayId),
                          _ReportRow(label: 'Active Loans', value: '${report.activeRecordCount}'),
                          _ReportRow(label: 'Total Principal Lent', value: CurrencyFormatter.format(report.totalPrincipal)),
                          _ReportRow(label: 'Total Interest Accrued', value: CurrencyFormatter.format(report.totalInterestAccrued)),
                          const Divider(height: 20),
                          _ReportRow(label: 'Total Balance Due', value: CurrencyFormatter.format(report.totalDue), isHighlight: true),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...records.map((r) {
                    return Card(
                      child: ListTile(
                        title: Text('${r.transactionId} • ${CurrencyFormatter.format(r.principalAmount)}'),
                        subtitle: Text('Started: ${AppDateFormatter.formatDate(r.startDate)} • Rate: ${r.interestRate}%/mo'),
                        trailing: Text(r.status.name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
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

class _MonthlyEarningsTab extends StatelessWidget {
  final RecordRepository recordRepository;

  const _MonthlyEarningsTab({required this.recordRepository});

  static const _monthNames = [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LedgerRecord>>(
      future: recordRepository.getAllActiveRecordsOnce(),
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
              final monthLabel = e.month >= 1 && e.month <= 12 ? _monthNames[e.month] : 'Month ${e.month}';
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.calendar_month, color: AppTheme.gold),
                  title: Text('$monthLabel ${e.year}', style: const TextStyle(fontWeight: FontWeight.bold)),
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

class _OverdueLoansTab extends StatelessWidget {
  final RecordRepository recordRepository;

  const _OverdueLoansTab({required this.recordRepository});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<OverdueRecord>>(
      future: () async {
        final records = await recordRepository.getAllActiveRecordsOnce();
        final activityMap = await recordRepository.getActiveRecordLastActivityMap();
        return CalculationEngine.getOverdue(records, activityMap, DateTime.now());
      }(),
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
            return Card(
              child: ListTile(
                leading: const Icon(Icons.timer_outlined, color: AppTheme.rose),
                title: Text(
                  '${o.record.customerName ?? "Customer"} • ${o.record.transactionId}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'Principal: ${CurrencyFormatter.format(o.record.principalAmount)} • Inactive: ${o.daysSinceActivity} days',
                ),
                trailing: Text(
                  'Last: ${o.formattedLastActivityDate}',
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
