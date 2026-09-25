import 'package:flutter/material.dart';
import '../../core/calculations/calculation_engine.dart';
import '../../core/ui/formatters/currency_formatter.dart';
import '../../core/ui/theme/app_theme.dart';
import '../../core/utils/uuid_generator.dart';
import '../../domain/models/item_rate.dart';
import '../../domain/models/ledger_item.dart';

/// A modern, responsive dialog for Adding or Editing Collateral Items.
///
/// Features:
/// - Supports both Add and Edit modes with live pre-filling.
/// - Metallic category selector with auto-fill from [currentRates].
/// - Quick purity presets (22K 91.6%, 18K 75%, 24K 99.9%, Silver 925, 100%).
/// - Live instant reactive valuation card (Fine weight, Market valuation, Max Lendable).
/// - Styled specifically for seamless use on both Android and Windows.
class AddEditCollateralDialog extends StatefulWidget {
  final LedgerItem? initialItem;
  final List<ItemRate> currentRates;
  final ValueChanged<LedgerItem> onSave;

  const AddEditCollateralDialog({
    super.key,
    this.initialItem,
    this.currentRates = const [],
    required this.onSave,
  });

  static Future<void> show(
    BuildContext context, {
    LedgerItem? initialItem,
    List<ItemRate> currentRates = const [],
    required ValueChanged<LedgerItem> onSave,
  }) async {
    final isWide = MediaQuery.of(context).size.width >= 700;

    if (isWide) {
      await showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: AppTheme.cardDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppTheme.borderDark, width: 1),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
            child: AddEditCollateralDialog(
              initialItem: initialItem,
              currentRates: currentRates,
              onSave: onSave,
            ),
          ),
        ),
      );
    } else {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppTheme.cardDark,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          side: BorderSide(color: AppTheme.borderDark, width: 1),
        ),
        builder: (ctx) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: FractionallySizedBox(
            heightFactor: 0.88,
            child: AddEditCollateralDialog(
              initialItem: initialItem,
              currentRates: currentRates,
              onSave: onSave,
            ),
          ),
        ),
      );
    }
  }

  @override
  State<AddEditCollateralDialog> createState() => _AddEditCollateralDialogState();
}

