import 'package:flutter/material.dart';
import '../../../core/calculations/calculations.dart';
import '../../../core/di/injection.dart';
import '../../../core/navigation/app_routes.dart';
import '../../../core/ui/formatters/id_formatter.dart';
import '../../../core/ui/theme/app_ui.dart';
import '../../../core/utils/app_date_formatter.dart';
import '../../../domain/domain.dart';
import '../widgets/add_edit_customer_dialog.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final CustomerRepository _customerRepository = sl<CustomerRepository>();
  final RecordRepository _recordRepository = sl<RecordRepository>();

  final TextEditingController _searchController = TextEditingController();
  List<Customer> _allCustomers = [];
  List<Customer> _filteredCustomers = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    try {
      final customers = await _customerRepository.getAllCustomersOnce();
      if (mounted) {
        setState(() {
          _allCustomers = customers;
          _applySearch();
        });
      }
    } catch (e, stack) {
      debugPrint('Error loading customers: $e\n$stack');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
            AppIdFormatter.formatCustomerId(c.displayId).toLowerCase().contains(q) ||
            (c.phone != null && c.phone!.contains(q));
      }).toList();
    }
  }

  Future<void> _showAddCustomerDialog() async {
    final added = await AddEditCustomerDialog.show(context);
    if (added == true && mounted) {
      _loadCustomers();
      ScaffoldMessenger.of(context).showSnackBar(
        AppTheme.successSnackBar('Borrower added!'),
      );
    }
  }


  // ignore: unused_element
  void _showCustomerDetailSheet(Customer customer) async {
    final records = await _recordRepository.getRecordsByCustomer(customer.id).first;
    final customerReports = CalculationEngine.getCustomerReport([customer], records, today: DateTime.now().dateOnly);
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
                        AppIdFormatter.formatCustomerId(customer.displayId),
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
                        AppNavigator.navigate(
                          context,
                          AddEntryRoute(customerId: customer.id),
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
                          await AppNavigator.navigate(
                            context,
                            RecordDetailRoute(r.id, record: r),
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
                                            AppIdFormatter.formatTransactionId(r.transactionId),
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
                                      'Started ${AppDateFormatter.formatDate(r.startDate)} • ${AppDateFormatter.formatMonths(CalculationEngine.calculateRecordFinancials(r, DateTime.now()).months)}',
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
        title: const Text('Borrowers'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'customers_fab',
        onPressed: _showAddCustomerDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('New Customer'),
      ),
      body: Column(
        children: [
          // Borrowers | Lenders Segmented Control (§10.2 peer entry point)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment<int>(
                    value: 0,
                    label: Text('Borrowers'),
                    icon: Icon(Icons.people_outline, size: 18),
                  ),
                  ButtonSegment<int>(
                    value: 1,
                    label: Text('Lenders'),
                    icon: Icon(Icons.account_balance_outlined, size: 18),
                  ),
                ],
                selected: const {0},
                onSelectionChanged: (val) {
                  if (val.first == 1) {
                    AppNavigator.navigate(context, const LendersRoute());
                  }
                },
              ),
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by borrower name, ID (e.g. CUST26-27-01), phone...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
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

          // Borrower List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredCustomers.isEmpty
                    ? AppEmptyState(
                        icon: Icons.people_outline,
                        title: _searchQuery.isNotEmpty ? 'No matching borrowers' : 'No borrowers added yet',
                        description: _searchQuery.isNotEmpty
                            ? 'Try searching by a different name, phone, or ID.'
                            : 'Add borrowers to keep track of loans, collateral, and payments.',
                        actionLabel: _searchQuery.isNotEmpty ? 'Clear Search' : '+ New Customer',
                        onAction: () {
                          if (_searchQuery.isNotEmpty) {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                              _applySearch();
                            });
                          } else {
                            _showAddCustomerDialog();
                          }
                        },
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        itemCount: _filteredCustomers.length,
                        itemBuilder: (context, index) {
                          final customer = _filteredCustomers[index];
                          return AppCard(
                            margin: const EdgeInsets.only(bottom: 8),
                            onTap: () async {
                              await AppNavigator.navigate(
                                context,
                                CustomerDetailRoute(customer.id),
                              );
                              if (mounted) {
                                _loadCustomers();
                              }
                            },
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
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
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 2),
                                  Text(
                                    AppIdFormatter.formatCustomerId(customer.displayId),
                                    style: const TextStyle(
                                      color: AppTheme.gold,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (customer.phone != null && customer.phone!.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      customer.phone!,
                                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                    ),
                                  ],
                                ],
                              ),
                              trailing: const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 14,
                                color: AppTheme.textMuted,
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
