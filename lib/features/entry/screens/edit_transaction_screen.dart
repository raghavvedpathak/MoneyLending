import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';
import '../../../core/ui/formatters/currency_formatter.dart';
import '../../../core/ui/theme/app_theme.dart';
import '../../../core/utils/app_date_formatter.dart';
import '../../../core/utils/uuid_generator.dart';
import '../../../domain/domain.dart';

/// Screen allowing moneylenders to edit and update an existing transaction.
class EditTransactionScreen extends StatefulWidget {
  final LedgerRecord record;

  const EditTransactionScreen({super.key, required this.record});

  @override
  State<EditTransactionScreen> createState() => _EditTransactionScreenState();
}

class _EditTransactionScreenState extends State<EditTransactionScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _principalController;
  late final TextEditingController _interestRateController;
  late DateTime _startDate;
  DateTime? _endDate;
  late RecordStatus _status;
  late List<LedgerItem> _items;

  // Controllers for adding a collateral item
  final _itemNameController = TextEditingController();
  final _itemWeightController = TextEditingController();
  final _itemPurityController = TextEditingController();
  final _itemRateController = TextEditingController();
  String _itemCategory = 'GOLD';

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    _principalController = TextEditingController(text: r.principalAmount.toStringAsFixed(2));
    _interestRateController = TextEditingController(text: r.interestRate.toStringAsFixed(1));
    _startDate = r.startDate;
    _endDate = r.endDate;
    _status = r.status;
    _items = List<LedgerItem>.from(r.items);
  }

  @override
  void dispose() {
    _principalController.dispose();
    _interestRateController.dispose();
    _itemNameController.dispose();
    _itemWeightController.dispose();
    _itemPurityController.dispose();
    _itemRateController.dispose();
    super.dispose();
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _startDate = picked);
    }
  }

  Future<void> _selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now(),
      firstDate: _startDate,
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _endDate = picked);
    }
  }

  void _showAddCollateralDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Collateral Item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _itemNameController,
                  decoration: const InputDecoration(
                    labelText: 'Item Name * (e.g. Gold Ring)',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('edit_category_$_itemCategory'),
                  initialValue: _itemCategory,
                  isExpanded: true,
                  dropdownColor: AppTheme.cardDark,
                  menuMaxHeight: 350,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                  icon: const Icon(Icons.arrow_drop_down, color: AppTheme.gold),
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: const [
                    DropdownMenuItem(value: 'GOLD', child: Text('Gold', style: TextStyle(color: AppTheme.textPrimary))),
                    DropdownMenuItem(value: 'SILVER', child: Text('Silver', style: TextStyle(color: AppTheme.textPrimary))),
                    DropdownMenuItem(value: 'BRONZE', child: Text('Bronze', style: TextStyle(color: AppTheme.textPrimary))),
                    DropdownMenuItem(value: 'VEHICLE', child: Text('Vehicle / Property', style: TextStyle(color: AppTheme.textPrimary))),
                    DropdownMenuItem(value: 'OTHER', child: Text('Other', style: TextStyle(color: AppTheme.textPrimary))),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => _itemCategory = val);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _itemWeightController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Weight (g)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _itemPurityController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Purity (%)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _itemRateController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Rate per gram (₹)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = _itemNameController.text.trim();
                final weight = double.tryParse(_itemWeightController.text.trim()) ?? 0.0;
                final purity = double.tryParse(_itemPurityController.text.trim()) ?? 0.0;
                final rate = double.tryParse(_itemRateController.text.trim()) ?? 0.0;

                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter an item name')),
                  );
                  return;
                }

                final itemValue = weight > 0 && rate > 0 ? weight * rate : 0.0;
                final newItem = LedgerItem(
                  id: AppUuid.generate(),
                  recordId: widget.record.id,
                  name: name,
                  itemCategory: _itemCategory,
                  weight: weight > 0 ? weight : 0.0,
                  purity: purity > 0 ? purity : 0.0,
                  rate: rate > 0 ? rate : 0.0,
                  itemValue: itemValue > 0 ? itemValue : 0.0,
                  lendPercentage: 75.0,
                  lendableAmount: itemValue > 0 ? itemValue * 0.75 : 0.0,
                );

                setState(() {
                  _items.add(newItem);
                  _itemNameController.clear();
                  _itemWeightController.clear();
                  _itemPurityController.clear();
                  _itemRateController.clear();
                });
                Navigator.of(ctx).pop();
              },
              child: const Text('Add Item'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    final principal = double.tryParse(_principalController.text.trim()) ?? 0.0;
    final rate = double.tryParse(_interestRateController.text.trim()) ?? 0.0;

    if (principal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Principal amount must be greater than 0')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final updatedRecord = widget.record.copyWith(
        principalAmount: principal,
        interestRate: rate,
        startDate: _startDate,
        endDate: _endDate,
        status: _status,
        items: _items,
      );

      await sl<RecordRepository>().updateRecord(updatedRecord);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppTheme.successSnackBar('Transaction ${widget.record.transactionId} updated!'),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          AppTheme.errorSnackBar('Error updating transaction: $e'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final isGiven = r.type == RecordType.GIVEN;

    return Scaffold(
      appBar: AppBar(
        title: Text('Edit ${r.transactionId}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check_rounded),
            tooltip: 'Save Changes',
            onPressed: _isSaving ? null : _saveChanges,
          ),
        ],
      ),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Customer Header Card (Read-only)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: AppTheme.subCardDecoration,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'CUSTOMER',
                              style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              r.customerName ?? 'Customer',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: AppTheme.badgeDecoration(isGiven ? AppTheme.accentCyan : AppTheme.emerald),
                          child: Text(
                            isGiven ? 'LOAN GIVEN' : 'LOAN TAKEN',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isGiven ? AppTheme.accentCyan : AppTheme.emerald,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Loan Financials: Principal & Interest Rate
                  const Text('Financial Terms', style: AppTheme.sectionHeaderStyle),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _principalController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Principal Amount (₹) *',
                            prefixIcon: Icon(Icons.currency_rupee),
                          ),
                          validator: (v) {
                            final val = double.tryParse(v ?? '');
                            if (val == null || val <= 0) return 'Invalid principal';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _interestRateController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Rate (%/mo) *',
                            prefixIcon: Icon(Icons.percent),
                          ),
                          validator: (v) {
                            final val = double.tryParse(v ?? '');
                            if (val == null || val < 0) return 'Invalid rate';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Start Date & Due/End Date
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _selectStartDate,
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text('Start: ${AppDateFormatter.formatDate(_startDate)}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _selectEndDate,
                          icon: const Icon(Icons.event, size: 16),
                          label: Text(
                            _endDate != null ? 'End: ${AppDateFormatter.formatDate(_endDate!)}' : 'No End Date',
                          ),
                        ),
                      ),
                      if (_endDate != null)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          tooltip: 'Clear End Date',
                          onPressed: () => setState(() => _endDate = null),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Status Selector
                  const Text('Loan Status', style: AppTheme.sectionHeaderStyle),
                  const SizedBox(height: 8),
                  SegmentedButton<RecordStatus>(
                    segments: const [
                      ButtonSegment(
                        value: RecordStatus.ACTIVE,
                        label: Text('ACTIVE'),
                        icon: Icon(Icons.play_circle_outline),
                      ),
                      ButtonSegment(
                        value: RecordStatus.SETTLED,
                        label: Text('SETTLED'),
                        icon: Icon(Icons.check_circle_outline),
                      ),
                    ],
                    selected: {_status},
                    onSelectionChanged: (set) {
                      setState(() => _status = set.first);
                    },
                  ),
                  const SizedBox(height: 24),

                  // Collateral Items Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Collateral Items (${_items.length})',
                        style: AppTheme.sectionHeaderStyle,
                      ),
                      TextButton.icon(
                        onPressed: _showAddCollateralDialog,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Item'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_items.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: AppTheme.emptyStateDecoration,
                      child: const Center(
                        child: Text(
                          'No collateral items. Click "Add Item" to attach gold, silver or other security.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                        ),
                      ),
                    )
                  else
                    ..._items.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            '${item.itemCategory} • ${item.weight}g @ ${item.purity}% • '
                            'Val: ${CurrencyFormatter.format(item.itemValue)}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: AppTheme.rose),
                            tooltip: 'Remove Item',
                            onPressed: () {
                              setState(() => _items.removeAt(index));
                            },
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 32),

                  // Save Button
                  ElevatedButton(
                    onPressed: _saveChanges,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Save Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
    );
  }
}
