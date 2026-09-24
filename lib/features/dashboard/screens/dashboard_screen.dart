import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/calculations/calculations.dart';
import '../../../core/di/injection.dart';
import '../../../core/navigation/app_routes.dart' hide Settings;
import '../../../core/ui/formatters/currency_formatter.dart';
import '../../../core/ui/theme/app_theme.dart';
import '../../../domain/domain.dart';
import '../viewmodels/dashboard_viewmodel.dart';
import '../widgets/add_edit_record_bottom_sheet.dart';
import '../widgets/rate_management_card.dart';
import '../widgets/stale_rate_banner.dart';

/// Tab 1: Dashboard (§10.1).
///
/// Features mandated by §10.1:
/// - Top App Bar with search bar filtering records by customer name or transactionId.
/// - Rate Management Card (top of Dashboard, above tabs) with inline edits & M-10 FIX Add Category.
/// - Stale-rate yellow warning banner that scrolls up to Rate Management Card.
/// - Collection Alert Section with Risk Summary Header and Unified Alert Cards (§5.3 / §5.4 / [FIX-RISKVIEWMODEL-1]).
/// - Given / Taken toggle & summary cards via formatCurrency().
/// - Record List with [FIX-TIMESTAMP-RECORDLIST-1]: startDate formatted as DateFormat('dd/MM/yyyy, HH:mm').
/// - FloatingActionButton opening AddEditRecordBottomSheet with live rate auto-fill.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final DashboardViewModel _viewModel;
  final RecordRepository _recordRepository = sl<RecordRepository>();
  final SettingsRepository _settingsRepository = sl<SettingsRepository>();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  RecordType _currentTab = RecordType.GIVEN;
  Settings? _settings;
  String _searchQuery = '';
  bool _showSafeRecords = false;

  @override
  void initState() {
    super.initState();
    _viewModel = DashboardViewModel();
    _loadSettings();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  Future<void> _loadSettings() async {
    final s = await _settingsRepository.getSettingsOnce();
    if (mounted) setState(() => _settings = s);
  }

  @override
  void dispose() {
    _viewModel.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _scrollToRateManagementCard() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  void _openAddEditBottomSheet([RecordType? type]) async {
    final result = await AddEditRecordBottomSheet.show(
      context,
      initialType: type ?? _currentTab,
    );
    if (result == true && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: SizedBox(
          height: 42,
          child: TextField(
            controller: _searchController,
            style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search ${_settings?.name ?? "records"}, transaction ID...',
              hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: AppTheme.gold, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: AppTheme.textMuted, size: 18),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              filled: true,
              fillColor: AppTheme.subCardDark,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.borderDark),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.borderDark),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.gold),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'dashboard_fab',
        onPressed: () => _openAddEditBottomSheet(_currentTab),
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

            final allRecords = snapshot.data ?? [];
            final dashboardData = CalculationEngine.getDashboard(allRecords, today: DateTime.now().dateOnly);

            final givenRecords = allRecords.where((r) => r.isGiven).toList();
            final takenRecords = allRecords.where((r) => r.isTaken).toList();

            final currentRecords = _currentTab == RecordType.GIVEN ? givenRecords : takenRecords;
            final filteredRecords = _filterRecords(currentRecords, _searchQuery);

            final givenCount = givenRecords.length;
            final takenCount = takenRecords.length;

            final avgRateGiven = givenCount > 0
                ? (givenRecords.map((r) => r.interestRate).reduce((a, b) => a + b) / givenCount)
                : 0.0;
            final avgRateTaken = takenCount > 0
                ? (takenRecords.map((r) => r.interestRate).reduce((a, b) => a + b) / takenCount)
                : 0.0;

            final netPrincipal = dashboardData.totalPrincipalGiven - dashboardData.totalPrincipalTaken;
            final netDue = dashboardData.totalDueGiven - dashboardData.totalDueTaken;

            return LayoutBuilder(
              builder: (context, constraints) {
                return ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  children: [
                    // 1. Rate Management Card (top of Dashboard, above tabs)
                    RateManagementCard(viewModel: _viewModel),
                    const SizedBox(height: 12),

                    // 2. Stale-rate banner (before Risk Summary header)
                    StreamBuilder<ItemRate?>(
                      stream: _viewModel.oldestStaleRate,
                      builder: (context, staleSnap) {
                        final oldest = staleSnap.data ?? _viewModel.currentOldestStaleRate;
                        return StaleRateBanner(
                          oldestStaleRate: oldest,
                          onTap: _scrollToRateManagementCard,
                        );
                      },
                    ),
                    const SizedBox(height: 12),

                    // 3. Collection Alert Section (Risk Summary Header + Unified Cards)
                    _buildCollectionAlertSection(),
                    const SizedBox(height: 16),

                    // 4. Executive Net Position Summary Card
                    _NetPositionCard(
                      netPrincipal: netPrincipal,
                      netDue: netDue,
                      totalGivenPrincipal: dashboardData.totalPrincipalGiven,
                      totalTakenPrincipal: dashboardData.totalPrincipalTaken,
                      activeGivenCount: givenCount,
                      activeTakenCount: takenCount,
                    ),
                    const SizedBox(height: 16),

                    // 5. Given / Taken Toggle
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

                    // 6. Summary Cards for selected tab
                    if (_currentTab == RecordType.GIVEN)
                      _buildSummaryCards(
                        principal: dashboardData.totalPrincipalGiven,
                        interest: dashboardData.totalInterestAccruedGiven,
                        totalDue: dashboardData.totalDueGiven,
                        avgRate: avgRateGiven,
                        color: AppTheme.accentCyan,
                      )
                    else
                      _buildSummaryCards(
                        principal: dashboardData.totalPrincipalTaken,
                        interest: dashboardData.totalInterestAccruedTaken,
                        totalDue: dashboardData.totalDueTaken,
                        avgRate: avgRateTaken,
                        color: AppTheme.emerald,
                      ),
                    const SizedBox(height: 20),

                    // 7. Record List Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _currentTab == RecordType.GIVEN ? 'Active Loans Given' : 'Active Borrowings Taken',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          '${filteredRecords.length} records',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // 8. Record List Items with [FIX-TIMESTAMP-RECORDLIST-1]
                    if (filteredRecords.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        alignment: Alignment.center,
                        child: Text(
                          _searchQuery.isNotEmpty
                              ? 'No records matching "$_searchQuery"'
                              : 'No active ${_currentTab == RecordType.GIVEN ? 'given loans' : 'taken borrowings'}',
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredRecords.length,
                        itemBuilder: (context, index) {
                          final record = filteredRecords[index];
                          return _buildRecordRow(record);
                        },
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  List<LedgerRecord> _filterRecords(List<LedgerRecord> records, String query) {
    final list = query.isEmpty
        ? List<LedgerRecord>.from(records)
        : records.where((r) {
            final nameMatch = (r.customerName ?? '').toLowerCase().contains(query);
            final txnMatch = r.transactionId.toLowerCase().contains(query);
            final idMatch = r.customerId.toLowerCase().contains(query);
            return nameMatch || txnMatch || idMatch;
          }).toList();
    // [FIX-TIMESTAMP-RECORDLIST-1] (revised v1.15) Rows are ordered by startDate descending
    // (date, then time-of-day), so a backdated record sits at its real position in time.
    list.sort((a, b) => b.startDate.compareTo(a.startDate));
    return list;
  }

  Widget _buildSummaryCards({
    required double principal,
    required double interest,
    required double totalDue,
    required double avgRate,
    required Color color,
  }) {
    return Row(
      children: [
        Expanded(
          child: _StatMiniCard(
            label: 'Principal',
            value: CurrencyFormatter.format(principal),
            color: color,
            icon: Icons.payments_outlined,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatMiniCard(
            label: 'Interest',
            value: CurrencyFormatter.format(interest),
            color: AppTheme.gold,
            icon: Icons.trending_up_rounded,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatMiniCard(
            label: 'Total Due',
            value: CurrencyFormatter.format(totalDue),
            color: AppTheme.rose,
            icon: Icons.account_balance_wallet_outlined,
          ),
        ),
      ],
    );
  }

  /// Record Row with [FIX-TIMESTAMP-RECORDLIST-1] (revised v1.15)
  /// Each record row shows its transaction date with formatDate(startDate) — e.g. "20 September 2026"
  Widget _buildRecordRow(LedgerRecord record) {
    final formattedDate = formatDate(record.startDate);
    final todayDate = DateTime.now().dateOnly;
    final financials = calculateRecordFinancials(record, todayDate);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderDark),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: () {
          AppNavigator.navigate(
            context,
            RecordDetailRoute(record.id, record: record),
          );
        },
        title: Row(
          children: [
            Expanded(
              child: Text(
                record.customerName ?? 'Customer',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.subCardDark,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppTheme.borderDark),
              ),
              child: Text(
                record.transactionId,
                style: const TextStyle(fontSize: 11, color: AppTheme.gold, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // [FIX-TIMESTAMP-RECORDLIST-1] (revised v1.15) Transaction date via formatDate(startDate)
              Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 14, color: AppTheme.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    formattedDate,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '•  ${record.interestRate.toStringAsFixed(1)}%/mo',
                    style: const TextStyle(fontSize: 12, color: AppTheme.gold),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Principal: ${CurrencyFormatter.format(record.principalAmount)}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  Text(
                    'Due: ${CurrencyFormatter.format(financials.totalDue)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.rose,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
      ),
    ),
  );
  }

  /// Collection Alert Section (§10.1 & §5.3/§5.4)
  Widget _buildCollectionAlertSection() {
    return StreamBuilder<List<RecordRisk>>(
      stream: _viewModel.recordRisks,
      builder: (context, snapshot) {
        final risks = snapshot.data ?? _viewModel.currentRecordRisks;
        final summary = _viewModel.currentRiskSummary;

        final atRiskList = risks.where((r) => r.atRisk).toList();
        final safeList = risks.where((r) => !r.atRisk).toList();

        return Container(
          decoration: BoxDecoration(
            color: AppTheme.cardDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: summary.allSafe
                  ? AppTheme.emerald.withValues(alpha: 0.3)
                  : AppTheme.rose.withValues(alpha: 0.4),
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Risk Summary Header (always visible)
              _buildRiskSummaryHeader(summary),

              // Unified alert cards for at-risk records
              if (atRiskList.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...atRiskList.map((risk) => _buildUnifiedRiskCard(risk)),
              ],

              // Safe records collapsible toggle
              if (safeList.isNotEmpty) ...[
                const SizedBox(height: 10),
                InkWell(
                  onTap: () => setState(() => _showSafeRecords = !_showSafeRecords),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: Row(
                      children: [
                        Icon(
                          _showSafeRecords ? Icons.expand_less : Icons.expand_more,
                          color: AppTheme.emerald,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _showSafeRecords
                              ? 'Hide safe records'
                              : 'Show all ${safeList.length} safe records',
                          style: const TextStyle(
                            color: AppTheme.emerald,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showSafeRecords) ...[
                  const SizedBox(height: 6),
                  ...safeList.map((risk) => _buildUnifiedRiskCard(risk)),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildRiskSummaryHeader(RiskSummary summary) {
    if (summary.allSafe) {
      return const Row(
        children: [
          Icon(Icons.check_circle_outline, color: AppTheme.emerald, size: 20),
          SizedBox(width: 8),
          Text(
            'All records safe today',
            style: TextStyle(
              color: AppTheme.emerald,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      );
    }

    final exposureFormatted = CurrencyFormatter.format(summary.totalExposure);
    return Row(
      children: [
        const Icon(Icons.warning_amber_rounded, color: AppTheme.rose, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${summary.atRiskCount} customer${summary.atRiskCount == 1 ? '' : 's'} at risk today · $exposureFormatted total exposure',
            style: const TextStyle(
              color: AppTheme.rose,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  /// Unified Alert Card per RecordRisk (§10.1 & [FIX-RATEMISSING-DISPLAY-1])
  Widget _buildUnifiedRiskCard(RecordRisk risk) {
    final isTriggered = risk.atRisk;
    final cardBg = isTriggered
        ? AppTheme.rose.withValues(alpha: 0.08)
        : AppTheme.subCardDark;
    final borderColor = isTriggered
        ? AppTheme.rose.withValues(alpha: 0.35)
        : AppTheme.borderDark;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // (1) Header row: customer name + customer ID + transactionId
          Row(
            children: [
              Expanded(
                child: Text(
                  risk.record.customerName ?? 'Customer',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Text(
                '${risk.record.customerId} • ${risk.record.transactionId}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // (2) Collateral row
          Row(
            children: [
              Expanded(
                child: _buildRiskCollateralContent(risk),
              ),
              const SizedBox(width: 8),
              if (risk.collateralDrop)
                const Icon(Icons.warning_amber_rounded, color: AppTheme.gold, size: 18)
              else
                const Icon(Icons.check_circle_rounded, color: AppTheme.emerald, size: 18),
            ],
          ),
          const SizedBox(height: 6),

          // (3) Projection row
          Row(
            children: [
              Expanded(
                child: Text(
                  'Due in 2 months: ${CurrencyFormatter.format(risk.projectedOutstanding)} → Item value at lending: ${CurrencyFormatter.format(risk.itemValueAtLending)}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(width: 8),
              if (risk.overshoot)
                const Icon(Icons.error_outline_rounded, color: AppTheme.rose, size: 18)
              else
                const Icon(Icons.check_circle_rounded, color: AppTheme.emerald, size: 18),
            ],
          ),

          // (4) Action line: "Contact customer now."
          if (isTriggered) ...[
            const SizedBox(height: 8),
            const Text(
              'Contact customer now.',
              style: TextStyle(
                color: AppTheme.rose,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRiskCollateralContent(RecordRisk risk) {
    if (!risk.hasCollateral) {
      return Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'No collateral',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Due today: ${CurrencyFormatter.format(risk.totalDue)}',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      );
    }

    if (risk.currentCollateralValue == null) {
      return Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final cat in risk.missingRateCategories)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.gold.withValues(alpha: 0.5)),
              ),
              child: Text(
                'Rate missing for $cat',
                style: const TextStyle(fontSize: 11, color: AppTheme.gold, fontWeight: FontWeight.w600),
              ),
            ),
          Text(
            'Due today: ${CurrencyFormatter.format(risk.totalDue)}',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      );
    }

    return Text(
      'Collateral today: ${CurrencyFormatter.format(risk.currentCollateralValue!)} → Due today: ${CurrencyFormatter.format(risk.totalDue)}',
      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
    );
  }
}

class _StatMiniCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _StatMiniCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderDark),
      ),
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
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ],
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
