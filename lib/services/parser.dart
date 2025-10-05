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
        final items = _parseLLMResponse(response);
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
    return _parseWithImprovedRegex(receiptText);
  }

  static String _buildExtractionPrompt(String receiptText) {
    return '''Extract ALL food and grocery items from this receipt text. Return ONLY a JSON array of items.

Receipt text:
$receiptText

Rules:
- Extract EVERY food/grocery item you can find
- Include quantity if mentioned (default to 1 if not specified)
- Clean up names (remove brand names, sizes, but keep main food item)
- Categorize each item by grocery type
- Return JSON array format: [{"name": "item name", "quantity": number, "type": "grocery_type"}]
- Look for items even if the text is messy or has OCR errors

Available types: meat, poultry, seafood, vegetable, fruit, dairy, grain, beverage, snack, condiment, frozen, other

Examples:
- "Heritage Farm® Bone In Skin On Chicken Thighs, 1 lb" → {"name": "chicken thighs", "quantity": 1, "type": "poultry"}
- "2x Kroger AutumnCrisp Fresh Seedless Green Grapes" → {"name": "green grapes", "quantity": 2, "type": "fruit"}
- "Kroger® 93/7 Ground Beef Tray 1 LB" → {"name": "ground beef", "quantity": 1, "type": "meat"}
- "Kroger® Heavy Whipping Cream Pint" → {"name": "heavy whipping cream", "quantity": 1, "type": "dairy"}
- "Kroger® Less Sodium Fat Free Chicken Broth" → {"name": "chicken broth", "quantity": 1, "type": "beverage"}
- "Frozen Dairy Dessert Sandwiches" → {"name": "ice cream sandwiches", "quantity": 1, "type": "frozen"}
- "Fresh Cherry Tomatoes on the Vine" → {"name": "cherry tomatoes", "quantity": 1, "type": "vegetable"}
- "Crushed Tomatoes" → {"name": "crushed tomatoes", "quantity": 1, "type": "condiment"}

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

  static List<ParsedItem> _parseLLMResponse(String response) {
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
              items.add(ParsedItem(
                name: _titleCase(name), 
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

  static List<ParsedItem> _parseWithImprovedRegex(String fullText) {
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
      var processedLine = _processItemLineImproved(line);
      if (processedLine != null) {
        print('  -> Parsed: "${processedLine.name}" (qty: ${processedLine.quantity})');
        items.add(processedLine);
      } else {
        print('  -> Rejected');
      }
    }

    // Merge duplicates by normalized name
    final merged = <String, ParsedItem>{};
    for (final it in items) {
      final key = _normalizeName(it.name);
      final existing = merged[key];
      if (existing == null) {
        merged[key] = it;
      } else {
        merged[key] = existing.copyWith(quantity: existing.quantity + it.quantity);
      }
    }
    
    print('Final parsed items: ${merged.values.map((i) => '${i.name} (${i.quantity})').join(', ')}');
    print('============================');
    
    return merged.values.toList();
  }


  static ParsedItem? _processItemLineImproved(String line) {
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

    return ParsedItem(name: _titleCase(name), quantity: qty);
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
