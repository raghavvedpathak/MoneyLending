import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../formatters/currency_formatter.dart';
import 'app_theme.dart';

export '../formatters/currency_formatter.dart';
export 'app_theme.dart';

/// Central UI/UX System for MoneyLending.
///
/// Serves as the Single Source of Truth for:
/// - Reusable high-contrast components
/// - Micro-interactions & 1-tap quick actions
/// - Tabular financial typography
/// - Consistent visual hierarchy and tone
class AppUi {
  AppUi._();

  // ===========================================================================
  // TYPOGRAPHY & TABULAR FINANCIAL NUMBERS
  // ===========================================================================

  /// Applies tabular figures so numbers and currencies align neatly vertically.
  static const TextStyle tabularFigures = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Currency amount style with tabular figures.
  static TextStyle currencyStyle({
    double fontSize = 16,
    FontWeight fontWeight = FontWeight.w700,
    Color color = AppTheme.textPrimary,
  }) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: -0.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  /// Section heading style.
  static const TextStyle sectionHeading = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: AppTheme.textPrimary,
  );

  /// Subtle helper / caption style.
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppTheme.textSecondary,
  );
}

// =============================================================================
// 1. REUSABLE CONTAINER SURFACES
// =============================================================================

/// Standard 1px bordered card with luxury elevation and optional tap action.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderRadius;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final border = Border.all(
      color: borderColor ?? AppTheme.borderDark,
      width: 1,
    );

    final card = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppTheme.cardDark,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );

    return card;
  }
}

/// Recessed Slate-100 container for secondary groupings, form sections, or sub-tables.
class AppSubCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? borderColor;
  final double borderRadius;
  final VoidCallback? onTap;

  const AppSubCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin,
    this.borderColor,
    this.borderRadius = 10,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: AppTheme.subCardDark,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: borderColor ?? AppTheme.borderDark,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// 2. STAT & METRIC CARDS
// =============================================================================

