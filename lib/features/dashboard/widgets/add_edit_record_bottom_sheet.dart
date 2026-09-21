import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';
import '../../../core/ui/formatters/currency_formatter.dart';
import '../../../core/ui/theme/app_theme.dart';
import '../../../core/ui/widgets/date_input_field.dart';
import '../../../core/utils/uuid_generator.dart';
import '../../../domain/domain.dart';

/// Modal bottom sheet for adding or editing a record (§10.1).
///
/// Mandated by Screen Inventory §10.1:
/// - Opened via Dashboard FloatingActionButton (`showModalBottomSheet`).
/// - Auto-fills collateral rate when an item category is selected using
///   [ItemRateRepository.watchCurrentRates()].
class AddEditRecordBottomSheet extends StatefulWidget {
  final RecordType initialType;
  final LedgerRecord? existingRecord;

  const AddEditRecordBottomSheet({
    super.key,
    this.initialType = RecordType.GIVEN,
    this.existingRecord,
  });

  static Future<bool?> show(
    BuildContext context, {
    RecordType initialType = RecordType.GIVEN,
    LedgerRecord? existingRecord,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddEditRecordBottomSheet(
        initialType: initialType,
        existingRecord: existingRecord,
      ),
    );
  }

  @override
  State<AddEditRecordBottomSheet> createState() => _AddEditRecordBottomSheetState();
}

class _AddEditRecordBottomSheetState extends State<AddEditRecordBottomSheet> {
  final _formKey = GlobalKey<FormState>();

  late RecordType _selectedType;
  Customer? _selectedCustomer;
  List<Customer> _customers = [];
  bool _isLoadingCustomers = true;

  final _principalController = TextEditingController();
  final _interestRateController = TextEditingController();
  DateTime _startDate = DateTime.now();

  // Collateral Items
  final List<LedgerItem> _items = [];
  final _itemNameController = TextEditingController();
  String _itemCategory = 'GOLD';
  final _itemWeightController = TextEditingController();
  final _itemPurityController = TextEditingController();
  final _itemRateController = TextEditingController();

  List<ItemRate> _currentRates = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.existingRecord?.type ?? widget.initialType;
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final customerRepo = sl<CustomerRepository>();
      final settingsRepo = sl<SettingsRepository>();
      final itemRateRepo = sl<ItemRateRepository>();

      final customers = await customerRepo.getAllCustomers().first;
      final settings = await settingsRepo.getSettingsOnce();
      final rates = await itemRateRepo.getCurrentRatesOnce();

