import 'package:flutter/material.dart';
import '../models/recipe.dart';
import '../services/theme_service.dart';

class RecipesScreen extends StatefulWidget {
  final List<Recipe> recipes;
  final List<String> usedIngredients;

  const RecipesScreen({
    super.key,
    required this.recipes,
    required this.usedIngredients,
  });

  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends State<RecipesScreen> {
  bool _showIngredientsDetails = false;
  late final ThemeService _themeService;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _themeService.isDarkMode ? ThemeService.darkBackground : ThemeService.lightBackground,
      appBar: AppBar(
        title: Text(
          'Recipe Suggestions',
          style: TextStyle(
            color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : ThemeService.lightTextPrimary,
          ),
        ),
        backgroundColor: _themeService.isDarkMode ? ThemeService.darkBackground : ThemeService.lightBackground,
        elevation: 0,
        iconTheme: IconThemeData(
          color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : ThemeService.lightTextPrimary,
        ),
      ),
      body: widget.recipes.isEmpty
          ? _buildEmptyState(context)
          : Column(
              children: [
                _buildIngredientsHeader(context),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: widget.recipes.length,
                    itemBuilder: (context, index) {
                      return _buildRecipeCard(context, widget.recipes[index]);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildIngredientsHeader(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _themeService.isDarkMode ? ThemeService.darkCardBackground : Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: _themeService.isDarkMode ? Border.all(color: ThemeService.darkBorder) : null,
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _showIngredientsDetails = !_showIngredientsDetails;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    Icons.kitchen_rounded,
                    color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : Theme.of(context).colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.usedIngredients.isEmpty 
                          ? 'No ingredients from fridge - using pantry staples'
                          : 'Using ${widget.usedIngredients.length} ingredients from your fridge',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : Theme.of(context).colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  Icon(
                    _showIngredientsDetails ? Icons.expand_less : Icons.expand_more,
                    color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ],
              ),
            ),
          ),
          if (_showIngredientsDetails)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: widget.usedIngredients.isEmpty 
                  ? Text(
                      'These recipes use common pantry staples like salt, pepper, oil, garlic, onions, rice, pasta, and canned goods. You may need to buy a few fresh ingredients as listed in each recipe.',
                      style: TextStyle(
                        color: _themeService.isDarkMode ? ThemeService.darkTextSecondary : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    )
                  : Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: widget.usedIngredients.map((ingredient) {
                        return Chip(
                          label: Text(
                            ingredient,
                            style: const TextStyle(fontSize: 11),
                          ),
                          backgroundColor: _themeService.isDarkMode ? ThemeService.darkBorder : Theme.of(context).colorScheme.surface,
                          labelStyle: TextStyle(
                            color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : Theme.of(context).colorScheme.onSurface,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        );
                      }).toList(),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecipeCard(BuildContext context, Recipe recipe) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      color: _themeService.isDarkMode ? ThemeService.darkCardBackground : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => _showRecipeDetails(context, recipe),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      recipe.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : null,
                          ),
                    ),
                  ),
                  Icon(
                    Icons.restaurant,
                    color: Theme.of(context).colorScheme.primary,
                    size: 24,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 16,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      const SizedBox(width: 4),
                        Text(
                          '${recipe.prepTime} prep',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: _themeService.isDarkMode ? ThemeService.darkTextSecondary : Theme.of(context).colorScheme.secondary,
                              ),
                      ),
                      if (recipe.cookTime != 'Unknown') ...[
                        const SizedBox(width: 8),
                        Text(
                          '• ${recipe.cookTime} cook',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: _themeService.isDarkMode ? ThemeService.darkTextSecondary : Theme.of(context).colorScheme.secondary,
                              ),
                        ),
                      ],
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        Icon(
                          Icons.kitchen,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      const SizedBox(width: 4),
                      Text(
                        '${recipe.ingredients.length} from fridge',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ],
                  ),
                  if (recipe.shoppingList.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shopping_cart,
                          size: 16,
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '+${recipe.shoppingList.length} to buy',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : Theme.of(context).colorScheme.tertiary,
                              ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Available ingredients section
              Text(
                'Available in your fridge:',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : Theme.of(context).colorScheme.primary,
                    ),
              ),
              const SizedBox(height: 4),
              ...recipe.ingredients.take(3).map((ingredient) => Padding(
                    padding: const EdgeInsets.only(left: 8, top: 2),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            ingredient,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: _themeService.isDarkMode ? ThemeService.darkTextSecondary : Theme.of(context).colorScheme.onSurface,
                                ),
                          ),
                        ),
                      ],
                    ),
                  )),
              if (recipe.ingredients.length > 3)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: Text(
                    '+ ${recipe.ingredients.length - 3} more from fridge',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _themeService.isDarkMode ? ThemeService.darkTextSecondary : Theme.of(context).colorScheme.primary,
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                ),
              // Shopping list section
              if (recipe.shoppingList.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Need to buy:',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : Theme.of(context).colorScheme.tertiary,
                      ),
                ),
                const SizedBox(height: 4),
                ...recipe.shoppingList.take(2).map((item) => Padding(
                      padding: const EdgeInsets.only(left: 8, top: 2),
                      child: Row(
                        children: [
                          Icon(
                            Icons.shopping_cart_outlined,
                            size: 16,
                            color: Theme.of(context).colorScheme.tertiary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: _themeService.isDarkMode ? ThemeService.darkTextSecondary : Theme.of(context).colorScheme.tertiary,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    )),
                if (recipe.shoppingList.length > 2)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: Text(
                      '+ ${recipe.shoppingList.length - 2} more to buy',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _themeService.isDarkMode ? ThemeService.darkTextSecondary : Theme.of(context).colorScheme.tertiary,
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _showRecipeDetails(context, recipe),
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('View Full Recipe'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRecipeDetails(BuildContext context, Recipe recipe) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      recipe.name,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${recipe.prepTime} prep',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        if (recipe.cookTime != 'Unknown') ...[
                          const SizedBox(width: 8),
                          Text(
                            '• ${recipe.cookTime} cook',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                      ],
                    ),
              const SizedBox(height: 24),
              Text(
                'Available in your fridge',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
              const SizedBox(height: 12),
              ...recipe.ingredients.map((ingredient) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            ingredient,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                      ],
                    ),
                  )),
              if (recipe.shoppingList.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Need to buy',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                ),
                const SizedBox(height: 12),
                ...recipe.shoppingList.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.shopping_cart_outlined,
                            size: 20,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Theme.of(context).colorScheme.secondary,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
                    const SizedBox(height: 24),
                    Text(
                      'Directions',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    ...recipe.instructions.asMap().entries.map((entry) {
                      final index = entry.key;
                      final instruction = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                instruction,
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      height: 1.5,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.restaurant_menu,
              size: 64,
              color: _themeService.isDarkMode ? ThemeService.darkTextSecondary : Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No recipes generated',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : null,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adding more items to your fridge or check your Mistral API connection.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _themeService.isDarkMode ? ThemeService.darkTextSecondary : Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
