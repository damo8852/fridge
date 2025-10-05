import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

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
  // prices like 3.89 or $8.99
  static final _price = RegExp(r'(?<!\d)(?:\$)?\d{1,3}(?:[.,]\d{2})(?!\d)');
  // quantity: "2x Milk" / "2 Milk"  OR suffix "Milk x2"
  static final _qtyPrefix = RegExp(r'^\s*(\d+)\s*x?\s+');
  static final _qtySuffix = RegExp(r'\s+x\s*(\d+)\s*$');
  // weight tokens we strip
  static final _weight = RegExp(r'\b\d+(?:\.\d+)?\s?(?:lb|lbs|oz|kg|g)\b', caseSensitive: false);
  // UPC codes (12-13 digits)
  static final _upc = RegExp(r'\b\d{12,13}\b');
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
      
      final response = await _callOllama(prompt);
      if (response != null) {
        print('LLM Response: "$response"');
        final items = _parseLLMResponse(response);
        print('Extracted items: ${items.map((i) => '${i.name} (${i.quantity})').join(', ')}');
        return items;
      }
    } catch (e) {
      print('LLM parsing failed: $e');
    }
    
    // Fallback to regex parsing
    print('Falling back to regex parsing');
    return _parseWithRegex(receiptText);
  }

  static String _buildExtractionPrompt(String receiptText) {
    return '''Extract food and grocery items from this receipt text. Return ONLY a JSON array of items.

Receipt text:
$receiptText

Rules:
- Only extract food/grocery items (not household items, electronics, etc.)
- Include quantity if mentioned
- Clean up names (remove brand names, sizes, but keep main food item)
- Return JSON array format: [{"name": "item name", "quantity": number}]

Examples:
- "Heritage Farm® Bone In Skin On Chicken Thighs, 1 lb" → {"name": "chicken thighs", "quantity": 1}
- "2x Kroger AutumnCrisp Fresh Seedless Green Grapes" → {"name": "green grapes", "quantity": 2}
- "Kroger® 93/7 Ground Beef Tray 1 LB" → {"name": "ground beef", "quantity": 1}

JSON array:''';
  }

  static Future<String?> _callOllama(String prompt) async {
    try {
      final response = await http.post(
        Uri.parse('http://10.0.0.218:11434/api/generate'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'model': 'llama3.2:3b',
          'prompt': prompt,
          'stream': false,
          'options': {
            'temperature': 0.1,
            'top_p': 0.9,
            'num_predict': 200,
          }
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['response']?.toString().trim();
      } else {
        print('Ollama API error: ${response.statusCode} - ${response.body}');
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
            
            if (name != null && name.isNotEmpty) {
              final qty = quantity is int ? quantity : (int.tryParse(quantity?.toString() ?? '1') ?? 1);
              items.add(ParsedItem(name: _titleCase(name), quantity: qty));
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

  static List<ParsedItem> _parseWithRegex(String fullText) {
    // Fallback to the original regex parsing logic
    final rawLines = fullText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final items = <ParsedItem>[];
    var stopAtTotals = false;
    var inItemSection = false;

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

      // Skip obvious noise lines
      if (_noise.hasMatch(low)) continue;
      if (_dateLike.hasMatch(low)) continue;
      if (_longDigits.hasMatch(low)) continue;

      // Check if this looks like an item line
      final hasPrice = _price.hasMatch(line);
      final hasQtyPrefix = _qtyPrefix.hasMatch(line);
      final hasQtySuffix = _qtySuffix.hasMatch(line);
      final hasUPC = _upc.hasMatch(line);

      // If we have a price or quantity, we're in the item section
      if (hasPrice || hasQtyPrefix || hasQtySuffix || hasUPC) {
        inItemSection = true;
      }

      // Skip lines that don't look like items
      if (!inItemSection) continue;

      // Process the line as a potential item
      print('Processing line: "$line"');
      var processedLine = _processItemLine(line);
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

  static ParsedItem? _processItemLine(String line) {
    // Extract quantity first
    int qty = 1;
    var name = line;
    
    final mPrefix = _qtyPrefix.firstMatch(name);
    if (mPrefix != null) {
      qty = int.tryParse(mPrefix.group(1) ?? '1') ?? 1;
      name = name.replaceFirst(mPrefix.group(0)!, '').trim();
    } else {
      final mSuffix = _qtySuffix.firstMatch(name);
      if (mSuffix != null) {
        qty = int.tryParse(mSuffix.group(1) ?? '1') ?? 1;
        name = name.replaceFirst(mSuffix.group(0)!, '').trim();
      }
    }

    // Clean up the name by removing various patterns
    name = _cleanItemName(name);
    
    // Validate the name
    if (!_isValidItemName(name)) return null;

    return ParsedItem(name: _titleCase(name), quantity: qty);
  }

  static String _cleanItemName(String name) {
    // Remove prices
    name = name.replaceAll(_price, '');
    
    // Remove weights
    name = name.replaceAll(_weight, '');
    
    // Remove UPC codes
    name = name.replaceAll(_upc, '');
    
    // Remove product codes
    name = name.replaceAll(RegExp(r'#?\b\d{4,}\b'), '');
    
    // Remove common store abbreviations and noise words
    name = name.replaceAll(RegExp(r'\b(pkg|ea|misc|dept|tpr|promo|ct|pk|lb|oz|each|per|price|sale|discount|coupon|clearance|manager|special)\b', caseSensitive: false), '');
    
    // Remove extra whitespace
    name = name.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    
    // Remove leading/trailing punctuation
    name = name.replaceAll(RegExp(r'^[^\w\s]+|[^\w\s]+$'), '');
    
    return name.trim();
  }

  static bool _isValidItemName(String name) {
    if (name.isEmpty) return false;
    
    // Must have at least 2 alphabetic characters
    final alphaCount = RegExp(r'[A-Za-z]').allMatches(name).length;
    if (alphaCount < 2) return false;
    
    // Must not be mostly numbers or symbols
    final alphaRatio = alphaCount / name.length;
    if (alphaRatio < 0.3) return false;
    
    // Must not be too short or too long
    if (name.length < 3 || name.length > 100) return false;
    
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
  ParsedItem({required this.name, required this.quantity});
  ParsedItem copyWith({String? name, int? quantity}) =>
      ParsedItem(name: name ?? this.name, quantity: quantity ?? this.quantity);
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