      if (mounted) {
        setState(() {
          _customers = customers;
          _isLoadingCustomers = false;
          _currentRates = rates;

          if (widget.existingRecord != null) {
            final rec = widget.existingRecord!;
            _principalController.text = rec.principalAmount.toStringAsFixed(0);
            _interestRateController.text = rec.interestRate.toStringAsFixed(1);
            _startDate = rec.startDate;
            _selectedCustomer = customers.where((c) => c.id == rec.customerId).firstOrNull;
            _items.addAll(rec.items);
          } else {
            _interestRateController.text = settings.defaultInterestRate.toStringAsFixed(1);
          }

          _autoFillRateForCategory(_itemCategory);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingCustomers = false;
          _interestRateController.text = '2.0';
        });
      }
    }
  }

  void _autoFillRateForCategory(String category) {
    for (final r in _currentRates) {
      if (r.itemCategory.trim().toUpperCase() == category.trim().toUpperCase()) {
        if (r.ratePerUnit > 0) {
          _itemRateController.text = r.ratePerUnit.toStringAsFixed(0);
          return;
        }
      }
    }
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

  void _addCollateralItem() {
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
    if (weight <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Weight must be greater than zero')),
      );
      return;
    }

    final double effectivePurity = purity > 0 ? purity : 100.0;
    final double itemVal = weight * (effectivePurity / 100.0) * rate;

    final item = LedgerItem(
      id: AppUuid.generate(),
      recordId: widget.existingRecord?.id ?? '',
      name: name,
      itemCategory: _itemCategory,
      weight: weight,
      purity: effectivePurity,
      rate: rate,
      itemValue: itemVal,
    );

    setState(() {
      _items.add(item);
      _itemNameController.clear();
      _itemWeightController.clear();
      _itemPurityController.clear();
      _autoFillRateForCategory(_itemCategory);
    });
  }

  Future<void> _saveRecord() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a customer first'),
          backgroundColor: AppTheme.rose,
        ),
      );
      return;
    }

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
      final recordRepo = sl<RecordRepository>();

      final record = LedgerRecord(
        id: widget.existingRecord?.id ?? AppUuid.generate(),
        transactionId: widget.existingRecord?.transactionId ?? '',
        customerId: _selectedCustomer!.id,
        customerName: _selectedCustomer!.name,
        type: _selectedType,
        principalAmount: principal,
        interestRate: rate,
        startDate: _startDate,
        items: _items,
        status: RecordStatus.ACTIVE,
      );

      if (widget.existingRecord != null) {
        await recordRepo.updateRecord(record);
      } else {
        await recordRepo.insertRecord(record);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save record: $e'),
            backgroundColor: AppTheme.rose,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: AppTheme.gold, width: 2),
        ),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.textMuted.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      _selectedType == RecordType.GIVEN
                          ? Icons.arrow_outward_rounded
                          : Icons.arrow_downward_rounded,
                      color: _selectedType == RecordType.GIVEN ? AppTheme.accentCyan : AppTheme.emerald,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.existingRecord != null
                          ? 'Edit Record'
                          : (_selectedType == RecordType.GIVEN ? 'New Loan Given' : 'New Loan Taken'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.borderDark),

          // Scrollable Form
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
                children: [
                  // Type Selector (Given vs Taken)
                  SegmentedButton<RecordType>(
                    segments: const [
                      ButtonSegment(
                        value: RecordType.GIVEN,
                        label: Text('Given (Lent)'),
                        icon: Icon(Icons.arrow_upward_rounded),
                      ),
                      ButtonSegment(
                        value: RecordType.TAKEN,
                        label: Text('Taken (Borrowed)'),
                        icon: Icon(Icons.arrow_downward_rounded),
                      ),
                    ],
                    selected: {_selectedType},
                    onSelectionChanged: (val) {
                      setState(() => _selectedType = val.first);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Customer Selector
                  if (_isLoadingCustomers)
                    const Center(child: CircularProgressIndicator())
                  else
                    DropdownButtonFormField<Customer>(
                      initialValue: _selectedCustomer,
                      decoration: const InputDecoration(
                        labelText: 'Customer *',
                        prefixIcon: Icon(Icons.person_outline, color: AppTheme.gold),
                      ),
                      items: _customers.map((c) {
                        return DropdownMenuItem(
                          value: c,
                          child: Text('${c.name} (${c.displayId})'),
                        );
                      }).toList(),
                      onChanged: (c) => setState(() => _selectedCustomer = c),
                      validator: (val) => val == null ? 'Please select a customer' : null,
                    ),
                  const SizedBox(height: 16),

                  // Principal & Interest Rate
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _principalController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Principal (₹) *',
                            prefixIcon: Icon(Icons.payments_outlined, color: AppTheme.gold),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) return 'Required';
                            if (double.tryParse(val) == null) return 'Invalid';
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
                            labelText: 'Rate %/mo *',
                            suffixText: '%',
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) return 'Required';
                            if (double.tryParse(val) == null) return 'Invalid';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Start Date (moment money was given/taken)
                  DateInputField(
                    label: 'Start Date & Time (Lending moment)',
                    initialDate: _startDate,
                    onDateChanged: (d) {
                      if (d != null) setState(() => _startDate = d);
                    },
                  ),
                  const SizedBox(height: 20),

                  // Collateral Items Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Pledged Collateral Items',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      Text(
                        '${_items.length} items',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Add Item Inputs
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.subCardDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.borderDark),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _itemNameController,
                                decoration: const InputDecoration(
                                  labelText: 'Item Name',
                                  hintText: 'e.g. Gold Necklace',
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 1,
                              child: DropdownButtonFormField<String>(
                                initialValue: _itemCategory,
                                isDense: true,
                                decoration: const InputDecoration(labelText: 'Category'),
                                items: const [
                                  DropdownMenuItem(value: 'GOLD', child: Text('GOLD')),
                                  DropdownMenuItem(value: 'SILVER', child: Text('SILVER')),
                                  DropdownMenuItem(value: 'PLATINUM', child: Text('PLATINUM')),
                                  DropdownMenuItem(value: 'OTHER', child: Text('OTHER')),
                                ],
                                onChanged: (cat) {
                                  if (cat != null) {
                                    setState(() {
                                      _itemCategory = cat;
                                      _autoFillRateForCategory(cat);
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _itemWeightController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Weight (g)',
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _itemPurityController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Purity (kt/%)',
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _itemRateController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Rate / g (₹)',
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _addCollateralItem,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add Collateral Item'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.gold,
                              side: const BorderSide(color: AppTheme.gold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Added Items List
                  if (_items.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ..._items.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final item = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.cardDark,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.borderDark),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${item.name} (${item.itemCategory})',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  Text(
                                    '${item.weight}g · Val: ${CurrencyFormatter.format(item.itemValue)}',
                                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppTheme.rose, size: 20),
                              onPressed: () => setState(() => _items.removeAt(idx)),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],

                  const SizedBox(height: 24),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _saveRecord,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Icon(Icons.check_circle_outline, color: Colors.black),
                      label: Text(
                        widget.existingRecord != null ? 'Save Changes' : 'Create Record',
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.gold,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
