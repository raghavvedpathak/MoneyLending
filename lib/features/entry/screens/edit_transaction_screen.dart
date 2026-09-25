import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';
import '../../../core/ui/formatters/id_formatter.dart';
import '../../../core/ui/theme/app_theme.dart';
import '../../../core/utils/app_date_formatter.dart';
import '../../../core/utils/uuid_generator.dart';
import '../../../domain/domain.dart';
import '../../../presentation/widgets/add_edit_collateral_dialog.dart';
import '../../../presentation/widgets/collateral_item_tile.dart';

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
          AppTheme.successSnackBar('Transaction ${AppIdFormatter.formatTransactionId(widget.record.transactionId)} updated!'),
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
        title: Text('Edit ${AppIdFormatter.formatTransactionId(r.transactionId)}'),
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
                      Row(
                        children: [
                          const Icon(Icons.shield_outlined, size: 18, color: AppTheme.gold),
                          const SizedBox(width: 8),
                          Text(
                            'Collateral Items (${_items.length})',
                            style: AppTheme.sectionHeaderStyle,
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
                            'No collateral items attached (Unsecured / Direct Loan)',
                            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Click "+ Add Collateral Item" to attach gold, silver or other security.',
                            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else
                    ..._items.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      return CollateralItemTile(
                        item: item,
                        onEdit: () {
                          AddEditCollateralDialog.show(
                            context,
                            initialItem: item,
                            onSave: (updated) {
                              setState(() => _items[index] = updated);
                            },
                          );
                        },
                        onDelete: () {
                          setState(() => _items.removeAt(index));
                        },
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
