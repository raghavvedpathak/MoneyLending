import 'package:flutter/material.dart';
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

  // Collateral Items
  final List<LedgerItem> _items = [];
  final _itemNameController = TextEditingController();
  String _itemCategory = 'GOLD';
  final _itemWeightController = TextEditingController();
  final _itemPurityController = TextEditingController();
  final _itemRateController = TextEditingController();

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

      final customers = await customerRepo.getAllCustomers().first;
      final settings = await settingsRepo.getSettingsOnce();

      if (mounted) {
        setState(() {
          _customers = customers;
          _isLoadingCustomers = false;
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

    final itemValue = weight > 0 && rate > 0 ? weight * rate : 0.0;
    final newItem = LedgerItem(
      id: AppUuid.generate(),
      recordId: '',
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
                  decoration: const InputDecoration(labelText: 'Item Name (e.g. Gold Chain)'),
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
                    DropdownMenuItem(value: 'OTHER', child: Text('Other Item', style: TextStyle(color: AppTheme.textPrimary))),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => _itemCategory = val);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _itemWeightController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Weight (grams)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _itemPurityController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Purity (Carat / %)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _itemRateController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Market Rate per Unit (₹)'),
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
                          child: ListTile(
                            leading: Icon(
                              item.itemCategory == 'GOLD'
                                  ? Icons.monetization_on
                                  : Icons.shield_outlined,
                              color: AppTheme.gold,
                            ),
                            title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              '${item.itemCategory} • ${item.weight}g • Value: ${CurrencyFormatter.format(item.itemValue)}',
                              style: const TextStyle(color: AppTheme.textSecondary),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppTheme.rose),
                              onPressed: () => setState(() => _items.remove(item)),
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
