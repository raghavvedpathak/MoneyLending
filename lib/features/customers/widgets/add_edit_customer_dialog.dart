import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';
import '../../../core/ui/theme/app_theme.dart';
import '../../../core/utils/uuid_generator.dart';
import '../../../domain/domain.dart';

/// Modal dialog for adding or editing a customer (§10.2).
class AddEditCustomerDialog extends StatefulWidget {
  final Customer? existingCustomer;

  const AddEditCustomerDialog({
    super.key,
    this.existingCustomer,
  });

  static Future<bool?> show(
    BuildContext context, {
    Customer? existingCustomer,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AddEditCustomerDialog(
        existingCustomer: existingCustomer,
      ),
    );
  }

  @override
  State<AddEditCustomerDialog> createState() => _AddEditCustomerDialogState();
}

class _AddEditCustomerDialogState extends State<AddEditCustomerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();

  final CustomerRepository _customerRepository = sl<CustomerRepository>();
  bool _isSaving = false;

  bool get _isEditing => widget.existingCustomer != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final cust = widget.existingCustomer!;
      _nameController.text = cust.name;
      _phoneController.text = cust.phone ?? '';
      _addressController.text = cust.address ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _saveCustomer() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final name = _nameController.text.trim();
      final phone = _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim();
      final address = _addressController.text.trim().isEmpty ? null : _addressController.text.trim();

      if (_isEditing) {
        final updated = widget.existingCustomer!.copyWith(
          name: name,
          phone: phone,
          address: address,
        );
        await _customerRepository.updateCustomer(updated);
      } else {
        final newCust = Customer(
          id: AppUuid.generate(),
          displayId: '', // Auto-assigned with FY prefix by repository/DB
          name: name,
          phone: phone,
          address: address,
          createdAt: DateTime.now(),
        );
        await _customerRepository.insertCustomer(newCust);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          AppTheme.errorSnackBar('Failed to save customer: $e'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Edit Customer' : 'Add New Customer'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Full Name *',
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a customer name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  prefixIcon: Icon(Icons.location_on),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveCustomer,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEditing ? 'Update Customer' : 'Save Customer'),
        ),
      ],
    );
  }
}