/// Unified Executive KPI Card for Dashboard, Customer Detail, and Reports.
class AppStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData? icon;
  final Color accentColor;
  final String? subtitle;
  final Widget? trailingBadge;
  final VoidCallback? onTap;

  const AppStatCard({
    super.key,
    required this.title,
    required this.value,
    this.icon,
    this.accentColor = AppTheme.gold,
    this.subtitle,
    this.trailingBadge,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(icon, size: 13, color: accentColor),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ?trailingBadge,
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppUi.currencyStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: accentColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// 3. STATUS BADGES & PILLS
// =============================================================================

/// Standardized high-contrast status badge.
class AppStatusBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  const AppStatusBadge({
    super.key,
    required this.label,
    this.icon,
    required this.color,
    this.borderRadius = 6,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  });

  factory AppStatusBadge.active({String label = 'Active'}) {
    return AppStatusBadge(
      label: label,
      icon: Icons.check_circle_outline_rounded,
      color: AppTheme.emerald,
    );
  }

  factory AppStatusBadge.settled({String label = 'Settled'}) {
    return AppStatusBadge(
      label: label,
      icon: Icons.done_all_rounded,
      color: AppTheme.silver,
    );
  }

  factory AppStatusBadge.overdue({String? label}) {
    return AppStatusBadge(
      label: label ?? 'Overdue 30d+',
      icon: Icons.schedule_rounded,
      color: AppTheme.rose,
    );
  }

  factory AppStatusBadge.risk({required String label}) {
    return AppStatusBadge(
      label: label,
      icon: Icons.warning_amber_rounded,
      color: AppTheme.rose,
    );
  }

  factory AppStatusBadge.warning({required String label}) {
    return AppStatusBadge(
      label: label,
      icon: Icons.info_outline_rounded,
      color: AppTheme.gold,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: color.withValues(alpha: 0.28),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 4. 1-TAP QUICK ACTION CHIPS
// =============================================================================

/// Modern 1-tap interactive preset chip (e.g. "Pay Interest", "Full Settle").
class AppQuickChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final VoidCallback onPressed;
  final bool isSelected;

  const AppQuickChip({
    super.key,
    required this.label,
    this.icon,
    this.color = AppTheme.gold,
    required this.onPressed,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? color : color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? color : color.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 13,
                  color: isSelected ? Colors.white : color,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// 5. LIVE LTV (LOAN-TO-VALUE) COLLATERAL HEALTH BAR
// =============================================================================

/// Real-time visual progress bar indicating collateral safety vs loan risk.
class AppLtvBar extends StatelessWidget {
  final double principal;
  final double collateralValue;

  const AppLtvBar({
    super.key,
    required this.principal,
    required this.collateralValue,
  });

  @override
  Widget build(BuildContext context) {
    if (collateralValue <= 0) {
      return const SizedBox.shrink();
    }

    final ltv = (principal / collateralValue) * 100.0;
    final clampedRatio = (ltv / 100.0).clamp(0.0, 1.0);

    Color barColor;
    String statusText;
    IconData statusIcon;

    if (ltv <= 75.0) {
      barColor = AppTheme.emerald;
      final cushion = collateralValue - principal;
      statusText = 'Safe Margin • Cushion: ${CurrencyFormatter.format(cushion)}';
      statusIcon = Icons.shield_outlined;
    } else if (ltv <= 90.0) {
      barColor = AppTheme.gold;
      statusText = 'Moderate Margin • Approaching 90%';
      statusIcon = Icons.info_outline;
    } else {
      barColor = AppTheme.rose;
      final deficit = principal - collateralValue;
      statusText = deficit > 0
          ? 'Under-collateralized by ${CurrencyFormatter.format(deficit)}'
          : 'High Risk • LTV > 90%';
      statusIcon = Icons.warning_amber_rounded;
    }

    return AppSubCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(statusIcon, size: 14, color: barColor),
                  const SizedBox(width: 6),
                  Text(
                    'Loan-To-Value (LTV): ${ltv.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: barColor,
                    ),
                  ),
                ],
              ),
              Text(
                'Collateral: ${CurrencyFormatter.format(collateralValue)}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: clampedRatio,
              minHeight: 6,
              backgroundColor: AppTheme.borderDark,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: barColor,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 6. SECTION HEADER & EMPTY STATE
// =============================================================================

/// Standardized section title with optional count pill and trailing action.
class AppSectionHeader extends StatelessWidget {
  final String title;
  final int? count;
  final Widget? trailing;

  const AppSectionHeader({
    super.key,
    required this.title,
    this.count,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: AppUi.sectionHeading),
              if (count != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.subCardDark,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.borderDark),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Clean zero-data empty state with icon, title, description, and action button.
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: AppTheme.gold),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            if (description != null) ...[
              const SizedBox(height: 6),
              Text(
                description!,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add, size: 16),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// 7. CONFIRMATION DIALOG
// =============================================================================

/// Standardized Confirmation Dialog with clean human-centered language.
class AppConfirmDialog {
  AppConfirmDialog._();

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool isDestructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(
          message,
          style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancelLabel),
          ),
          ElevatedButton(
            style: isDestructive
                ? ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.rose,
                    foregroundColor: Colors.white,
                  )
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );

    return result ?? false;
  }
}

// =============================================================================
// 8. PAYMENT RECEIPT VOUCHER & SHARE DIALOG
// =============================================================================

/// Displays a payment confirmation receipt with 1-tap WhatsApp/Text sharing.
class AppReceiptDialog {
  AppReceiptDialog._();

  static Future<void> show(
    BuildContext context, {
    required String customerName,
    required String transactionId,
    required double amountPaid,
    required double interestPaid,
    required double principalPaid,
    required double remainingPrincipal,
    required double remainingInterest,
    required DateTime paymentDate,
    String? notes,
  }) async {
    final formattedDate =
        '${paymentDate.day.toString().padLeft(2, '0')}/${paymentDate.month.toString().padLeft(2, '0')}/${paymentDate.year}';

    final shareText = '''
🧾 PAYMENT RECEIPT
Customer: $customerName
Transaction ID: $transactionId
Date: $formattedDate
----------------------------------------
Amount Received: ${CurrencyFormatter.format(amountPaid)}
• Interest Cleared: ${CurrencyFormatter.format(interestPaid)}
• Principal Reduced: ${CurrencyFormatter.format(principalPaid)}
----------------------------------------
Remaining Balance:
• Principal: ${CurrencyFormatter.format(remainingPrincipal)}
• Total Due: ${CurrencyFormatter.format(remainingPrincipal + remainingInterest)}
${notes != null && notes.isNotEmpty ? '\nNote: $notes' : ''}
----------------------------------------
Thank you!
'''.trim();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.emerald.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.check_circle_rounded, color: AppTheme.emerald, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Payment Recorded', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSubCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Paid:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                      Text(
                        CurrencyFormatter.format(amountPaid),
                        style: AppUi.currencyStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.emerald),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Interest Cleared:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      Text(
                        CurrencyFormatter.format(interestPaid),
                        style: AppUi.currencyStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.gold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Principal Reduced:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      Text(
                        CurrencyFormatter.format(principalPaid),
                        style: AppUi.currencyStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.accentCyan),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Remaining Balance:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
                      Text(
                        CurrencyFormatter.format(remainingPrincipal + remainingInterest),
                        style: AppUi.currencyStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.emerald,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.share_rounded, size: 16),
            label: const Text('Share Receipt'),
            onPressed: () async {
              try {
                // ignore: deprecated_member_use
                await Share.share(shareText, subject: 'Payment Receipt - $transactionId');
              } catch (_) {}
            },
          ),
        ],
      ),
    );
  }
}

