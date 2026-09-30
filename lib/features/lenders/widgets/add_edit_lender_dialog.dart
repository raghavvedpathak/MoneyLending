import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';
import '../../../core/ui/theme/app_theme.dart';
import '../../../domain/domain.dart';

/// Dialog for creating or editing a Lender party (§4.1, §4.3, §10.1).
///
/// Features:
/// - Segmented toggle between Individual and Institution.
/// - Required phone for Individual; required institution details for Institution.
/// - Saves via [LenderRepository.addLender] or [LenderRepository.updateLender].
class AddEditLenderDialog extends StatefulWidget {
  final Lender? existingLender;

  const AddEditLenderDialog({super.key, this.existingLender});

  static Future<bool?> show(BuildContext context, {Lender? existingLender}) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AddEditLenderDialog(existingLender: existingLender),
    );
  }

  @override
  State<AddEditLenderDialog> createState() => _AddEditLenderDialogState();
}

class _AddEditLenderDialogState extends State<AddEditLenderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _institutionController = TextEditingController();
  final _notesController = TextEditingController();

  late LenderType _lenderType;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final lender = widget.existingLender;
    _lenderType = lender?.lenderType ?? LenderType.individual;
    if (lender != null) {
      _nameController.text = lender.name;
      _phoneController.text = lender.phone ?? '';
      _institutionController.text = lender.institutionDetails ?? '';
      _notesController.text = lender.notes ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _institutionController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final lenderRepo = sl<LenderRepository>();

    try {
      if (widget.existingLender != null) {
        final updated = widget.existingLender!.copyWith(
          name: _nameController.text.trim(),
          lenderType: _lenderType,
          phone: _phoneController.text.trim().isNotEmpty
              ? _phoneController.text.trim()
              : null,
          institutionDetails: _institutionController.text.trim().isNotEmpty
              ? _institutionController.text.trim()
              : null,
          notes: _notesController.text.trim().isNotEmpty
              ? _notesController.text.trim()
              : null,
          updatedAt: DateTime.now(),
        );
        await lenderRepo.updateLender(updated);
      } else {
        await lenderRepo.addLender(
          lenderType: _lenderType,
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim().isNotEmpty
              ? _phoneController.text.trim()
              : null,
          institutionDetails: _institutionController.text.trim().isNotEmpty
              ? _institutionController.text.trim()
              : null,
          notes: _notesController.text.trim().isNotEmpty
              ? _notesController.text.trim()
              : null,
          createdAt: DateTime.now(),
        );
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppTheme.errorSnackBar('Failed to save lender: $e'),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingLender != null;

    return AlertDialog(
      backgroundColor: AppTheme.cardDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.borderDark),
      ),
      title: Text(
        isEditing ? 'Edit Lender' : 'Add New Lender',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Lender Type Segmented Button
              SegmentedButton<LenderType>(
                segments: const [
                  ButtonSegment(
                    value: LenderType.individual,
                    label: Text('Individual'),
                    icon: Icon(Icons.person_outline, size: 18),
                  ),
                  ButtonSegment(
                    value: LenderType.institution,
                    label: Text('Institution'),
                    icon: Icon(Icons.account_balance_outlined, size: 18),
                  ),
                ],
                selected: {_lenderType},
                onSelectionChanged: (val) {
                  setState(() => _lenderType = val.first);
                },
              ),
              const SizedBox(height: 16),

              // 2. Name field
              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  labelText: _lenderType == LenderType.individual
                      ? 'Lender Name *'
                      : 'Institution Name *',
                  hintText: _lenderType == LenderType.individual
                      ? 'e.g. Ramesh Kumar'
                      : 'e.g. Apex Finance Corp',
                  prefixIcon: const Icon(Icons.person, color: AppTheme.gold),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // 3. Phone field (required for individual)
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  labelText: _lenderType == LenderType.individual
                      ? 'Phone Number *'
                      : 'Contact Phone',
                  hintText: 'e.g. 9876543210',
                  prefixIcon: const Icon(Icons.phone_outlined, color: AppTheme.gold),
                ),
                validator: (val) {
                  if (_lenderType == LenderType.individual) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Phone number is required for individual lenders';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // 4. Institution Details (shown for institution)
              if (_lenderType == LenderType.institution) ...[
                TextFormField(
                  controller: _institutionController,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: 'Institution Details *',
                    hintText: 'e.g. NBFC License, Branch, GST',
                    prefixIcon: Icon(Icons.business_outlined, color: AppTheme.gold),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Institution details are required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
              ],

              // 5. Notes (optional)
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText: 'Additional financing terms or branch info',
                  prefixIcon: Icon(Icons.note_alt_outlined, color: AppTheme.gold),
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
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.gold,
            foregroundColor: Colors.white,
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(isEditing ? 'Save Changes' : 'Add Lender'),
        ),
      ],
    );
  }
}
