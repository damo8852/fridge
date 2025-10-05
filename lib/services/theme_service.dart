import 'package:flutter/material.dart';

class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  bool _isDarkMode = false;
  bool get isDarkMode => _isDarkMode;

  void toggleDarkMode() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }

  void setDarkMode(bool isDark) {
    _isDarkMode = isDark;
    notifyListeners();
  }

  // Dark mode colors
  static const Color darkBackground = Color(0xFF1A1A1A);
  static const Color darkCardBackground = Color(0xFF2C2C2C);
  static const Color darkTextPrimary = Color(0xFFE8E8E8);
  static const Color darkTextSecondary = Color(0xFF9E9E9E);
  static const Color darkBorder = Color(0xFF4A4A4A);

  // Light mode colors
  static const Color lightBackground = Color(0xFFF8F9FA);
  static const Color lightCardBackground = Colors.white;
  static const Color lightTextPrimary = Color(0xFF2C3E50);
  static const Color lightTextSecondary = Color(0xFF7F8C8D);
  static const Color lightBorder = Color(0xFFE0E0E0);
}
