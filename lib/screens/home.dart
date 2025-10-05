import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/auth.dart';
import '../services/recipes.dart';
import '../services/notifications.dart';
import '../services/llm_service.dart';
import '../services/theme_service.dart';
import '../widgets/item_tile.dart';
import '../models/grocery_type.dart';
import 'scan.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  User get user => _auth.currentUser!;
  String _status = 'Ready';
  Set<GroceryType> _selectedFilters = {};
  bool _llmAvailable = false;
  late final ThemeService _themeService;
  
  // Sorting options
  String _sortOption = 'expiry_asc';

  @override
  void initState() {
    super.initState();
    _themeService = ThemeService();
    _themeService.addListener(_onThemeChanged);
    _checkLLMAvailability();
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

  Future<void> _checkLLMAvailability() async {
    final available = await LLMService().isAvailable();
    if (mounted) {
      setState(() => _llmAvailable = available);
    }
  }

  void _toggleDarkMode() {
    _themeService.toggleDarkMode();
  }

  void _showCategoryPicker() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
        title: Text(
          'Filter by Category',
          style: TextStyle(
            color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : ThemeService.lightTextPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: _themeService.isDarkMode ? ThemeService.darkCardBackground : ThemeService.lightCardBackground,
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // All Items option
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: _selectedFilters.isEmpty 
                      ? const Color(0xFF4A90E2).withOpacity(0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _selectedFilters.isEmpty 
                        ? const Color(0xFF4A90E2)
                        : (_themeService.isDarkMode ? ThemeService.darkBorder : ThemeService.lightBorder),
                  ),
                ),
                child: ListTile(
                  leading: const Icon(
                    Icons.all_inclusive_rounded,
                    color: Color(0xFF4A90E2),
                  ),
                  title: const Text('All Items'),
                  onTap: () {
                    setState(() => _selectedFilters.clear());
                    setDialogState(() {});
                    Navigator.pop(context);
                  },
                ),
              ),
              // Category grid
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: GroceryType.allTypes.length,
                itemBuilder: (context, index) {
                  final type = GroceryType.allTypes[index];
                  final isSelected = _selectedFilters.contains(type);
                  final color = _getGroceryColor(type);
                  final icon = _getGroceryIcon(type);
                  
                  return Container(
                    decoration: BoxDecoration(
                      color: isSelected 
                          ? color.withOpacity(0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected 
                            ? color
                            : (_themeService.isDarkMode ? ThemeService.darkBorder : ThemeService.lightBorder),
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
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
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            children: [
                              Icon(
                                icon,
                                color: color,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  type.displayName,
                                  style: TextStyle(
                                    color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : ThemeService.lightTextPrimary,
                                    fontSize: 13,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  Icons.check_circle_rounded,
                                  color: color,
                                  size: 16,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
    );
  }


  IconData _getSortIcon(String sortOption) {
    switch (sortOption) {
      case 'expiry_asc':
      case 'expiry_desc':
        return Icons.schedule_rounded;
      case 'name_asc':
      case 'name_desc':
        return Icons.sort_by_alpha_rounded;
      case 'quantity_asc':
      case 'quantity_desc':
        return Icons.inventory_2_rounded;
      case 'type_asc':
      case 'type_desc':
        return Icons.category_rounded;
      default:
        return Icons.sort_rounded;
    }
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
        return Icons.emoji_food_beverage_rounded;
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
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _llmAvailable ? Icons.auto_awesome : Icons.auto_awesome_outlined,
                        size: 18,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _status,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Filter and Sort controls
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Filter dropdown
                Expanded(
                  child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                    child: Row(
                children: [
                        const Icon(
                          Icons.filter_list_rounded,
                          color: Color(0xFF4A90E2),
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _showCategoryPicker(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: _themeService.isDarkMode ? const Color(0xFF4A4A4A) : const Color(0xFFE0E0E0),
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _selectedFilters.isNotEmpty 
                                        ? Icons.filter_list_rounded
                                        : Icons.all_inclusive_rounded,
                                    color: _selectedFilters.isNotEmpty 
                                        ? const Color(0xFF4A90E2)
                                        : const Color(0xFF4A90E2),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _selectedFilters.isEmpty 
                                          ? 'All Items'
                                          : _selectedFilters.length == 1
                                              ? _selectedFilters.first.displayName
                                              : '${_selectedFilters.length} Categories',
                                      style: TextStyle(
                                        color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : ThemeService.lightTextPrimary,
                                        fontSize: 14,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.arrow_drop_down_rounded,
                                    color: Color(0xFF7F8C8D),
                                    size: 20,
                                  ),
                ],
              ),
            ),
          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Sort dropdown
                Expanded(
                  child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                    child: Row(
              children: [
                        Icon(
                          _getSortIcon(_sortOption),
                          color: const Color(0xFF27AE60),
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _sortOption,
                              isExpanded: true,
                              items: [
                                DropdownMenuItem<String>(
                                  value: 'expiry_asc',
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.schedule_rounded,
                                        color: Color(0xFF27AE60),
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Expiry (Soon)',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : ThemeService.lightTextPrimary,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'expiry_desc',
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.schedule_rounded,
                                        color: Color(0xFF27AE60),
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Expiry (Late)',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : ThemeService.lightTextPrimary,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'name_asc',
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.sort_by_alpha_rounded,
                                        color: Color(0xFF27AE60),
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Name (A-Z)',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : ThemeService.lightTextPrimary,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'name_desc',
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.sort_by_alpha_rounded,
                                        color: Color(0xFF27AE60),
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Name (Z-A)',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : ThemeService.lightTextPrimary,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'quantity_asc',
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.inventory_2_rounded,
                                        color: Color(0xFF27AE60),
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Qty (Low)',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : ThemeService.lightTextPrimary,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'quantity_desc',
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.inventory_2_rounded,
                                        color: Color(0xFF27AE60),
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Qty (High)',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : ThemeService.lightTextPrimary,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'type_asc',
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.category_rounded,
                                        color: Color(0xFF27AE60),
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Category (A-Z)',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : ThemeService.lightTextPrimary,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'type_desc',
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.category_rounded,
                                        color: Color(0xFF27AE60),
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Category (Z-A)',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : ThemeService.lightTextPrimary,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _sortOption = value);
                                }
                              },
                            ),
                          ),
                        ),
                      ],
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
                  child: _buildActionButton(
                  onPressed: _seedTestData,
                    icon: Icons.auto_awesome_rounded,
                    label: 'Seed Data',
                    color: const Color(0xFF9B59B6),
                ),
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
                    color: const Color(0xFF27AE60),
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
                        onFinish: () async => ref.delete(),
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

  Future<void> _seedTestData() async {
    final ownerId = user.uid;
    final itemsRef = _db.collection('users').doc(ownerId).collection('items');

    final now = DateTime.now();
    final sample = [
      {
        'name': 'Milk',
        'expiryDate': Timestamp.fromDate(now.add(const Duration(days: 7))),
        'quantity': 1,
        'groceryType': GroceryType.dairy.name,
        'source': 'seed'
      },
      {
        'name': 'Eggs',
        'expiryDate': Timestamp.fromDate(now.add(const Duration(days: 35))),
        'quantity': 12,
        'groceryType': GroceryType.dairy.name,
        'source': 'seed'
      },
      {
        'name': 'Berries',
        'expiryDate': Timestamp.fromDate(now.add(const Duration(days: 5))),
        'quantity': 1,
        'groceryType': GroceryType.fruit.name,
        'source': 'seed'
      },
    ];

    final batch = _db.batch();
    for (final item in sample) {
      final doc = itemsRef.doc();
      batch.set(doc, {
        ...item,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final expiry = (item['expiryDate'] as Timestamp).toDate();
      await NotificationsService.instance.scheduleExpiryReminder(
        id: doc.id.hashCode,
        title: 'Use soon: ${item['name']}',
        body: 'Expires tomorrow',
        when: expiry.subtract(const Duration(days: 1)),
      );
    }
    await batch.commit();
    if (mounted) setState(() => _status = 'Seeded ${sample.length} items');
  }

  Future<void> _recommendRecipes() async {
    if (!mounted) return;
    setState(() => _status = 'Getting recipes…');
    try {
      final recipes = await RecipesService(region: 'us-central1').recommend();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(recipes.isEmpty ? 'No matches yet' : recipes.join(' • '))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recipes unavailable: $e')),
      );
    } finally {
      if (mounted) setState(() => _status = 'Ready');
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isDarkMode});
  
  final bool isDarkMode;

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
                color: const Color(0xFF4A90E2).withOpacity(isDarkMode ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.kitchen_outlined,
                size: 64,
                color: Color(0xFF4A90E2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Your fridge is empty',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? const Color(0xFFE8E8E8) : const Color(0xFF2C3E50),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap "Add Item" to start tracking your groceries',
              style: TextStyle(
                fontSize: 14,
                color: isDarkMode ? const Color(0xFF9E9E9E) : const Color(0xFF7F8C8D),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
