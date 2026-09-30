import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';
import '../../../core/navigation/app_routes.dart';
import '../../../core/ui/formatters/id_formatter.dart';
import '../../../core/ui/theme/app_theme.dart';
import '../../../domain/domain.dart';
import '../widgets/add_edit_lender_dialog.dart';

/// Screen Inventory §10.1: LenderListScreen.
///
/// Navigation peer to Borrowers entry point:
/// - Lists all Lenders (TAKEN-side counterpart to Borrowers/Customers).
/// - Shows Lender ID (e.g. LEND26-27-01), type, phone or institution details.
/// - Search bar for fast filtering by name, ID, phone, or institution details.
/// - FloatingActionButton -> [AddEditLenderDialog].
/// - Delete guard enforcing [LenderHasRecordsException] if records are active/settled.
class LenderListScreen extends StatefulWidget {
  final bool isEmbeddedInTab;

  const LenderListScreen({
    super.key,
    this.isEmbeddedInTab = false,
  });

  @override
  State<LenderListScreen> createState() => _LenderListScreenState();
}

class _LenderListScreenState extends State<LenderListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openAddLenderDialog() async {
    final added = await AddEditLenderDialog.show(context);
    if (added == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        AppTheme.successSnackBar('Lender added successfully!'),
      );
    }
  }

  Future<void> _confirmDeleteLender(Lender lender) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.borderDark),
        ),
        title: const Text('Delete Lender'),
        content: Text(
          'Are you sure you want to delete ${lender.name} (${AppIdFormatter.formatLenderId(lender.displayId)})?\n\n'
          'The lender ID will be permanently retired and never reissued.\n\n'
          'Lenders with existing loans or records cannot be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.rose,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete Lender'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await sl<LenderRepository>().deleteLender(lender.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            AppTheme.successSnackBar('Lender deleted successfully'),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            AppTheme.errorSnackBar(
              e is LenderHasRecordsException
                  ? 'Cannot delete lender with ${e.recordCount} active/settled record(s)'
                  : 'Failed to delete lender: $e',
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lenderRepo = sl<LenderRepository>();

    final content = Column(
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
              selected: const {1},
              onSelectionChanged: (val) {
                if (val.first == 0) {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    AppNavigator.navigate(context, const BorrowersRoute());
                  }
                }
              },
            ),
          ),
        ),

        // Search Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search by lender name, ID (e.g. LEND26-27-01), phone...',
              hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: AppTheme.gold, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: AppTheme.textMuted, size: 18),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              filled: true,
              fillColor: AppTheme.subCardDark,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.borderDark),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.borderDark),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.gold),
              ),
            ),
          ),
        ),

        // Lenders List via Stream
        Expanded(
          child: StreamBuilder<List<Lender>>(
            stream: lenderRepo.watchAllLenders(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text('Error loading lenders: ${snapshot.error}'),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final allLenders = snapshot.data ?? [];
              final filteredLenders = _filterLenders(allLenders, _searchQuery);

              if (filteredLenders.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.account_balance_outlined, size: 64, color: AppTheme.textMuted),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isNotEmpty ? 'No matching lenders' : 'No lenders added yet',
                        style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tap "New Lender" to register an individual financier or institution.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: filteredLenders.length,
                itemBuilder: (context, index) {
                  final lender = filteredLenders[index];
                  return _buildLenderCard(lender);
                },
              );
            },
          ),
        ),
      ],
    );

    if (widget.isEmbeddedInTab) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'lenders_fab',
          onPressed: _openAddLenderDialog,
          icon: const Icon(Icons.add),
          label: const Text('New Lender'),
        ),
        body: content,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lenders (Financiers)'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'lenders_fab',
        onPressed: _openAddLenderDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Lender'),
      ),
      body: content,
    );
  }

  List<Lender> _filterLenders(List<Lender> lenders, String query) {
    if (query.isEmpty) return lenders;
    return lenders.where((l) {
      final nameMatch = l.name.toLowerCase().contains(query);
      final idMatch = l.displayId.toLowerCase().contains(query) ||
          AppIdFormatter.formatLenderId(l.displayId).toLowerCase().contains(query);
      final phoneMatch = (l.phone ?? '').toLowerCase().contains(query);
      final instMatch = (l.institutionDetails ?? '').toLowerCase().contains(query);
      return nameMatch || idMatch || phoneMatch || instMatch;
    }).toList();
  }

  Widget _buildLenderCard(Lender lender) {
    final isInstitution = lender.isInstitution;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () async {
          await AppNavigator.navigate(
            context,
            LenderDetailRoute(lender.id),
          );
        },
        leading: CircleAvatar(
          backgroundColor: isInstitution
              ? AppTheme.accentCyan.withValues(alpha: 0.15)
              : AppTheme.emerald.withValues(alpha: 0.15),
          foregroundColor: isInstitution ? AppTheme.accentCyan : AppTheme.emerald,
          child: Icon(
            isInstitution ? Icons.account_balance_rounded : Icons.person_rounded,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                lender.name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: AppTheme.badgeDecoration(
                isInstitution ? AppTheme.accentCyan : AppTheme.emerald,
              ),
              child: Text(
                lender.lenderType.displayName,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isInstitution ? AppTheme.accentCyan : AppTheme.emerald,
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppIdFormatter.formatLenderId(lender.displayId),
                style: const TextStyle(
                  color: AppTheme.gold,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              if (lender.phone != null && lender.phone!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  lender.phone!,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
              if (lender.institutionDetails != null && lender.institutionDetails!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  lender.institutionDetails!,
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: AppTheme.textMuted, size: 20),
          tooltip: 'Delete Lender',
          onPressed: () => _confirmDeleteLender(lender),
        ),
      ),
    );
  }
}
