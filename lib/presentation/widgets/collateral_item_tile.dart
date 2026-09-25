import 'package:flutter/material.dart';
import '../../core/calculations/calculation_engine.dart';
import '../../core/ui/formatters/currency_formatter.dart';
import '../../core/ui/theme/app_theme.dart';
import '../../domain/models/item_rate.dart';
import '../../domain/models/ledger_item.dart';

/// A modern, responsive Collateral Item Display Card for Android and Windows.
///
/// Clearly presents all item attributes in clean, well-labeled columns:
/// - Gross Weight
/// - Purity % (with Karat indicator)
/// - Pure Fine Weight (Net Metal)
/// - Applied Lending Rate
/// - Total Market Valuation
/// - Max Lendable (LTV)
/// - Optional Live Market Drift (when [currentRates] are provided)
///
/// Supports inline [onEdit] and [onDelete] callbacks.
class CollateralItemTile extends StatelessWidget {
  final LedgerItem item;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final List<ItemRate>? currentRates;
  final bool showLiveDrift;

  const CollateralItemTile({
    super.key,
    required this.item,
    this.onEdit,
    this.onDelete,
    this.currentRates,
    this.showLiveDrift = false,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;
    final categoryColor = _getCategoryColor(item.itemCategory);
    final categoryIcon = _getCategoryIcon(item.itemCategory);

    // Live drift calculations (if requested)
    double? liveRate;
    double liveVal = 0.0;
    double valDiff = 0.0;
    double valDiffPct = 0.0;
    bool hasDrift = false;

    if (showLiveDrift && currentRates != null) {
      liveRate = CalculationEngine.getUsableRate(currentRates!, item.itemCategory);
      if (liveRate != null && liveRate > 0) {
        liveVal = CalculationEngine.calculateLiveItemValue(item, currentRates!);
        final lendingVal = item.itemValue > 0
            ? item.itemValue
            : CalculationEngine.calculateItemValue(item);
        if (lendingVal > 0 && liveVal != lendingVal) {
          valDiff = liveVal - lendingVal;
          valDiffPct = (valDiff / lendingVal) * 100.0;
          hasDrift = true;
        }
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.subCardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderDark, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Category Icon + Item Name + Category Badge + Actions
            Row(
              children: [
                // Metallic Category Icon
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: categoryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: categoryColor.withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: Icon(categoryIcon, size: 16, color: categoryColor),
                ),
                const SizedBox(width: 10),

                // Name & Purity Karat Hint
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: AppTheme.badgeDecoration(categoryColor, borderRadius: 4),
                        child: Text(
                          item.itemCategory.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: categoryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Edit Action
                if (onEdit != null)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.gold),
                    tooltip: 'Edit Item',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: onEdit,
                  ),

                // Delete Action
                if (onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.rose),
                    tooltip: 'Remove Item',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: onDelete,
                  ),
              ],
            ),

            // Description / Hallmark Notes (if provided)
            if (item.description != null && item.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Row(
                  children: [
                    const Icon(Icons.notes_rounded, size: 13, color: AppTheme.textMuted),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        item.description!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 10),

            // Metrics Columns: Responsive Grid for Android and Windows
            if (isWide)
              _buildDesktopColumnsBar(context, hasDrift, liveVal, valDiff, valDiffPct)
            else
              _buildMobileMetricsGrid(context, hasDrift, liveVal, valDiff, valDiffPct),
          ],
        ),
      ),
    );
  }

  /// Wide Screen / Desktop Layout: Horizontal Data Table Columns
  Widget _buildDesktopColumnsBar(
    BuildContext context,
    bool hasDrift,
    double liveVal,
    double valDiff,
    double valDiffPct,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderDark),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildColumnCell('Gross Weight', '${item.weight.toStringAsFixed(2)} g'),
          _buildColumnCell('Purity', '${item.purity.toStringAsFixed(1)}% ${_karatHint(item.purity)}'),
          _buildColumnCell('Pure Fine Wt', '${item.fineWeight.toStringAsFixed(2)} g', hint: 'Net metal'),
          _buildColumnCell('Applied Rate', item.rate > 0 ? '₹${item.rate.toStringAsFixed(0)} / g' : '-'),
          _buildColumnCell(
            'Valuation',
            CurrencyFormatter.format(item.itemValue),
            valueColor: AppTheme.gold,
            isBold: true,
          ),
          _buildColumnCell(
            'Max Lend (${item.lendPercentage.toStringAsFixed(0)}%)',
            CurrencyFormatter.format(item.lendableAmount),
            valueColor: AppTheme.emerald,
            isBold: true,
          ),
          if (hasDrift)
            _buildColumnCell(
              'Live Value',
              '${CurrencyFormatter.format(liveVal)} (${valDiff >= 0 ? "+" : ""}${valDiffPct.toStringAsFixed(1)}%)',
              valueColor: valDiff >= 0 ? AppTheme.emerald : AppTheme.rose,
              isBold: true,
            ),
        ],
      ),
    );
  }

  /// Mobile / Android Screen Layout: Structured, Compact Metric Pills Grid
  Widget _buildMobileMetricsGrid(
    BuildContext context,
    bool hasDrift,
    double liveVal,
    double valDiff,
    double valDiffPct,
  ) {
    return Column(
      children: [
        // Primary Specs Row (Gross Weight, Purity, Pure Fine Wt)
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                label: 'Gross Weight',
                value: '${item.weight.toStringAsFixed(2)} g',
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildMetricTile(
                label: 'Purity',
                value: '${item.purity.toStringAsFixed(1)}% ${_karatHint(item.purity)}',
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildMetricTile(
                label: 'Pure Metal',
                value: '${item.fineWeight.toStringAsFixed(2)} g',
                valueColor: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Financial Valuation Row (Applied Rate, Valuation, Max Lendable)
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                label: 'Applied Rate',
                value: item.rate > 0 ? '₹${item.rate.toStringAsFixed(0)}/g' : '-',
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildMetricTile(
                label: 'Market Valuation',
                value: CurrencyFormatter.format(item.itemValue),
                valueColor: AppTheme.gold,
                isBold: true,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildMetricTile(
                label: 'Max Lend (${item.lendPercentage.toStringAsFixed(0)}%)',
                value: CurrencyFormatter.format(item.lendableAmount),
                valueColor: AppTheme.emerald,
                isBold: true,
              ),
            ),
          ],
        ),

        // Live Market Drift Banner (if active)
        if (hasDrift) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (valDiff >= 0 ? AppTheme.emerald : AppTheme.rose).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: (valDiff >= 0 ? AppTheme.emerald : AppTheme.rose).withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      valDiff >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                      size: 14,
                      color: valDiff >= 0 ? AppTheme.emerald : AppTheme.rose,
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'Live Market Value:',
                      style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
                Text(
                  '${CurrencyFormatter.format(liveVal)} (${valDiff >= 0 ? "+" : ""}${CurrencyFormatter.format(valDiff)}, ${valDiff >= 0 ? "+" : ""}${valDiffPct.toStringAsFixed(1)}%)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: valDiff >= 0 ? AppTheme.emerald : AppTheme.rose,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    Color? valueColor,
    bool isBold = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMuted,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                color: valueColor ?? AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumnCell(
    String label,
    String value, {
    Color? valueColor,
    bool isBold = false,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMuted,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(width: 4),
              Text(
                '($hint)',
                style: const TextStyle(fontSize: 9, color: AppTheme.textMuted),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: valueColor ?? AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  static String _karatHint(double purity) {
    if ((purity - 91.6).abs() < 1.0) return '(22K)';
    if ((purity - 75.0).abs() < 1.0) return '(18K)';
    if ((purity - 99.9).abs() < 0.5) return '(24K)';
    if ((purity - 92.5).abs() < 0.5) return '(925)';
    return '';
  }

  static Color _getCategoryColor(String cat) {
    switch (cat.toUpperCase()) {
      case 'GOLD':
        return AppTheme.gold;
      case 'SILVER':
        return AppTheme.silver;
      case 'PLATINUM':
        return const Color(0xFF38BDF8); // Sky
      case 'BRONZE':
        return const Color(0xFFD97706); // Amber/Bronze
      case 'VEHICLE':
        return const Color(0xFF818CF8); // Indigo
      default:
        return AppTheme.textSecondary;
    }
  }

  static IconData _getCategoryIcon(String cat) {
    switch (cat.toUpperCase()) {
      case 'GOLD':
        return Icons.monetization_on_rounded;
      case 'SILVER':
        return Icons.shield_rounded;
      case 'PLATINUM':
        return Icons.diamond_rounded;
      case 'BRONZE':
        return Icons.military_tech_rounded;
      case 'VEHICLE':
        return Icons.directions_car_rounded;
      default:
        return Icons.category_rounded;
    }
  }
}
