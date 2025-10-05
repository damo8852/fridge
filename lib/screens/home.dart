import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/auth.dart';
import '../services/llm_service.dart';
import '../services/notifications.dart';
import '../services/theme_service.dart';
import '../widgets/item_tile.dart';
import '../models/grocery_type.dart';
import '../models/recipe.dart';
import 'scan.dart';
import 'recipes_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  User get user => _auth.currentUser!;
  Set<GroceryType> _selectedFilters = {};
  late final ThemeService _themeService;
  
  // Sorting options
  String _sortOption = 'expiry_asc';

  @override
  void initState() {
    super.initState();
    _themeService = ThemeService();
    _themeService.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _themeService.removeListener(_onThemeChanged);
    super.dispose();
  }


  void _toggleDarkMode() {
    _themeService.toggleDarkMode();
  }

  String _getSortDisplayName(String sortOption) {
    switch (sortOption) {
      case 'expiry_asc':
        return 'Expiry (Earliest First)';
      case 'expiry_desc':
        return 'Expiry (Latest First)';
      case 'name_asc':
        return 'Name (A-Z)';
      case 'name_desc':
        return 'Name (Z-A)';
      case 'quantity_asc':
        return 'Quantity (Low to High)';
      case 'quantity_desc':
        return 'Quantity (High to Low)';
      case 'type_asc':
        return 'Category (A-Z)';
      case 'type_desc':
        return 'Category (Z-A)';
      default:
        return 'Default';
    }
  }

  void _showCompactFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(
            color: _themeService.isDarkMode ? ThemeService.darkCardBackground : ThemeService.lightCardBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _themeService.isDarkMode ? ThemeService.darkBorder : ThemeService.lightBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const Icon(
                      Icons.tune_rounded,
                      color: Color(0xFF4A90E2),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Filters',
                      style: TextStyle(
                        color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : ThemeService.lightTextPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.close_rounded,
                        color: _themeService.isDarkMode ? ThemeService.darkTextSecondary : ThemeService.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Multi-column filters
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      // Categories Column
                      _buildFilterColumn(
                        'CATEGORIES',
                        Icons.category_rounded,
                        GroceryType.allTypes.map((type) => _FilterOption(
                          label: type.displayName,
                          icon: _getGroceryIcon(type),
                          color: _getGroceryColor(type),
                          isSelected: _selectedFilters.contains(type),
                          onTap: () {
                            setState(() {
                              if (_selectedFilters.contains(type)) {
                                _selectedFilters.remove(type);
                              } else {
                                _selectedFilters.add(type);
                              }
                            });
                            setDialogState(() {});
                          },
                        )).toList(),
                      ),
                      const SizedBox(height: 20),
                      // Sort Column
                      _buildFilterColumn(
                        'SORT BY',
                        Icons.sort_rounded,
                        [
                          _FilterOption(
                            label: 'Expiry (Earliest First)',
                            icon: Icons.schedule_rounded,
                            color: const Color(0xFF27AE60),
                            isSelected: _sortOption == 'expiry_asc',
                            onTap: () {
                              setState(() => _sortOption = 'expiry_asc');
                              setDialogState(() {});
                            },
                          ),
                          _FilterOption(
                            label: 'Expiry (Latest First)',
                            icon: Icons.schedule_rounded,
                            color: const Color(0xFF27AE60),
                            isSelected: _sortOption == 'expiry_desc',
                            onTap: () {
                              setState(() => _sortOption = 'expiry_desc');
                              setDialogState(() {});
                            },
                          ),
                          _FilterOption(
                            label: 'Name (A-Z)',
                            icon: Icons.sort_by_alpha_rounded,
                            color: const Color(0xFF27AE60),
                            isSelected: _sortOption == 'name_asc',
                            onTap: () {
                              setState(() => _sortOption = 'name_asc');
                              setDialogState(() {});
                            },
                          ),
                          _FilterOption(
                            label: 'Name (Z-A)',
                            icon: Icons.sort_by_alpha_rounded,
                            color: const Color(0xFF27AE60),
                            isSelected: _sortOption == 'name_desc',
                            onTap: () {
                              setState(() => _sortOption = 'name_desc');
                              setDialogState(() {});
                            },
                          ),
                          _FilterOption(
                            label: 'Quantity (Low to High)',
                            icon: Icons.inventory_2_rounded,
                            color: const Color(0xFF27AE60),
                            isSelected: _sortOption == 'quantity_asc',
                            onTap: () {
                              setState(() => _sortOption = 'quantity_asc');
                              setDialogState(() {});
                            },
                          ),
                          _FilterOption(
                            label: 'Quantity (High to Low)',
                            icon: Icons.inventory_2_rounded,
                            color: const Color(0xFF27AE60),
                            isSelected: _sortOption == 'quantity_desc',
                            onTap: () {
                              setState(() => _sortOption = 'quantity_desc');
                              setDialogState(() {});
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterColumn(String title, IconData titleIcon, List<_FilterOption> options) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              titleIcon,
              color: _themeService.isDarkMode ? ThemeService.darkTextSecondary : ThemeService.lightTextSecondary,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: _themeService.isDarkMode ? ThemeService.darkTextSecondary : ThemeService.lightTextSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 1,
          color: _themeService.isDarkMode ? ThemeService.darkBorder : ThemeService.lightBorder,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((option) => _buildFilterChip(option)).toList(),
        ),
      ],
    );
  }

  Widget _buildFilterChip(_FilterOption option) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: option.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: option.isSelected 
                ? option.color.withOpacity(0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: option.isSelected 
                  ? option.color
                  : (_themeService.isDarkMode ? ThemeService.darkBorder : ThemeService.lightBorder),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                option.icon,
                color: option.color,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                option.label,
                style: TextStyle(
                  color: option.isSelected 
                      ? option.color
                      : (_themeService.isDarkMode ? ThemeService.darkTextPrimary : ThemeService.lightTextPrimary),
                  fontSize: 12,
                  fontWeight: option.isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortItems(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
  ) {
    return List.from(items)..sort((a, b) {
      final dataA = a.data();
      final dataB = b.data();
      
      switch (_sortOption) {
        case 'expiry_asc':
          final expiryA = (dataA['expiryDate'] as Timestamp?)?.toDate();
          final expiryB = (dataB['expiryDate'] as Timestamp?)?.toDate();
          if (expiryA == null && expiryB == null) return 0;
          if (expiryA == null) return 1;
          if (expiryB == null) return -1;
          return expiryA.compareTo(expiryB);
          
        case 'expiry_desc':
          final expiryA = (dataA['expiryDate'] as Timestamp?)?.toDate();
          final expiryB = (dataB['expiryDate'] as Timestamp?)?.toDate();
          if (expiryA == null && expiryB == null) return 0;
          if (expiryA == null) return -1;
          if (expiryB == null) return 1;
          return expiryB.compareTo(expiryA);
          
        case 'name_asc':
          return (dataA['name'] ?? '').toString().toLowerCase()
              .compareTo((dataB['name'] ?? '').toString().toLowerCase());
              
        case 'name_desc':
          return (dataB['name'] ?? '').toString().toLowerCase()
              .compareTo((dataA['name'] ?? '').toString().toLowerCase());
              
        case 'quantity_asc':
          final qtyA = (dataA['quantity'] ?? 0) as num;
          final qtyB = (dataB['quantity'] ?? 0) as num;
          return qtyA.compareTo(qtyB);
          
        case 'quantity_desc':
          final qtyA = (dataA['quantity'] ?? 0) as num;
          final qtyB = (dataB['quantity'] ?? 0) as num;
          return qtyB.compareTo(qtyA);
          
        case 'type_asc':
          return (dataA['groceryType'] ?? 'other').toString()
              .compareTo((dataB['groceryType'] ?? 'other').toString());
              
        case 'type_desc':
          return (dataB['groceryType'] ?? 'other').toString()
              .compareTo((dataA['groceryType'] ?? 'other').toString());
              
        default:
          return 0;
      }
    });
  }

  Widget _buildActionButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    // Create much darker colors for dark mode with subtle glow effects
    Color buttonColor = _themeService.isDarkMode 
        ? const Color(0xFF1E1E1E) 
        : Colors.white;
    Color iconColor = _themeService.isDarkMode 
        ? color.withOpacity(0.9)
        : color;
    Color textColor = _themeService.isDarkMode 
        ? color.withOpacity(0.9)
        : color;
    
    return Container(
      decoration: BoxDecoration(
        color: buttonColor,
        borderRadius: BorderRadius.circular(12),
        border: _themeService.isDarkMode 
            ? Border.all(color: color.withOpacity(0.2), width: 1)
            : null,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(_themeService.isDarkMode ? 0.15 : 0.1),
            blurRadius: _themeService.isDarkMode ? 8 : 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: iconColor,
                  size: 20,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getGroceryIcon(GroceryType type) {
    switch (type) {
      case GroceryType.meat:
        return Icons.restaurant_rounded;
      case GroceryType.poultry:
        return Icons.egg_rounded;
      case GroceryType.seafood:
        return Icons.set_meal_rounded;
      case GroceryType.vegetable:
        return Icons.eco_rounded;
      case GroceryType.fruit:
        return Icons.apple_rounded;
      case GroceryType.dairy:
        return Icons.local_drink_rounded;
      case GroceryType.grain:
        return Icons.grain_rounded;
      case GroceryType.beverage:
        return Icons.local_cafe_rounded;
      case GroceryType.snack:
        return Icons.cookie_rounded;
      case GroceryType.condiment:
        return Icons.local_fire_department_rounded;
      case GroceryType.frozen:
        return Icons.ac_unit_rounded;
      case GroceryType.other:
        return Icons.inventory_rounded;
    }
  }

  Color _getGroceryColor(GroceryType type) {
    switch (type) {
      case GroceryType.meat:
        return const Color(0xFFE74C3C);
      case GroceryType.poultry:
        return const Color(0xFFF39C12);
      case GroceryType.seafood:
        return const Color(0xFF3498DB);
      case GroceryType.vegetable:
        return const Color(0xFF27AE60);
      case GroceryType.fruit:
        return const Color(0xFFE91E63);
      case GroceryType.dairy:
        return const Color(0xFF9B59B6);
      case GroceryType.grain:
        return const Color(0xFF8E44AD);
      case GroceryType.beverage:
        return const Color(0xFF1ABC9C);
      case GroceryType.snack:
        return const Color(0xFFF1C40F);
      case GroceryType.condiment:
        return const Color(0xFFFF5722);
      case GroceryType.frozen:
        return const Color(0xFF00BCD4);
      case GroceryType.other:
        return const Color(0xFF95A5A6);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ownerId = user.uid;

    return Scaffold(
      backgroundColor: _themeService.isDarkMode ? ThemeService.darkBackground : ThemeService.lightBackground,
      appBar: AppBar(
        title: Row(
          children: [
          const SizedBox(width: 12),
            Text(
              'My Fridge',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : ThemeService.lightTextPrimary,
              ),
            ),
          ],
        ),
        backgroundColor: _themeService.isDarkMode ? ThemeService.darkBackground : ThemeService.lightBackground,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: _themeService.isDarkMode ? 'Switch to light mode' : 'Switch to dark mode',
            onPressed: _toggleDarkMode,
            icon: Icon(
              _themeService.isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              color: _themeService.isDarkMode ? const Color(0xFFF1C40F) : const Color(0xFF7F8C8D),
            ),
            style: IconButton.styleFrom(
              padding: const EdgeInsets.all(8),
              minimumSize: const Size(32, 32),
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              await AuthService.instance.signOut();
            },
            icon: const Icon(
              Icons.logout_rounded,
              color: Color(0xFF7F8C8D),
            ),
            style: IconButton.styleFrom(
              padding: const EdgeInsets.all(8),
              minimumSize: const Size(32, 32),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Color(0xFF4A90E2), Color(0xFF357ABD)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4A90E2).withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
        onPressed: _addItemDialog,
          backgroundColor: Colors.transparent,
          elevation: 0,
          icon: const Icon(
            Icons.add_rounded,
            color: Colors.white,
          ),
          label: const Text(
            'Add Item',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Welcome section
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: _themeService.isDarkMode 
                ? const LinearGradient(
                    colors: [Color(0xFF2C3E50), Color(0xFF34495E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : const LinearGradient(
                    colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: (_themeService.isDarkMode ? const Color(0xFF2C3E50) : const Color(0xFF667eea)).withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hi, ${user.isAnonymous ? 'Guest' : (user.displayName ?? 'you')}! 👋',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Manage your fridge items',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Compact Filter Button
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: _themeService.isDarkMode ? ThemeService.darkCardBackground : ThemeService.lightCardBackground,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(_themeService.isDarkMode ? 0.2 : 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _showCompactFilters(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.tune_rounded,
                                color: Color(0xFF4A90E2),
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _selectedFilters.isEmpty 
                                      ? 'All Items • ${_getSortDisplayName(_sortOption)}'
                                      : '${_selectedFilters.length} Categories • ${_getSortDisplayName(_sortOption)}',
                                  style: TextStyle(
                                    color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : ThemeService.lightTextPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                color: _themeService.isDarkMode ? ThemeService.darkTextSecondary : ThemeService.lightTextSecondary,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Action buttons
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: _CarbonEmissionsWidget(isDarkMode: _themeService.isDarkMode),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionButton(
                  onPressed: _recommendRecipes,
                    icon: Icons.restaurant_menu_rounded,
                    label: 'Recipes',
                    color: const Color(0xFFE67E22),
                ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ScanPage()),
                  ),
                    icon: Icons.qr_code_scanner_rounded,
                    label: 'Scan',
                    color: const Color(0xFF9B59B6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _db
                  .collection('users')
                  .doc(ownerId)
                  .collection('items')
                  .orderBy('expiryDate')
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return _EmptyState(isDarkMode: _themeService.isDarkMode);
                }

                // Filter items by grocery type
                final filteredDocs = _selectedFilters.isEmpty 
                    ? docs 
                    : docs.where((doc) {
                        final data = doc.data();
                        final groceryType = GroceryType.fromString(data['groceryType'] ?? 'other');
                        return _selectedFilters.contains(groceryType);
                      }).toList();

                if (filteredDocs.isEmpty) {
                  return Center(
                    child: Text(
                      'No items found for this filter',
                      style: TextStyle(
                        color: _themeService.isDarkMode ? const Color(0xFF9E9E9E) : const Color(0xFF7F8C8D),
                        fontSize: 16,
                      ),
                    ),
                  );
                }
                
                // Sort the filtered items
                final sortedDocs = _sortItems(filteredDocs);
                
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemCount: sortedDocs.length,
                  itemBuilder: (context, i) {
                    final ref = sortedDocs[i].reference;
                    final data = sortedDocs[i].data();
                    final groceryType = GroceryType.fromString(data['groceryType'] ?? 'other');
                    return Container(
                      decoration: BoxDecoration(
                        color: _themeService.isDarkMode ? ThemeService.darkCardBackground : ThemeService.lightCardBackground,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(_themeService.isDarkMode ? 0.2 : 0.06),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ItemTile(
                        name: (data['name'] ?? 'Unknown').toString(),
                        expiry: (data['expiryDate'] as Timestamp?)?.toDate(),
                        quantity: (data['quantity'] ?? 1),
                        groceryType: groceryType,
                        isDarkMode: _themeService.isDarkMode,
                        onEdit: () => _editItemDialog(ref, data),
                        onUsedHalf: () async {
                          final q = data['quantity'];
                          final newQ = (q is num) ? (q / 2) : 1;
                          await ref.update({
                            'quantity': newQ,
                            'updatedAt': FieldValue.serverTimestamp(),
                          });
                        },
                        onFinish: () async {
                          // Move item to finished_items collection before deleting
                          final docSnapshot = await ref.get();
                          if (docSnapshot.exists) {
                            final data = docSnapshot.data() as Map<String, dynamic>;
                            final user = _auth.currentUser!;
                            final finishedItemsRef = _db
                                .collection('users')
                                .doc(user.uid)
                                .collection('finished_items')
                                .doc();
                            
                            await finishedItemsRef.set({
                              'name': data['name'],
                              'quantity': data['quantity'],
                              'groceryType': data['groceryType'],
                              'finishedAt': FieldValue.serverTimestamp(),
                              'originalExpiryDate': data['expiryDate'],
                            });
                          }
                          
                          // Now delete from main collection
                          await ref.delete();
                        },
                        onRemove: () async {
                          // Simply delete the item without moving to finished_items
                          await ref.delete();
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addItemDialog() async {
    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    DateTime expiry = DateTime.now().add(const Duration(days: 5));
    GroceryType selectedType = GroceryType.other;
    bool isPredicting = false;

    Future<void> predictExpiry() async {
      final name = nameCtrl.text.trim();
      if (name.isEmpty) return;

      setState(() => isPredicting = true);

      try {
        final prediction = await LLMService().predictExpiryAndType(name);
        if (prediction != null) {
          final days = prediction['days'] as int?;
          final type = prediction['type'] as String?;

          if (days != null) {
            setState(() {
              expiry = DateTime.now().add(Duration(days: days));
              if (type != null) {
                selectedType = GroceryType.fromString(type);
              }
            });
          }
        }
      } catch (e) {
        print('Prediction error: $e');
      } finally {
        setState(() => isPredicting = false);
      }
    }

    Future<void> save() async {
      final name = nameCtrl.text.trim();
      if (name.isEmpty) return;
      final ref = _db.collection('users').doc(user.uid).collection('items').doc();
      await ref.set({
        'name': name,
        'quantity': int.tryParse(qtyCtrl.text) ?? 1,
        'expiryDate': Timestamp.fromDate(expiry),
        'groceryType': selectedType.name,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'source': 'manual',
      });
      await NotificationsService.instance.scheduleExpiryReminder(
        id: ref.id.hashCode,
        title: 'Use soon: $name',
        body: 'Expires tomorrow',
        when: expiry.subtract(const Duration(days: 1)),
      );
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return StatefulBuilder(builder: (context, setLocal) {
          return AlertDialog(
            title: const Text('Add Item'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name'),
                  onChanged: (value) {
                    // Trigger prediction when name changes (with debounce)
                    if (value.trim().isNotEmpty) {
                      Future.delayed(const Duration(milliseconds: 1000), () {
                        if (nameCtrl.text.trim() == value.trim()) {
                          predictExpiry();
                        }
                      });
                    }
                  },
                ),
                TextField(
                  controller: qtyCtrl,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<GroceryType>(
                        value: selectedType,
                        decoration: const InputDecoration(labelText: 'Grocery Type'),
                        items: GroceryType.allTypes.map((type) => DropdownMenuItem(
                          value: type,
                          child: Text(type.displayName),
                        )).toList(),
                        onChanged: (value) {
                          if (value != null) setLocal(() => selectedType = value);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: isPredicting ? null : () async {
                        final name = nameCtrl.text.trim();
                        if (name.isNotEmpty) {
                          await predictExpiry();
                        }
                      },
                      icon: isPredicting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                      tooltip: 'Predict expiry with AI',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: expiry,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 120)),
                    );
                    if (picked != null) setLocal(() => expiry = picked); // local state
                  },
                  icon: const Icon(Icons.calendar_month),
                  label: Text('Expires ${expiry.toLocal().toString().split(' ').first}'),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context, rootNavigator: true).pop(), child: const Text('Cancel')),
              FilledButton(onPressed: () async {
                try {
                  final name = nameCtrl.text.trim();
                  if (name.isNotEmpty) {
                    await save();
                  }
                } catch (e) {
                  // Handle any errors during save, but still close the dialog
                  print('Error saving item: $e');
                }
                if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
              }, child: const Text('Save')),
            ],
          );
        });
      },
    );
  }

  Future<void> _editItemDialog(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
  ) async {
    final nameCtrl = TextEditingController(text: (data['name'] ?? '').toString());
    final qtyCtrl = TextEditingController(text: (data['quantity'] ?? 1).toString());
    DateTime expiry =
        (data['expiryDate'] as Timestamp?)?.toDate() ?? DateTime.now().add(const Duration(days: 5));
    GroceryType selectedType = GroceryType.fromString(data['groceryType'] ?? 'other');

    Future<void> save() async {
      await ref.update({
        'name': nameCtrl.text.trim(),
        'quantity': int.tryParse(qtyCtrl.text) ?? 1,
        'expiryDate': Timestamp.fromDate(expiry),
        'groceryType': selectedType.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return StatefulBuilder(builder: (context, setLocal) {
          return AlertDialog(
            title: const Text('Edit Item'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
                TextField(
                  controller: qtyCtrl,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<GroceryType>(
                  value: selectedType,
                  decoration: const InputDecoration(labelText: 'Grocery Type'),
                  items: GroceryType.allTypes.map((type) => DropdownMenuItem(
                    value: type,
                    child: Text(type.displayName),
                  )).toList(),
                  onChanged: (value) {
                    if (value != null) setLocal(() => selectedType = value);
                  },
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: expiry,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 120)),
                    );
                    if (picked != null) setLocal(() => expiry = picked);
                  },
                  icon: const Icon(Icons.calendar_month),
                  label: Text('Expires ${expiry.toLocal().toString().split(' ').first}'),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context, rootNavigator: true).pop(), child: const Text('Cancel')),
              FilledButton(onPressed: () async {
                try {
                  await save();
                } catch (e) {
                  // Handle any errors during save, but still close the dialog
                  print('Error updating item: $e');
                }
                if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
              }, child: const Text('Save')),
            ],
          );
        });
      },
    );
  }


  Future<void> _recommendRecipes() async {
    if (!mounted) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Generating simple recipes...',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Should take 10-20 seconds',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );


    try {
      // Check if LLM is available
      final isLLMAvailable = await LLMService().isAvailable();
      if (!isLLMAvailable) {
        if (!mounted) return;
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Local LLM not available. Please ensure Ollama is running.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      // Fetch all items from Firestore
      final ownerId = user.uid;
      final snapshot = await _db
          .collection('users')
          .doc(ownerId)
          .collection('items')
          .get();

      if (snapshot.docs.isEmpty) {
        if (!mounted) return;
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Add some items to your fridge first!'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      // Extract ingredient names
      final ingredients = snapshot.docs
          .map((doc) => doc.data()['name']?.toString() ?? '')
          .where((name) => name.isNotEmpty)
          .toList();

      if (ingredients.isEmpty) {
        if (!mounted) return;
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No ingredients found')),
        );
        return;
      }

      // Filter ingredients by selected categories if any are selected
      final filteredIngredients = _selectedFilters.isEmpty 
          ? ingredients
          : ingredients.where((ingredient) {
              // For now, we'll use a simple approach - if filters are selected,
              // we'll pass them to the LLM to focus on those categories
              return true; // We'll let the LLM handle the filtering based on categories
            }).toList();

      // Generate recipes using Mistral AI (requesting 2 for faster generation)
      // Pass selected filters to help the LLM focus on those categories
      final recipeData = await LLMService().generateRecipes(
        filteredIngredients, 
        count: 2,
        preferredCategories: _selectedFilters.isNotEmpty 
            ? _selectedFilters.map((type) => type.displayName).toList()
            : null,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog

      if (recipeData.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not generate recipes. Please try again.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      // Convert to Recipe objects
      final recipes = recipeData.map((data) => Recipe.fromMap(data)).toList();

      // Navigate to RecipesScreen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RecipesScreen(
            recipes: recipes,
            usedIngredients: ingredients,
          ),
        ),
      );

    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating recipes: $e')),
      );
    }
  }
}

class _EmptyState extends StatefulWidget {
  const _EmptyState({required this.isDarkMode});
  
  final bool isDarkMode;

  @override
  State<_EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<_EmptyState> {
  double _carbonSaved = 0.0;
  int _itemsFinished = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _calculateCarbonSavings();
  }

  Future<void> _calculateCarbonSavings() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Query for finished items (items that were consumed/used)
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('finished_items')
          .get();

      int totalItems = 0;
      double totalCarbon = 0.0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final quantity = (data['quantity'] ?? 1) as num;
        final groceryType = data['groceryType'] ?? 'other';
        
        totalItems += quantity.toInt();
        
        // Calculate carbon footprint based on food type
        // These are approximate CO2 equivalents in kg per kg of food
        double carbonPerKg = _getCarbonFootprint(groceryType);
        totalCarbon += quantity * carbonPerKg * 0.5; // Assume average 0.5kg per item
      }

      if (mounted) {
        setState(() {
          _carbonSaved = totalCarbon;
          _itemsFinished = totalItems;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  double _getCarbonFootprint(String groceryType) {
    // Carbon footprint in kg CO2 per kg of food (approximate values)
    switch (groceryType) {
      case 'meat':
        return 27.0; // Beef has highest carbon footprint
      case 'poultry':
        return 6.9; // Chicken
      case 'seafood':
        return 13.6; // Fish
      case 'dairy':
        return 3.2; // Dairy products
      case 'vegetable':
        return 2.0; // Vegetables
      case 'fruit':
        return 1.0; // Fruits
      case 'grain':
        return 1.4; // Grains
      case 'frozen':
        return 3.0; // Frozen foods (higher due to energy)
      default:
        return 2.5; // Average
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF27AE60).withOpacity(widget.isDarkMode ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.eco_rounded,
                size: 64,
                color: Color(0xFF27AE60),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Your fridge is empty',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: widget.isDarkMode ? const Color(0xFFE8E8E8) : const Color(0xFF2C3E50),
              ),
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              const CircularProgressIndicator()
            else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF27AE60).withOpacity(widget.isDarkMode ? 0.15 : 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF27AE60).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.eco_rounded,
                          color: Color(0xFF27AE60),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Carbon Impact Saved',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: widget.isDarkMode ? const Color(0xFFE8E8E8) : const Color(0xFF2C3E50),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_carbonSaved.toStringAsFixed(1)} kg CO₂',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF27AE60),
                      ),
                    ),
                    Text(
                      'from ${_itemsFinished} items finished',
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.isDarkMode ? const Color(0xFF9E9E9E) : const Color(0xFF7F8C8D),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildSustainabilityTips(),
            ],
            const SizedBox(height: 16),
            Text(
              'Tap "Add Item" to start tracking your groceries',
              style: TextStyle(
                fontSize: 14,
                color: widget.isDarkMode ? const Color(0xFF9E9E9E) : const Color(0xFF7F8C8D),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSustainabilityTips() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF4A90E2).withOpacity(widget.isDarkMode ? 0.15 : 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF4A90E2).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lightbulb_outline_rounded,
                color: Color(0xFF4A90E2),
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                'Sustainability Tips',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: widget.isDarkMode ? const Color(0xFFE8E8E8) : const Color(0xFF2C3E50),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '• Plan meals to reduce food waste\n• Buy local and seasonal produce\n• Use leftovers creatively\n• Compost food scraps',
            style: TextStyle(
              fontSize: 12,
              color: widget.isDarkMode ? const Color(0xFF9E9E9E) : const Color(0xFF7F8C8D),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterOption {
  final String label;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  _FilterOption({
    required this.label,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });
}

class _CarbonEmissionsWidget extends StatefulWidget {
  const _CarbonEmissionsWidget({required this.isDarkMode});
  
  final bool isDarkMode;

  @override
  State<_CarbonEmissionsWidget> createState() => _CarbonEmissionsWidgetState();
}

class _CarbonEmissionsWidgetState extends State<_CarbonEmissionsWidget> {
  @override
  void initState() {
    super.initState();
  }

  double _calculateCarbonSavings(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    double totalCarbon = 0.0;

    for (var doc in docs) {
      final data = doc.data();
      final quantity = (data['quantity'] ?? 1) as num;
      final groceryType = data['groceryType'] ?? 'other';
      
      double carbonPerKg = _getCarbonFootprint(groceryType);
      totalCarbon += quantity * carbonPerKg * 0.5; // Assume average 0.5kg per item
    }

    return totalCarbon;
  }

  double _getCarbonFootprint(String groceryType) {
    switch (groceryType) {
      case 'meat':
        return 27.0;
      case 'poultry':
        return 6.9;
      case 'seafood':
        return 13.6;
      case 'dairy':
        return 3.2;
      case 'vegetable':
        return 2.0;
      case 'fruit':
        return 1.0;
      case 'grain':
        return 1.4;
      case 'frozen':
        return 3.0;
      default:
        return 2.5;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('finished_items')
          .snapshots(),
      builder: (context, snapshot) {
        double carbonSaved = 0.0;
        bool isLoading = true;
        
        if (snapshot.hasData) {
          carbonSaved = _calculateCarbonSavings(snapshot.data!.docs);
          isLoading = false;
        } else if (snapshot.hasError) {
          isLoading = false;
        } else if (snapshot.connectionState == ConnectionState.done) {
          isLoading = false;
        }
        
        return Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF27AE60), Color(0xFF2ECC71)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF27AE60).withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('You\'ve saved ${carbonSaved.toStringAsFixed(1)} kg CO₂ by using your food!'),
                    backgroundColor: const Color(0xFF27AE60),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.eco_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        children: [
                        TextSpan(
                          text: isLoading ? 'Loading...' : '${carbonSaved.toStringAsFixed(1)} kg CO₂ ',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                          TextSpan(
                            text: 'Saved',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
