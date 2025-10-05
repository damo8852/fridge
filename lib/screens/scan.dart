import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
// Removed mobile_scanner import
import 'package:image_picker/image_picker.dart';

import '../services/parser.dart';
// Removed notifications import (was only used for barcode functionality)
import '../services/llm_service.dart';
import '../services/theme_service.dart';
import '../models/grocery_type.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with SingleTickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  // Removed barcode scanner components
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  List<ParsedItem> _preview = [];
  bool _busy = false;
  String? _err;
  late final ThemeService _themeService;

  ExpiryRules? _rules;
  UpcMap? _upc;

  // Removed barcode handling

  @override
  void initState() {
    super.initState();
    _themeService = ThemeService();
    _themeService.addListener(_onThemeChanged);
    // Removed tab controller and barcode scanner initialization
    _loadAssets();
  }

  void _onThemeChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadAssets() async {
    _rules ??= await ExpiryRules.load();
    _upc ??= await UpcMap.load();
    if (mounted) setState(() {});
  }

  void _toggleDarkMode() {
    _themeService.toggleDarkMode();
  }

  @override
  void dispose() {
    _themeService.removeListener(_onThemeChanged);
    // Removed tab controller and barcode scanner disposal
    _textRecognizer.close();
    super.dispose();
  }

  void _clearPreview() {
    if (mounted) {
      setState(() {
        _preview = [];
        _err = null;
      });
    }
  }


  Future<void> _pickAndProcess(ImageSource source) async {
    setState(() {
      _busy = true;
      _err = null;
      _preview = [];
    });
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(source: source, imageQuality: 85);
      if (x == null) {
        setState(() => _busy = false);
        return;
      }
      final file = File(x.path);
      final input = InputImage.fromFile(file);
      final result = await _textRecognizer.processImage(input);
      final items = await ReceiptParser.parse(result.text);
      setState(() => _preview = items);
    } catch (e) {
      setState(() => _err = 'OCR failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _saveAll() async {
    if (_preview.isEmpty) return;
    
    setState(() => _busy = true);
    
    try {
      final user = _auth.currentUser!;
      final rules = _rules ?? await ExpiryRules.load();

      final batch = _db.batch();
      final col = _db.collection('users').doc(user.uid).collection('items');
      final now = DateTime.now();

      // Temporarily disabled notifications to prevent crashes
      // final notificationTasks = <Future<void>>[];

      for (final it in _preview) {
        // Use type from parsed item if available, otherwise try LLM prediction
        int days = 5; // Default fallback
        GroceryType itemType = it.type; // Use type from parsed item
        
        try {
          final prediction = await LLMService().predictExpiryAndType(it.name);
          if (prediction != null) {
            days = prediction['days'] as int? ?? rules.guessDays(it.name);
            // Only override type if LLM prediction is more specific than 'other'
            final typeStr = prediction['type'] as String?;
            if (typeStr != null && itemType == GroceryType.other) {
              itemType = GroceryType.fromString(typeStr);
            }
          } else {
            days = rules.guessDays(it.name);
          }
        } catch (e) {
          print('LLM prediction failed for ${it.name}, using rules: $e');
          days = rules.guessDays(it.name);
        }
        
        final expiry = now.add(Duration(days: days));
        final doc = col.doc();
        
        batch.set(doc, {
          'name': it.name,
          'quantity': it.quantity,
          'expiryDate': Timestamp.fromDate(expiry),
          'groceryType': itemType.name,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'source': 'receipt',
        });
        
        // Temporarily disable notifications to prevent crashes
        // Schedule notification (don't await here, collect for later)
        // Use a more stable ID generation to avoid potential hash collisions
        // final notificationId = doc.id.hashCode.abs();
        // notificationTasks.add(
        //   _scheduleNotificationSafely(
        //     id: notificationId,
        //     title: 'Use soon: ${it.name}',
        //     body: 'Expires tomorrow',
        //     when: expiry.subtract(const Duration(days: 1)),
        //   ),
        // );
      }
      
      // Commit the batch first with timeout
      await batch.commit().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Firestore batch commit timed out');
        },
      );
      
      // Then handle notifications (fire and forget, don't block UI)
      // Schedule notifications in the background without blocking
      // Temporarily disable notifications to prevent crashes
      // if (notificationTasks.isNotEmpty) {
      //   unawaited(_handleNotificationsSafely(notificationTasks));
      // }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${_preview.length} items')),
        );
        // Clear the preview and reset state instead of navigating away
        _clearPreview();
      }
    } catch (e) {
      print('Error saving items: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save items: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Removed barcode handling methods

  // Removed _confirmAndSave method (was for barcode functionality)

  void _editParsedItem(int index) {
    final it = _preview[index];
    final nameCtrl = TextEditingController(text: it.name);
    final qtyCtrl = TextEditingController(text: it.quantity.toString());

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Edit parsed item'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
              TextField(controller: qtyCtrl, decoration: const InputDecoration(labelText: 'Quantity'), keyboardType: TextInputType.number),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                setState(() {
                  _preview[index] = ParsedItem(
                    name: nameCtrl.text.trim(),
                    quantity: int.tryParse(qtyCtrl.text) ?? it.quantity,
                  );
                });
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _themeService.isDarkMode ? ThemeService.darkBackground : ThemeService.lightBackground,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _themeService.isDarkMode ? ThemeService.darkCardBackground : Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(_themeService.isDarkMode ? 0.3 : 0.1),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.qr_code_scanner_rounded,
                color: Color(0xFF27AE60),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Smart Scanner',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : ThemeService.lightTextPrimary,
              ),
            ),
          ],
        ),
        backgroundColor: _themeService.isDarkMode ? ThemeService.darkBackground : ThemeService.lightBackground,
        elevation: 0,
        iconTheme: IconThemeData(
          color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : ThemeService.lightTextPrimary,
        ),
        actions: [
          IconButton(
            tooltip: _themeService.isDarkMode ? 'Switch to light mode' : 'Switch to dark mode',
            onPressed: _toggleDarkMode,
            icon: Icon(
              _themeService.isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              color: _themeService.isDarkMode ? const Color(0xFFF1C40F) : const Color(0xFF7F8C8D),
            ),
            style: IconButton.styleFrom(
              padding: const EdgeInsets.all(8),
              minimumSize: const Size(32, 32),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildReceiptTab(),
    );
  }

  Widget _buildReceiptTab() {
    return Column(
      children: [
        if (_err != null)
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE74C3C).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFE74C3C).withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFFE74C3C),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _err!,
                    style: const TextStyle(
                      color: Color(0xFFE74C3C),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _busy
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF27AE60).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF27AE60)),
                          strokeWidth: 3,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Processing receipt...',
                        style: TextStyle(
                          color: _themeService.isDarkMode ? ThemeService.darkTextSecondary : const Color(0xFF7F8C8D),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                )
              : _preview.isEmpty
                  ? const SizedBox.shrink()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _preview.length,
                      itemBuilder: (_, i) {
                        final it = _preview[i];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: _themeService.isDarkMode ? ThemeService.darkCardBackground : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(_themeService.isDarkMode ? 0.2 : 0.06),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            title: Text(
                              it.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _themeService.isDarkMode ? ThemeService.darkTextPrimary : const Color(0xFF2C3E50),
                              ),
                            ),
                            subtitle: Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _themeService.isDarkMode 
                                    ? const Color(0xFF2C3E50).withOpacity(0.3)
                                    : const Color(0xFFE8F4FD),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Qty: ${it.quantity}',
                                style: TextStyle(
                                  color: _themeService.isDarkMode 
                                      ? const Color(0xFF7BB3F0)
                                      : const Color(0xFF3498DB),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            trailing: Container(
                              decoration: BoxDecoration(
                                color: _themeService.isDarkMode 
                                    ? ThemeService.darkCardBackground
                                    : const Color(0xFFF8F9FA),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: IconButton(
                                icon: Icon(
                                  Icons.edit_rounded,
                                  color: _themeService.isDarkMode ? const Color(0xFF7BB3F0) : const Color(0xFF4A90E2),
                                ),
                                onPressed: () => _editParsedItem(i),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
        Container(
          margin: const EdgeInsets.only(top: 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _themeService.isDarkMode ? ThemeService.darkCardBackground : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(_themeService.isDarkMode ? 0.3 : 0.1),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child:                   _buildActionButton(
                      icon: Icons.photo_library_rounded,
                      label: 'Gallery',
                      color: _themeService.isDarkMode ? const Color(0xFFBB6BD9) : const Color(0xFF9B59B6),
                      onPressed: _busy ? null : () => _pickAndProcess(ImageSource.gallery),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child:                     _buildActionButton(
                      icon: Icons.camera_alt_rounded,
                      label: 'Camera',
                      color: _themeService.isDarkMode ? const Color(0xFF5DADE2) : const Color(0xFF3498DB),
                      onPressed: _busy ? null : () => _pickAndProcess(ImageSource.camera),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildActionButton(
                      icon: _busy 
                        ? null 
                        : Icons.check_circle_rounded,
                      label: _busy ? 'Saving...' : 'Save All',
                      color: _themeService.isDarkMode ? const Color(0xFF58D68D) : const Color(0xFF27AE60),
                      onPressed: (_preview.isEmpty || _busy) ? null : _saveAll,
                      isLoading: _busy,
                    ),
                  ),
                ],
              ),
              if (_preview.isNotEmpty) ...[
                const SizedBox(height: 12),
                  _buildActionButton(
                  icon: Icons.clear_all_rounded,
                  label: 'Clear Preview',
                  color: _themeService.isDarkMode ? const Color(0xFFFF6B6B) : const Color(0xFFE74C3C),
                  onPressed: _busy ? null : _clearPreview,
                  isFullWidth: true,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData? icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
    bool isLoading = false,
    bool isFullWidth = false,
  }) {
    Widget button = Container(
      height: 48,
      decoration: BoxDecoration(
        color: onPressed != null ? color : color.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        boxShadow: onPressed != null ? [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ] : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null && !isLoading) ...[
                  Icon(
                    icon,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                ],
                if (isLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                if (isLoading) const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (isFullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }

  // Removed _buildBarcodeTab method
}

