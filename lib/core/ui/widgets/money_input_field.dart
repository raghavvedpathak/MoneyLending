import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../domain/util/money.dart';

/// Reusable Money Input Widget.
///
/// Mandated by Architecture Spec §2.2 and [FIX-MONEY-1]:
/// - Shared numeric field owned by :core:ui.
/// - Accepts digits and at most one '.', refuses a third decimal digit as it is typed.
/// - Returns its parsed value through [parseMoney].
/// - Must never be inlined in feature screens.
class MoneyInputField extends StatefulWidget {
  final double? initialValue;
  final ValueChanged<double?> onChanged;
  final String label;
  final String hint;
  final String? errorText;
  final String prefixText;
  final bool isRequired;
  final bool enabled;
  final bool autofocus;
  final FocusNode? focusNode;

  const MoneyInputField({
    super.key,
    this.initialValue,
    required this.onChanged,
    this.label = 'Amount',
    this.hint = '0.00',
    this.errorText,
    this.prefixText = '₹ ',
    this.isRequired = false,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
  });

  @override
  State<MoneyInputField> createState() => _MoneyInputFieldState();
}

class _MoneyInputFieldState extends State<MoneyInputField> {
  late final TextEditingController _controller;
  String? _internalError;

  @override
  void initState() {
    super.initState();
    final initialText = widget.initialValue != null
        ? (widget.initialValue! % 1 == 0
            ? widget.initialValue!.toStringAsFixed(0)
            : widget.initialValue!.toString())
        : '';
    _controller = TextEditingController(text: initialText);
  }

  @override
  void didUpdateWidget(covariant MoneyInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue) {
      final currentParsed = parseMoney(_controller.text);
      if (currentParsed != widget.initialValue) {
        final newText = widget.initialValue != null
            ? (widget.initialValue! % 1 == 0
                ? widget.initialValue!.toStringAsFixed(0)
                : widget.initialValue!.toString())
            : '';
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
    final parsed = parseMoney(text);

    if (text.trim().isEmpty) {
      setState(() {
        _internalError = widget.isRequired ? 'This field is required' : null;
      });
      widget.onChanged(null);
      return;
    }

    if (parsed == null) {
      setState(() {
        _internalError = 'Invalid amount';
      });
      widget.onChanged(null);
      return;
    }

    if (_internalError != null) {
      setState(() {
        _internalError = null;
      });
    }
    widget.onChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayedError = widget.errorText ?? _internalError;

    return TextFormField(
      controller: _controller,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        // Refuses any character other than digits and at most one '.', and refuses a 3rd decimal digit
        TextInputFormatter.withFunction((oldValue, newValue) {
          final text = newValue.text;
          if (text.isEmpty) return newValue;

          // Only allow digits with at most 1 decimal point and at most 2 decimal digits
          final regExp = RegExp(r'^\d{0,12}(\.\d{0,2})?$');
          if (regExp.hasMatch(text)) {
            return newValue;
          }
          return oldValue;
        }),
      ],
      onChanged: _onTextChanged,
      decoration: InputDecoration(
        labelText: widget.isRequired ? '${widget.label} *' : widget.label,
        hintText: widget.hint,
        prefixText: widget.prefixText,
        prefixStyle: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary,
        ),
        errorText: displayedError,
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: theme.colorScheme.outlineVariant,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: theme.colorScheme.primary,
            width: 2,
          ),
        ),
      ),
    );
  }
}
