import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../../../core/calculations/calculation_engine.dart';
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

  // Linking TAKEN record to GIVEN record
  String? _linkedRecordId;
  List<LedgerRecord> _activeGivenRecords = [];

  // Controllers for adding a collateral item
  final _itemNameController = TextEditingController();
  final _itemDescriptionController = TextEditingController();
  final _itemWeightController = TextEditingController();
  final _itemPurityController = TextEditingController();
  final _itemRateController = TextEditingController();
  final _itemLendPercentageController = TextEditingController(text: '75');
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
    _linkedRecordId = r.linkedRecordId;
    if (r.type == RecordType.TAKEN) {
      _loadActiveGivenRecords();
    }
  }

  Future<void> _loadActiveGivenRecords() async {
    try {
      final records = await sl<RecordRepository>().getActiveGivenRecords().first;
      if (mounted) {
        setState(() => _activeGivenRecords = records);
      }
    } catch (_) {}
  }

  void _importCollateralFromGiven(LedgerRecord linkedGiven) {
    setState(() {
      for (final it in linkedGiven.items) {
        if (_items.any((existing) => existing.sourceItemId == it.id)) continue;
        _items.add(it.copyWith(
          id: AppUuid.generate(),
          recordId: widget.record.id,
          description: it.description != null && it.description!.isNotEmpty
              ? 'Re-pledged from ${linkedGiven.transactionId}: ${it.description}'
              : 'Re-pledged from ${linkedGiven.transactionId}',
          sourceItemId: it.id,
        ));
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      AppTheme.successSnackBar('Imported ${linkedGiven.items.length} collateral item(s) from ${linkedGiven.transactionId}'),
    );
  }

  @override
  void dispose() {
    _principalController.dispose();
    _interestRateController.dispose();
    _itemNameController.dispose();
    _itemDescriptionController.dispose();
    _itemWeightController.dispose();
    _itemPurityController.dispose();
    _itemRateController.dispose();
    _itemLendPercentageController.dispose();
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
        builder: (ctx, setDialogState) {
          final weight = double.tryParse(_itemWeightController.text.trim()) ?? 0.0;
          final purity = double.tryParse(_itemPurityController.text.trim()) ?? 0.0;
          final rate = double.tryParse(_itemRateController.text.trim()) ?? 0.0;
          final lendPct = double.tryParse(_itemLendPercentageController.text.trim()) ?? 75.0;

          final fineWeight = purity > 0 ? (weight * (purity / 100.0)) : weight;
          final itemVal = (fineWeight > 0 && rate > 0)
              ? CalculationEngine.roundMoney(fineWeight * rate)
              : 0.0;
          final lendable = (itemVal > 0 && lendPct > 0)
              ? CalculationEngine.roundMoney(itemVal * (lendPct / 100.0))
              : 0.0;

          return AlertDialog(
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
                  TextField(
                    controller: _itemDescriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description / Notes (Optional)',
                      hintText: 'e.g. 22K Hallmark, Ruby stone',
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
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _itemPurityController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Purity (%)'),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _itemRateController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Rate / g (₹)'),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _itemLendPercentageController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Lend %'),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ),
                    ],
                  ),
                  if (itemVal > 0 || fineWeight > 0) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.subCardDark,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Fine Weight:', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                              Text(
                                '${fineWeight.toStringAsFixed(2)} g',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Item Valuation:', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                              Text(
                                CurrencyFormatter.format(itemVal),
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.gold),
                              ),
                            ],
                          ),
                          if (lendable > 0) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Max Lendable:', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                                Text(
                                  CurrencyFormatter.format(lendable),
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.emerald),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
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
                  final desc = _itemDescriptionController.text.trim();
                  final curWeight = double.tryParse(_itemWeightController.text.trim()) ?? 0.0;
                  final curPurity = double.tryParse(_itemPurityController.text.trim()) ?? 0.0;
                  final curRate = double.tryParse(_itemRateController.text.trim()) ?? 0.0;
                  final curLendPct = double.tryParse(_itemLendPercentageController.text.trim()) ?? 75.0;

                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter an item name')),
                    );
                    return;
                  }

                  final curFineWeight = curPurity > 0 ? (curWeight * (curPurity / 100.0)) : curWeight;
                  final curItemValue = (curFineWeight > 0 && curRate > 0)
                      ? CalculationEngine.roundMoney(curFineWeight * curRate)
                      : 0.0;
                  final curLendable = (curItemValue > 0 && curLendPct > 0)
                      ? CalculationEngine.roundMoney(curItemValue * (curLendPct / 100.0))
                      : 0.0;

                  final newItem = LedgerItem(
                    id: AppUuid.generate(),
                    recordId: widget.record.id,
                    name: name,
                    itemCategory: _itemCategory,
                    description: desc.isNotEmpty ? desc : null,
                    weight: curWeight > 0 ? curWeight : 0.0,
                    purity: curPurity > 0 ? curPurity : 0.0,
                    rate: curRate > 0 ? curRate : 0.0,
                    itemValue: curItemValue > 0 ? curItemValue : 0.0,
                    lendPercentage: curLendPct,
                    lendableAmount: curLendable > 0 ? curLendable : 0.0,
                  );

                  setState(() {
                    _items.add(newItem);
                    _itemNameController.clear();
                    _itemDescriptionController.clear();
                    _itemWeightController.clear();
                    _itemPurityController.clear();
                    _itemRateController.clear();
                    _itemLendPercentageController.text = '75';
                  });
                  Navigator.of(ctx).pop();
                },
                child: const Text('Add Item'),
              ),
            ],
          );
        },
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
        linkedRecordId: _linkedRecordId,
        clearLinkedRecord: widget.record.type == RecordType.TAKEN && _linkedRecordId == null,
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
                  const SizedBox(height: 16),

                  // Link to Given Loan (for TAKEN records)
                  if (!isGiven) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.subCardDark,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _linkedRecordId != null ? AppTheme.gold.withValues(alpha: 0.5) : AppTheme.borderDark,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.link, size: 16, color: AppTheme.gold),
                                  SizedBox(width: 6),
                                  Text(
                                    'Link to Given Loan (Optional)',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                  ),
                                ],
                              ),
                              if (_linkedRecordId != null)
                                TextButton(
                                  onPressed: () => setState(() => _linkedRecordId = null),
                                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                                  child: const Text('Clear', style: TextStyle(fontSize: 12, color: AppTheme.rose)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Back this borrowing with a customer loan to automatically track profit spread.',
                            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String?>(
                            key: ValueKey('edit_linked_given_$_linkedRecordId'),
                            initialValue: _linkedRecordId,
                            isExpanded: true,
                            dropdownColor: AppTheme.cardDark,
                            menuMaxHeight: 350,
                            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                            decoration: const InputDecoration(
                              labelText: 'Linked Given Loan',
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('None (Direct / Standalone Borrowing)', style: TextStyle(color: AppTheme.textMuted)),
                              ),
                              ..._activeGivenRecords.map((g) {
                                final itemInfo = g.items.isNotEmpty ? ' • ${g.items.length} collateral item(s)' : '';
                                return DropdownMenuItem<String?>(
                                  value: g.id,
                                  child: Text(
                                    '${g.transactionId} (${g.customerName ?? "Customer"}) - ₹${g.principalAmount.toStringAsFixed(0)}$itemInfo',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: AppTheme.textPrimary),
                                  ),
                                );
                              }),
                            ],
                            onChanged: (val) {
                              setState(() => _linkedRecordId = val);
                              if (val != null) {
                                final linkedGiven = _activeGivenRecords.firstWhereOrNull((r) => r.id == val);
                                if (linkedGiven != null && linkedGiven.items.isNotEmpty && _items.isEmpty) {
                                  _importCollateralFromGiven(linkedGiven);
                                }
                              }
                            },
                          ),
                          if (_linkedRecordId != null) ...[
                            Builder(builder: (ctx) {
                              final linkedGiven = _activeGivenRecords.firstWhereOrNull((r) => r.id == _linkedRecordId);
                              if (linkedGiven == null || linkedGiven.items.isEmpty) return const SizedBox.shrink();
                              return Container(
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppTheme.emerald.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppTheme.emerald.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.shield_outlined, size: 14, color: AppTheme.emerald),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Collateral: ${linkedGiven.items.map((i) => i.name).join(", ")}',
                                        style: const TextStyle(fontSize: 11, color: AppTheme.emerald, fontWeight: FontWeight.w500),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    TextButton.icon(
                                      icon: const Icon(Icons.copy, size: 12, color: AppTheme.emerald),
                                      label: const Text('Re-pledge Collateral', style: TextStyle(fontSize: 11, color: AppTheme.emerald, fontWeight: FontWeight.bold)),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      onPressed: () => _importCollateralFromGiven(linkedGiven),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

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
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.subCardDark,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.borderDark),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Text(
                                        item.name,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: AppTheme.badgeDecoration(AppTheme.gold),
                                        child: Text(
                                          item.itemCategory,
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.gold),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: AppTheme.rose, size: 20),
                                  tooltip: 'Remove Item',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () {
                                    setState(() => _items.removeAt(index));
                                  },
                                ),
                              ],
                            ),
                            if (item.description != null && item.description!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                item.description!,
                                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontStyle: FontStyle.italic),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(
                                  '${item.weight}g @ ${item.purity}% purity (${item.fineWeight.toStringAsFixed(2)}g fine)',
                                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                ),
                                if (item.rate > 0) ...[
                                  Text(
                                    ' • ₹${item.rate.toStringAsFixed(0)}/g',
                                    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              children: [
                                if (item.itemValue > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: AppTheme.badgeDecoration(AppTheme.gold),
                                    child: Text(
                                      'Valuation: ${CurrencyFormatter.format(item.itemValue)}',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.gold),
                                    ),
                                  ),
                                if (item.lendableAmount > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: AppTheme.badgeDecoration(AppTheme.emerald),
                                    child: Text(
                                      'Max Lendable (${item.lendPercentage.toStringAsFixed(0)}%): ${CurrencyFormatter.format(item.lendableAmount)}',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.emerald),
                                    ),
                                  ),
                              ],
                            ),
                          ],
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
