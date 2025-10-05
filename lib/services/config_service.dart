import 'package:cloud_firestore/cloud_firestore.dart';

class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  // Cache for the API key to avoid repeated Firestore reads
  String? _cachedApiKey;
  DateTime? _cacheTime;
  static const Duration _cacheExpiry = Duration(minutes: 30); // Cache for 30 minutes

  /// Get the Mistral API key from Firebase
  /// This reads from a Firestore document: /config/mistral
  Future<String?> getMistralApiKey() async {
    // Check cache first
    if (_cachedApiKey != null && 
        _cacheTime != null && 
        DateTime.now().difference(_cacheTime!) < _cacheExpiry) {
      return _cachedApiKey;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('mistral')
          .get();

      if (doc.exists) {
        final data = doc.data();
        final apiKey = data?['api_key'] as String?;
        
        // Cache the result
        _cachedApiKey = apiKey;
        _cacheTime = DateTime.now();
        
        return apiKey;
      } else {
        print('Mistral config document not found in Firestore');
        return null;
      }
    } catch (e) {
      print('Error fetching Mistral API key from Firebase: $e');
      return null;
    }
  }

  /// Check if API key is configured
  Future<bool> hasMistralApiKey() async {
    final key = await getMistralApiKey();
    return key != null && key.isNotEmpty;
  }

  /// Clear the cached API key (force refresh on next call)
  void clearCache() {
    _cachedApiKey = null;
    _cacheTime = null;
  }

  /// Initialize - no longer needed since we read from Firebase
  Future<void> initializeWithDefaultKey() async {
    // This method is kept for compatibility but does nothing
    // The API key should be set directly in Firebase Console
    print('ConfigService: API key should be configured in Firebase Console at /config/mistral');
  }
}
