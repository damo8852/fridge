import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

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

/// Very lightweight receipt line parser (improved heuristics)
class ReceiptParser {
  // prices like 3.89 or $8.99
  static final _price = RegExp(r'(?<!\d)(?:\$)?\d{1,3}(?:[.,]\d{2})(?!\d)');
  // quantity: "2x Milk" / "2 Milk"  OR suffix "Milk x2"
  static final _qtyPrefix = RegExp(r'^\s*(\d+)\s*x?\s+');
  static final _qtySuffix = RegExp(r'\s+x\s*(\d+)\s*$');
  // weight tokens we strip
  static final _weight = RegExp(r'\b\d+(?:\.\d+)?\s?(?:lb|lbs|oz|kg|g)\b', caseSensitive: false);
  // obvious non-item lines
  static final _noise = RegExp(
    r'\b(?:subtotal|total|tax|purchase|change|cash|visa|debit|credit|auth|exp(?:iration| date)?|cashier|lane|sequence|seq|eps|term|ref|date|time|pm|am|#\d+)\b',
    caseSensitive: false,
  );
  // looks like a date/time line
  static final _dateLike = RegExp(r'\b\d{1,2}[:/.-]\d{1,2}[:/.-]\d{2,4}\b|\b\d{1,2}:\d{2}\s?(?:AM|PM)?\b', caseSensitive: false);
  // product codes / long digit runs
  static final _longDigits = RegExp(r'\b\d{5,}\b');

  static List<ParsedItem> parse(String fullText) {
    final rawLines = fullText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final items = <ParsedItem>[];
    var stopAtTotals = false;

    for (var line in rawLines) {
      final low = line.toLowerCase();

      // Hard stop if we hit SUBTOTAL/TOTAL section
      if (low.contains('subtotal') || low.contains(RegExp(r'\btotal\b'))) {
        stopAtTotals = true;
      }
      if (stopAtTotals) continue;

      // Quick reject: obvious noise, dates/times, long digit blobs
      if (_noise.hasMatch(low)) continue;
      if (_dateLike.hasMatch(low)) continue;
      if (_longDigits.hasMatch(low)) continue;

      // Keep only lines that look like an item row:
      //  - have a price OR a leading quantity OR a trailing "x2"
      final hasPrice = _price.hasMatch(line);
      final hasQtyPrefix = _qtyPrefix.hasMatch(line);
      final hasQtySuffix = _qtySuffix.hasMatch(line);

      if (!(hasPrice || hasQtyPrefix || hasQtySuffix)) continue;

      // Strip price/weight/junk tokens
      var name = line
          .replaceAll(_price, '')
          .replaceAll(_weight, '')
          .replaceAll(RegExp(r'\s{2,}'), ' ')
          .trim();

      // Extract quantity
      int qty = 1;
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

      // Remove product codes like "#12345" / "934518"
      name = name.replaceAll(RegExp(r'#?\b\d{4,}\b'), '').trim();

      // Drop common store abbreviations
      name = name.replaceAll(RegExp(r'\b(pkg|ea|misc|dept|tpr|promo)\b', caseSensitive: false), '').trim();

      // Keep only if we still have at least 2 alphabetic tokens
      final alphaTokens = name.split(RegExp(r'\s+')).where((t) => RegExp(r'[A-Za-z]').hasMatch(t)).toList();
      if (alphaTokens.length < 2) continue;

      items.add(ParsedItem(name: _titleCase(name), quantity: qty));
    }

    // Merge duplicates by normalized name
    final merged = <String, ParsedItem>{};
    for (final it in items) {
      final key = it.name.toLowerCase();
      final existing = merged[key];
      if (existing == null) {
        merged[key] = it;
      } else {
        merged[key] = existing.copyWith(quantity: existing.quantity + it.quantity);
      }
    }
    return merged.values.toList();
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
