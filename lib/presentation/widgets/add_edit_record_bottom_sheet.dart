import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../../core/di/injection.dart';
import '../../core/ui/formatters/id_formatter.dart';
import '../../core/ui/theme/app_theme.dart';
import '../../core/ui/widgets/date_input_field.dart';
import '../../core/utils/uuid_generator.dart';
import '../../domain/domain.dart';
import 'add_edit_collateral_dialog.dart';
import 'collateral_item_tile.dart';
import 'customer_picker_field.dart';

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

  // Linking TAKEN record to GIVEN record
  List<LedgerRecord> _activeGivenRecords = [];
  String? _linkedRecordId;

  // Collateral Items
  final List<LedgerItem> _items = [];
  List<ItemRate> _currentRates = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.existingRecord?.type ?? widget.initialType;
    _linkedRecordId = widget.existingRecord?.linkedRecordId;
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final customerRepo = sl<CustomerRepository>();
      final settingsRepo = sl<SettingsRepository>();
      final itemRateRepo = sl<ItemRateRepository>();
      final recordRepo = sl<RecordRepository>();

      final customers = await customerRepo.getAllCustomers().first;
      final settings = await settingsRepo.watchSettings().first;
      final rates = await itemRateRepo.getCurrentRatesOnce();
      final givenRecords = await recordRepo.getActiveGivenRecords().first;

      if (mounted) {
        setState(() {
          _customers = customers;
          _isLoadingCustomers = false;
          _currentRates = rates;
          _activeGivenRecords = givenRecords;

          if (widget.existingRecord != null) {
            final rec = widget.existingRecord!;
            _principalController.text = rec.principalAmount.toStringAsFixed(0);
            _interestRateController.text = rec.interestRate.toStringAsFixed(1);
            _startDate = rec.startDate;
            _selectedCustomer = customers.where((c) => c.id == rec.customerId).firstOrNull;
            _linkedRecordId = rec.linkedRecordId;
            _items.addAll(rec.items);
          } else {
            _interestRateController.text = settings.defaultInterestRate.toStringAsFixed(1);
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
          recordId: widget.existingRecord?.id ?? '',
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
        linkedRecordId: _selectedType == RecordType.TAKEN ? _linkedRecordId : null,
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
                    CustomerPickerField(
                      customers: _customers,
                      selectedCustomer: _selectedCustomer,
                      onChanged: (c) => setState(() => _selectedCustomer = c),
                      validator: (val) => val == null ? 'Please select a customer' : null,
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
                            key: ValueKey('linked_given_$_linkedRecordId'),
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
                      if (d != null) {
                        setState(() => _startDate = d);
                      }
                    },
                  ),
                  const SizedBox(height: 20),

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
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                        ],
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          AddEditCollateralDialog.show(
                            context,
                            currentRates: _currentRates,
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
                            'Click "+ Add Collateral Item" to attach gold, silver or other pledges.',
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
                        currentRates: _currentRates,
                        onEdit: () {
                          AddEditCollateralDialog.show(
                            context,
                            initialItem: item,
                            currentRates: _currentRates,
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
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_circle_outline, color: Colors.white),
                      label: Text(
                        widget.existingRecord != null ? 'Save Changes' : 'Create Record',
                        style: const TextStyle(
                          color: Colors.white,
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
