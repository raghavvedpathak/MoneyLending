import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';
import '../../../core/ui/formatters/id_formatter.dart';
import '../../../core/ui/theme/app_theme.dart';
import '../../../core/ui/widgets/date_input_field.dart';
import '../../../core/utils/uuid_generator.dart';
import '../../../domain/domain.dart';
import '../../../presentation/widgets/add_edit_collateral_dialog.dart';
import '../../../presentation/widgets/collateral_item_tile.dart';
import '../../../presentation/widgets/customer_picker_field.dart';

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
    super.dispose();
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

                      return CustomerPickerField(
                        key: ValueKey('add_entry_cust_${currentSelection?.id ?? 'none'}'),
                        customers: customerList,
                        selectedCustomer: currentSelection,
                        onChanged: (c) => setState(() => _selectedCustomer = c),
                        onQuickAddCustomer: _showQuickAddCustomerDialog,
                        validator: (c) => c == null ? 'Please select a customer' : null,
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
                                    '${AppIdFormatter.formatTransactionId(g.transactionId)} (${g.customerName ?? "Customer"}) - ₹${g.principalAmount.toStringAsFixed(0)}$itemInfo',
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
                      Row(
                        children: [
                          const Icon(Icons.shield_outlined, size: 18, color: AppTheme.gold),
                          const SizedBox(width: 8),
                          Text(
                            'Collateral Items (${_items.length})',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          AddEditCollateralDialog.show(
                            context,
                            onSave: (newItem) {
                              setState(() => _items.add(newItem));
                            },
                          );
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Collateral Item'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.gold,
                          side: const BorderSide(color: AppTheme.gold),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_items.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                      decoration: AppTheme.emptyStateDecoration,
                      child: Column(
                        children: [
                          const Icon(Icons.security_outlined, size: 36, color: AppTheme.textMuted),
                          const SizedBox(height: 8),
                          const Text(
                            'No collateral items added yet (Unsecured / Direct Loan)',
                            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Click "+ Add Collateral Item" for gold, silver or other pledges.',
                            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else
                    ..._items.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final item = entry.value;
                      return CollateralItemTile(
                        item: item,
                        onEdit: () {
                          AddEditCollateralDialog.show(
                            context,
                            initialItem: item,
                            onSave: (updated) {
                              setState(() => _items[idx] = updated);
                            },
                          );
                        },
                        onDelete: () {
                          setState(() => _items.removeAt(idx));
                        },
                      );
                    }),
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
