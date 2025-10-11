import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import '../models/grocery_type.dart';
import 'config_service.dart';

class ExpiryRules {
  final List<ExpiryRule> rules;
  ExpiryRules(this.rules);

  static Future<ExpiryRules> load() async {
    final raw = await rootBundle.loadString('assets/expiry_rules.json');
    final map = json.decode(raw) as Map<String, dynamic>;
    final list = (map['rules'] as List).map((e) => ExpiryRule.fromJson(e)).toList();
    return ExpiryRules(list);
  }

  /// Return shelf-life days for a product name (best match; fallback 5 days)
  int guessDays(String name) {
    final tokens = _tokens(name);
    int bestScore = -1;
    int bestDays = 5;
    for (final r in rules) {
      final s = _score(tokens, r.match);
      if (s > bestScore) {
        bestScore = s;
        bestDays = r.days;
      }
    }
    return bestDays;
  }

  List<String> _tokens(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();

  /// Simple overlap score
  int _score(List<String> a, List<String> b) {
    final sa = a.toSet(), sb = b.map((e) => e.toLowerCase()).toSet();
    return sa.intersection(sb).length;
  }
}

class ExpiryRule {
  final List<String> match;
  final int days;
  ExpiryRule({required this.match, required this.days});
  factory ExpiryRule.fromJson(Map<String, dynamic> j) =>
      ExpiryRule(match: List<String>.from(j['match']), days: j['days']);
}

/// Enhanced receipt line parser for modern receipt formats
class ReceiptParser {
  // obvious non-item lines
  static final _noise = RegExp(
    r'\b(?:subtotal|total|tax|purchase|change|cash|visa|debit|credit|auth|exp(?:iration| date)?|cashier|lane|sequence|seq|eps|term|ref|date|time|pm|am|#\d+|receipt|store|thank|you|welcome|save|savings|discount|coupon|sale|clearance|manager|special|price|each|per|lb|oz|ct|pk|ea|pkg|misc|dept|tpr|promo)\b',
    caseSensitive: false,
  );
  // looks like a date/time line
  static final _dateLike = RegExp(r'\b\d{1,2}[:/.-]\d{1,2}[:/.-]\d{2,4}\b|\b\d{1,2}:\d{2}\s?(?:AM|PM)?\b', caseSensitive: false);
  // product codes / long digit runs
  static final _longDigits = RegExp(r'\b\d{5,}\b');
  // common receipt headers/footers
  static final _receiptHeader = RegExp(r'\b(?:receipt|invoice|order|transaction|purchase|check|register|terminal|pos|point\s*of\s*sale)\b', caseSensitive: false);
  static final _receiptFooter = RegExp(r'\b(?:thank\s*you|visit\s*us|store\s*hours|return\s*policy|warranty|guarantee|satisfaction|customer\s*service)\b', caseSensitive: false);

  static Future<List<ParsedItem>> parse(String fullText) async {
    print('=== LLM Receipt Parser ===');
    print('Raw OCR Text:');
    print(fullText);
    print('==========================');
    
    // Use LLM to extract food items from receipt text
    return await _parseWithLLM(fullText);
  }

  static Future<List<ParsedItem>> _parseWithLLM(String receiptText) async {
    try {
      final prompt = _buildExtractionPrompt(receiptText);
      print('LLM Prompt: "$prompt"');
      
      final response = await _callMistral(prompt);
      if (response != null && response.trim().isNotEmpty) {
        print('LLM Response: "$response"');
        final items = await _parseLLMResponse(response);
        if (items.isNotEmpty) {
          print('Extracted items: ${items.map((i) => '${i.name} (${i.quantity})').join(', ')}');
          return items;
        }
      }
    } catch (e) {
      print('LLM parsing failed: $e');
    }
    
    // Fallback to improved regex parsing
    print('Falling back to improved regex parsing');
    return await _parseWithImprovedRegex(receiptText);
  }

