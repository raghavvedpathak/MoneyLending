import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../../../core/calculations/calculations.dart';
import '../../../core/di/injection.dart';
import '../../../core/ui/formatters/currency_formatter.dart';
import '../../../core/ui/theme/app_theme.dart';
import '../../../core/ui/widgets/date_input_field.dart';
import '../../../core/utils/uuid_generator.dart';
import '../../../domain/domain.dart';

class AddEntryScreen extends StatefulWidget {
  final RecordType initialType;
  final String? preselectedCustomerId;

  const AddEntryScreen({
    super.key,
    this.initialType = RecordType.GIVEN,
    this.preselectedCustomerId,
  });

  @override
  State<AddEntryScreen> createState() => _AddEntryScreenState();
}

class _AddEntryScreenState extends State<AddEntryScreen> {
  final _formKey = GlobalKey<FormState>();

  late RecordType _selectedType;
  Customer? _selectedCustomer;
  List<Customer> _customers = [];
  bool _isLoadingCustomers = true;

  final _principalController = TextEditingController();
  final _interestRateController = TextEditingController();
  DateTime _startDate = DateTime.now();

  // Linking TAKEN record to GIVEN record
  List<LedgerRecord> _activeGivenRecords = [];
  String? _linkedRecordId;

  // Collateral Items
  final List<LedgerItem> _items = [];
  final _itemNameController = TextEditingController();
  final _itemDescriptionController = TextEditingController();
  String _itemCategory = 'GOLD';
  final _itemWeightController = TextEditingController();
  final _itemPurityController = TextEditingController(text: '91.6');
  final _itemRateController = TextEditingController();
  final _itemLendPercentageController = TextEditingController(text: '75');

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType;
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final customerRepo = sl<CustomerRepository>();
      final settingsRepo = sl<SettingsRepository>();
      final recordRepo = sl<RecordRepository>();

      final customers = await customerRepo.getAllCustomers().first;
      final settings = await settingsRepo.watchSettings().first;
      final givenRecords = await recordRepo.getActiveGivenRecords().first;

