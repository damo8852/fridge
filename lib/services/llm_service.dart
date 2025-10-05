import 'dart:convert';
import 'package:http/http.dart' as http;

class LLMService {
  // Configuration for Ollama server
  // Will automatically try different addresses based on platform
  static const List<String> _baseUrls = [
    'http://10.0.2.2:11434',      // Android Emulator
    'http://localhost:11434',      // iOS Simulator / Web
    'http://127.0.0.1:11434',      // Alternative localhost
    'http://10.0.0.214:11434',     // Physical device (update to your computer's IP)
  ];
  static const String _model = 'llama3.2:latest'; // Default model
  static const String _recipeModel = 'llama3.2:1b'; // Faster model for recipes only

  String? _workingBaseUrl; // Cache the working URL

  static final LLMService _instance = LLMService._internal();
  factory LLMService() => _instance;
  LLMService._internal();

  /// Find the first working Ollama server URL
  Future<String?> _findWorkingUrl() async {
    // Return cached URL if we already found one
    if (_workingBaseUrl != null) {
      return _workingBaseUrl;
    }

    // Try each URL
    for (final url in _baseUrls) {
      try {
        final response = await http.get(
          Uri.parse('$url/api/tags'),
        ).timeout(const Duration(seconds: 2));

        if (response.statusCode == 200) {
          _workingBaseUrl = url;
          print('✓ Connected to Ollama at: $url');
          return url;
        }
      } catch (e) {
        // Continue to next URL
        continue;
      }
    }

    print('✗ Could not connect to Ollama on any address');
    return null;
  }

  /// Predict expiry date in days for a given food item
  /// Returns number of days until expiry, or null if prediction fails
  Future<int?> predictExpiryDays(String itemName, {String? additionalContext}) async {
    try {
      final prompt = _buildPrompt(itemName, additionalContext);
      final response = await _callOllama(prompt);

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
      final response = await _callOllama(prompt);

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

Predict days until expiry. Respond with ONLY a number:

Examples:
milk -> 7
chicken -> 3
eggs -> 14
bread -> 5
strawberries -> 4
yogurt -> 10
spinach -> 5
beef -> 2

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

Types: meat, poultry, seafood, vegetable, fruit, dairy, grain, beverage, snack, condiment, frozen, other

$itemName ->''';
  }

  Future<String?> _callOllama(String prompt) async {
    final baseUrl = await _findWorkingUrl();
    if (baseUrl == null) {
      print('No working Ollama server found');
      return null;
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/generate'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'model': _model,
          'prompt': prompt,
          'stream': false,
          'options': {
            'temperature': 0.1, // Low temperature for consistent results
            'top_p': 0.9,
            'num_predict': 10, // Limit response length
          }
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final result = data['response']?.toString().trim();
        return result;
      } else {
        print('Ollama API error: ${response.statusCode} - ${response.body}');
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
      RegExp(r'^(\d{1,3})$'), // Just a number
      RegExp(r'(\d{1,3})\s*days?'), // "7 days" or "7 day"
      RegExp(r'(\d{1,3})[-–]\d+'), // "7-10" or "7–10"
      RegExp(r'\b(\d{1,3})\b'), // Any number in the text
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(cleanResponse);
      if (match != null) {
        final days = int.tryParse(match.group(1)!);
        if (days != null && days > 0 && days <= 365) {
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

  /// Check if Ollama is running and accessible
  Future<bool> isAvailable() async {
    final baseUrl = await _findWorkingUrl();
    return baseUrl != null;
  }

  /// Get list of available models
  Future<List<String>> getAvailableModels() async {
    final baseUrl = await _findWorkingUrl();
    if (baseUrl == null) return [];

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/tags'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final models = data['models'] as List?;
        if (models != null) {
          return models.map((model) => model['name'].toString()).toList();
        }
      }
    } catch (e) {
      print('Error getting models: $e');
    }

    return [];
  }

  /// Generate recipe suggestions based on available ingredients
  /// Returns a list of recipe objects with name, ingredients, and instructions
  Future<List<Map<String, dynamic>>> generateRecipes(List<String> ingredients, {int count = 2}) async {
    if (ingredients.isEmpty) {
      return [];
    }

    try {
      final prompt = _buildRecipePrompt(ingredients, count);
      final response = await _callOllamaForRecipes(prompt);

      if (response != null) {
        final recipes = _parseRecipes(response);
        return recipes;
      }
    } catch (e) {
      print('Recipe generation error: $e');
    }

    return [];
  }

  String _buildRecipePrompt(List<String> ingredients, int count) {
    // Limit to 4 main ingredients for simplicity
    final limitedIngredients = ingredients.take(4).toList();
    final ingredientsList = limitedIngredients.join(', ');

    // Ultra-simple prompt for 1B model
    return '''Ingredients: $ingredientsList

Make $count recipes. JSON only:
[{"name":"Recipe Name","ingredients":["item1","item2"],"instructions":["step1","step2"],"prepTime":"15min"}]''';
  }

  Future<String?> _callOllamaForRecipes(String prompt) async {
    final baseUrl = await _findWorkingUrl();
    if (baseUrl == null) {
      print('No working Ollama server found');
      return null;
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/generate'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'model': _recipeModel, // Use faster 1B model for recipes
          'prompt': prompt,
          'stream': false,
          'options': {
            'temperature': 0.3, // Lower for more predictable/faster output
            'top_p': 0.7,
            'num_predict': 400, // Minimal tokens for 2 simple recipes
            'num_ctx': 1024, // Smaller context
            'repeat_penalty': 1.3, // Higher to reduce repetition
          }
        }),
      ).timeout(const Duration(seconds: 30)); // Shorter timeout with 1B model

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final result = data['response']?.toString().trim();
        print('LLM Response received (${result?.length ?? 0} chars)');
        return result;
      } else {
        print('Ollama API error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('HTTP request error: $e');
    }

    return null;
  }

  List<Map<String, dynamic>> _parseRecipes(String response) {
    try {
      // Try to find JSON array in the response
      final jsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(response);
      if (jsonMatch != null) {
        final jsonStr = jsonMatch.group(0)!;
        final decoded = json.decode(jsonStr);

        if (decoded is List) {
          return decoded.map((recipe) {
            if (recipe is Map<String, dynamic>) {
              return {
                'name': recipe['name']?.toString() ?? 'Unnamed Recipe',
                'ingredients': (recipe['ingredients'] as List?)?.map((e) => e.toString()).toList() ?? [],
                'instructions': (recipe['instructions'] as List?)?.map((e) => e.toString()).toList() ?? [],
                'prepTime': recipe['prepTime']?.toString() ?? 'Unknown',
              };
            }
            return <String, dynamic>{};
          }).where((r) => r.isNotEmpty).toList();
        }
      }
    } catch (e) {
      print('Error parsing recipes JSON: $e');
    }

    // Fallback: return empty list if parsing fails
    return [];
  }
}