  static String _buildExtractionPrompt(String receiptText) {
    return '''Extract ALL food and grocery items from this receipt text. Return ONLY a JSON array of items.

Receipt text:
$receiptText

Rules:
- Extract EVERY food/grocery item you can find
- Include quantity if mentioned (default to 1 if not specified)
- Clean up names (remove brand names, sizes, descriptions, explanations)
- Categorize each item by grocery type
- Return JSON array format: [{"name": "item name", "quantity": number, "type": "grocery_type"}]
- Look for items even if the text is messy or has OCR errors
- CRITICAL: Avoid duplicates - if you see "X brand avocados" AND "avocados" as separate items, only return "avocados"
- CRITICAL: Avoid duplicates #2 - if you see "Country Style Pork Ribs" AND "Country Style Pork Ribs", only return "Country Style Pork Ribs"
- CRITICAL: Keep names CLEAN and READABLE - no explanations, no "→" arrows, no extra text
- CRITICAL: Expand abbreviations naturally (e.g., "chkn thgh" → "chicken thigh", "avoc" → "avocado")
- CRITICAL: Remove brand names but keep descriptive terms (e.g., "Fever Tree Tonic" → "tonic water", "Haas Avocado" → "avocado", "Country Style Pork Ribs" → "country style pork ribs")
- CRITICAL: Keep specific food descriptions when they add value (e.g., "Country Style Pork Ribs" not just "pork ribs")
- CRITICAL: Merge similar items with different descriptions into single entries
- CRITICAL: Return clean, readable food names with appropriate specificity

Available types: meat, poultry, seafood, vegetable, fruit, dairy, grain, beverage, snack, condiment, frozen, other

Examples:
- "Heritage Farm® Bone In Skin On Chicken Thighs, 1 lb" → {"name": "chicken thighs", "quantity": 1, "type": "poultry"}
- "2x Kroger AutumnCrisp Fresh Seedless Green Grapes" → {"name": "green grapes", "quantity": 2, "type": "fruit"}
- "Kroger® 93/7 Ground Beef Tray 1 LB" → {"name": "ground beef", "quantity": 1, "type": "meat"}
- "Fever Tree Tonic Water" → {"name": "tonic water", "quantity": 1, "type": "beverage"}
- "Haas Avocado" → {"name": "avocado", "quantity": 1, "type": "fruit"}
- "Country Style Pork Ribs" → {"name": "country style pork ribs", "quantity": 1, "type": "meat"}
- "chkn thgh" → {"name": "chicken thigh", "quantity": 1, "type": "poultry"}
- "grnd bf" → {"name": "ground beef", "quantity": 1, "type": "meat"}
- "avoc" → {"name": "avocado", "quantity": 1, "type": "fruit"}
- "tom" → {"name": "tomato", "quantity": 1, "type": "vegetable"}

JSON array:''';
  }

