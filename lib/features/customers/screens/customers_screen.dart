import 'package:flutter/material.dart';
import '../../../core/calculations/calculations.dart';
import '../../../core/di/injection.dart';
import '../../../core/ui/formatters/currency_formatter.dart';
import '../../../core/ui/theme/app_theme.dart';
import '../../../core/utils/app_date_formatter.dart';
import '../../../core/utils/uuid_generator.dart';
import '../../../domain/domain.dart';
import '../../entry/screens/add_entry_screen.dart';
import '../../entry/screens/loan_details_screen.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final CustomerRepository _customerRepository = sl<CustomerRepository>();
  final RecordRepository _recordRepository = sl<RecordRepository>();

  List<Customer> _allCustomers = [];
  List<Customer> _filteredCustomers = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    final customers = await _customerRepository.getAllCustomers().first;
    if (mounted) {
      setState(() {
        _allCustomers = customers;
        _applySearch();
        _isLoading = false;
      });
    }
  }

  void _applySearch() {
    if (_searchQuery.trim().isEmpty) {
      _filteredCustomers = _allCustomers;
    } else {
      final q = _searchQuery.toLowerCase();
      _filteredCustomers = _allCustomers.where((c) {
        return c.name.toLowerCase().contains(q) ||
            c.displayId.toLowerCase().contains(q) ||
            (c.phone != null && c.phone!.contains(q));
      }).toList();
    }
  }

  void _showAddCustomerDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add New Customer'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Full Name *',
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  prefixIcon: Icon(Icons.location_on),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;

              final customer = Customer(
                id: AppUuid.generate(),
                displayId: '', // Auto-generates CUST-0001
                name: name,
                phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                address: addressCtrl.text.trim().isEmpty ? null : addressCtrl.text.trim(),
                createdAt: DateTime.now(),
              );

              await _customerRepository.insertCustomer(customer);
              if (ctx.mounted) {
                Navigator.of(ctx).pop();
              }
              if (mounted) {
                _loadCustomers();
                ScaffoldMessenger.of(context).showSnackBar(
                  AppTheme.successSnackBar('Customer added!'),
                );
              }
            },
            child: const Text('Save Customer'),
          ),
        ],
      ),
    );
  }

  void _showCustomerDetailSheet(Customer customer) async {
    final records = await _recordRepository.getRecordsByCustomer(customer.id).first;
    final customerReports = CalculationEngine.getCustomerReport([customer], records, DateTime.now());
    final report = customerReports.isNotEmpty
        ? customerReports.first
        : CustomerReport(
            customer: customer,
            activeRecordCount: 0,
            totalPrincipal: 0.0,
            totalInterestAccrued: 0.0,
            totalDue: 0.0,
          );

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.cardDark,
      constraints: const BoxConstraints(maxWidth: 720),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: AppTheme.handleDecoration,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            customer.name,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            customer.phone ?? 'No phone provided',
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: AppTheme.badgeDecoration(AppTheme.gold, borderRadius: 8),
                      child: Text(
                        customer.displayId,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.gold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (customer.address != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.textMuted),
                      const SizedBox(width: 4),
                      Text(customer.address!, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    ],
                  ),
                ],
                const Divider(height: 28),

                // Financial Summary Cards
                Row(
                  children: [
                    Expanded(
                      child: _SummaryBox(
                        title: 'Total Lent',
                        value: CurrencyFormatter.format(report.totalPrincipal),
                        color: AppTheme.accentCyan,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SummaryBox(
                        title: 'Interest Accrued',
                        value: CurrencyFormatter.format(report.totalInterestAccrued),
                        color: AppTheme.gold,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SummaryBox(
                        title: 'Total Due',
                        value: CurrencyFormatter.format(report.totalDue),
                        color: AppTheme.rose,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Ledger Records
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Loans & Records (${records.length})',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AddEntryScreen(preselectedCustomerId: customer.id),
                          ),
                        ).then((_) => _loadCustomers());
                      },
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add Loan'),
                    ),
                  ],
                ),
                if (records.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('No loan records found for this customer.', style: TextStyle(color: AppTheme.textSecondary)),
                    ),
                  )
                else
                  ...records.map((r) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          Navigator.of(ctx).pop();
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => LoanDetailsScreen(record: r),
                            ),
                          );
                          if (mounted) {
                            _loadCustomers();
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: AppTheme.badgeDecoration(AppTheme.gold),
                                          child: Text(
                                            r.transactionId,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.gold),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: AppTheme.badgeDecoration(r.isGiven ? AppTheme.accentCyan : AppTheme.emerald),
                                          child: Text(
                                            r.isGiven ? 'GIVEN' : 'TAKEN',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: r.isGiven ? AppTheme.accentCyan : AppTheme.emerald,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Principal: ${CurrencyFormatter.format(r.principalAmount)}  |  ${r.interestRate}%/mo',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Started ${AppDateFormatter.formatDate(r.startDate)}',
                                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: AppTheme.badgeDecoration(r.isActive ? AppTheme.emerald : AppTheme.accentCyan),
                                    child: Text(
                                      r.status.name.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: r.isActive ? AppTheme.emerald : AppTheme.accentCyan,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.textMuted),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'customers_fab',
        onPressed: _showAddCustomerDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('New Customer'),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by name, ID (e.g. CUST-0001), phone...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                            _applySearch();
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (q) {
                setState(() {
                  _searchQuery = q;
                  _applySearch();
                });
              },
            ),
          ),

          // Customer List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredCustomers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.people_outline, size: 64, color: AppTheme.textMuted),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isNotEmpty ? 'No matching customers' : 'No customers added yet',
                              style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredCustomers.length,
                        itemBuilder: (context, index) {
                          final customer = _filteredCustomers[index];
                          return Card(
                            child: ListTile(
                              onTap: () => _showCustomerDetailSheet(customer),
                              leading: CircleAvatar(
                                backgroundColor: AppTheme.gold.withValues(alpha: 0.15),
                                foregroundColor: AppTheme.gold,
                                child: Text(
                                  customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text(
                                customer.name,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                customer.phone ?? 'No phone number',
                                style: const TextStyle(color: AppTheme.textSecondary),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: AppTheme.tagDecoration(),
                                child: Text(
                                  customer.displayId,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: AppTheme.gold,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _SummaryBox extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const _SummaryBox({
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: AppTheme.statBoxDecoration(color),
      child: Column(
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
