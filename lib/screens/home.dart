import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/auth.dart';
import '../services/llm_service.dart';
import '../services/notifications.dart';
import '../services/theme_service.dart';
import '../services/parser.dart';
import '../widgets/item_tile.dart';
import '../models/grocery_type.dart';
import '../models/recipe.dart';
import 'scan.dart';
import 'recipes_screen.dart';
import 'auth_gate.dart';

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
  bool _isSelectionMode = false;
  bool _isMultiSelectMode = false;
  Set<String> _selectedItems = {};
  
  // Sorting options
  String _sortOption = 'expiry_asc';
  
  // Must contain filter
  String _mustContainText = '';

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



  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      _isMultiSelectMode = _isSelectionMode;
      _selectedItems.clear();
    });
  }

  void _enterMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = true;
      _isSelectionMode = true;
      _selectedItems.clear();
    });
  }

  void _exitMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = false;
      _isSelectionMode = false;
      _selectedItems.clear();
    });
  }

  void _toggleItemSelection(String itemId) {
    setState(() {
      if (_selectedItems.contains(itemId)) {
        _selectedItems.remove(itemId);
      } else {
        _selectedItems.add(itemId);
      }
    });
  }

  void _deleteSelectedItems() async {
    if (_selectedItems.isEmpty) return;
    
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Selected Items'),
        content: Text('Are you sure you want to delete ${_selectedItems.length} item(s)?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE74C3C),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    // Store deleted items data for undo
    final deletedItems = <String, Map<String, dynamic>>{};
    for (final itemId in _selectedItems) {
      final docRef = _db.collection('users').doc(user.uid).collection('items').doc(itemId);
      final docSnapshot = await docRef.get();
      if (docSnapshot.exists) {
        deletedItems[itemId] = docSnapshot.data() as Map<String, dynamic>;
      }
    }
    
    // Delete items
    final batch = _db.batch();
    for (final itemId in _selectedItems) {
      final docRef = _db.collection('users').doc(user.uid).collection('items').doc(itemId);
      batch.delete(docRef);
    }
    
    try {
      await batch.commit();
      final deletedCount = _selectedItems.length;
      setState(() {
        _selectedItems.clear();
        _isSelectionMode = false;
        _isMultiSelectMode = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted $deletedCount items'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () async {
                // Restore deleted items
                final restoreBatch = _db.batch();
                for (final entry in deletedItems.entries) {
                  final docRef = _db.collection('users').doc(user.uid).collection('items').doc(entry.key);
                  restoreBatch.set(docRef, entry.value);
                }
                await restoreBatch.commit();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Restored $deletedCount items')),
                  );
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete items: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }


  void _finishSelectedItems() async {
    if (_selectedItems.isEmpty) return;
    
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finish Selected Items'),
        content: Text('Are you sure you want to mark ${_selectedItems.length} item(s) as finished? These items will be moved to your finished items history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF27AE60),
            ),
            child: const Text('Finish'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    // Store finished items data and IDs for undo
    final finishedItemsData = <String, Map<String, dynamic>>{};
    final finishedItemsIds = <String, String>{}; // maps original item ID to finished_items doc ID
    
    final batch = _db.batch();
    final user = _auth.currentUser!;
    
    for (final itemId in _selectedItems) {
      final docRef = _db.collection('users').doc(user.uid).collection('items').doc(itemId);
      
      // Get the item data first
      final docSnapshot = await docRef.get();
      if (docSnapshot.exists) {
        final data = docSnapshot.data() as Map<String, dynamic>;
        finishedItemsData[itemId] = data;
        
        // Move to finished_items collection
        final finishedItemsRef = _db
            .collection('users')
            .doc(user.uid)
            .collection('finished_items')
            .doc();
        
        finishedItemsIds[itemId] = finishedItemsRef.id;
        
        batch.set(finishedItemsRef, {
          'name': data['name'],
          'quantity': data['quantity'],
          'groceryType': data['groceryType'],
          'finishedAt': FieldValue.serverTimestamp(),
          'originalExpiryDate': data['expiryDate'],
        });
        
        // Delete from main collection
        batch.delete(docRef);
      }
    }
    
    try {
      await batch.commit();
      final finishedCount = _selectedItems.length;
      setState(() {
        _selectedItems.clear();
        _isSelectionMode = false;
        _isMultiSelectMode = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Finished $finishedCount items'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () async {
                // Restore items to main collection and remove from finished_items
                final undoBatch = _db.batch();
                for (final entry in finishedItemsData.entries) {
                  final itemId = entry.key;
                  final data = entry.value;
                  
                  // Restore to main collection
                  final docRef = _db.collection('users').doc(user.uid).collection('items').doc(itemId);
                  undoBatch.set(docRef, data);
                  
                  // Remove from finished_items
                  final finishedDocId = finishedItemsIds[itemId];
                  if (finishedDocId != null) {
                    final finishedDocRef = _db
                        .collection('users')
                        .doc(user.uid)
                        .collection('finished_items')
                        .doc(finishedDocId);
                    undoBatch.delete(finishedDocRef);
                  }
                }
                await undoBatch.commit();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Restored $finishedCount items')),
                  );
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to finish items: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }


  void _selectAllVisibleItems() {
    // This will be called from the app bar, but we need access to the current docs
    // We'll use a different approach - store the current docs in a variable
    if (_currentSortedDocs != null) {
      setState(() {
        if (_selectedItems.length == _currentSortedDocs!.length) {
          _selectedItems.clear();
        } else {
          _selectedItems = _currentSortedDocs!.map((doc) => doc.id).toSet();
        }
      });
    }
  }

  int _getCurrentItemsCount() {
    return _currentSortedDocs?.length ?? 0;
  }

  // Store current sorted docs for select all functionality
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _currentSortedDocs;

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

  String _getFilterDisplayText() {
    final parts = <String>[];
    
    if (_selectedFilters.isEmpty && _mustContainText.isEmpty) {
      parts.add('All Items');
    } else {
      if (_selectedFilters.isNotEmpty) {
        parts.add('${_selectedFilters.length} Categories');
      }
      if (_mustContainText.isNotEmpty) {
        parts.add('contains "$_mustContainText"');
      }
    }
    
    parts.add(_getSortDisplayName(_sortOption));
    return parts.join(' • ');
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
              // Must contain text field
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          color: _themeService.isDarkMode ? ThemeService.darkTextSecondary : ThemeService.lightTextSecondary,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'MUST CONTAIN',
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
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Enter text to filter items...',
                        hintStyle: TextStyle(
                          color: _themeService.isDarkMode ? ThemeService.darkTextSecondary : ThemeService.lightTextSecondary,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: _themeService.isDarkMode ? ThemeService.darkTextSecondary : ThemeService.lightTextSecondary,
                        ),
                        suffixIcon: _mustContainText.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  Icons.clear_rounded,
                                  color: _themeService.isDarkMode ? ThemeService.darkTextSecondary : ThemeService.lightTextSecondary,
                                ),
                                onPressed: () {
                                  setState(() => _mustContainText = '');
                                  setDialogState(() {});
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: _themeService.isDarkMode ? ThemeService.darkBorder : ThemeService.lightBorder,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: _themeService.isDarkMode ? ThemeService.darkBorder : ThemeService.lightBorder,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF4A90E2),
                          ),
                        ),
                        filled: true,
                        fillColor: _themeService.isDarkMode ? ThemeService.darkCardBackground : ThemeService.lightCardBackground,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      style: TextStyle(
                        color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : ThemeService.lightTextPrimary,
                      ),
                      onChanged: (value) {
                        setState(() => _mustContainText = value);
                        setDialogState(() {});
                      },
                      controller: TextEditingController(text: _mustContainText),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
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
    bool isFullWidth = false,
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
    
    Widget button = Container(
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
            padding: isFullWidth 
              ? const EdgeInsets.symmetric(vertical: 12, horizontal: 16)
              : const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: isFullWidth 
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      color: iconColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              : Column(
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

    if (isFullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
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
        title: (_isSelectionMode || _isMultiSelectMode)
          ? Row(
              children: [
                Text(
                  '${_selectedItems.length} selected',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : ThemeService.lightTextPrimary,
                  ),
                ),
              ],
            )
          : Row(
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
        leading: (_isSelectionMode || _isMultiSelectMode) ? IconButton(
          icon: Icon(
            Icons.close_rounded,
            color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : ThemeService.lightTextPrimary,
          ),
          onPressed: _exitMultiSelectMode,
          tooltip: 'Exit selection',
        ) : Builder(
          builder: (context) => IconButton(
            icon: Icon(
              Icons.menu,
              color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : ThemeService.lightTextPrimary,
            ),
            onPressed: () => Scaffold.of(context).openDrawer(),
            tooltip: 'Menu',
          ),
        ),
        actions: (_isSelectionMode || _isMultiSelectMode) ? [
          IconButton(
            icon: Icon(
              Icons.select_all_rounded, 
              size: 18,
              color: _themeService.isDarkMode ? const Color(0xFF7BB3F0) : const Color(0xFF4A90E2),
            ),
            onPressed: () {
              // We'll need to pass the current docs to select all
              // For now, we'll select all visible items
              _selectAllVisibleItems();
            },
            tooltip: _selectedItems.length == _getCurrentItemsCount() ? 'Deselect All' : 'Select All',
            style: IconButton.styleFrom(
              padding: const EdgeInsets.all(6),
              minimumSize: const Size(28, 28),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.check_circle_rounded, 
              size: 18,
              color: _themeService.isDarkMode ? const Color(0xFF81C784) : const Color(0xFF27AE60),
            ),
            onPressed: _selectedItems.isEmpty ? null : _finishSelectedItems,
            tooltip: 'Finish Selected',
            style: IconButton.styleFrom(
              padding: const EdgeInsets.all(6),
              minimumSize: const Size(28, 28),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.priority_high_rounded, 
              size: 18,
              color: _themeService.isDarkMode ? const Color(0xFFE57373) : const Color(0xFFE74C3C),
            ),
            onPressed: _selectedItems.isEmpty ? null : _prioritizeSelectedItems,
            tooltip: 'Prioritize Selected',
            style: IconButton.styleFrom(
              padding: const EdgeInsets.all(6),
              minimumSize: const Size(28, 28),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.delete_rounded, 
              size: 18,
              color: _themeService.isDarkMode ? const Color(0xFFE57373) : const Color(0xFFE74C3C),
            ),
            onPressed: _selectedItems.isEmpty ? null : _deleteSelectedItems,
            tooltip: 'Delete Selected',
            style: IconButton.styleFrom(
              padding: const EdgeInsets.all(6),
              minimumSize: const Size(28, 28),
            ),
          ),
        ] : [
          IconButton(
            icon: const Icon(Icons.checklist),
            onPressed: _enterMultiSelectMode,
            tooltip: 'Select items',
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: _themeService.isDarkMode 
            ? ThemeService.darkBackground 
            : ThemeService.lightBackground,
        child: Column(
          children: [
            // Custom header - simplified without background
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Row(
                  children: [
                    // Logo/Icon
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF27AE60),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.eco_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // App name and tagline
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'EcoPantry',
                            style: TextStyle(
                              color: _themeService.isDarkMode 
                                  ? ThemeService.darkTextPrimary 
                                  : ThemeService.lightTextPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Reduce waste, save the planet',
                            style: TextStyle(
                              color: _themeService.isDarkMode 
                                  ? ThemeService.darkTextSecondary 
                                  : ThemeService.lightTextSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Menu items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 1),
                children: [
                  // Carbon Impact Section Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                    child: Text(
                      'IMPACT',
                      style: TextStyle(
                        color: _themeService.isDarkMode 
                            ? ThemeService.darkTextSecondary 
                            : ThemeService.lightTextSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  
                  // Carbon Savings Card
                  _buildCarbonSavingsCard(),
                  
                  const SizedBox(height: 8),
                  
                  // App Section Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                    child: Text(
                      'APP',
                      style: TextStyle(
                        color: _themeService.isDarkMode 
                            ? ThemeService.darkTextSecondary 
                            : ThemeService.lightTextSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  
                  // Finished Items
                  _buildDrawerItem(
                    icon: Icons.check_circle_rounded,
                    title: 'Finished Items',
                    subtitle: 'View your consumption history',
                    iconColor: const Color(0xFF27AE60),
                    onTap: () {
                      Navigator.pop(context);
                      _showFinishedItemsHistory();
                    },
                  ),
                  
                  // Settings
                  _buildDrawerItem(
                    icon: Icons.settings_rounded,
                    title: 'Settings',
                    subtitle: 'App preferences & configuration',
                    iconColor: const Color(0xFF4A90E2),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/settings');
                    },
                  ),
                  
                  const Divider(height: 32, indent: 24, endIndent: 24),
                  
                  // Account Section
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                    child: Text(
                      'ACCOUNT',
                      style: TextStyle(
                        color: _themeService.isDarkMode 
                            ? ThemeService.darkTextSecondary 
                            : ThemeService.lightTextSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  
                  // User info
                  _buildDrawerItem(
                    icon: Icons.person_rounded,
                    title: user.isAnonymous ? 'Guest User' : (user.displayName ?? 'User'),
                    subtitle: user.email ?? 'Not signed in',
                    iconColor: const Color(0xFF9B59B6),
                    onTap: null,
                  ),
                  
                  // Logout
                  _buildDrawerItem(
                    icon: Icons.logout_rounded,
                    title: 'Logout',
                    subtitle: 'Sign out of your account',
                    iconColor: const Color(0xFFE74C3C),
                    onTap: () async {
                      Navigator.pop(context);
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Logout'),
                          content: const Text('Are you sure you want to logout?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFE74C3C),
                              ),
                              child: const Text('Logout'),
                            ),
                          ],
                        ),
                      );
                      
                      if (confirmed == true) {
                        await AuthService.instance.signOut();
                        if (mounted) {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (context) => const AuthGate()),
                            (route) => false,
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
            
            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: _themeService.isDarkMode 
                        ? ThemeService.darkBorder 
                        : ThemeService.lightBorder,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.eco_rounded,
                    size: 16,
                    color: Color(0xFF27AE60),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Making a difference, one meal at a time',
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                      style: TextStyle(
                        color: _themeService.isDarkMode 
                            ? ThemeService.darkTextSecondary 
                            : ThemeService.lightTextSecondary,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
          heroTag: "add_fab",
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
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
                
                // Filter items by grocery type and must contain text
                final filteredDocs = docs.where((doc) {
                  final data = doc.data();
                  
                  // Check grocery type filter
                  if (_selectedFilters.isNotEmpty) {
                    final groceryType = GroceryType.fromString(data['groceryType'] ?? 'other');
                    if (!_selectedFilters.contains(groceryType)) {
                      return false;
                    }
                  }
                  
                  // Check must contain filter
                  if (_mustContainText.isNotEmpty) {
                    final itemName = (data['name'] ?? '').toString().toLowerCase();
                    if (!itemName.contains(_mustContainText.toLowerCase())) {
                      return false;
                    }
                  }
                  
                  return true;
                }).toList();

                // Sort the filtered items
                final sortedDocs = _sortItems(filteredDocs);
                
                // Store current sorted docs for select all functionality
                _currentSortedDocs = sortedDocs;
                
                return CustomScrollView(
                  slivers: [
                    // Welcome section
                    SliverToBoxAdapter(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(16, 24, 16, 16),
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
                            const SizedBox(width: 16),
                            _CarbonEmissionsWidget(isDarkMode: _themeService.isDarkMode),
                          ],
                        ),
                      ),
                    ),
                    
                    // Compact Filter Button
                    SliverToBoxAdapter(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                              _getFilterDisplayText(),
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
                    ),
                    
                    // Action buttons
                    SliverToBoxAdapter(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                        child: Row(
                          children: [
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
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildActionButton(
                                onPressed: _showPrioritizedItems,
                                icon: Icons.priority_high_rounded,
                                label: 'Priority',
                                color: const Color(0xFFE74C3C),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // Items list or empty state
                    if (docs.isEmpty)
                      SliverFillRemaining(
                        child: _EmptyState(isDarkMode: _themeService.isDarkMode),
                      )
                    else if (filteredDocs.isEmpty)
                      SliverFillRemaining(
                        child: Center(
                          child: Text(
                            'No items found for this filter',
                            style: TextStyle(
                              color: _themeService.isDarkMode ? const Color(0xFF9E9E9E) : const Color(0xFF7F8C8D),
                              fontSize: 16,
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.only(top: 1),
                        sliver: SliverList.separated(
                        itemCount: sortedDocs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final ref = sortedDocs[i].reference;
                          final data = sortedDocs[i].data();
                          final groceryType = GroceryType.fromString(data['groceryType'] ?? 'other');
                          final itemId = sortedDocs[i].id;
                          final isSelected = _selectedItems.contains(itemId);
                          
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: _themeService.isDarkMode ? ThemeService.darkCardBackground : ThemeService.lightCardBackground,
                              borderRadius: BorderRadius.circular(16),
                              border: _isSelectionMode && isSelected 
                                ? Border.all(color: const Color(0xFF27AE60), width: 2)
                                : null,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(_themeService.isDarkMode ? 0.2 : 0.06),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: _isSelectionMode 
                              ? ListTile(
                                  leading: Checkbox(
                                    value: isSelected,
                                    onChanged: (_) => _toggleItemSelection(itemId),
                                    activeColor: const Color(0xFF27AE60),
                                  ),
                                  title: Text(
                                    (data['name'] ?? 'Unknown').toString(),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : const Color(0xFF2C3E50),
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Qty: ${data['quantity'] ?? 1} • ${groceryType.displayName}',
                                    style: TextStyle(
                                      color: _themeService.isDarkMode ? ThemeService.darkTextSecondary : const Color(0xFF7F8C8D),
                                    ),
                                  ),
                                  onTap: () => _toggleItemSelection(itemId),
                                )
                              : ItemTile(
                                  name: (data['name'] ?? 'Unknown').toString(),
                                  expiry: (data['expiryDate'] as Timestamp?)?.toDate(),
                                  quantity: (data['quantity'] ?? 1),
                                  groceryType: groceryType,
                                  isDarkMode: _themeService.isDarkMode,
                                  isSelectionMode: _isSelectionMode,
                                  isSelected: _selectedItems.contains(itemId),
                                  isCompactView: _themeService.isCompactView,
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
                                    // Store item data for undo
                                    final docSnapshot = await ref.get();
                                    if (!docSnapshot.exists) return;
                                    
                                    final data = docSnapshot.data() as Map<String, dynamic>;
                                    final itemName = (data['name'] ?? 'Unknown').toString();
                                    final user = _auth.currentUser!;
                                    final itemId = ref.id;
                                    
                                    // Move to finished_items collection
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
                                    
                                    // Delete from main collection
                                    await ref.delete();
                                    
                                    // Show undo snackbar
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Finished "$itemName"'),
                                          duration: const Duration(seconds: 3),
                                          action: SnackBarAction(
                                            label: 'Undo',
                                            onPressed: () async {
                                              // Restore to main collection
                                              final docRef = _db.collection('users').doc(user.uid).collection('items').doc(itemId);
                                              await docRef.set(data);
                                              
                                              // Remove from finished_items
                                              await finishedItemsRef.delete();
                                              
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(content: Text('Restored "$itemName"')),
                                                );
                                              }
                                            },
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  onRemove: () async {
                                    // Store item data for undo
                                    final docSnapshot = await ref.get();
                                    if (!docSnapshot.exists) return;
                                    
                                    final data = docSnapshot.data() as Map<String, dynamic>;
                                    final itemName = (data['name'] ?? 'Unknown').toString();
                                    final itemId = ref.id;
                                    
                                    // Delete the item
                                    await ref.delete();
                                    
                                    // Show undo snackbar
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Deleted "$itemName"'),
                                          duration: const Duration(seconds: 3),
                                          action: SnackBarAction(
                                            label: 'Undo',
                                            onPressed: () async {
                                              // Restore the item
                                              final docRef = _db.collection('users').doc(user.uid).collection('items').doc(itemId);
                                              await docRef.set(data);
                                              
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(content: Text('Restored "$itemName"')),
                                                );
                                              }
                                            },
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  onSelectMultiple: () {
                                    if (!_isSelectionMode) {
                                      _toggleSelectionMode();
                                      _toggleItemSelection(itemId);
                                    }
                                  },
                                  onPrioritize: () => _prioritizeItem(ref, data),
                                  onUnprioritize: () => _unprioritizeItem(ref, data),
                                  isPrioritized: data['isPrioritized'] == true,
                                  onSelectionChanged: (selected) {
                                    if (selected) {
                                      _selectedItems.add(itemId);
                                    } else {
                                      _selectedItems.remove(itemId);
                                    }
                                    setState(() {});
                                  },
                                ),
                          );
                        },
                      ),
                      ),
                    
                    // Bottom padding for FAB
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 120),
                    ),
                  ],
                );
              },
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
      
      // Check for duplicates before adding
      final existingItems = await _db
          .collection('users')
          .doc(user.uid)
          .collection('items')
          .get();
      
      final existingNames = existingItems.docs
          .map((doc) => (doc.data()['name'] ?? '').toString().toLowerCase())
          .toSet();
      
      if (existingNames.contains(name.toLowerCase())) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Item "$name" already exists in your fridge'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      
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
                Row(
                  children: [
                    Expanded(
                      child: TextField(
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
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () async {
                        final name = nameCtrl.text.trim();
                        if (name.isNotEmpty) {
                          try {
                            final simplifiedName = await ReceiptParser.simplifyFoodName(name);
                            if (simplifiedName != name) {
                              nameCtrl.text = simplifiedName;
                              setLocal(() {});
                              // Trigger prediction with simplified name
                              Future.delayed(const Duration(milliseconds: 500), () {
                                if (nameCtrl.text.trim() == simplifiedName) {
                                  predictExpiry();
                                }
                              });
                            }
                          } catch (e) {
                            print('AI simplification failed: $e');
                          }
                        }
                      },
                      icon: const Icon(Icons.auto_awesome),
                      tooltip: 'Simplify name with AI',
                    ),
                  ],
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


  Future<void> _prioritizeItem(DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data) async {
    final itemName = (data['name'] ?? 'Unknown').toString();
    
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Prioritize Item'),
        content: Text('Prioritize "$itemName" for recipe suggestions? This will help generate recipes that use this item as a main ingredient.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE74C3C),
            ),
            child: const Text('Prioritize'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    // Add priority flag to the item
    await ref.update({
      'isPrioritized': true,
      'prioritizedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$itemName" has been prioritized for recipe suggestions'),
          backgroundColor: const Color(0xFFE74C3C),
        ),
      );
    }
  }

  Future<void> _prioritizeSelectedItems() async {
    if (_selectedItems.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Prioritize Items'),
        content: Text('Mark ${_selectedItems.length} selected items as priority for recipe suggestions?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE74C3C),
            ),
            child: const Text('Prioritize'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final batch = _db.batch();
      int successCount = 0;

      for (final itemId in _selectedItems) {
        try {
          final ref = _db.collection('users').doc(user.uid).collection('items').doc(itemId);
          batch.update(ref, {
            'isPrioritized': true,
            'prioritizedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          successCount++;
        } catch (e) {
          print('Error prioritizing item $itemId: $e');
        }
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$successCount items marked as priority'),
            backgroundColor: const Color(0xFFE74C3C),
          ),
        );
        _exitMultiSelectMode();
      }
    }
  }

  Future<void> _unprioritizeItem(DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data) async {
    final itemName = (data['name'] ?? 'Unknown').toString();
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Priority'),
        content: Text('Remove priority from "$itemName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.update({
        'isPrioritized': false,
        'prioritizedAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Priority removed from "$itemName"'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _showPrioritizedItems() async {
    try {
      final prioritizedItems = await _db
          .collection('users')
          .doc(user.uid)
          .collection('items')
          .where('isPrioritized', isEqualTo: true)
          .get();

      if (!mounted) return;

      // Sort items by prioritizedAt manually
      final sortedItems = prioritizedItems.docs.toList()
        ..sort((a, b) {
          final aTime = a.data()['prioritizedAt'] as Timestamp?;
          final bTime = b.data()['prioritizedAt'] as Timestamp?;
          
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          
          return bTime.compareTo(aTime); // Descending order
        });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _themeService.isDarkMode 
          ? ThemeService.darkCard 
          : ThemeService.lightCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(
                    Icons.priority_high_rounded,
                    color: const Color(0xFFE74C3C),
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Prioritized Items',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _themeService.isDarkMode 
                          ? ThemeService.darkTextPrimary 
                          : ThemeService.lightTextPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${sortedItems.length}',
                    style: TextStyle(
                      fontSize: 16,
                      color: _themeService.isDarkMode 
                          ? ThemeService.darkTextSecondary 
                          : ThemeService.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: sortedItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.priority_high_outlined,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No prioritized items',
                            style: TextStyle(
                              fontSize: 18,
                              color: _themeService.isDarkMode 
                                  ? ThemeService.darkTextSecondary 
                                  : ThemeService.lightTextSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Prioritize items to see them here',
                            style: TextStyle(
                              fontSize: 14,
                              color: _themeService.isDarkMode 
                                  ? ThemeService.darkTextSecondary 
                                  : ThemeService.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: sortedItems.length,
                      itemBuilder: (context, index) {
                        final doc = sortedItems[index];
                        final data = doc.data();
                        final ref = doc.reference;
                        
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          color: _themeService.isDarkMode 
                              ? ThemeService.darkBackground 
                              : ThemeService.lightBackground,
                          child: ListTile(
                            leading: Icon(
                              _getGroceryIcon(GroceryType.fromString(data['groceryType'] ?? 'other')),
                              color: _getGroceryColor(GroceryType.fromString(data['groceryType'] ?? 'other')),
                            ),
                            title: Text(
                              data['name'] ?? 'Unknown',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _themeService.isDarkMode 
                                    ? ThemeService.darkTextPrimary 
                                    : ThemeService.lightTextPrimary,
                              ),
                            ),
                            subtitle: Text(
                              'Prioritized ${_formatPrioritizedDate(data['prioritizedAt'])}',
                              style: TextStyle(
                                color: _themeService.isDarkMode 
                                    ? ThemeService.darkTextSecondary 
                                    : ThemeService.lightTextSecondary,
                              ),
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'unprioritize') {
                                  _unprioritizeItem(ref, data);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'unprioritize',
                                  child: Row(
                                    children: [
                                      Icon(Icons.priority_high_outlined, color: Colors.orange),
                                      SizedBox(width: 8),
                                      Text('Remove Priority'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading prioritized items: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  String _formatPrioritizedDate(dynamic timestamp) {
    if (timestamp == null) return 'recently';
    
    try {
      final date = timestamp.toDate();
      final now = DateTime.now();
      final difference = now.difference(date);
      
      if (difference.inDays > 0) {
        return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
      } else {
        return 'just now';
      }
    } catch (e) {
      return 'recently';
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

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: _themeService.isDarkMode 
                            ? ThemeService.darkTextPrimary 
                            : ThemeService.lightTextPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: _themeService.isDarkMode 
                            ? ThemeService.darkTextSecondary 
                            : ThemeService.lightTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  color: _themeService.isDarkMode 
                      ? ThemeService.darkTextSecondary 
                      : ThemeService.lightTextSecondary,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatCarbonValue(double carbonKg) {
    // Convert kg to lbs if user preference is set to lbs (1 kg = 2.20462 lbs)
    if (_themeService.useLbs) {
      final carbonLbs = carbonKg * 2.20462;
      return '${carbonLbs.toStringAsFixed(1)} lbs CO₂';
    } else {
      return '${carbonKg.toStringAsFixed(1)} kg CO₂';
    }
  }

  Widget _buildCarbonSavingsCard() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('users')
          .doc(user.uid)
          .collection('finished_items')
          .snapshots(),
      builder: (context, snapshot) {
        double carbonSaved = 0.0;
        int itemsFinished = 0;
        
        if (snapshot.hasData) {
          itemsFinished = snapshot.data!.docs.length;
          for (var doc in snapshot.data!.docs) {
            final data = doc.data();
            final quantity = (data['quantity'] ?? 1) as num;
            final groceryType = data['groceryType'] ?? 'other';
            
            double carbonPerKg = _getCarbonFootprint(groceryType);
            carbonSaved += quantity * carbonPerKg * 0.5; // Assume average 0.5kg per item
          }
        }
        
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF27AE60), Color(0xFF2ECC71)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF27AE60).withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.eco_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Carbon Impact Saved',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatCarbonValue(carbonSaved),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'emissions avoided',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$itemsFinished',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'items finished',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showFinishedItemsHistory() async {
    try {
      final finishedItems = await _db
          .collection('users')
          .doc(user.uid)
          .collection('finished_items')
          .orderBy('finishedAt', descending: true)
          .get();

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: _themeService.isDarkMode 
            ? ThemeService.darkCard 
            : ThemeService.lightCard,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF27AE60).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF27AE60),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Finished Items',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _themeService.isDarkMode 
                              ? ThemeService.darkTextPrimary 
                              : ThemeService.lightTextPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '${finishedItems.docs.length}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _themeService.isDarkMode 
                            ? ThemeService.darkTextSecondary 
                            : ThemeService.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Your consumption history & environmental impact',
                  style: TextStyle(
                    fontSize: 13,
                    color: _themeService.isDarkMode 
                        ? ThemeService.darkTextSecondary 
                        : ThemeService.lightTextSecondary,
                  ),
                ),
              ),
              const Divider(height: 24),
              Expanded(
                child: finishedItems.docs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No finished items yet',
                              style: TextStyle(
                                fontSize: 18,
                                color: _themeService.isDarkMode 
                                    ? ThemeService.darkTextSecondary 
                                    : ThemeService.lightTextSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Items you finish will appear here',
                              style: TextStyle(
                                fontSize: 14,
                                color: _themeService.isDarkMode 
                                    ? ThemeService.darkTextSecondary 
                                    : ThemeService.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: finishedItems.docs.length,
                        itemBuilder: (context, index) {
                          final doc = finishedItems.docs[index];
                          final data = doc.data();
                          final groceryType = GroceryType.fromString(data['groceryType'] ?? 'other');
                          final finishedAt = data['finishedAt'] as Timestamp?;
                          
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: _themeService.isDarkMode 
                                ? ThemeService.darkBackground 
                                : ThemeService.lightBackground,
                            child: ListTile(
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: _getGroceryColor(groceryType).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  _getGroceryIcon(groceryType),
                                  color: _getGroceryColor(groceryType),
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                data['name'] ?? 'Unknown',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _themeService.isDarkMode 
                                      ? ThemeService.darkTextPrimary 
                                      : ThemeService.lightTextPrimary,
                                ),
                              ),
                              subtitle: Text(
                                'Qty: ${data['quantity'] ?? 1} • Finished ${_formatFinishedDate(finishedAt)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _themeService.isDarkMode 
                                      ? ThemeService.darkTextSecondary 
                                      : ThemeService.lightTextSecondary,
                                ),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF27AE60).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  color: Color(0xFF27AE60),
                                  size: 16,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading finished items: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  String _formatFinishedDate(dynamic timestamp) {
    if (timestamp == null) return 'recently';
    
    try {
      final date = (timestamp as Timestamp).toDate();
      final now = DateTime.now();
      final difference = now.difference(date);
      
      if (difference.inDays > 0) {
        return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
      } else {
        return 'just now';
      }
    } catch (e) {
      return 'recently';
    }
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
        // Allow recipe generation even with empty fridge
        // The LLM will handle empty fridge case with pantry staples
      }

      // Extract ingredient names and prioritize items
      final ingredients = snapshot.docs
          .map((doc) => doc.data()['name']?.toString() ?? '')
          .where((name) => name.isNotEmpty)
          .toList();
      
      // Get prioritized items
      final prioritizedItems = snapshot.docs
          .where((doc) => doc.data()['isPrioritized'] == true)
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

      // Generate recipes using Mistral AI (requesting 3 for better variety)
      // Pass selected filters and prioritized items to help the LLM focus
      final recipeData = await LLMService().generateRecipes(
        filteredIngredients, 
        count: 3,
        preferredCategories: _selectedFilters.isNotEmpty 
            ? _selectedFilters.map((type) => type.displayName).toList()
            : null,
        prioritizeFilteredItems: _selectedFilters.isNotEmpty,
        prioritizedItems: prioritizedItems,
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
  late final ThemeService _themeService;

  @override
  void initState() {
    super.initState();
    _themeService = ThemeService();
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

  String _formatCarbonValue(double carbonKg) {
    // Convert kg to lbs if user preference is set to lbs (1 kg = 2.20462 lbs)
    if (_themeService.useLbs) {
      final carbonLbs = carbonKg * 2.20462;
      return '${carbonLbs.toStringAsFixed(1)} lbs CO₂';
    } else {
      return '${carbonKg.toStringAsFixed(1)} kg CO₂';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                        _formatCarbonValue(_carbonSaved),
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
      ),
    );
  }

  Widget _buildSustainabilityTips() {
    return Container(
      height: 120, // Fixed height to ensure scrolling works
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
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                '• Plan meals to reduce food waste\n• Buy local and seasonal produce\n• Use leftovers creatively\n• Compost food scraps\n• Store food properly to extend freshness\n• Freeze excess ingredients before they spoil\n• Use vegetable scraps for homemade broth\n• Choose imperfect produce to reduce waste',
                style: TextStyle(
                  fontSize: 12,
                  color: widget.isDarkMode ? const Color(0xFF9E9E9E) : const Color(0xFF7F8C8D),
                  height: 1.4,
                ),
              ),
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
  late final ThemeService _themeService;

  @override
  void initState() {
    super.initState();
    _themeService = ThemeService();
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

  String _formatCarbonValue(double carbonKg) {
    // Convert kg to lbs if user preference is set to lbs (1 kg = 2.20462 lbs)
    if (_themeService.useLbs) {
      final carbonLbs = carbonKg * 2.20462;
      return '${carbonLbs.toStringAsFixed(1)} lbs CO₂';
    } else {
      return '${carbonKg.toStringAsFixed(1)} kg CO₂';
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
          width: 100,
          constraints: const BoxConstraints(
            minHeight: 50,
            maxHeight: 60,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF27AE60).withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFF27AE60).withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('You\'ve saved ${_formatCarbonValue(carbonSaved)} by using your food!'),
                    backgroundColor: const Color(0xFF27AE60),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.eco_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isLoading ? '...' : _formatCarbonValue(carbonSaved),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
