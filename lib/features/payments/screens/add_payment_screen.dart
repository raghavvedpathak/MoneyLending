import 'package:flutter/material.dart';
import '../../../core/calculations/calculations.dart';
import '../../../core/di/injection.dart';
import '../../../core/ui/formatters/id_formatter.dart';
import '../../../core/ui/theme/app_ui.dart';
import '../../../core/ui/widgets/date_input_field.dart';
import '../../../core/utils/app_date_formatter.dart';
import '../../../core/utils/uuid_generator.dart';
import '../../../domain/domain.dart';

class AddPaymentScreen extends StatefulWidget {
  final LedgerRecord record;

  const AddPaymentScreen({
    super.key,
    required this.record,
  });

  @override
  State<AddPaymentScreen> createState() => _AddPaymentScreenState();
}

class _AddPaymentScreenState extends State<AddPaymentScreen> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime _paymentDate = DateTime.now();

  double _enteredAmount = 0.0;
  double _outstandingInterest = 0.0;
  double _outstandingPrincipal = 0.0;
  double _monthsElapsed = 0.0;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _computeCurrentFinancials();
  }

  void _computeCurrentFinancials() {
    final financials = CalculationEngine.calculateRecordFinancials(
      widget.record,
      _paymentDate,
    );
    setState(() {
      _outstandingInterest = financials.outstandingInterest;
      _outstandingPrincipal = financials.outstandingPrincipal;
      _monthsElapsed = financials.months;
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submitPayment() async {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment amount must be greater than 0')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Mandated by §5.2.4: Allocate payment using Interest-First rule
      final allocation = CalculationEngine.allocatePayment(
        amount,
        _outstandingInterest,
      );

      final payment = Payment(
        id: AppUuid.generate(),
        recordId: widget.record.id,
        amount: amount,
        date: _paymentDate,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        interestPaid: allocation.interestPaid,
        principalPaid: allocation.principalPaid,
      );

      await sl<RecordRepository>().addPayment(payment);

      if (mounted) {
        final newRemainingPrincipal = (_outstandingPrincipal - allocation.principalPaid).clamp(0.0, double.infinity);
        final newRemainingInterest = (_outstandingInterest - allocation.interestPaid).clamp(0.0, double.infinity);

        await AppReceiptDialog.show(
          context,
          customerName: widget.record.customerName ?? 'Customer',
          transactionId: widget.record.transactionId,
          amountPaid: amount,
          interestPaid: allocation.interestPaid,
          principalPaid: allocation.principalPaid,
          remainingPrincipal: newRemainingPrincipal,
          remainingInterest: newRemainingInterest,
          paymentDate: _paymentDate,
          notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        );

        if (mounted) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          AppTheme.errorSnackBar('Error saving payment: $e'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Live split preview
    final allocation = CalculationEngine.allocatePayment(
      _enteredAmount,
      _outstandingInterest,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Record Payment • ${AppIdFormatter.formatTransactionId(widget.record.transactionId)}'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
          // Header Summary Card
          AppCard(
            backgroundColor: AppTheme.subCardDark,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.record.customerName ?? 'Customer',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    AppStatusBadge(
                      label: AppIdFormatter.formatTransactionId(widget.record.transactionId),
                      color: AppTheme.gold,
                      borderRadius: 8,
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Outstanding Interest (${AppDateFormatter.formatMonths(_monthsElapsed)})', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                        Text(
                          CurrencyFormatter.format(_outstandingInterest),
                          style: AppUi.currencyStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.gold,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Remaining Principal', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                        Text(
                          CurrencyFormatter.format(_outstandingPrincipal),
                          style: AppUi.currencyStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.accentCyan,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 1-Tap Quick Action Preset Chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_outstandingInterest > 0)
                AppQuickChip(
                  label: 'Pay Full Interest (${CurrencyFormatter.format(_outstandingInterest)})',
                  icon: Icons.bolt_rounded,
                  color: AppTheme.gold,
                  isSelected: (_enteredAmount - _outstandingInterest).abs() < 0.01,
                  onPressed: () {
                    setState(() {
                      _amountController.text = _outstandingInterest.toStringAsFixed(2);
                      _enteredAmount = _outstandingInterest;
                    });
                  },
                ),
              if (_outstandingPrincipal > 0 || _outstandingInterest > 0)
                AppQuickChip(
                  label: 'Full Settlement (${CurrencyFormatter.format(_outstandingInterest + _outstandingPrincipal)})',
                  icon: Icons.check_circle_outline_rounded,
                  color: AppTheme.emerald,
                  isSelected: (_enteredAmount - (_outstandingInterest + _outstandingPrincipal)).abs() < 0.01,
                  onPressed: () {
                    final total = _outstandingInterest + _outstandingPrincipal;
                    setState(() {
                      _amountController.text = total.toStringAsFixed(2);
                      _enteredAmount = total;
                    });
                  },
                ),
              AppQuickChip(
                label: '+₹500',
                color: AppTheme.silver,
                onPressed: () {
                  final cur = double.tryParse(_amountController.text.trim()) ?? 0.0;
                  final next = cur + 500;
                  setState(() {
                    _amountController.text = next.toStringAsFixed(0);
                    _enteredAmount = next;
                  });
                },
              ),
              AppQuickChip(
                label: '+₹1,000',
                color: AppTheme.silver,
                onPressed: () {
                  final cur = double.tryParse(_amountController.text.trim()) ?? 0.0;
                  final next = cur + 1000;
                  setState(() {
                    _amountController.text = next.toStringAsFixed(0);
                    _enteredAmount = next;
                  });
                },
              ),
              AppQuickChip(
                label: '+₹5,000',
                color: AppTheme.silver,
                onPressed: () {
                  final cur = double.tryParse(_amountController.text.trim()) ?? 0.0;
                  final next = cur + 5000;
                  setState(() {
                    _amountController.text = next.toStringAsFixed(0);
                    _enteredAmount = next;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Payment Input
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              labelText: 'Payment Amount *',
              prefixText: '₹ ',
              hintText: '0.00',
            ),
            onChanged: (val) {
              setState(() {
                _enteredAmount = double.tryParse(val.trim()) ?? 0.0;
              });
            },
          ),
          const SizedBox(height: 16),

          // Live Interest-First Split Card
          if (_enteredAmount > 0)
            AppCard(
              backgroundColor: AppTheme.gold.withValues(alpha: 0.06),
              borderColor: AppTheme.gold.withValues(alpha: 0.25),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.pie_chart_outline, size: 18, color: AppTheme.gold),
                      SizedBox(width: 8),
                      Text(
                        'Payment Allocation (Interest cleared first)',
                        style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.gold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Interest Cleared:', style: TextStyle(color: AppTheme.textSecondary)),
                      Text(
                        CurrencyFormatter.format(allocation.interestPaid),
                        style: AppUi.currencyStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.gold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Principal Reduced:', style: TextStyle(color: AppTheme.textSecondary)),
                      Text(
                        CurrencyFormatter.format(allocation.principalPaid),
                        style: AppUi.currencyStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.emerald,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),

          // Date Input
          DateInputField(
            label: 'Payment Date',
            initialDate: _paymentDate,
            onDateChanged: (d) {
              if (d != null) {
                _paymentDate = d;
                _computeCurrentFinancials();
              }
            },
          ),
          const SizedBox(height: 16),

          // Notes
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Notes / Reference (Optional)',
              hintText: 'e.g. Cash payment / GPay receipt #',
            ),
          ),
          const SizedBox(height: 32),

          // Save Button
          ElevatedButton(
            onPressed: _isSaving ? null : _submitPayment,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _isSaving
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: AppTheme.bgDark, strokeWidth: 2))
                : const Text('Record Payment', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    ),
  ),
);
  }
}