      if (mounted) {
        setState(() {
          _customers = customers;
          _isLoadingCustomers = false;
          _activeGivenRecords = givenRecords;
          _interestRateController.text = settings.defaultInterestRate.toStringAsFixed(1);

          if (widget.preselectedCustomerId != null) {
            _selectedCustomer = customers.where((c) => c.id == widget.preselectedCustomerId).firstOrNull;
          }
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

  void _importCollateralFromGiven(LedgerRecord linkedGiven) {
    setState(() {
      for (final it in linkedGiven.items) {
        if (_items.any((existing) => existing.sourceItemId == it.id)) continue;
        _items.add(it.copyWith(
          id: AppUuid.generate(),
          recordId: '',
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

  void _addCollateralItem() {
    final name = _itemNameController.text.trim();
    final weight = double.tryParse(_itemWeightController.text.trim()) ?? 0.0;
    final purity = double.tryParse(_itemPurityController.text.trim()) ?? 0.0;
    final rate = double.tryParse(_itemRateController.text.trim()) ?? 0.0;
    final desc = _itemDescriptionController.text.trim();
    final lendPct = double.tryParse(_itemLendPercentageController.text.trim()) ?? 75.0;

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an item name')),
      );
      return;
    }

    final double effectivePurity = purity > 0 ? purity : 100.0;
    final itemValue = CalculationEngine.roundMoney(weight * (effectivePurity / 100.0) * rate);
    final lendable = CalculationEngine.roundMoney(itemValue * (lendPct / 100.0));

    final newItem = LedgerItem(
      id: AppUuid.generate(),
      recordId: '',
      name: name,
      itemCategory: _itemCategory,
      description: desc.isNotEmpty ? desc : null,
      weight: weight > 0 ? weight : 0.0,
      purity: effectivePurity,
      rate: rate > 0 ? rate : 0.0,
      itemValue: itemValue,
      lendPercentage: lendPct,
      lendableAmount: lendable,
    );

    setState(() {
      _items.add(newItem);
      _itemNameController.clear();
      _itemDescriptionController.clear();
      _itemWeightController.clear();
      _itemPurityController.text = _itemCategory == 'GOLD' ? '91.6' : (_itemCategory == 'SILVER' ? '92.5' : '100');
      _itemRateController.clear();
    });
    Navigator.of(context).pop();
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
                  decoration: const InputDecoration(labelText: 'Item Name (e.g. Gold Chain) *'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('category_$_itemCategory'),
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
                    DropdownMenuItem(value: 'PLATINUM', child: Text('Platinum', style: TextStyle(color: AppTheme.textPrimary))),
                    DropdownMenuItem(value: 'BRONZE', child: Text('Bronze', style: TextStyle(color: AppTheme.textPrimary))),
                    DropdownMenuItem(value: 'VEHICLE', child: Text('Vehicle / Property', style: TextStyle(color: AppTheme.textPrimary))),
                    DropdownMenuItem(value: 'OTHER', child: Text('Other Item', style: TextStyle(color: AppTheme.textPrimary))),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() {
                        _itemCategory = val;
                        if (val == 'GOLD') {
                          _itemPurityController.text = '91.6';
                        } else if (val == 'SILVER') {
                          _itemPurityController.text = '92.5';
                        } else {
                          _itemPurityController.text = '100';
                        }
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _itemDescriptionController,
                  decoration: const InputDecoration(labelText: 'Description / Remarks (Optional)'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _itemWeightController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Weight (g) *'),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _itemPurityController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Purity (%) *'),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _itemRateController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Rate / g (₹) *'),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _itemLendPercentageController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'LTV %', suffixText: '%'),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                    ),
                  ],
                ),
                Builder(
                  builder: (context) {
                    final w = double.tryParse(_itemWeightController.text.trim()) ?? 0.0;
                    final p = double.tryParse(_itemPurityController.text.trim()) ?? 0.0;
                    final r = double.tryParse(_itemRateController.text.trim()) ?? 0.0;
                    final lPct = double.tryParse(_itemLendPercentageController.text.trim()) ?? 75.0;
                    if (w <= 0) return const SizedBox.shrink();

                    final effPurity = p > 0 ? p : 100.0;
                    final fineWeight = w * (effPurity / 100.0);
                    final itemVal = fineWeight * r;
                    final maxLendable = itemVal * (lPct / 100.0);

                    return Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.subCardDark,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.borderDark),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              const Text('Fine Wt', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                              Text('${fineWeight.toStringAsFixed(2)}g', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                            ],
                          ),
                          Column(
                            children: [
                              const Text('Valuation', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                              Text(CurrencyFormatter.format(itemVal), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.gold)),
                            ],
                          ),
                          Column(
                            children: [
                              const Text('Max Lend', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                              Text(CurrencyFormatter.format(maxLendable), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.emerald)),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
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
              onPressed: _addCollateralItem,
              child: const Text('Add Item'),
            ),
          ],
        ),
      ),
    );
  }

  void _showQuickAddCustomerDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quick Add Customer'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Customer Full Name *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone Number'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressCtrl,
                decoration: const InputDecoration(labelText: 'Address / City'),
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
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;

              final newCustomer = Customer(
                id: AppUuid.generate(),
                displayId: '', // Database generates CUST-0001
                name: name,
                phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                address: addressCtrl.text.trim().isEmpty ? null : addressCtrl.text.trim(),
                createdAt: DateTime.now(),
              );

              final saved = await sl<CustomerRepository>().insertCustomer(newCustomer);
              final all = await sl<CustomerRepository>().getAllCustomers().first;
              if (ctx.mounted) {
                Navigator.of(ctx).pop();
              }
              if (mounted) {
                setState(() {
                  _customers = all;
                  _selectedCustomer = saved;
                });
              }
            },
            child: const Text('Save Customer'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitEntry() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or add a customer')),
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

    // Auto-commit any item the user was typing before saving
    final pendingName = _itemNameController.text.trim();
    if (pendingName.isNotEmpty) {
      final weight = double.tryParse(_itemWeightController.text.trim()) ?? 0.0;
      final purity = double.tryParse(_itemPurityController.text.trim()) ?? 0.0;
      final itemRate = double.tryParse(_itemRateController.text.trim()) ?? 0.0;
      final desc = _itemDescriptionController.text.trim();
      final lendPct = double.tryParse(_itemLendPercentageController.text.trim()) ?? 75.0;

      final double effectivePurity = purity > 0 ? purity : 100.0;
      final double itemVal = CalculationEngine.roundMoney(weight * (effectivePurity / 100.0) * itemRate);
      final double lendable = CalculationEngine.roundMoney(itemVal * (lendPct / 100.0));

      _items.add(LedgerItem(
        id: AppUuid.generate(),
        recordId: '',
        name: pendingName,
        itemCategory: _itemCategory,
        description: desc.isNotEmpty ? desc : null,
        weight: weight,
        purity: effectivePurity,
        rate: itemRate,
        itemValue: itemVal,
        lendPercentage: lendPct,
        lendableAmount: lendable,
      ));
      _itemNameController.clear();
      _itemDescriptionController.clear();
      _itemWeightController.clear();
    }

    setState(() => _isSaving = true);

    try {
      final record = LedgerRecord(
        id: AppUuid.generate(),
        transactionId: '', // Auto-generated TXN-000001
        type: _selectedType,
        customerId: _selectedCustomer!.id,
        customerName: _selectedCustomer!.name,
        startDate: _startDate,
        principalAmount: principal,
        interestRate: rate,
        status: RecordStatus.ACTIVE,
        items: _items,
        linkedRecordId: _selectedType == RecordType.TAKEN ? _linkedRecordId : null,
      );

      await sl<RecordRepository>().insertRecord(record);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppTheme.successSnackBar('${_selectedType == RecordType.GIVEN ? "Loan Given" : "Loan Taken"} entry created!'),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          AppTheme.errorSnackBar('Error creating entry: $e'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedType == RecordType.GIVEN ? 'New Loan (Given)' : 'New Borrowing (Taken)'),
      ),
      body: _isLoadingCustomers
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                  // Type Selector
                  SegmentedButton<RecordType>(
                    segments: const [
                      ButtonSegment(
                        value: RecordType.GIVEN,
                        label: Text('GIVEN (Lent)'),
                        icon: Icon(Icons.arrow_upward_rounded),
                      ),
                      ButtonSegment(
                        value: RecordType.TAKEN,
                        label: Text('TAKEN (Borrowed)'),
                        icon: Icon(Icons.arrow_downward_rounded),
                      ),
                    ],
                    selected: {_selectedType},
                    onSelectionChanged: (set) {
                      setState(() => _selectedType = set.first);
                    },
                  ),
                  const SizedBox(height: 20),

                  // Customer Selection
                  Builder(
                    builder: (context) {
                      final uniqueMap = <String, Customer>{};
                      for (final c in _customers) {
                        uniqueMap[c.id] = c;
                      }
                      final customerList = uniqueMap.values.toList();
                      final currentSelection = (_selectedCustomer != null && uniqueMap.containsKey(_selectedCustomer!.id))
                          ? uniqueMap[_selectedCustomer!.id]
                          : null;

                      return Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<Customer>(
                              key: ValueKey('add_entry_cust_${currentSelection?.id ?? 'none'}'),
                              initialValue: currentSelection,
                              isExpanded: true,
                              dropdownColor: AppTheme.cardDark,
                              menuMaxHeight: 350,
                              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                              icon: const Icon(Icons.arrow_drop_down, color: AppTheme.gold),
                              hint: const Text('Select a customer', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                              decoration: const InputDecoration(
                                labelText: 'Customer *',
                                prefixIcon: Icon(Icons.person_rounded, color: AppTheme.gold),
                              ),
                              items: customerList.map((c) {
                                return DropdownMenuItem<Customer>(
                                  value: c,
                                  child: Text(
                                    '${c.name} (${c.displayId})',
                                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (c) => setState(() => _selectedCustomer = c),
                              validator: (c) => c == null ? 'Please select a customer' : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            icon: const Icon(Icons.person_add_rounded),
                            tooltip: 'Quick Add Customer',
                            onPressed: _showQuickAddCustomerDialog,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Link to Given Loan (for TAKEN records)
                  if (_selectedType == RecordType.TAKEN) ...[
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
                            'Back this borrowing with a customer loan to automatically track profit spread (interim & net profit).',
                            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String?>(
                            key: ValueKey('add_entry_linked_given_$_linkedRecordId'),
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

                  // Principal & Interest Rate
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _principalController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Principal Amount *',
                            prefixText: '₹ ',
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) return 'Required';
                            final d = double.tryParse(val.trim());
                            if (d == null || d <= 0) return 'Invalid';
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
                            labelText: 'Rate (% / mo) *',
                            suffixText: '%',
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) return 'Required';
                            final d = double.tryParse(val.trim());
                            if (d == null || d < 0) return 'Invalid';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Start Date
                  DateInputField(
                    label: 'Start Date (Money Handed Over)',
                    initialDate: _startDate,
                    onDateChanged: (d) {
                      if (d != null) setState(() => _startDate = d);
                    },
                  ),
                  const SizedBox(height: 24),

                  // Collateral Items Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Collateral Items (${_items.length})',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      TextButton.icon(
                        onPressed: _showAddCollateralDialog,
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Add Collateral'),
                      ),
                    ],
                  ),
                  if (_items.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: AppTheme.emptyStateDecoration,
                      child: const Text(
                        'No collateral items added yet. Click "Add Collateral" for gold/silver pledges.',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ..._items.map((item) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(
                                  item.itemCategory == 'GOLD'
                                      ? Icons.monetization_on
                                      : Icons.shield_outlined,
                                  color: AppTheme.gold,
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                            decoration: AppTheme.badgeDecoration(AppTheme.gold),
                                            child: Text(
                                              item.itemCategory,
                                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.gold),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (item.description != null && item.description!.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          item.description!,
                                          style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppTheme.textMuted),
                                        ),
                                      ],
                                      const SizedBox(height: 4),
                                      Text(
                                        '${item.weight}g · ${item.purity}% purity (${item.fineWeight.toStringAsFixed(2)}g fine) · Val: ${CurrencyFormatter.format(item.itemValue)} · Max Lend: ${CurrencyFormatter.format(item.lendableAmount)}',
                                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: AppTheme.rose),
                                  onPressed: () => setState(() => _items.remove(item)),
                                ),
                              ],
                            ),
                          ),
                        )),
                  const SizedBox(height: 32),

                  // Submit Button
                  ElevatedButton(
                    onPressed: _isSaving ? null : _submitEntry,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isSaving
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: AppTheme.bgDark, strokeWidth: 2))
                        : const Text('Save Loan Entry', style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            ),
          ),
        ),
    );
  }
}
