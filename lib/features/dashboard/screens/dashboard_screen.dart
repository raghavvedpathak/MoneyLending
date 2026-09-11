import 'package:flutter/material.dart';
import '../../../core/calculations/calculations.dart';
import '../../../core/di/injection.dart';
import '../../../core/ui/formatters/currency_formatter.dart';
import '../../../core/ui/theme/app_theme.dart';
import '../../../core/utils/app_date_formatter.dart';
import '../../../domain/domain.dart';
import '../../entry/screens/add_entry_screen.dart';
import '../../payments/screens/add_payment_screen.dart';
import '../viewmodels/dashboard_viewmodel.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final DashboardViewModel _viewModel;
  final RecordRepository _recordRepository = sl<RecordRepository>();
  final SettingsRepository _settingsRepository = sl<SettingsRepository>();

  RecordType _currentTab = RecordType.GIVEN;
  Settings? _settings;

  @override
  void initState() {
    super.initState();
    _viewModel = DashboardViewModel();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final s = await _settingsRepository.getSettingsOnce();
    if (mounted) setState(() => _settings = s);
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  void _openAddEntry() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddEntryScreen(initialType: _currentTab),
      ),
    );
    if (result == true && mounted) {
      setState(() {});
    }
  }

  void _openAddPayment(LedgerRecord record) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddPaymentScreen(record: record),
      ),
    );
    if (result == true && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_settings?.name ?? 'Money Lending Ledger'),
            const Text(
              'Girvi & Mortgage Management',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddEntry,
        icon: const Icon(Icons.add),
        label: Text(_currentTab == RecordType.GIVEN ? 'New Loan Given' : 'New Loan Taken'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _loadSettings();
          setState(() {});
        },
        child: CustomScrollView(
          slivers: [
            // 1. Metric Summary Cards
            SliverToBoxAdapter(
              child: FutureBuilder<List<LedgerRecord>>(
                future: _recordRepository.getAllActiveRecordsOnce(),
                builder: (context, snapshot) {
                  final records = snapshot.data ?? [];
                  final dashboardData = CalculationEngine.getDashboard(records, DateTime.now());

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isTabletOrWide = constraints.maxWidth >= 720;
                        if (isTabletOrWide) {
                          return Row(
                            children: [
                              Expanded(
                                child: _MetricCard(
                                  title: 'Total Given (Lent)',
                                  value: CurrencyFormatter.format(dashboardData.totalPrincipalGiven),
                                  icon: Icons.arrow_outward_rounded,
                                  color: AppTheme.accentCyan,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _MetricCard(
                                  title: 'Total Taken (Borrowed)',
                                  value: CurrencyFormatter.format(dashboardData.totalPrincipalTaken),
                                  icon: Icons.arrow_downward_rounded,
                                  color: AppTheme.emerald,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _MetricCard(
                                  title: 'Accrued Interest',
                                  value: CurrencyFormatter.format(dashboardData.totalInterestAccruedGiven),
                                  icon: Icons.trending_up_rounded,
                                  color: AppTheme.goldDark,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _MetricCard(
                                  title: 'Total Due (Given)',
                                  value: CurrencyFormatter.format(dashboardData.totalDueGiven),
                                  icon: Icons.account_balance_wallet_rounded,
                                  color: AppTheme.rose,
                                ),
                              ),
                            ],
                          );
                        }

                        return Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _MetricCard(
                                    title: 'Total Given (Lent)',
                                    value: CurrencyFormatter.format(dashboardData.totalPrincipalGiven),
                                    icon: Icons.arrow_outward_rounded,
                                    color: AppTheme.accentCyan,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _MetricCard(
                                    title: 'Total Taken (Borrowed)',
                                    value: CurrencyFormatter.format(dashboardData.totalPrincipalTaken),
                                    icon: Icons.arrow_downward_rounded,
                                    color: AppTheme.emerald,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _MetricCard(
                                    title: 'Accrued Interest',
                                    value: CurrencyFormatter.format(dashboardData.totalInterestAccruedGiven),
                                    icon: Icons.trending_up_rounded,
                                    color: AppTheme.goldDark,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _MetricCard(
                                    title: 'Total Due (Given)',
                                    value: CurrencyFormatter.format(dashboardData.totalDueGiven),
                                    icon: Icons.account_balance_wallet_rounded,
                                    color: AppTheme.rose,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  );
                },
              ),
            ),

            // 2. Collection Alert Section (§5.3 & §5.4 / [FIX-FEAT-OVERSHOOT-1])
            SliverToBoxAdapter(
              child: StreamBuilder<List<CollectionAlertCardData>>(
                stream: _viewModel.collectionAlertCards,
                builder: (context, snapshot) {
                  final cards = snapshot.data ?? _viewModel.currentAlertCards;
                  final hasAlerts = cards.any((c) => c.isTriggered);

                  if (!hasAlerts) {
                    return StreamBuilder<bool>(
                      stream: _viewModel.alertsLoaded,
                      builder: (context, loadedSnap) {
                        final loaded = loadedSnap.data ?? _viewModel.isAlertsLoaded;
                        if (!loaded) return const SizedBox.shrink();
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: AppTheme.bannerDecoration(AppTheme.emerald),
                          child: const Row(
                            children: [
                              Icon(Icons.check_circle_rounded, color: AppTheme.emerald, size: 20),
                              SizedBox(width: 10),
                              Text(
                                'All active loans have healthy collateral today',
                                style: TextStyle(color: AppTheme.emerald, fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  }

                  final alertCards = cards.where((c) => c.isTriggered).toList();

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: AppTheme.bannerDecoration(AppTheme.gold, borderRadius: 14),
                    child: ExpansionTile(
                      initiallyExpanded: true,
                      leading: const Icon(Icons.warning_amber_rounded, color: AppTheme.gold),
                      title: Text(
                        'Collateral Risk Alerts (${alertCards.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.gold),
                      ),
                      subtitle: const Text(
                        'Live market drop or projected 2-month interest overshoot',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                      children: alertCards.map((alert) {
                        return ListTile(
                          dense: true,
                          title: Text(
                            '${alert.record.customerName ?? "Customer"} • ${alert.record.transactionId}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'Principal: ${CurrencyFormatter.format(alert.record.principalAmount)} | '
                            'Collateral: ${CurrencyFormatter.format(alert.currentCollateralValue)}',
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (alert.isCollateralUnderwater)
                                Text('DROP RISK', style: AppTheme.badgeTextStyle(AppTheme.rose, fontSize: 11)),
                              if (alert.isOvershoot)
                                Text('OVERSHOOT', style: AppTheme.badgeTextStyle(AppTheme.goldDark, fontSize: 11)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
            ),

            // 3. Tab Filter (Given vs Taken)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: SegmentedButton<RecordType>(
                  segments: const [
                    ButtonSegment(
                      value: RecordType.GIVEN,
                      label: Text('Given (Money Lent)'),
                      icon: Icon(Icons.arrow_upward_rounded),
                    ),
                    ButtonSegment(
                      value: RecordType.TAKEN,
                      label: Text('Taken (Money Borrowed)'),
                      icon: Icon(Icons.arrow_downward_rounded),
                    ),
                  ],
                  selected: {_currentTab},
                  onSelectionChanged: (val) {
                    setState(() => _currentTab = val.first);
                  },
                ),
              ),
            ),

            // 4. Live Record List
            StreamBuilder<List<LedgerRecord>>(
              stream: _recordRepository.getAllActiveRecords().map(
                (list) => list.where((r) => r.type == _currentTab).toList(),
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final records = snapshot.data ?? [];
                if (records.isEmpty) {
                  return SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _currentTab == RecordType.GIVEN
                                ? Icons.account_balance_wallet_outlined
                                : Icons.savings_outlined,
                            size: 64,
                            color: AppTheme.textMuted,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _currentTab == RecordType.GIVEN
                                ? 'No active loan given records'
                                : 'No active borrowing records',
                            style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Click the button below to add your first record',
                            style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final record = records[index];
                      final financials = CalculationEngine.calculateRecordFinancials(record, DateTime.now());

                      return Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _openAddPayment(record),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: AppTheme.badgeDecoration(AppTheme.gold),
                                          child: Text(
                                            record.transactionId,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: AppTheme.gold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          record.customerName ?? 'Customer',
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    _StatusBadge(status: record.status),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Principal', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                                        Text(
                                          CurrencyFormatter.format(record.principalAmount),
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Rate', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                                        Text(
                                          '${record.interestRate.toStringAsFixed(1)}%/mo',
                                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        const Text('Total Due', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                                        Text(
                                          CurrencyFormatter.format(financials.totalDue),
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.rose,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const Divider(height: 20),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Started: ${AppDateFormatter.formatDate(record.startDate)}',
                                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => _openAddPayment(record),
                                      icon: const Icon(Icons.payment_rounded, size: 16),
                                      label: const Text('Record Payment'),
                                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: records.length,
                  ),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.metricCardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, size: 18, color: color),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final RecordStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isSettled = status == RecordStatus.SETTLED;
    final accent = isSettled ? AppTheme.accentCyan : AppTheme.emerald;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: AppTheme.badgeDecoration(accent),
      child: Text(
        isSettled ? 'SETTLED' : 'ACTIVE',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: accent,
        ),
      ),
    );
  }
}
