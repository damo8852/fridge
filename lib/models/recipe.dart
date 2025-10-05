class Recipe {
  final String name;
  final List<String> ingredients;
  final List<String> instructions;
  final String prepTime;
  final String cookTime;
  final List<String> shoppingList;

  Recipe({
    required this.name,
    required this.ingredients,
    required this.instructions,
    required this.prepTime,
    this.cookTime = 'Unknown',
    this.shoppingList = const [],
  });

  factory Recipe.fromMap(Map<String, dynamic> map) {
    return Recipe(
      name: map['name']?.toString() ?? 'Unnamed Recipe',
      ingredients: (map['ingredients'] as List?)?.map((e) => e.toString()).toList() ?? [],
      instructions: (map['instructions'] as List?)?.map((e) => e.toString()).toList() ?? [],
      prepTime: map['prepTime']?.toString() ?? 'Unknown',
      cookTime: map['cookTime']?.toString() ?? 'Unknown',
      shoppingList: (map['shoppingList'] as List?)?.map((e) => e.toString()).toList() ?? [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'ingredients': ingredients,
      'instructions': instructions,
      'prepTime': prepTime,
      'cookTime': cookTime,
      'shoppingList': shoppingList,
    };
  }
}
