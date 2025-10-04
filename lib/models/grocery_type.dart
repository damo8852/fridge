enum GroceryType {
  meat('Meat'),
  poultry('Poultry'),
  seafood('Seafood'),
  vegetable('Vegetable'),
  fruit('Fruit'),
  dairy('Dairy'),
  grain('Grain'),
  beverage('Beverage'),
  snack('Snack'),
  condiment('Condiment'),
  frozen('Frozen'),
  other('Other');

  const GroceryType(this.displayName);
  
  final String displayName;

  static GroceryType fromString(String value) {
    return GroceryType.values.firstWhere(
      (type) => type.name == value || type.displayName == value,
      orElse: () => GroceryType.other,
    );
  }

  static List<GroceryType> get allTypes => GroceryType.values;
}
