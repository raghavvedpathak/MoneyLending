import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _loadSettingsAndRates();
  }

  Future<void> _loadSettingsAndRates() async {
    final settings = await _settingsRepository.getSettingsOnce();
    final goldRate = await _itemRateRepository.getCurrentRateOnce('GOLD');
    final silverRate = await _itemRateRepository.getCurrentRateOnce('SILVER');

    if (mounted) {
      setState(() {
        _shopNameController.text = settings.name.isEmpty ? 'My Lending Firm' : settings.name;
        _phoneController.text = settings.phone;
        _addressController.text = settings.address;
        _defaultRateController.text = settings.defaultInterestRate.toStringAsFixed(1);

        if (goldRate != null) {
          _goldRateController.text = goldRate.ratePerUnit.toStringAsFixed(0);
        }
        if (silverRate != null) {
          _silverRateController.text = silverRate.ratePerUnit.toStringAsFixed(0);
        }

        _isLoading = false;
      });
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
      final updated = current.copyWith(
        name: _shopNameController.text.trim().isEmpty ? null : _shopNameController.text.trim(),
        phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
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
                          controller: _shopNameController,
                          decoration: const InputDecoration(labelText: 'Lending Business / Shop Name'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(labelText: 'Contact Phone Number'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
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
