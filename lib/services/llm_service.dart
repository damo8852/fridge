import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config_service.dart';

class LLMService {
  // Mistral API configuration
  static const String _baseUrl = 'https://api.mistral.ai/v1';
  static const String _model = 'mistral-tiny'; // Fast and cost-effective model
  static const String _recipeModel = 'mistral-small'; // Better model for recipe generation

  final ConfigService _configService = ConfigService();

  static final LLMService _instance = LLMService._internal();
  factory LLMService() => _instance;
  LLMService._internal();

  /// Get the Mistral API key
  Future<String?> _getApiKey() async {
    return await _configService.getMistralApiKey();
  }

  /// Predict expiry date in days for a given food item
  /// Returns number of days until expiry, or null if prediction fails
  Future<int?> predictExpiryDays(String itemName, {String? additionalContext}) async {
    try {
      final prompt = _buildPrompt(itemName, additionalContext);
      final response = await _callMistral(prompt, _model);

      if (response != null) {
        final days = _parseExpiryDays(response);
        return days;
      }
    } catch (e) {
      print('LLM prediction error: $e');
    }

    return null;
  }

  /// Predict expiry date and grocery type for a given food item
  /// Returns a map with 'days' and 'type' keys, or null if prediction fails
  Future<Map<String, dynamic>?> predictExpiryAndType(String itemName, {String? additionalContext}) async {
    try {
      final prompt = _buildPromptWithType(itemName, additionalContext);
      final response = await _callMistral(prompt, _model);

      if (response != null) {
        final result = _parseExpiryAndType(response);
        return result;
      }
    } catch (e) {
      print('LLM prediction error: $e');
    }

    return null;
  }

  String _buildPrompt(String itemName, String? additionalContext) {
    final context = additionalContext != null ? ' Additional context: $additionalContext' : '';

    return '''Food item: $itemName$context

Predict days until expiry. You can also assume that items that belong in the fridge are refridgerated accordingly. Respond with ONLY a number:

For Example:
milk -> 7
chicken -> 3
eggs -> 14
bread -> 5
strawberries -> 4
yogurt -> 10
spinach -> 5
beef -> 2
rice -> 730
jasmine rice -> 730
basmati rice -> 730
brown rice -> 730
white rice -> 730
pasta -> 730
noodles -> 730
quinoa -> 365
oats -> 365
oatmeal -> 365
flour -> 365
salt -> 3650
pepper -> 1095
sugar -> 1095
oil -> 365
vinegar -> 1095
honey -> 3650
spices -> 1095
herbs -> 730
nuts -> 365
beans -> 730
lentils -> 730
coffee -> 365
tea -> 730
cereal -> 365

$itemName ->''';
  }

  String _buildPromptWithType(String itemName, String? additionalContext) {
    final context = additionalContext != null ? ' Additional context: $additionalContext' : '';

    return '''Food item: $itemName$context

Predict days and type. Respond with ONLY JSON:

Examples:
milk -> {"days": 7, "type": "dairy"}
chicken -> {"days": 3, "type": "poultry"}
eggs -> {"days": 14, "type": "dairy"}
bread -> {"days": 5, "type": "grain"}
strawberries -> {"days": 4, "type": "fruit"}
yogurt -> {"days": 10, "type": "dairy"}
spinach -> {"days": 5, "type": "vegetable"}
beef -> {"days": 2, "type": "meat"}
rice -> {"days": 730, "type": "grain"}
jasmine rice -> {"days": 730, "type": "grain"}
basmati rice -> {"days": 730, "type": "grain"}
brown rice -> {"days": 730, "type": "grain"}
white rice -> {"days": 730, "type": "grain"}
pasta -> {"days": 730, "type": "grain"}
noodles -> {"days": 730, "type": "grain"}
quinoa -> {"days": 365, "type": "grain"}
oats -> {"days": 365, "type": "grain"}
oatmeal -> {"days": 365, "type": "grain"}
flour -> {"days": 365, "type": "grain"}
salt -> {"days": 3650, "type": "condiment"}
pepper -> {"days": 1095, "type": "condiment"}
sugar -> {"days": 1095, "type": "condiment"}
oil -> {"days": 365, "type": "condiment"}
vinegar -> {"days": 1095, "type": "condiment"}
honey -> {"days": 3650, "type": "condiment"}
spices -> {"days": 1095, "type": "condiment"}
herbs -> {"days": 730, "type": "condiment"}
nuts -> {"days": 365, "type": "snack"}
beans -> {"days": 730, "type": "grain"}
lentils -> {"days": 730, "type": "grain"}
coffee -> {"days": 365, "type": "beverage"}
tea -> {"days": 730, "type": "beverage"}
cereal -> {"days": 365, "type": "grain"}

Types: meat, poultry, seafood, vegetable, fruit, dairy, grain, beverage, snack, condiment, frozen, other

$itemName ->''';
  }

