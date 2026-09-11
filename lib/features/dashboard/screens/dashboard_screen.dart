import 'package:flutter/material.dart';
import '../../../core/calculations/calculations.dart';
import '../../../core/di/injection.dart';
import '../../../core/ui/formatters/currency_formatter.dart';
import '../../../core/ui/theme/app_theme.dart';
import '../../../domain/domain.dart';
import '../../entry/screens/add_entry_screen.dart';
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

  void _openAddEntry([RecordType? type]) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddEntryScreen(initialType: type ?? _currentTab),
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
        heroTag: 'dashboard_fab',
        onPressed: () => _openAddEntry(_currentTab),
        icon: const Icon(Icons.add),
        label: Text(_currentTab == RecordType.GIVEN ? 'New Loan Given' : 'New Loan Taken'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadSettings();
          setState(() {});
        },
        child: StreamBuilder<List<LedgerRecord>>(
          stream: _recordRepository.getAllActiveRecords(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final records = snapshot.data ?? [];
            final dashboardData = CalculationEngine.getDashboard(records, DateTime.now());

            final givenRecords = records.where((r) => r.isGiven).toList();
            final takenRecords = records.where((r) => r.isTaken).toList();

            final givenCount = givenRecords.length;
            final takenCount = takenRecords.length;

            final avgRateGiven = givenCount > 0
                ? (givenRecords.map((r) => r.interestRate).reduce((a, b) => a + b) / givenCount)
                : 0.0;
            final avgRateTaken = takenCount > 0
                ? (takenRecords.map((r) => r.interestRate).reduce((a, b) => a + b) / takenCount)
                : 0.0;

            double totalCollateralValueGiven = 0.0;
            int totalCollateralItemsCount = 0;
            for (final r in givenRecords) {
              for (final item in r.items) {
                totalCollateralItemsCount++;
                totalCollateralValueGiven += (item.itemValue ?? calculateItemValue(item));
              }
            }

            final netPrincipal = dashboardData.totalPrincipalGiven - dashboardData.totalPrincipalTaken;
            final netDue = dashboardData.totalDueGiven - dashboardData.totalDueTaken;

            return LayoutBuilder(
              builder: (context, constraints) {
                final isTabletOrWide = constraints.maxWidth >= 720;

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  children: [
                    // 1. Executive Net Position Summary Card
                    _NetPositionCard(
                      netPrincipal: netPrincipal,
                      netDue: netDue,
                      totalGivenPrincipal: dashboardData.totalPrincipalGiven,
                      totalTakenPrincipal: dashboardData.totalPrincipalTaken,
                      activeGivenCount: givenCount,
                      activeTakenCount: takenCount,
                    ),
                    const SizedBox(height: 16),

                    // 2. Collateral Risk & Market Alerts
                    _CollateralAlertsSection(viewModel: _viewModel),
                    const SizedBox(height: 16),

                    // 3. Responsive Given and Taken Views
                    if (isTabletOrWide) ...[
                      // Tablet & Desktop: Side-by-side Given & Taken deep dive
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _GivenPortfolioCard(
                              activeCount: givenCount,
                              principal: dashboardData.totalPrincipalGiven,
                              accruedInterest: dashboardData.totalInterestAccruedGiven,
                              totalDue: dashboardData.totalDueGiven,
                              avgRate: avgRateGiven,
                              collateralValue: totalCollateralValueGiven,
                              collateralItemsCount: totalCollateralItemsCount,
                              onAddGiven: () => _openAddEntry(RecordType.GIVEN),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _TakenPortfolioCard(
                              activeCount: takenCount,
                              principal: dashboardData.totalPrincipalTaken,
                              accruedInterest: dashboardData.totalInterestAccruedTaken,
                              totalDue: dashboardData.totalDueTaken,
                              avgRate: avgRateTaken,
                              onAddTaken: () => _openAddEntry(RecordType.TAKEN),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      // Smartphone: Tab selector + Selected Portfolio Card
                      SegmentedButton<RecordType>(
                        segments: [
                          ButtonSegment(
                            value: RecordType.GIVEN,
                            label: Text('Given ($givenCount)'),
                            icon: const Icon(Icons.arrow_upward_rounded),
                          ),
                          ButtonSegment(
                            value: RecordType.TAKEN,
                            label: Text('Taken ($takenCount)'),
                            icon: const Icon(Icons.arrow_downward_rounded),
                          ),
                        ],
                        selected: {_currentTab},
                        onSelectionChanged: (val) {
                          setState(() => _currentTab = val.first);
                        },
                      ),
                      const SizedBox(height: 16),
                      if (_currentTab == RecordType.GIVEN)
                        _GivenPortfolioCard(
                          activeCount: givenCount,
                          principal: dashboardData.totalPrincipalGiven,
                          accruedInterest: dashboardData.totalInterestAccruedGiven,
                          totalDue: dashboardData.totalDueGiven,
                          avgRate: avgRateGiven,
                          collateralValue: totalCollateralValueGiven,
                          collateralItemsCount: totalCollateralItemsCount,
                          onAddGiven: () => _openAddEntry(RecordType.GIVEN),
                        )
                      else
                        _TakenPortfolioCard(
                          activeCount: takenCount,
                          principal: dashboardData.totalPrincipalTaken,
                          accruedInterest: dashboardData.totalInterestAccruedTaken,
                          totalDue: dashboardData.totalDueTaken,
                          avgRate: avgRateTaken,
                          onAddTaken: () => _openAddEntry(RecordType.TAKEN),
                        ),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Executive Net Lending Position Banner
class _NetPositionCard extends StatelessWidget {
  final double netPrincipal;
  final double netDue;
  final double totalGivenPrincipal;
  final double totalTakenPrincipal;
  final int activeGivenCount;
  final int activeTakenCount;

  const _NetPositionCard({
    required this.netPrincipal,
    required this.netDue,
    required this.totalGivenPrincipal,
    required this.totalTakenPrincipal,
    required this.activeGivenCount,
    required this.activeTakenCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.35), width: 1.2),
        gradient: LinearGradient(
          colors: [
            AppTheme.cardDark,
            AppTheme.gold.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.account_balance_wallet_rounded, color: AppTheme.gold, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Net Lending Exposure',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: AppTheme.badgeDecoration(AppTheme.gold),
                child: Text(
                  '${activeGivenCount + activeTakenCount} Total Active',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.gold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              CurrencyFormatter.format(netPrincipal),
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: AppTheme.gold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Net outstanding balance: ${CurrencyFormatter.format(netDue)}',
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const Divider(height: 28, color: AppTheme.borderDark),
          Row(
            children: [
              Expanded(
                child: _NetStatMini(
                  label: 'Capital Lent (Given)',
                  amount: CurrencyFormatter.format(totalGivenPrincipal),
                  count: '$activeGivenCount loans',
                  color: AppTheme.accentCyan,
                  icon: Icons.arrow_outward_rounded,
                ),
              ),
              Container(width: 1, height: 40, color: AppTheme.borderDark),
              Expanded(
                child: _NetStatMini(
                  label: 'Capital Borrowed (Taken)',
                  amount: CurrencyFormatter.format(totalTakenPrincipal),
                  count: '$activeTakenCount borrowings',
                  color: AppTheme.emerald,
                  icon: Icons.arrow_downward_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NetStatMini extends StatelessWidget {
  final String label;
  final String amount;
  final String count;
  final Color color;
  final IconData icon;

  const _NetStatMini({
    required this.label,
    required this.amount,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              amount,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color),
            ),
          ),
          Text(
            count,
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Detailed Portfolio Card for GIVEN (Money Lent)
class _GivenPortfolioCard extends StatelessWidget {
  final int activeCount;
  final double principal;
  final double accruedInterest;
  final double totalDue;
  final double avgRate;
  final double collateralValue;
  final int collateralItemsCount;
  final VoidCallback onAddGiven;

  const _GivenPortfolioCard({
    required this.activeCount,
    required this.principal,
    required this.accruedInterest,
    required this.totalDue,
    required this.avgRate,
    required this.collateralValue,
    required this.collateralItemsCount,
    required this.onAddGiven,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.accentCyan.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.arrow_outward_rounded, color: AppTheme.accentCyan, size: 24),
                  SizedBox(width: 8),
                  Text(
                    'Given (Money Lent)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: AppTheme.badgeDecoration(AppTheme.accentCyan),
                child: Text(
                  '$activeCount Active Loans',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.accentCyan,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _MetricRow(
            label: 'Total Principal Lent',
            value: CurrencyFormatter.format(principal),
            color: AppTheme.accentCyan,
            icon: Icons.payments_outlined,
          ),
          const SizedBox(height: 10),
          _MetricRow(
            label: 'Accrued Interest Receivable',
            value: CurrencyFormatter.format(accruedInterest),
            color: AppTheme.gold,
            icon: Icons.trending_up_rounded,
          ),
          const SizedBox(height: 10),
          _MetricRow(
            label: 'Total Outstanding Receivable',
            value: CurrencyFormatter.format(totalDue),
            color: AppTheme.rose,
            isHighlight: true,
            icon: Icons.account_balance_wallet_outlined,
          ),
          const Divider(height: 24, color: AppTheme.borderDark),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Average Interest Rate', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              Text(
                '${avgRate.toStringAsFixed(1)}% / month',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Pledged Collateral Value', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              Text(
                '${CurrencyFormatter.format(collateralValue)} ($collateralItemsCount items)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.gold),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onAddGiven,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Loan Given'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.accentCyan,
                side: const BorderSide(color: AppTheme.accentCyan),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Detailed Portfolio Card for TAKEN (Money Borrowed)
class _TakenPortfolioCard extends StatelessWidget {
  final int activeCount;
  final double principal;
  final double accruedInterest;
  final double totalDue;
  final double avgRate;
  final VoidCallback onAddTaken;

  const _TakenPortfolioCard({
    required this.activeCount,
    required this.principal,
    required this.accruedInterest,
    required this.totalDue,
    required this.avgRate,
    required this.onAddTaken,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.emerald.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.arrow_downward_rounded, color: AppTheme.emerald, size: 24),
                  SizedBox(width: 8),
                  Text(
                    'Taken (Money Borrowed)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: AppTheme.badgeDecoration(AppTheme.emerald),
                child: Text(
                  '$activeCount Active Borrowings',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.emerald,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _MetricRow(
            label: 'Total Principal Borrowed',
            value: CurrencyFormatter.format(principal),
            color: AppTheme.emerald,
            icon: Icons.savings_outlined,
          ),
          const SizedBox(height: 10),
          _MetricRow(
            label: 'Accrued Interest Payable',
            value: CurrencyFormatter.format(accruedInterest),
            color: AppTheme.goldDark,
            icon: Icons.trending_up_rounded,
          ),
          const SizedBox(height: 10),
          _MetricRow(
            label: 'Total Outstanding Repayable',
            value: CurrencyFormatter.format(totalDue),
            color: AppTheme.emerald,
            isHighlight: true,
            icon: Icons.price_check_rounded,
          ),
          const Divider(height: 24, color: AppTheme.borderDark),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Average Borrowing Rate', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              Text(
                '${avgRate.toStringAsFixed(1)}% / month',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Settlement Priority', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              Text('Interest-First Rule', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.gold)),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onAddTaken,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Borrowing Taken'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.emerald,
                side: const BorderSide(color: AppTheme.emerald),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final bool isHighlight;

  const _MetricRow({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.isHighlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isHighlight ? color.withValues(alpha: 0.12) : AppTheme.subCardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHighlight ? color.withValues(alpha: 0.4) : AppTheme.borderDark,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isHighlight ? FontWeight.w600 : FontWeight.normal,
                  color: isHighlight ? Colors.white : AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Collateral Alerts Section (Drop Risk and Overshoot Warnings)
class _CollateralAlertsSection extends StatelessWidget {
  final DashboardViewModel viewModel;

  const _CollateralAlertsSection({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CollectionAlertCardData>>(
      stream: viewModel.collectionAlertCards,
      builder: (context, snapshot) {
        final cards = snapshot.data ?? viewModel.currentAlertCards;
        final hasAlerts = cards.any((c) => c.isTriggered);

        if (!hasAlerts) {
          return StreamBuilder<bool>(
            stream: viewModel.alertsLoaded,
            builder: (context, loadedSnap) {
              final loaded = loadedSnap.data ?? viewModel.isAlertsLoaded;
              if (!loaded) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: AppTheme.bannerDecoration(AppTheme.emerald),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: AppTheme.emerald, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'All active Given loans have healthy collateral coverage today',
                        style: TextStyle(color: AppTheme.emerald, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        }

        final alertCards = cards.where((c) => c.isTriggered).toList();

        return Container(
          decoration: AppTheme.bannerDecoration(AppTheme.gold, borderRadius: 16),
          child: ExpansionTile(
            initiallyExpanded: true,
            leading: const Icon(Icons.warning_amber_rounded, color: AppTheme.gold),
            title: Text(
              'Collateral Risk Alerts (${alertCards.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.gold),
            ),
            subtitle: const Text(
              'Live market price drop or projected 2-month interest overshoot',
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
    );
  }
}
