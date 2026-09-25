import 'package:flutter/material.dart';
import '../../core/ui/formatters/id_formatter.dart';
import '../../core/ui/theme/app_theme.dart';
import '../../domain/models/customer.dart';

/// A modern, responsive Customer Selector Field for Android and Windows.
///
/// Replaces clumsy [DropdownButtonFormField] with:
/// - A sleek, high-contrast card showing avatar, customer name, formatted ID (CUST-26/27-01), and phone.
/// - A searchable modal dialog on Windows / bottom sheet on Android with live search by Name, Phone, or Display ID.
/// - Full [FormField] integration for seamless form validation.
class CustomerPickerField extends FormField<Customer> {
  final Customer? selectedCustomer;
  final List<Customer> customers;
  final ValueChanged<Customer?> onChanged;
  final VoidCallback? onQuickAddCustomer;
  final String labelText;

  CustomerPickerField({
    super.key,
    required this.customers,
    required this.onChanged,
    this.selectedCustomer,
    this.onQuickAddCustomer,
    this.labelText = 'Customer *',
    super.enabled = true,
    super.validator,
  }) : super(
          initialValue: selectedCustomer,
          builder: (FormFieldState<Customer> field) {
            final state = field as _CustomerPickerFieldState;
            return state._buildField(field.context);
          },
        );

  @override
  FormFieldState<Customer> createState() => _CustomerPickerFieldState();
}

class _CustomerPickerFieldState extends FormFieldState<Customer> {
  @override
  CustomerPickerField get widget => super.widget as CustomerPickerField;

