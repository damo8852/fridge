class Recipe {
  final String name;
  final List<String> ingredients;
  final List<String> instructions;
  final String prepTime;

  Recipe({
    required this.name,
    required this.ingredients,
    required this.instructions,
    required this.prepTime,
  });

  factory Recipe.fromMap(Map<String, dynamic> map) {
    return Recipe(
      name: map['name']?.toString() ?? 'Unnamed Recipe',
      ingredients: (map['ingredients'] as List?)?.map((e) => e.toString()).toList() ?? [],
      instructions: (map['instructions'] as List?)?.map((e) => e.toString()).toList() ?? [],
      prepTime: map['prepTime']?.toString() ?? 'Unknown',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'ingredients': ingredients,
      'instructions': instructions,
      'prepTime': prepTime,
    };
  }
}