class _AddEditCollateralDialogState extends State<AddEditCollateralDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _weightCtrl;
  late final TextEditingController _purityCtrl;
  late final TextEditingController _rateCtrl;
  late final TextEditingController _lendPctCtrl;

  late String _category;

  @override
  void initState() {
    super.initState();
    final it = widget.initialItem;
    _category = it?.itemCategory ?? 'GOLD';
    _nameCtrl = TextEditingController(text: it?.name ?? '');
    _descCtrl = TextEditingController(text: it?.description ?? '');
    _weightCtrl = TextEditingController(text: it != null && it.weight > 0 ? it.weight.toString() : '');
    _purityCtrl = TextEditingController(
      text: it != null && it.purity > 0
          ? it.purity.toString()
          : (_category == 'GOLD' ? '91.6' : (_category == 'SILVER' ? '92.5' : '100')),
    );
    _rateCtrl = TextEditingController(text: it != null && it.rate > 0 ? it.rate.toString() : '');
    _lendPctCtrl = TextEditingController(
      text: it != null && it.lendPercentage > 0 ? it.lendPercentage.toString() : '75',
    );

    // If adding a new item and rate is empty, auto-fill from current rates
    if (it == null && _rateCtrl.text.isEmpty) {
      _autoFillRateForCategory(_category);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _weightCtrl.dispose();
    _purityCtrl.dispose();
    _rateCtrl.dispose();
    _lendPctCtrl.dispose();
    super.dispose();
  }

  void _autoFillRateForCategory(String category) {
    final live = CalculationEngine.getUsableRate(widget.currentRates, category);
    if (live != null && live > 0) {
      _rateCtrl.text = live.toStringAsFixed(0);
    }
  }

  void _selectCategory(String cat) {
    setState(() {
      _category = cat;
      if (cat == 'GOLD') {
        _purityCtrl.text = '91.6';
      } else if (cat == 'SILVER') {
        _purityCtrl.text = '92.5';
      }
      _autoFillRateForCategory(cat);
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtrl.text.trim();
    final weight = double.tryParse(_weightCtrl.text.trim()) ?? 0.0;
    final purity = double.tryParse(_purityCtrl.text.trim()) ?? 0.0;
    final rate = double.tryParse(_rateCtrl.text.trim()) ?? 0.0;
    final lendPct = double.tryParse(_lendPctCtrl.text.trim()) ?? 75.0;
    final desc = _descCtrl.text.trim();

    final effPurity = purity > 0 ? purity : 100.0;
    final fineWeight = weight * (effPurity / 100.0);
    final itemVal = CalculationEngine.roundMoney(fineWeight * rate);
    final lendable = CalculationEngine.roundMoney(itemVal * (lendPct / 100.0));

    final result = LedgerItem(
      id: widget.initialItem?.id ?? AppUuid.generate(),
      recordId: widget.initialItem?.recordId ?? '',
      name: name,
      itemCategory: _category,
      description: desc.isNotEmpty ? desc : null,
      weight: weight,
      purity: effPurity,
      rate: rate,
      itemValue: itemVal,
      lendPercentage: lendPct,
      lendableAmount: lendable,
      sourceItemId: widget.initialItem?.sourceItemId,
    );

    widget.onSave(result);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialItem != null;

    // Real-time calculation computation
    final w = double.tryParse(_weightCtrl.text.trim()) ?? 0.0;
    final p = double.tryParse(_purityCtrl.text.trim()) ?? 0.0;
    final r = double.tryParse(_rateCtrl.text.trim()) ?? 0.0;
    final lPct = double.tryParse(_lendPctCtrl.text.trim()) ?? 75.0;

    final effPurity = p > 0 ? p : 100.0;
    final fineWeight = w * (effPurity / 100.0);
    final itemVal = fineWeight * r;
    final maxLendable = itemVal * (lPct / 100.0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Drag handle for bottom sheet
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: AppTheme.handleDecoration,
            ),
          ),
          const SizedBox(height: 10),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.gold.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isEditing ? Icons.edit_note_rounded : Icons.add_circle_outline_rounded,
                        color: AppTheme.gold,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      isEditing ? 'Edit Collateral Item' : 'Add Collateral Item',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 12),

          // Form Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category Selection: GOLD or SILVER (Jewellery Business)
                    const Text(
                      'Jewellery Category *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => _selectCategory('GOLD'),
                            borderRadius: BorderRadius.circular(10),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                color: _category == 'GOLD'
                                    ? AppTheme.gold.withValues(alpha: 0.15)
                                    : AppTheme.subCardDark,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _category == 'GOLD'
                                      ? AppTheme.gold
                                      : AppTheme.borderDark,
                                  width: _category == 'GOLD' ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.monetization_on_rounded,
                                    size: 20,
                                    color: _category == 'GOLD'
                                        ? AppTheme.gold
                                        : AppTheme.textMuted,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'GOLD',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: _category == 'GOLD'
                                          ? AppTheme.gold
                                          : AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () => _selectCategory('SILVER'),
                            borderRadius: BorderRadius.circular(10),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                color: _category == 'SILVER'
                                    ? AppTheme.silver.withValues(alpha: 0.15)
                                    : AppTheme.subCardDark,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _category == 'SILVER'
                                      ? AppTheme.silver
                                      : AppTheme.borderDark,
                                  width: _category == 'SILVER' ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.circle_rounded,
                                    size: 18,
                                    color: _category == 'SILVER'
                                        ? AppTheme.silver
                                        : AppTheme.textMuted,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'SILVER',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: _category == 'SILVER'
                                          ? AppTheme.silver
                                          : AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Item Name
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Jewellery Item Name *',
                        hintText: _category == 'GOLD'
                            ? 'e.g. 22K Gold Chain, Ring, Bangle, Necklace'
                            : 'e.g. Silver Anklet (Payal), Utensil, Coin, Chain',
                        prefixIcon: Icon(
                          Icons.label_outline_rounded,
                          color: _category == 'GOLD' ? AppTheme.gold : AppTheme.silver,
                        ),
                      ),
                      validator: (val) =>
                          val == null || val.trim().isEmpty ? 'Please enter an item name' : null,
                    ),
                    const SizedBox(height: 12),

                    // Description / Remarks
                    TextFormField(
                      controller: _descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Description / Remarks (Optional)',
                        hintText: 'e.g. Hallmark 916, Gross 15g with 1.2g stones, Mint condition',
                        prefixIcon: Icon(Icons.notes_rounded, color: AppTheme.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Weight and Purity Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Gross Weight
                        Expanded(
                          child: TextFormField(
                            controller: _weightCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Gross Weight (g) *',
                              hintText: '0.00',
                              suffixText: 'g',
                            ),
                            onChanged: (_) => setState(() {}),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) return 'Enter weight';
                              final d = double.tryParse(val.trim());
                              if (d == null || d <= 0) return 'Must be > 0';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Purity %
                        Expanded(
                          child: TextFormField(
                            controller: _purityCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Purity (%) *',
                              hintText: _category == 'GOLD' ? '91.6' : '92.5',
                              suffixText: '%',
                            ),
                            onChanged: (_) => setState(() {}),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) return 'Enter purity';
                              final d = double.tryParse(val.trim());
                              if (d == null || d <= 0 || d > 100) return '0 to 100%';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Quick Purity Preset Pills (Dynamic for Gold / Silver)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          const Text('Presets: ',
                              style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                          if (_category == 'GOLD') ...[
                            _purityPill('22K (91.6%)', '91.6'),
                            const SizedBox(width: 5),
                            _purityPill('18K (75%)', '75.0'),
                            const SizedBox(width: 5),
                            _purityPill('24K (99.9%)', '99.9'),
                            const SizedBox(width: 5),
                            _purityPill('14K (58.5%)', '58.5'),
                          ] else ...[
                            _purityPill('92.5% (Sterling)', '92.5'),
                            const SizedBox(width: 5),
                            _purityPill('99.9% (Fine)', '99.9'),
                            const SizedBox(width: 5),
                            _purityPill('80.0%', '80.0'),
                            const SizedBox(width: 5),
                            _purityPill('70.0%', '70.0'),
                            const SizedBox(width: 5),
                            _purityPill('100%', '100'),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Applied Rate and LTV % Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Rate / g
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _rateCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Rate / gram (₹) *',
                              hintText: 'e.g. 6850',
                              prefixText: '₹ ',
                            ),
                            onChanged: (_) => setState(() {}),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) return 'Enter rate';
                              final d = double.tryParse(val.trim());
                              if (d == null || d <= 0) return 'Must be > 0';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Lend Percentage (LTV)
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _lendPctCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'LTV / Lend %',
                              hintText: '75',
                              suffixText: '%',
                            ),
                            onChanged: (_) => setState(() {}),
                            validator: (val) {
                              if (val != null && val.trim().isNotEmpty) {
                                final d = double.tryParse(val.trim());
                                if (d == null || d <= 0 || d > 100) return '0-100%';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Real-Time Live Valuation Preview Card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.subCardDark,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: itemVal > 0
                              ? AppTheme.gold.withValues(alpha: 0.4)
                              : AppTheme.borderDark,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.auto_graph_rounded, size: 14, color: AppTheme.gold),
                              SizedBox(width: 6),
                              Text(
                                'Calculated Item Valuation & Lending Limit',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildCalcColumn(
                                label: 'Pure Fine Weight',
                                value: '${fineWeight.toStringAsFixed(2)} g',
                                hint: 'Net metal',
                              ),
                              Container(width: 1, height: 28, color: AppTheme.borderDark),
                              _buildCalcColumn(
                                label: 'Market Valuation',
                                value: CurrencyFormatter.format(itemVal),
                                valueColor: AppTheme.gold,
                                isBold: true,
                              ),
                              Container(width: 1, height: 28, color: AppTheme.borderDark),
                              _buildCalcColumn(
                                label: 'Max Lend (${lPct.toStringAsFixed(0)}% LTV)',
                                value: CurrencyFormatter.format(maxLendable),
                                valueColor: AppTheme.emerald,
                                isBold: true,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: _submit,
                            icon: Icon(
                              isEditing ? Icons.check_circle_outline : Icons.add_circle_outline,
                              color: Colors.white,
                            ),
                            label: Text(
                              isEditing ? 'Update Collateral Item' : 'Add Collateral Item',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _purityPill(String label, String value) {
    final isSelected = _purityCtrl.text.trim() == value;
    return InkWell(
      onTap: () {
        setState(() {
          _purityCtrl.text = value;
        });
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.gold.withValues(alpha: 0.2) : AppTheme.cardDark,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? AppTheme.gold : AppTheme.borderDark,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? AppTheme.gold : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildCalcColumn({
    required String label,
    required String value,
    Color? valueColor,
    bool isBold = false,
    String? hint,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
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
}
