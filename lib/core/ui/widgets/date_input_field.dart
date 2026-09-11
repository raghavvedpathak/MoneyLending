import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../formatters/date_formatter.dart';

/// Reusable DD/MM/YYYY masked-entry input widget.
///
/// Mandated by Architecture Spec §2.2 and [FIX-DATEINPUT-1]:
/// Shared UI primitive owned by :core:ui.
/// Must never be inlined in feature screens.
class DateInputField extends StatefulWidget {
  final DateTime? initialDate;
  final ValueChanged<DateTime?> onDateChanged;
  final String label;
  final String? hint;
  final String? errorText;
  final bool isRequired;
  final DateTime? firstDate;
  final DateTime? lastDate;

  const DateInputField({
    super.key,
    this.initialDate,
    required this.onDateChanged,
    this.label = 'Date',
    this.hint = 'DD/MM/YYYY',
    this.errorText,
    this.isRequired = false,
    this.firstDate,
    this.lastDate,
  });

  @override
  State<DateInputField> createState() => _DateInputFieldState();
}

class _DateInputFieldState extends State<DateInputField> {
  late final TextEditingController _controller;
  String? _internalError;

  DateTime? _currentDate;

  @override
  void initState() {
    super.initState();
    _currentDate = widget.initialDate;
    final initialText = widget.initialDate != null
        ? AppDateFormatter.formatInputDate(widget.initialDate!)
        : '';
    _controller = TextEditingController(text: initialText);
  }

  @override
  void didUpdateWidget(covariant DateInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialDate != oldWidget.initialDate) {
      final newText = widget.initialDate != null
          ? AppDateFormatter.formatInputDate(widget.initialDate!)
          : '';
      if (_controller.text != newText) {
        _controller.text = newText;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged(String text) {
    if (text.length < 10) {
      setState(() {
        _internalError = widget.isRequired ? 'Enter complete date (DD/MM/YYYY)' : null;
      });
      widget.onDateChanged(null);
      return;
    }

    try {
      final parts = text.split('/');
      if (parts.length == 3) {
        final day = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final year = int.parse(parts[2]);

        if (month < 1 || month > 12) {
          setState(() => _internalError = 'Invalid month (01-12)');
          widget.onDateChanged(null);
          return;
        }

        final daysInMonth = DateTime(year, month + 1, 0).day;
        if (day < 1 || day > daysInMonth) {
          setState(() => _internalError = 'Invalid day (01-$daysInMonth)');
          widget.onDateChanged(null);
          return;
        }

        final parsedDate = DateTime(year, month, day);
        if (widget.firstDate != null && parsedDate.isBefore(widget.firstDate!)) {
          setState(() => _internalError = 'Date cannot be before ${AppDateFormatter.formatDate(widget.firstDate!)}');
          widget.onDateChanged(null);
          return;
        }
        if (widget.lastDate != null && parsedDate.isAfter(widget.lastDate!)) {
          setState(() => _internalError = 'Date cannot be after ${AppDateFormatter.formatDate(widget.lastDate!)}');
          widget.onDateChanged(null);
          return;
        }

        setState(() {
          _internalError = null;
          _currentDate = parsedDate;
        });
        widget.onDateChanged(parsedDate);
        return;
      }
    } catch (_) {
      setState(() {
        _internalError = 'Invalid date format';
        _currentDate = null;
      });
      widget.onDateChanged(null);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.initialDate ?? now,
      firstDate: widget.firstDate ?? DateTime(2000),
      lastDate: widget.lastDate ?? DateTime(2100),
    );

    if (picked != null) {
      final formatted = AppDateFormatter.formatInputDate(picked);
      _controller.text = formatted;
      setState(() {
        _internalError = null;
        _currentDate = picked;
      });
      widget.onDateChanged(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveError = widget.errorText ?? _internalError;
    final helperText = _currentDate != null ? formatDate(_currentDate!) : null;

    return TextFormField(
      controller: _controller,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(8),
        _DateInputFormatter(),
      ],
      onChanged: _onTextChanged,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        helperText: helperText,
        errorText: effectiveError,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        prefixIcon: const Icon(Icons.calendar_today_outlined),
        suffixIcon: IconButton(
          icon: const Icon(Icons.event),
          tooltip: 'Select date from picker',
          onPressed: _pickDate,
        ),
      ),
    );
  }
}

/// Custom formatter to enforce DD/MM/YYYY masking as the user types.
class _DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.length < oldValue.text.length) {
      return newValue;
    }

    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      if ((i == 1 || i == 3) && i != text.length - 1) {
        buffer.write('/');
      }
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