  Future<String?> _callMistral(String prompt, String model) async {
    final apiKey = await _getApiKey();
    if (apiKey == null) {
      print('No Mistral API key found');
      return null;
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: json.encode({
          'model': model,
          'messages': [
            {
              'role': 'user',
              'content': prompt,
            }
          ],
          'temperature': 0.1, // Low temperature for consistent results
          'max_tokens': 50, // Limit response length for expiry predictions
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final result = data['choices']?[0]?['message']?['content']?.toString().trim();
        return result;
      } else {
        print('Mistral API error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('HTTP request error: $e');
    }

    return null;
  }

  int? _parseExpiryDays(String response) {
    // Clean the response and extract first number
    final cleanResponse = response.trim().toLowerCase();

    // Look for patterns like "7", "7 days", "7-10", etc.
    final patterns = [
      RegExp(r'^(\d{1,4})$'), // Just a number
      RegExp(r'(\d{1,4})\s*days?'), // "7 days" or "7 day"
      RegExp(r'(\d{1,4})[-–]\d+'), // "7-10" or "7–10"
      RegExp(r'\b(\d{1,4})\b'), // Any number in the text
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(cleanResponse);
      if (match != null) {
        final days = int.tryParse(match.group(1)!);
        if (days != null && days > 0 && days <= 3650) {
          return days;
        }
      }
    }

    return null;
  }

  Map<String, dynamic>? _parseExpiryAndType(String response) {
    try {
      // Try to parse as JSON first
      final cleanResponse = response.trim();
      final data = json.decode(cleanResponse);
      if (data is Map<String, dynamic>) {
        final days = data['days'];
        final type = data['type'];

        if (days is int && type is String) {
          return {'days': days, 'type': type};
        }
      }
    } catch (e) {
      // If JSON parsing fails, try to extract numbers and guess type
      final days = _parseExpiryDays(response);
      if (days != null) {
        return {'days': days, 'type': 'other'};
      }
    }

    return null;
  }

  /// Check if Mistral API is available
  Future<bool> isAvailable() async {
    final apiKey = await _getApiKey();
    return apiKey != null && apiKey.isNotEmpty;
  }

  /// Get list of available Mistral models
  Future<List<String>> getAvailableModels() async {
    // Return the models we're configured to use
    return [_model, _recipeModel];
  }

  /// Generate recipe suggestions based on available ingredients
  /// Returns a list of recipe objects with name, ingredients, and instructions
  Future<List<Map<String, dynamic>>> generateRecipes(List<String> ingredients, {int count = 2, List<String>? preferredCategories, bool prioritizeFilteredItems = false, List<String>? prioritizedItems}) async {
    if (ingredients.isEmpty) {
      return [];
    }

    try {
      final prompt = _buildRecipePrompt(ingredients, count, preferredCategories, prioritizeFilteredItems, prioritizedItems);
      final response = await _callMistralForRecipes(prompt);

      if (response != null) {
        final recipes = _parseRecipes(response);
        return recipes;
      }
    } catch (e) {
      print('Recipe generation error: $e');
    }

    return [];
  }

  String _buildRecipePrompt(List<String> ingredients, int count, List<String>? preferredCategories, bool prioritizeFilteredItems, List<String>? prioritizedItems) {
    // Handle empty fridge case
    if (ingredients.isEmpty) {
      return '''Your fridge is currently empty. Suggest $count simple, delicious recipes that are easy to make with basic pantry staples and minimal shopping.

Common pantry staples (assume available): salt, pepper, olive oil, vegetable oil, butter, garlic, onions, flour, sugar, vinegar, soy sauce, ketchup, mustard, mayonnaise, herbs, spices, rice, pasta, canned tomatoes, canned beans

Return ONLY a valid JSON array with this exact format:
[
  {
    "name": "Recipe Name",
    "ingredients": ["2 cups rice", "1 can diced tomatoes", "2 tbsp olive oil", "salt and pepper"],
    "instructions": [
      "Cook rice according to package instructions",
      "Heat oil in a pan and add diced tomatoes",
      "Season with salt and pepper",
      "Serve rice topped with tomato mixture"
    ],
    "prepTime": "10min",
    "cookTime": "20min",
    "shoppingList": ["fresh vegetables", "protein of choice"]
  }
]

Rules:
- Create recipes that require minimal ingredients to buy (2-4 items max)
- Focus on pantry staples + a few fresh ingredients
- Make simple, delicious recipes that are budget-friendly
- Include specific quantities in ingredients array
- Write detailed, step-by-step instructions (4-6 steps)
- Clearly indicate what needs to be purchased in shoppingList

Important: Return ONLY the JSON array, no other text.''';
    }

    // Limit to 4 main ingredients for simplicity
    final limitedIngredients = ingredients.take(4).toList();
    final ingredientsList = limitedIngredients.join(', ');

    // Focus on best tasting combinations with detailed instructions
    String categoryInstruction = '';
    if (preferredCategories != null && preferredCategories.isNotEmpty) {
      categoryInstruction = '\n\nIMPORTANT: Focus on recipes that primarily use ingredients from these categories: ${preferredCategories.join(', ')}.';
    }
    
    String priorityInstruction = '';
    if (prioritizeFilteredItems && preferredCategories != null && preferredCategories.isNotEmpty) {
      priorityInstruction = '\n\nPRIORITY: The user has filtered their fridge to show only ${preferredCategories.join(', ')} items. Prioritize recipes that use these filtered ingredients as the main components.';
    }
    
    String prioritizedItemsInstruction = '';
    if (prioritizedItems != null && prioritizedItems.isNotEmpty) {
      prioritizedItemsInstruction = '\n\nHIGH PRIORITY: The user has specifically marked these items as priority: ${prioritizedItems.join(', ')}. Make sure to include these items as main ingredients in your recipe suggestions.';
    }
    
    return '''You have these ingredients available in your fridge: $ingredientsList

Suggest $count simple, delicious recipes using these available ingredients.$categoryInstruction$priorityInstruction$prioritizedItemsInstruction

IMPORTANT INGREDIENT DISTINCTION:
- "ingredients" array should include ingredients that are available in the fridge (from the list above) PLUS common pantry staples
- "shoppingList" array should include ingredients that need to be purchased (NOT in the fridge and NOT common pantry staples)

Common pantry staples (assume available): salt, pepper, olive oil, vegetable oil, butter, garlic, onions, flour, sugar, vinegar, soy sauce, ketchup, mustard, mayonnaise, herbs, spices

Return ONLY a valid JSON array with this exact format:
[
  {
    "name": "Recipe Name",
    "ingredients": ["1 lb chicken breast, cubed", "1 cup grapes", "2 tbsp olive oil", "salt and pepper"],
    "instructions": [
      "Heat oil in a large skillet over medium-high heat",
      "Add chicken and cook for 5-6 minutes until golden brown",
      "Add grapes and cook for 2-3 minutes until warmed through",
      "Season with salt and pepper, serve immediately"
    ],
    "prepTime": "15min",
    "cookTime": "10min",
    "shoppingList": ["fresh herbs"]
  }
]

Rules:
- "ingredients" array: Use ingredients from available list: $ingredientsList PLUS common pantry staples
- "shoppingList" array: Only ingredients NOT in the fridge and NOT common pantry staples
- Focus on TASTE, not using every available ingredient
- Pick the BEST combinations from available ingredients
- Include specific quantities in ingredients array
- Write detailed, step-by-step instructions (4-6 steps)
- Include cooking temperatures and times
- Suggest minimal additional ingredients to buy (1-3 items max)
- Make simple, delicious recipes people love
- Don't force weird combinations

Important: Return ONLY the JSON array, no other text.''';
  }

  Future<String?> _callMistralForRecipes(String prompt) async {
    final apiKey = await _getApiKey();
    if (apiKey == null) {
      print('No Mistral API key found');
      return null;
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: json.encode({
          'model': _recipeModel, // Use mistral-small for better recipe generation
          'messages': [
            {
              'role': 'user',
              'content': prompt,
            }
          ],
          'temperature': 0.2, // Lower for more predictable output
          'max_tokens': 1000, // Increased for complete JSON generation
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final result = data['choices']?[0]?['message']?['content']?.toString().trim();
        print('LLM Response received (${result?.length ?? 0} chars)');
        return result;
      } else {
        print('Mistral API error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('HTTP request error: $e');
    }

    return null;
  }

  List<Map<String, dynamic>> _parseRecipes(String response) {
    try {
      print('Raw recipe response: $response');
      
      // Clean the response first
      var cleanResponse = response.trim();
      
      // Remove any markdown code blocks
      cleanResponse = cleanResponse.replaceAll(RegExp(r'```json\s*|\s*```'), '');
      
      // Try to find JSON array in the response
      final jsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(cleanResponse);
      if (jsonMatch != null) {
        var jsonStr = jsonMatch.group(0)!;
        
        // Try to fix incomplete JSON by adding missing closing brackets
        if (!jsonStr.endsWith(']')) {
          // Count open brackets and add missing closes
          final openBrackets = jsonStr.split('[').length - 1;
          final closeBrackets = jsonStr.split(']').length - 1;
          final missingCloses = openBrackets - closeBrackets;
          
          for (int i = 0; i < missingCloses; i++) {
            jsonStr += ']';
          }
        }
        
        print('Cleaned JSON string: $jsonStr');
        final decoded = json.decode(jsonStr);

        if (decoded is List) {
          return decoded.map((recipe) {
            if (recipe is Map<String, dynamic>) {
              return {
                'name': recipe['name']?.toString() ?? 'Unnamed Recipe',
                'ingredients': (recipe['ingredients'] as List?)?.map((e) => e.toString()).toList() ?? [],
                'instructions': (recipe['instructions'] as List?)?.map((e) => e.toString()).toList() ?? [],
                'prepTime': recipe['prepTime']?.toString() ?? 'Unknown',
                'cookTime': recipe['cookTime']?.toString() ?? 'Unknown',
                'shoppingList': (recipe['shoppingList'] as List?)?.map((e) => e.toString()).toList() ?? [],
              };
            }
            return <String, dynamic>{};
          }).where((r) => r.isNotEmpty).toList();
        }
      }
    } catch (e) {
      print('Error parsing recipes JSON: $e');
      print('Response that failed to parse: $response');
    }

    // Fallback: return empty list if parsing fails
    return [];
  }
}
