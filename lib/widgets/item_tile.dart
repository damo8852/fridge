import 'package:flutter/material.dart';
import '../models/grocery_type.dart';

class ItemTile extends StatelessWidget {
  const ItemTile({
    super.key,
    required this.name,
    required this.expiry,
    required this.quantity,
    required this.groceryType,
    required this.onEdit,
    required this.onUsedHalf,
    required this.onFinish,
    required this.onRemove,
    this.onSelectMultiple,
    this.onPrioritize,
    this.onUnprioritize,
    this.isDarkMode = false,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.isPrioritized = false,
    this.isCompactView = false,
    this.onSelectionChanged,
  });

  final String name;
  final DateTime? expiry;
  final num quantity;
  final GroceryType groceryType;
  final VoidCallback onEdit;
  final Future<void> Function() onUsedHalf;
  final Future<void> Function() onFinish;
  final Future<void> Function() onRemove;
  final VoidCallback? onSelectMultiple;
  final VoidCallback? onPrioritize;
  final VoidCallback? onUnprioritize;
  final bool isDarkMode;
  final bool isSelectionMode;
  final bool isSelected;
  final bool isPrioritized;
  final bool isCompactView;
  final ValueChanged<bool>? onSelectionChanged;

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

  bool _shouldShowPrioritize() {
    // Always show prioritize button for all items
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = expiry != null ? expiry!.toLocal().toString().split(' ').first : '—';
    int? daysLeft;
    if (expiry != null) {
      final today = DateTime.now();
      daysLeft = DateTime(expiry!.year, expiry!.month, expiry!.day)
          .difference(DateTime(today.year, today.month, today.day)).inDays;
    }
    
    final chip = daysLeft == null
        ? 'no date'
        : (daysLeft <= 0 ? 'today' : daysLeft == 1 ? 'in 1 day' : 'in $daysLeft days');
    
    final chipColor = daysLeft == null
        ? const Color(0xFF95A5A6)
        : (daysLeft <= 1 ? const Color(0xFFE74C3C) : daysLeft <= 3 ? const Color(0xFFF39C12) : const Color(0xFF27AE60));

    final groceryColor = _getGroceryColor(groceryType);
    final groceryIcon = _getGroceryIcon(groceryType);

    if (isCompactView) {
      return GestureDetector(
        onLongPress: onSelectMultiple,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Stack(
            children: [
              Row(
                children: [
                  // Smaller grocery type icon
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: groceryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      groceryIcon,
                      color: groceryColor,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Compact item details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isDarkMode ? const Color(0xFFE8E8E8) : const Color(0xFF2C3E50),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isPrioritized)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE74C3C),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  '!',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: groceryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                groceryType.displayName,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: groceryColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Qty: $quantity',
                              style: TextStyle(
                                fontSize: 10,
                                color: isDarkMode ? const Color(0xFF7BB3F0) : const Color(0xFF3498DB),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: chipColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                chip,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: chipColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Smaller action menu
                  Container(
                    decoration: BoxDecoration(
                      color: isDarkMode ? const Color(0xFF3C3C3C) : const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        color: Color(0xFF7F8C8D),
                        size: 16,
                      ),
                      onSelected: (v) {
                        if (v == 'edit') onEdit();
                        if (v == 'half') onUsedHalf();
                        if (v == 'finish') onFinish();
                        if (v == 'remove') onRemove();
                        if (v == 'select_multiple' && onSelectMultiple != null) onSelectMultiple!();
                        if (v == 'prioritize' && onPrioritize != null) onPrioritize!();
                        if (v == 'unprioritize' && onUnprioritize != null) onUnprioritize!();
                      },
                      itemBuilder: (_) => [
                        if (onSelectMultiple != null)
                          PopupMenuItem(
                            value: 'select_multiple',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.checklist_rounded,
                                  size: 18,
                                  color: Color(0xFF27AE60),
                                ),
                                const SizedBox(width: 8),
                                const Text('Select Multiple'),
                              ],
                            ),
                          ),
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              const Icon(
                                Icons.edit_rounded,
                                size: 18,
                                color: Color(0xFF4A90E2),
                              ),
                              const SizedBox(width: 8),
                              const Text('Edit'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'half',
                          child: Row(
                            children: [
                              const Icon(
                                Icons.remove_circle_outline,
                                size: 18,
                                color: Color(0xFFF39C12),
                              ),
                              const SizedBox(width: 8),
                              const Text('Used ½'),
                            ],
                          ),
                        ),
                        if (onPrioritize != null && _shouldShowPrioritize() && !isPrioritized)
                          PopupMenuItem(
                            value: 'prioritize',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.priority_high_rounded,
                                  size: 18,
                                  color: Color(0xFFE74C3C),
                                ),
                                const SizedBox(width: 8),
                                const Text('Prioritize Item'),
                              ],
                            ),
                          ),
                        if (onUnprioritize != null && isPrioritized)
                          PopupMenuItem(
                            value: 'unprioritize',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.priority_high_outlined,
                                  size: 18,
                                  color: Colors.orange,
                                ),
                                const SizedBox(width: 8),
                                const Text('Remove Priority'),
                              ],
                            ),
                          ),
                        PopupMenuItem(
                          value: 'finish',
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle_rounded,
                                size: 18,
                                color: Color(0xFF27AE60),
                              ),
                              const SizedBox(width: 8),
                              const Text('Finished'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'remove',
                          child: Row(
                            children: [
                              const Icon(
                                Icons.delete_rounded,
                                size: 18,
                                color: Color(0xFFE74C3C),
                              ),
                              const SizedBox(width: 8),
                              const Text('Remove'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Checkbox in top-right corner
              if (isSelectionMode)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (value) => onSelectionChanged?.call(value ?? false),
                    activeColor: const Color(0xFF27AE60),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // Regular view (existing code)
    return GestureDetector(
      onLongPress: onSelectMultiple,
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Row(
        children: [
          // Grocery type icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: groceryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              groceryIcon,
              color: groceryColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          // Item details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDarkMode ? const Color(0xFFE8E8E8) : const Color(0xFF2C3E50),
                        ),
                      ),
                    ),
                    if (isPrioritized)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE74C3C),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          '!',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: groceryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        groceryType.displayName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: groceryColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isDarkMode ? const Color(0xFF7BB3F0) : const Color(0xFF3498DB),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inventory_2_rounded,
                            size: 12,
                            color: isDarkMode ? const Color(0xFF7BB3F0) : const Color(0xFF3498DB),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Qty: $quantity',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: isDarkMode ? const Color(0xFF7BB3F0) : const Color(0xFF3498DB),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 14,
                      color: chipColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Expires: $dateStr',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDarkMode ? const Color(0xFF9E9E9E) : const Color(0xFF7F8C8D),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: chipColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        chip,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: chipColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Action menu
          Container(
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF3C3C3C) : const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: PopupMenuButton<String>(
              icon: const Icon(
                Icons.more_vert_rounded,
                color: Color(0xFF7F8C8D),
              ),
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'half') onUsedHalf();
                if (v == 'finish') onFinish();
                if (v == 'remove') onRemove();
                if (v == 'select_multiple' && onSelectMultiple != null) onSelectMultiple!();
                if (v == 'prioritize' && onPrioritize != null) onPrioritize!();
                if (v == 'unprioritize' && onUnprioritize != null) onUnprioritize!();
              },
              itemBuilder: (_) => [
                if (onSelectMultiple != null)
                  PopupMenuItem(
                    value: 'select_multiple',
                    child: Row(
                      children: [
                        const Icon(
                          Icons.checklist_rounded,
                          size: 18,
                          color: Color(0xFF27AE60),
                        ),
                        const SizedBox(width: 8),
                        const Text('Select Multiple'),
                      ],
                    ),
                  ),
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      const Icon(
                        Icons.edit_rounded,
                        size: 18,
                        color: Color(0xFF4A90E2),
                      ),
                      const SizedBox(width: 8),
                      const Text('Edit'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'half',
                  child: Row(
                    children: [
                      const Icon(
                        Icons.remove_circle_outline,
                        size: 18,
                        color: Color(0xFFF39C12),
                      ),
                      const SizedBox(width: 8),
                      const Text('Used ½'),
                    ],
                  ),
                ),
                if (onPrioritize != null && _shouldShowPrioritize() && !isPrioritized)
                  PopupMenuItem(
                    value: 'prioritize',
                    child: Row(
                      children: [
                        const Icon(
                          Icons.priority_high_rounded,
                          size: 18,
                          color: Color(0xFFE74C3C),
                        ),
                        const SizedBox(width: 8),
                        const Text('Prioritize Item'),
                      ],
                    ),
                  ),
                if (onUnprioritize != null && isPrioritized)
                  PopupMenuItem(
                    value: 'unprioritize',
                    child: Row(
                      children: [
                        const Icon(
                          Icons.priority_high_outlined,
                          size: 18,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        const Text('Remove Priority'),
                      ],
                    ),
                  ),
                PopupMenuItem(
                  value: 'finish',
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: Color(0xFF27AE60),
                      ),
                      const SizedBox(width: 8),
                      const Text('Finished'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'remove',
                  child: Row(
                    children: [
                      const Icon(
                        Icons.delete_rounded,
                        size: 18,
                        color: Color(0xFFE74C3C),
                      ),
                      const SizedBox(width: 8),
                      const Text('Remove'),
                    ],
                  ),
                ),
              ],
            ),
          ),
            ],
            ),
            // Checkbox in top-right corner
            if (isSelectionMode)
              Positioned(
                top: 0,
                right: 0,
                child: Checkbox(
                  value: isSelected,
                  onChanged: (value) => onSelectionChanged?.call(value ?? false),
                  activeColor: const Color(0xFF27AE60),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
