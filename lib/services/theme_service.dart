import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  bool _isDarkMode = false;
  bool _isCompactView = false;
  bool _useLbs = true; // Default to lbs for carbon display
  bool get isDarkMode => _isDarkMode;
  bool get isCompactView => _isCompactView;
  bool get useLbs => _useLbs;

  static const String _darkModeKey = 'dark_mode';
  static const String _compactViewKey = 'compact_view';
  static const String _useLbsKey = 'use_lbs';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool(_darkModeKey) ?? false;
    _isCompactView = prefs.getBool(_compactViewKey) ?? false;
    _useLbs = prefs.getBool(_useLbsKey) ?? true; // Default to lbs
    notifyListeners();
  }

  Future<void> toggleDarkMode() async {
    _isDarkMode = !_isDarkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModeKey, _isDarkMode);
    notifyListeners();
  }

  Future<void> setDarkMode(bool isDark) async {
    _isDarkMode = isDark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModeKey, _isDarkMode);
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    await toggleDarkMode();
  }

  Future<void> toggleCompactView() async {
    _isCompactView = !_isCompactView;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_compactViewKey, _isCompactView);
    notifyListeners();
  }

  Future<void> toggleCarbonUnit() async {
    _useLbs = !_useLbs;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useLbsKey, _useLbs);
    notifyListeners();
  }

  // Dark mode colors
  static const Color darkBackground = Color(0xFF1A1A1A);
  static const Color darkCard = Color(0xFF2C2C2C);
  static const Color darkCardBackground = Color(0xFF2C2C2C);
  static const Color darkTextPrimary = Color(0xFFE8E8E8);
  static const Color darkTextSecondary = Color(0xFF9E9E9E);
  static const Color darkBorder = Color(0xFF4A4A4A);

  // Light mode colors
  static const Color lightBackground = Color(0xFFF8F9FA);
  static const Color lightCard = Colors.white;
  static const Color lightCardBackground = Colors.white;
  static const Color lightTextPrimary = Color(0xFF2C3E50);
  static const Color lightTextSecondary = Color(0xFF7F8C8D);
  static const Color lightBorder = Color(0xFFE0E0E0);

  // Primary color
  static const Color primaryColor = Color(0xFF27AE60);
}
