import 'package:flutter/material.dart';
import '../../../core/data/backup/backup.dart';
import '../../../core/di/injection.dart';
import '../../../core/ui/theme/app_theme.dart';
import '../../../core/utils/uuid_generator.dart';
import '../../../domain/domain.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsRepository _settingsRepository = sl<SettingsRepository>();
  final ItemRateRepository _itemRateRepository = sl<ItemRateRepository>();

  final _shopNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _defaultRateController = TextEditingController();

  final _goldRateController = TextEditingController();
  final _silverRateController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isExporting = false;
  bool _isRestoring = false;
  bool _isClearing = false;

  @override
  void initState() {
    super.initState();
    _loadSettingsAndRates();
  }

  Future<void> _loadSettingsAndRates() async {
    try {
      final settings = await _settingsRepository.getSettingsOnce();
      final goldRate = await _itemRateRepository.getCurrentRateOnce('GOLD');
      final silverRate = await _itemRateRepository.getCurrentRateOnce('SILVER');

      if (mounted) {
        setState(() {
          _shopNameController.text = settings.name;
          _phoneController.text = settings.phone;
          _addressController.text = settings.address;
          _defaultRateController.text = settings.defaultInterestRate.toStringAsFixed(1);

          if (goldRate != null) {
            _goldRateController.text = goldRate.ratePerUnit.toStringAsFixed(0);
          }
          if (silverRate != null) {
            _silverRateController.text = silverRate.ratePerUnit.toStringAsFixed(0);
          }
        });
      }
    } catch (e, stack) {
      debugPrint('Error loading settings and rates: $e\n$stack');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _defaultRateController.dispose();
    _goldRateController.dispose();
    _silverRateController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      final current = await _settingsRepository.getSettingsOnce();
      final updated = Settings(
        id: current.id,
        name: _shopNameController.text.trim(),
        phone: _phoneController.text.trim(),
        address: _addressController.text.trim(),
        defaultInterestRate: double.tryParse(_defaultRateController.text.trim()) ?? 2.0,
      );

      await _settingsRepository.updateSettings(updated);

      // Save item rates if entered
      final goldVal = double.tryParse(_goldRateController.text.trim());
      if (goldVal != null && goldVal > 0) {
        await _itemRateRepository.upsertRate(
          ItemRate(
            id: AppUuid.generate(),
            itemCategory: 'GOLD',
            ratePerUnit: goldVal,
            effectiveDate: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
      }

      final silverVal = double.tryParse(_silverRateController.text.trim());
      if (silverVal != null && silverVal > 0) {
        await _itemRateRepository.upsertRate(
          ItemRate(
            id: AppUuid.generate(),
            itemCategory: 'SILVER',
            ratePerUnit: silverVal,
            effectiveDate: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
      }

      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          AppTheme.successSnackBar('Settings & Market Rates saved successfully!'),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          AppTheme.errorSnackBar('Error updating settings: $e'),
        );
      }
    }
  }

  Future<void> _exportBackup() async {
    setState(() => _isExporting = true);
    try {
      final backupService = sl<BackupService>();
      final path = await backupService.exportBackup();
      if (!mounted) return;
      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppTheme.successSnackBar('Backup exported successfully: $path'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppTheme.errorSnackBar('Failed to export backup: $e'),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _importBackup() async {
    try {
      final backupService = sl<BackupService>();
      final backup = await backupService.pickAndValidateBackup();
      if (!mounted || backup == null) return;

      // Show replace-all confirmation dialog (§7.2, Addendum G, FIX-ID-BACKUP-1)
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppTheme.gold),
              SizedBox(width: 8),
              Text('Restore Backup?'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Restoring this backup is a transactional replace-all operation. All existing customers, records, items, and payments on this device will be replaced.',
                style: TextStyle(height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.cardDark,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.borderDark),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• Version: ${backup.version}'),
                    Text('• Customers: ${backup.customers.length}'),
                    Text('• Records: ${backup.records.length}'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Are you sure you want to proceed? This cannot be undone.',
                style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.rose),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.rose,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('Restore (Replace All)'),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;

      setState(() => _isRestoring = true);
      await backupService.restoreBackup(backup);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        AppTheme.successSnackBar(
          'Backup restored successfully! ${backup.records.length} records loaded.',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppTheme.errorSnackBar('Error restoring backup: $e'),
        );
      }
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.rose),
            SizedBox(width: 8),
            Text('Clear All Data?'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This action will permanently delete all customers, loans, transactions, items, and payments from this device.',
              style: TextStyle(height: 1.4),
            ),
            SizedBox(height: 12),
            Text(
              'It also completely empties retired IDs, meaning every ID sequence (Customer, Transaction, and Payment) will restart at 01.',
              style: TextStyle(height: 1.4, color: AppTheme.textSecondary),
            ),
            SizedBox(height: 12),
            Text(
              'This action cannot be undone. Are you sure you want to proceed?',
              style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.rose),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const Key('settings_confirm_clear_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.rose,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Clear Everything'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isClearing = true);
    try {
      final backupService = sl<BackupService>();
      await backupService.clearAllData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppTheme.successSnackBar(
            'All data cleared successfully. ID sequences reset to 01.',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppTheme.errorSnackBar('Error clearing data: $e'),
        );
      }
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                // Business Profile
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.storefront_rounded, color: AppTheme.accentCyan),
                            SizedBox(width: 8),
                            Text('Business Profile', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          key: const Key('settings_shop_name_field'),
                          controller: _shopNameController,
                          decoration: const InputDecoration(labelText: 'Lending Business / Shop Name'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          key: const Key('settings_phone_field'),
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(labelText: 'Contact Phone Number'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          key: const Key('settings_address_field'),
                          controller: _addressController,
                          decoration: const InputDecoration(labelText: 'Business Address (Shown on PDFs)'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Loan Configuration
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.percent_rounded, color: AppTheme.gold),
                            SizedBox(width: 8),
                            Text('Default Loan Configuration', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          key: const Key('settings_default_rate_field'),
                          controller: _defaultRateController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Default Monthly Interest Rate (%)',
                            suffixText: '% / month',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Live Item Rates (Gold / Silver)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.diamond_outlined, color: AppTheme.emerald),
                            SizedBox(width: 8),
                            Text('Live Market Collateral Rates', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Used for automatic collateral drop and overshoot risk alerts (§5.3 & §5.4).',
                          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _goldRateController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Gold Rate (₹ / g)',
                                  prefixText: '₹ ',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _silverRateController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Silver Rate (₹ / g)',
                                  prefixText: '₹ ',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Backup & Restore (§7.2, Addendum G, FIX-ID-BACKUP-1)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.backup_rounded, color: AppTheme.accentCyan),
                            SizedBox(width: 8),
                            Text('JSON Backup & Restore', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Export an offline JSON backup or restore an existing one. Restoring replaces all records and customers transactionally (§7.2).',
                          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                key: const Key('settings_export_button'),
                                onPressed: _isExporting || _isRestoring ? null : _exportBackup,
                                icon: _isExporting
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.file_upload_outlined),
                                label: const Text('Export Backup'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                key: const Key('settings_restore_button'),
                                onPressed: _isExporting || _isRestoring ? null : _importBackup,
                                icon: _isRestoring
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.file_download_outlined),
                                label: const Text('Restore Backup'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Danger Zone / Clear All Data (§Tab 4)
                Card(
                  color: AppTheme.rose.withValues(alpha: 0.05),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: AppTheme.rose.withValues(alpha: 0.3)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: AppTheme.rose),
                            SizedBox(width: 8),
                            Text(
                              'Danger Zone',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.rose,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Permanently delete all customers, loans, transactions, and payments. Empties retired IDs so all sequences restart at 01.',
                          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            key: const Key('settings_clear_data_button'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.rose,
                              side: const BorderSide(color: AppTheme.rose),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: _isExporting || _isRestoring || _isClearing ? null : _clearAllData,
                            icon: _isClearing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.rose,
                                    ),
                                  )
                                : const Icon(Icons.delete_forever_rounded),
                            label: const Text('Clear All Data'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // System & Database Information
                Card(
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: AppTheme.textSecondary),
                            SizedBox(width: 8),
                            Text('App & Database Info', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        SizedBox(height: 12),
                        Text('Architecture: 100% Offline SQLite with Mutex & WAL'),
                        SizedBox(height: 4),
                        Text('Version: 1.0.0+1 (Native Android & Windows)'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Save Button
                ElevatedButton(
                  key: const Key('settings_save_button'),
                  onPressed: _isSaving ? null : _saveSettings,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isSaving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: AppTheme.bgDark, strokeWidth: 2))
                      : const Text('Save Settings & Market Rates', style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
    );
  }
}
