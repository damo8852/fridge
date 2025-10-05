import 'dart:convert';
import 'package:http/http.dart' as http;

class LLMService {
  // Use your computer's IP address instead of localhost for mobile devices
  // Replace with your actual IP address from ipconfig
  static const String _baseUrl = 'http://10.0.0.218:11434';
  static const String _model = 'llama2-uncensored:latest'; // Use available model
  
  static final LLMService _instance = LLMService._internal();
  factory LLMService() => _instance;
  LLMService._internal();

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
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/generate'),
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
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/tags'),
      ).timeout(const Duration(seconds: 3));
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Get list of available models
  Future<List<String>> getAvailableModels() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/tags'),
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
}
