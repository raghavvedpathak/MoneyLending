import 'package:flutter/material.dart';
import '../../../core/ui/theme/app_theme.dart';
import '../../../domain/domain.dart';

/// Stale-rate warning banner (§10.1).
///
/// Mandated by Screen Inventory §10.1:
/// - Shown before the Risk Summary header when any category has effectiveDate < today
///   or ratePerUnit == 0.0.
/// - Full-width yellow warning banner:
///   "Some rates were last updated on [oldest effectiveDate among current rates]. Update today's rates for accurate alerts."
/// - Tapping the banner scrolls the user up to the Rate Management Card.
/// - Never blocks or disables alert cards.
class StaleRateBanner extends StatelessWidget {
  final ItemRate? oldestStaleRate;
  final VoidCallback? onTap;

  const StaleRateBanner({
    super.key,
    required this.oldestStaleRate,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (oldestStaleRate == null) {
      return const SizedBox.shrink();
    }

    final dateStr = oldestStaleRate!.formattedEffectiveDate;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.goldDark.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.goldDark.withValues(alpha: 0.5), width: 1),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppTheme.goldDark, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Some rates were last updated on $dateStr. Update today’s rates for accurate alerts.',
                  style: const TextStyle(
                    color: AppTheme.goldDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_upward_rounded, color: AppTheme.goldDark, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