  @override
  void didUpdateWidget(CustomerPickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedCustomer != oldWidget.selectedCustomer) {
      setValue(widget.selectedCustomer);
    }
  }

  void _selectCustomer(Customer? customer) {
    didChange(customer);
    widget.onChanged(customer);
  }

  Future<void> _openCustomerPicker(BuildContext context) async {
    if (!widget.enabled) return;

    final isWide = MediaQuery.of(context).size.width >= 700;
    Customer? result;

    if (isWide) {
      // Windows Desktop / Tablet: Centered Elegant Modal Dialog
      result = await showDialog<Customer>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: AppTheme.cardDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppTheme.borderDark, width: 1),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540, maxHeight: 600),
            child: _CustomerPickerModalContent(
              customers: widget.customers,
              selectedCustomer: value,
              onQuickAddCustomer: widget.onQuickAddCustomer,
            ),
          ),
        ),
      );
    } else {
      // Android / Mobile: Sleek Modal Bottom Sheet
      result = await showModalBottomSheet<Customer>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppTheme.cardDark,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          side: BorderSide(color: AppTheme.borderDark, width: 1),
        ),
        builder: (ctx) => FractionallySizedBox(
          heightFactor: 0.85,
          child: _CustomerPickerModalContent(
            customers: widget.customers,
            selectedCustomer: value,
            onQuickAddCustomer: widget.onQuickAddCustomer,
          ),
        ),
      );
    }

    if (result != null) {
      _selectCustomer(result);
    }
  }

  Widget _buildField(BuildContext context) {
    final customer = value ?? widget.selectedCustomer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Label
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.labelText,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              if (customer != null && widget.enabled)
                InkWell(
                  onTap: () => _openCustomerPicker(context),
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      'Change',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.gold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Main Selector Box
        InkWell(
          onTap: widget.enabled ? () => _openCustomerPicker(context) : null,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: customer != null ? AppTheme.subCardDark : AppTheme.cardDark,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: hasError
                    ? AppTheme.rose
                    : (customer != null
                        ? AppTheme.gold.withValues(alpha: 0.5)
                        : AppTheme.borderDark),
                width: customer != null || hasError ? 1.5 : 1.0,
              ),
            ),
            child: customer == null
                ? Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.subCardDark,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.person_search_rounded,
                          color: AppTheme.gold,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Select a Customer',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Tap to search by name, phone or ID',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppTheme.textSecondary,
                        size: 22,
                      ),
                    ],
                  )
                : Row(
                    children: [
                      // Customer Avatar with Initials
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: AppTheme.gold.withValues(alpha: 0.15),
                        child: Text(
                          _getInitials(customer.name),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.gold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    customer.name,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: AppTheme.badgeDecoration(AppTheme.gold),
                                  child: Text(
                                    AppIdFormatter.formatCustomerId(customer.displayId),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.gold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                if (customer.phone != null &&
                                    customer.phone!.isNotEmpty) ...[
                                  const Icon(Icons.phone_rounded,
                                      size: 11, color: AppTheme.textMuted),
                                  const SizedBox(width: 4),
                                  Text(
                                    customer.phone!,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                                if (customer.address != null &&
                                    customer.address!.isNotEmpty) ...[
                                  if (customer.phone != null &&
                                      customer.phone!.isNotEmpty)
                                    const Text(' • ',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textMuted)),
                                  Flexible(
                                    child: Text(
                                      customer.address!,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textMuted,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (widget.enabled)
                        IconButton(
                          icon: const Icon(Icons.swap_horiz_rounded,
                              color: AppTheme.textSecondary, size: 20),
                          tooltip: 'Switch Customer',
                          onPressed: () => _openCustomerPicker(context),
                        ),
                    ],
                  ),
          ),
        ),

        // Error message if validation fails
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              errorText ?? '',
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.rose,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  static String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

/// The inner searchable modal sheet / dialog content
class _CustomerPickerModalContent extends StatefulWidget {
  final List<Customer> customers;
  final Customer? selectedCustomer;
  final VoidCallback? onQuickAddCustomer;

  const _CustomerPickerModalContent({
    required this.customers,
    this.selectedCustomer,
    this.onQuickAddCustomer,
  });

  @override
  State<_CustomerPickerModalContent> createState() =>
      _CustomerPickerModalContentState();
}

class _CustomerPickerModalContentState
    extends State<_CustomerPickerModalContent> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Customer> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.customers;
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = widget.customers;
      } else {
        _filtered = widget.customers.where((c) {
          final nameMatch = c.name.toLowerCase().contains(q);
          final phoneMatch = c.phone != null && c.phone!.toLowerCase().contains(q);
          final rawIdMatch = c.displayId.toLowerCase().contains(q);
          final formattedIdMatch = AppIdFormatter.formatCustomerId(c.displayId)
              .toLowerCase()
              .contains(q);
          final addrMatch = c.address != null && c.address!.toLowerCase().contains(q);
          return nameMatch || phoneMatch || rawIdMatch || formattedIdMatch || addrMatch;
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Drag handle (for bottom sheet)
        const SizedBox(height: 10),
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: AppTheme.handleDecoration,
          ),
        ),
        const SizedBox(height: 12),

        // Header Title & Actions
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.people_alt_rounded, color: AppTheme.gold, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Select Customer (${widget.customers.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              if (widget.onQuickAddCustomer != null)
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onQuickAddCustomer!();
                  },
                  icon: const Icon(Icons.person_add_rounded, size: 16),
                  label: const Text('New Customer'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.gold,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Search Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchCtrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search by name, phone, or ID (e.g. CUST-26/27-01)...',
              prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.gold),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () => _searchCtrl.clear(),
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),

        // List of Customers
        Expanded(
          child: _filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_off_rounded,
                            size: 40, color: AppTheme.textMuted),
                        const SizedBox(height: 10),
                        Text(
                          _searchCtrl.text.isEmpty
                              ? 'No customers found'
                              : 'No matching customers for "${_searchCtrl.text}"',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (widget.onQuickAddCustomer != null) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              widget.onQuickAddCustomer!();
                            },
                            icon: const Icon(Icons.person_add_rounded, size: 16),
                            label: const Text('Add Customer Now'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.gold,
                              side: const BorderSide(color: AppTheme.gold),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _filtered.length,
                  itemBuilder: (context, index) {
                    final c = _filtered[index];
                    final isSelected = widget.selectedCustomer?.id == c.id;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.gold.withValues(alpha: 0.10)
                            : AppTheme.cardDark,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? AppTheme.gold : AppTheme.borderDark,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: isSelected
                              ? AppTheme.gold
                              : AppTheme.subCardDark,
                          child: Text(
                            _CustomerPickerFieldState._getInitials(c.name),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                c.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: AppTheme.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1.5),
                              decoration: AppTheme.badgeDecoration(AppTheme.gold),
                              child: Text(
                                AppIdFormatter.formatCustomerId(c.displayId),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.gold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Row(
                          children: [
                            if (c.phone != null && c.phone!.isNotEmpty) ...[
                              const Icon(Icons.phone_rounded,
                                  size: 11, color: AppTheme.textMuted),
                              const SizedBox(width: 3),
                              Text(
                                c.phone!,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                            if (c.address != null && c.address!.isNotEmpty) ...[
                              if (c.phone != null && c.phone!.isNotEmpty)
                                const Text(' • ',
                                    style: TextStyle(
                                        fontSize: 11, color: AppTheme.textMuted)),
                              Flexible(
                                child: Text(
                                  c.address!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textMuted,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle_rounded,
                                color: AppTheme.gold, size: 20)
                            : const Icon(Icons.chevron_right_rounded,
                                color: AppTheme.textMuted, size: 18),
                        onTap: () => Navigator.of(context).pop(c),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