  static Future<String?> _callMistral(String prompt) async {
    try {
      // Import ConfigService to get API key
      final configService = ConfigService();
      final apiKey = await configService.getMistralApiKey();
      
      if (apiKey == null) {
        print('No Mistral API key found for receipt parsing');
        return null;
      }

      final response = await http.post(
        Uri.parse('https://api.mistral.ai/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: json.encode({
          'model': 'mistral-tiny', // Fast and cost-effective for parsing
          'messages': [
            {
              'role': 'user',
              'content': prompt,
            }
          ],
          'temperature': 0.1, // Low temperature for consistent parsing
          'max_tokens': 1000, // Enough for receipt items
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['choices']?[0]?['message']?['content']?.toString().trim();
      } else {
        print('Mistral API error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('HTTP request error: $e');
    }
    
    return null;
  }

  static Future<List<ParsedItem>> _parseLLMResponse(String response) async {
    try {
      // Clean the response
      var cleanResponse = response.trim();
      
      // Remove any markdown code blocks
      cleanResponse = cleanResponse.replaceAll(RegExp(r'```json\s*|\s*```'), '');
      
      // Try to find JSON array in the response
      final jsonMatch = RegExp(r'\[.*\]', dotAll: true).firstMatch(cleanResponse);
      if (jsonMatch != null) {
        cleanResponse = jsonMatch.group(0)!;
      }
      
      final data = json.decode(cleanResponse);
      if (data is List) {
        final items = <ParsedItem>[];
        for (final item in data) {
          if (item is Map<String, dynamic>) {
            final name = item['name']?.toString();
            final quantity = item['quantity'];
            final type = item['type']?.toString();
            
            if (name != null && name.isNotEmpty) {
              final qty = quantity is int ? quantity : (int.tryParse(quantity?.toString() ?? '1') ?? 1);
              // Clean the name first, then use AI for simplification
              final cleanedName = _cleanAIResponse(name);
              final simplifiedName = await _simplifyFoodNameWithAI(cleanedName) ?? _simplifyFoodName(cleanedName);
              items.add(ParsedItem(
                name: _titleCase(simplifiedName), 
                quantity: qty,
                type: type != null ? GroceryType.fromString(type) : GroceryType.other
              ));
            }
          }
        }
        return items;
      }
    } catch (e) {
      print('Failed to parse LLM response as JSON: $e');
    }
    
    return [];
  }

  static Future<List<ParsedItem>> _parseWithImprovedRegex(String fullText) async {
    final rawLines = fullText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final items = <ParsedItem>[];
    var stopAtTotals = false;

    for (var line in rawLines) {
      final low = line.toLowerCase();

      // Skip receipt headers
      if (_receiptHeader.hasMatch(low)) continue;
      
      // Stop at receipt footers
      if (_receiptFooter.hasMatch(low)) break;

      // Hard stop if we hit SUBTOTAL/TOTAL section
      if (low.contains('subtotal') || low.contains(RegExp(r'\btotal\b'))) {
        stopAtTotals = true;
      }
      if (stopAtTotals) continue;

      // Skip obvious noise lines (but be less aggressive)
      if (_noise.hasMatch(low) && !_looksLikeItemName(line)) continue;
      if (_dateLike.hasMatch(low)) continue;
      if (_longDigits.hasMatch(low) && !_looksLikeItemName(line)) continue;

      // Process the line as a potential item
      print('Processing line: "$line"');
      var processedLine = await _processItemLineImproved(line);
      if (processedLine != null) {
        print('  -> Parsed: "${processedLine.name}" (qty: ${processedLine.quantity})');
        items.add(processedLine);
      } else {
        print('  -> Rejected');
      }
    }

    // Merge duplicates by normalized name with enhanced similarity checking
    final merged = <String, ParsedItem>{};
    for (final it in items) {
      final key = _normalizeName(it.name);
      ParsedItem? existingItem;
      String? existingKey;
      
      // Check for exact match first
      existingItem = merged[key];
      if (existingItem != null) {
        existingKey = key;
      } else {
        // Check for similar items using fuzzy matching
        for (final entry in merged.entries) {
          if (_areSimilarFoodItems(it.name, entry.value.name)) {
            existingItem = entry.value;
            existingKey = entry.key;
            break;
          }
        }
      }
      
      if (existingItem != null && existingKey != null) {
        // Merge with existing item
        merged[existingKey] = existingItem.copyWith(quantity: existingItem.quantity + it.quantity);
      } else {
        // Add as new item
        merged[key] = it;
      }
    }
    
    print('Final parsed items: ${merged.values.map((i) => '${i.name} (${i.quantity})').join(', ')}');
    print('============================');
    
    return merged.values.toList();
  }


  static Future<ParsedItem?> _processItemLineImproved(String line) async {
    // More aggressive parsing for common receipt patterns
    var name = line;
    int qty = 1;
    
    // Look for quantity patterns more broadly
    final qtyPatterns = [
      RegExp(r'^(\d+)\s*x\s*', caseSensitive: false), // "2x Item"
      RegExp(r'^(\d+)\s+', caseSensitive: false), // "2 Item"
      RegExp(r'\s+x\s*(\d+)\s*$', caseSensitive: false), // "Item x2"
      RegExp(r'\s+(\d+)\s*x\s*\$', caseSensitive: false), // "Item 2x$5.99"
      RegExp(r'^(\d+\.\d+)\s+', caseSensitive: false), // "2.19 lbs"
    ];
    
    for (final pattern in qtyPatterns) {
      final match = pattern.firstMatch(name);
      if (match != null) {
        final qtyStr = match.group(1) ?? '1';
        qty = double.tryParse(qtyStr)?.round() ?? 1;
        name = name.replaceFirst(match.group(0)!, '').trim();
        break;
      }
    }
    
    // Clean up the name by removing various patterns
    name = _cleanItemNameImproved(name);
    
    // Validate the name - be more lenient if it looks like a food item
    if (!_isValidItemName(name)) {
      // If it looks like a food item but failed validation, try to salvage it
      if (_looksLikeItemName(line)) {
        // Try to extract just the food part
        final foodMatch = RegExp(r'\b([A-Za-z\s]+(?:chicken|beef|cream|broth|grapes|tomatoes|tofu|sandwiches|thighs|ground|whipping|frozen|dairy|dessert|cherry|crushed|organic|soft|silken|watermelon|sour|patch|kids)[A-Za-z\s]*)\b', caseSensitive: false).firstMatch(line);
        if (foodMatch != null) {
          name = foodMatch.group(1)!.trim();
        }
      }
      
      // Final validation
      if (!_isValidItemName(name)) return null;
    }

    // Use AI for food name simplification, fallback to static mapping
    final simplifiedName = await _simplifyFoodNameWithAI(name) ?? _simplifyFoodName(name);
    return ParsedItem(name: _titleCase(simplifiedName), quantity: qty);
  }


  static String _cleanItemNameImproved(String name) {
    // Remove prices (more comprehensive)
    name = name.replaceAll(RegExp(r'(?<!\d)(?:\$)?\d{1,3}(?:[.,]\d{2})(?!\d)'), '');
    
    // Remove weights and measurements
    name = name.replaceAll(RegExp(r'\b\d+(?:\.\d+)?\s?(?:lb|lbs|oz|kg|g|pt|qt|gal|ml|l)\b', caseSensitive: false), '');
    
    // Remove UPC codes
    name = name.replaceAll(RegExp(r'\b\d{12,13}\b'), '');
    
    // Remove product codes and long digit sequences
    name = name.replaceAll(RegExp(r'#?\b\d{4,}\b'), '');
    
    // Remove brand names and store names (common patterns)
    name = name.replaceAll(RegExp(r'\b(?:Kroger|Heritage Farm|Private Selection|Red Gold|Simple Truth Organic|SOUR PATCH KIDS)\s*[®™]?\s*', caseSensitive: false), '');
    
    // Remove common store abbreviations and noise words
    name = name.replaceAll(RegExp(r'\b(pkg|ea|misc|dept|tpr|promo|ct|pk|lb|oz|each|per|price|sale|discount|coupon|clearance|manager|special|item|coupo|approx|apprax)\b', caseSensitive: false), '');
    
    // Remove "UPC:" prefix
    name = name.replaceAll(RegExp(r'UPC:\s*', caseSensitive: false), '');
    
    // Remove extra whitespace
    name = name.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    
    // Remove leading/trailing punctuation
    name = name.replaceAll(RegExp(r'^[^\w\s]+|[^\w\s]+$'), '');
    
    return name.trim();
  }


  static bool _looksLikeItemName(String line) {
    final low = line.toLowerCase();
    
    // Check for common food/grocery keywords
    final foodKeywords = RegExp(r'\b(chicken|beef|cream|broth|grapes|tomatoes|tofu|sandwiches|thighs|ground|whipping|frozen|dairy|dessert|cherry|crushed|organic|soft|silken|watermelon|sour|patch|kids)\b', caseSensitive: false);
    
    // Check for brand names that indicate food items
    final brandKeywords = RegExp(r'\b(heritage|farm|kroger|private|selection|red|gold|simple|truth|organic)\b', caseSensitive: false);
    
    // Check for food-related measurements
    final foodMeasurements = RegExp(r'\b(lb|lbs|oz|pt|qt|gal|ct|pint|pound|ounce|count)\b', caseSensitive: false);
    
    return foodKeywords.hasMatch(low) || brandKeywords.hasMatch(low) || foodMeasurements.hasMatch(low);
  }

  static bool _isValidItemName(String name) {
    if (name.isEmpty) return false;
    
    // Must have at least 2 alphabetic characters
    final alphaCount = RegExp(r'[A-Za-z]').allMatches(name).length;
    if (alphaCount < 2) return false;
    
    // Must not be mostly numbers or symbols
    final alphaRatio = alphaCount / name.length;
    if (alphaRatio < 0.2) return false; // More lenient
    
    // Must not be too short or too long
    if (name.length < 2 || name.length > 100) return false; // More lenient
    
    return true;
  }

  static String _normalizeName(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '') // Remove punctuation
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .trim();
  }

  static String _titleCase(String s) =>
      s.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}').join(' ');

  /// Public method to simplify food names using AI with static fallback
  static Future<String> simplifyFoodName(String name) async {
    final aiResult = await _simplifyFoodNameWithAI(name);
    return aiResult ?? _simplifyFoodName(name);
  }

  // Food name simplification map for common abbreviations
  static final Map<String, String> _foodAbbreviations = {
    // Poultry
    'chkn': 'chicken',
    'chk': 'chicken',
    'thgh': 'thigh',
    'thighs': 'thigh',
    'brst': 'breast',
    'brsts': 'breast',
    'legs': 'leg',
    'wngs': 'wing',
    'wings': 'wing',
    
    // Beef
    'grnd': 'ground',
    'bf': 'beef',
    'stk': 'steak',
    'chp': 'chop',
    'chops': 'chop',
    
    // Pork
    'ham': 'ham',
    'bcn': 'bacon',
    
    // Dairy
    'milk': 'milk',
    'chz': 'cheese',
    'yog': 'yogurt',
    'cream': 'cream',
    'butter': 'butter',
    
    // Vegetables
    'veg': 'vegetable',
    'veggie': 'vegetable',
    'tom': 'tomato',
    'tomatoes': 'tomato',
    'onions': 'onion',
    'potatoes': 'potato',
    'lettuce': 'lettuce',
    'carrots': 'carrot',
    'peppers': 'pepper',
    'cucumbers': 'cucumber',
    
    // Fruits
    'apples': 'apple',
    'bananas': 'banana',
    'oranges': 'orange',
    'grapes': 'grape',
    'berries': 'berry',
    'strawberries': 'strawberry',
    'blueberries': 'blueberry',
    
    // Grains
    'bread': 'bread',
    'rice': 'rice',
    'pasta': 'pasta',
    'noodles': 'noodle',
    
    // Seafood
    'fish': 'fish',
    'salmon': 'salmon',
    'tuna': 'tuna',
    'shrimp': 'shrimp',
    'crab': 'crab',
    'lobster': 'lobster',
    
    // Beverages
    'juice': 'juice',
    'soda': 'soda',
    'water': 'water',
    'beer': 'beer',
    'wine': 'wine',
    
    // Frozen
    'ice cream': 'ice cream',
    'frozen': 'frozen',
    
    // Condiments
    'sauce': 'sauce',
    'ketchup': 'ketchup',
    'mustard': 'mustard',
    'mayo': 'mayonnaise',
    'mayonnaise': 'mayonnaise',
    'salt': 'salt',
    'spice': 'spice',
    'herb': 'herb',
    'herbs': 'herb',
    
    // Snacks
    'chips': 'chip',
    'crackers': 'cracker',
    'cookies': 'cookie',
    'candy': 'candy',
    'chocolate': 'chocolate',
  };

  /// AI-powered food name simplification using Mistral
  static Future<String?> _simplifyFoodNameWithAI(String name) async {
    try {
      final prompt = _buildFoodSimplificationPrompt(name);
      final response = await _callMistral(prompt);
      
      if (response != null && response.trim().isNotEmpty) {
        String simplified = response.trim();
        
        // Clean up any verbose responses
        simplified = _cleanAIResponse(simplified);
        
        // Validate that we got a reasonable response
        if (simplified.length > 1 && simplified.length < 100) {
          return simplified.toLowerCase();
        }
      }
    } catch (e) {
      print('AI food simplification failed for "$name": $e');
    }
    
    return null; // Fallback to static mapping
  }

  /// Clean up verbose AI responses
  static String _cleanAIResponse(String response) {
    // Remove explanations in parentheses
    response = response.replaceAll(RegExp(r'\([^)]*\)'), '').trim();
    
    // Remove arrows and explanations
    response = response.replaceAll(RegExp(r'\s*→\s*.*'), '').trim();
    response = response.replaceAll(RegExp(r'\s*->\s*.*'), '').trim();
    
    // Remove quotes if the entire response is quoted
    if (response.startsWith('"') && response.endsWith('"')) {
      response = response.substring(1, response.length - 1);
    }
    
    // Remove "no changes needed" type explanations
    response = response.replaceAll(RegExp(r'no changes needed.*', caseSensitive: false), '').trim();
    response = response.replaceAll(RegExp(r'already clear.*', caseSensitive: false), '').trim();
    response = response.replaceAll(RegExp(r'already readable.*', caseSensitive: false), '').trim();
    
    return response.trim();
  }

  static String _buildFoodSimplificationPrompt(String foodName) {
    return '''Simplify this food item name to be clean and readable. Return ONLY the simplified name, no explanation or extra text.

Food name: "$foodName"

Rules:
- Expand abbreviations naturally (chkn → chicken, grnd → ground, bf → beef, chz → cheese, avoc → avocado, tom → tomato)
- Remove brand names but keep descriptive terms (Fever Tree Tonic → tonic water, Haas Avocado → avocado, Country Style Pork Ribs → country style pork ribs)
- Remove measurements and sizes
- Keep specific food descriptions when they add value
- Make it clean and readable
- Return only the food name, nothing else

Examples:
"chkn thgh" → "chicken thigh"
"grnd bf" → "ground beef" 
"avoc" → "avocado"
"tom" → "tomato"
"chz" → "cheese"
"Fever Tree Tonic Water" → "tonic water"
"Haas Avocado" → "avocado"
"Country Style Pork Ribs" → "country style pork ribs"
"milk 1% lowfat" → "lowfat milk"
"grn beans" → "green beans"

Simplified name:''';
  }

  /// Static mapping fallback for food name simplification
  static String _simplifyFoodName(String name) {
    String simplified = name.toLowerCase();
    
    // Remove common brand names
    final brandNames = ['fever tree', 'haas', 'kroger', 'heritage farm', 'organic', 'fresh', 'simple truth', 'private selection'];
    for (String brand in brandNames) {
      simplified = simplified.replaceAll(brand, '').trim();
    }
    
    // Split into words and simplify each word
    List<String> words = simplified.split(' ');
    List<String> simplifiedWords = [];
    
    for (String word in words) {
      // Remove common suffixes and clean up
      String cleanWord = word.replaceAll(RegExp(r'[^a-z]'), '');
      
      // Skip empty words
      if (cleanWord.isEmpty) continue;
      
      // Check if it's an abbreviation we know
      if (_foodAbbreviations.containsKey(cleanWord)) {
        simplifiedWords.add(_foodAbbreviations[cleanWord]!);
      } else {
        // Keep the word as is if it's not an abbreviation
        simplifiedWords.add(cleanWord);
      }
    }
    
    return simplifiedWords.join(' ');
  }

  static bool _areSimilarFoodItems(String name1, String name2) {
    final normalized1 = _normalizeName(name1);
    final normalized2 = _normalizeName(name2);
    
    // Exact match after normalization
    if (normalized1 == normalized2) return true;
    
    // Check if one contains the other (e.g., "avocados" vs "organic avocados")
    if (normalized1.contains(normalized2) || normalized2.contains(normalized1)) {
      return true;
    }
    
    // Check for common food item patterns
    final words1 = normalized1.split(' ');
    final words2 = normalized2.split(' ');
    
    // If they share significant words, they might be the same item
    final commonWords = words1.where((word) => words2.contains(word) && word.length > 2).length;
    final totalWords = (words1.length + words2.length) / 2;
    
    // If more than 50% of words are common, consider them similar
    if (commonWords / totalWords > 0.5) return true;
    
    // Check for brand vs generic items (e.g., "Kroger avocados" vs "avocados")
    final brandWords = ['kroger', 'heritage', 'farm', 'private', 'selection', 'simple', 'truth', 'organic', 'red', 'gold'];
    final cleanWords1 = words1.where((word) => !brandWords.contains(word)).toList();
    final cleanWords2 = words2.where((word) => !brandWords.contains(word)).toList();
    
    if (cleanWords1.join(' ') == cleanWords2.join(' ')) return true;
    
    return false;
  }
}

class ParsedItem {
  final String name;
  final int quantity;
  final GroceryType type;
  ParsedItem({required this.name, required this.quantity, this.type = GroceryType.other});
  ParsedItem copyWith({String? name, int? quantity, GroceryType? type}) =>
      ParsedItem(name: name ?? this.name, quantity: quantity ?? this.quantity, type: type ?? this.type);
}

/// Barcode → product name mapping (local fallback)
class UpcMap {
  final Map<String, String> map;
  UpcMap(this.map);

  static Future<UpcMap> load() async {
    final raw = await rootBundle.loadString('assets/upc_map.json');
    final m = Map<String, dynamic>.from(json.decode(raw));
    return UpcMap(m.map((k, v) => MapEntry(k, v.toString())));
  }

  String nameFor(String upc) => map[upc] ?? 'Item $upc';
}
