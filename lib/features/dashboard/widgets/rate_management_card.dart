import 'package:flutter/material.dart';
import '../../../core/ui/theme/app_theme.dart';
import '../../../domain/domain.dart';
import '../viewmodels/dashboard_viewmodel.dart';

/// Rate Management Card (top of Dashboard, above tabs) (§10.1).
///
/// Mandated by Screen Inventory §10.1:
/// - Shows today's live rate for every item category.
/// - Loads rates via [ItemRateRepository.watchCurrentRates()] stream for real-time updates.
/// - Each row: category name + inline editable ratePerUnit + "Update" button.
/// - M-10 FIX: "Add Category" row at bottom with category name text field and "+" button.
/// - [FIX-RATE-USABLE-1]: Rate of 0.0 displays as "Not set" (never "₹0.00").
/// - Inline error validation beneath each row.
class RateManagementCard extends StatefulWidget {
  final DashboardViewModel viewModel;

  const RateManagementCard({
    super.key,
    required this.viewModel,
  });

  @override
  State<RateManagementCard> createState() => _RateManagementCardState();
}

class _RateManagementCardState extends State<RateManagementCard> {
  final TextEditingController _newCategoryController = TextEditingController();
  String? _addCategoryError;
  bool _isAdding = false;

  final Map<String, TextEditingController> _rateControllers = {};
  final Map<String, String?> _rateErrors = {};
  final Map<String, bool> _isUpdating = {};

  @override
  void dispose() {
    _newCategoryController.dispose();
    for (final c in _rateControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _getControllerForCategory(String category, double rate) {
    if (!_rateControllers.containsKey(category)) {
      // 0.0 displays as "" in editing mode or "Not set" placeholder
      _rateControllers[category] = TextEditingController(
        text: rate > 0.0 ? rate.toStringAsFixed(rate.truncateToDouble() == rate ? 0 : 2) : '',
      );
    }
    return _rateControllers[category]!;
  }

  Future<void> _handleUpdateRate(String category) async {
    final controller = _rateControllers[category];
    if (controller == null) return;

    final text = controller.text.trim();
    final parsed = double.tryParse(text);

    if (parsed == null || parsed <= 0.0) {
      setState(() {
        _rateErrors[category] = 'Rate must be greater than zero';
      });
      return;
    }

    setState(() {
      _rateErrors[category] = null;
      _isUpdating[category] = true;
    });

    final error = await widget.viewModel.updateCategoryRate(category, parsed);

    if (mounted) {
      setState(() {
        _isUpdating[category] = false;
        _rateErrors[category] = error;
      });

      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Updated $category rate to ₹$text/g for today'),
            backgroundColor: AppTheme.emerald,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _handleAddCategory() async {
    final name = _newCategoryController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _addCategoryError = 'Category name cannot be blank';
      });
      return;
    }

    setState(() {
      _addCategoryError = null;
      _isAdding = true;
    });

    final error = await widget.viewModel.addCategory(name);

    if (mounted) {
      setState(() {
        _isAdding = false;
        _addCategoryError = error;
        if (error == null) {
          _newCategoryController.clear();
        }
      });

      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added category "$name" with rate "Not set"'),
            backgroundColor: AppTheme.emerald,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.price_change_outlined, color: AppTheme.gold, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Today's Collateral Rates",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      'Live market valuation benchmark per unit',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppTheme.borderDark),
          const SizedBox(height: 12),

          // Rates list via watchCurrentRates() stream
          StreamBuilder<List<ItemRate>>(
            stream: widget.viewModel.watchCurrentRates(),
            builder: (context, snapshot) {
              final rates = snapshot.data ?? [];

              if (rates.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text(
                      'No categories defined yet. Add one below.',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                    ),
                  ),
                );
              }

              return Column(
                children: rates.map((rate) => _buildRateRow(rate)).toList(),
              );
            },
          ),

          const SizedBox(height: 8),
          const Divider(height: 1, color: AppTheme.borderDark),
          const SizedBox(height: 12),

          // M-10 FIX: Add new category row
          _buildAddCategoryRow(),
        ],
      ),
    );
  }

  Widget _buildRateRow(ItemRate rate) {
    final category = rate.itemCategory;
    final controller = _getControllerForCategory(category, rate.ratePerUnit);
    final error = _rateErrors[category];
    final isBusy = _isUpdating[category] ?? false;
    final isNotSet = rate.ratePerUnit <= 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Category badge & name
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (isNotSet)
                      const Text(
                        'Not set yet',
                        style: TextStyle(fontSize: 11, color: AppTheme.goldDark),
                      )
                    else
                      Text(
                        'Updated: ${rate.formattedEffectiveDate}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                  ],
                ),
              ),

              // Rate text field (editable inline)
              Expanded(
                flex: 4,
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      prefixText: '₹ ',
                      prefixStyle: const TextStyle(color: AppTheme.gold, fontWeight: FontWeight.bold),
                      hintText: isNotSet ? 'Not set' : 'Rate / g',
                      hintStyle: TextStyle(
                        color: isNotSet ? AppTheme.gold.withValues(alpha: 0.8) : AppTheme.textMuted,
                        fontStyle: isNotSet ? FontStyle.italic : FontStyle.normal,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      filled: true,
                      fillColor: AppTheme.subCardDark,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppTheme.borderDark),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: error != null ? AppTheme.rose : AppTheme.borderDark,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppTheme.gold),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // "Update" button
              SizedBox(
                height: 40,
                child: FilledButton(
                  onPressed: isBusy ? null : () => _handleUpdateRate(category),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.gold,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: isBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'Update',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                ),
              ),
            ],
          ),

          // Inline validation error
          if (error != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                error,
                style: const TextStyle(color: AppTheme.rose, fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAddCategoryRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: _newCategoryController,
                  style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'New category name (e.g. PLATINUM, BRONZE)',
                    hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    filled: true,
                    fillColor: AppTheme.subCardDark,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.borderDark),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: _addCategoryError != null ? AppTheme.rose : AppTheme.borderDark,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.gold),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 40,
              width: 48,
              child: FilledButton(
                onPressed: _isAdding ? null : _handleAddCategory,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accentCyan,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _isAdding
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.add, size: 22),
              ),
            ),
          ],
        ),
        if (_addCategoryError != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              _addCategoryError!,
              style: const TextStyle(color: AppTheme.rose, fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ],
    );
  }
}
