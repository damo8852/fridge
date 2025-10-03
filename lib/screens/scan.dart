import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';

import '../services/parser.dart';
import '../services/notifications.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with SingleTickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  late final TabController _tab;
  late final MobileScannerController _barcodeCtrl;
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  List<ParsedItem> _preview = [];
  bool _busy = false;
  String? _err;

  ExpiryRules? _rules;
  UpcMap? _upc;

  bool _handlingBarcode = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _barcodeCtrl = MobileScannerController(
      facing: CameraFacing.back,
      detectionSpeed: DetectionSpeed.normal,
      torchEnabled: false,
      formats: const [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code128,
      ],
    );
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    _rules ??= await ExpiryRules.load();
    _upc ??= await UpcMap.load();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tab.dispose();
    _barcodeCtrl.dispose();
    _textRecognizer.close();
    super.dispose();
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
      final items = ReceiptParser.parse(result.text);
      setState(() => _preview = items);
    } catch (e) {
      setState(() => _err = 'OCR failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _saveAll() async {
    if (_preview.isEmpty) return;
    final user = _auth.currentUser!;
    final rules = _rules ?? await ExpiryRules.load();

    final batch = _db.batch();
    final col = _db.collection('users').doc(user.uid).collection('items');
    final now = DateTime.now();

    for (final it in _preview) {
      final days = rules.guessDays(it.name);
      final expiry = now.add(Duration(days: days));
      final doc = col.doc();
      batch.set(doc, {
        'name': it.name,
        'quantity': it.quantity,
        'expiryDate': Timestamp.fromDate(expiry),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'source': 'receipt',
      });
      await NotificationsService.instance.scheduleExpiryReminder(
        id: doc.id.hashCode,
        title: 'Use soon: ${it.name}',
        body: 'Expires tomorrow',
        when: expiry.subtract(const Duration(days: 1)),
      );
    }
    await batch.commit();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${_preview.length} items')),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _handleBarcode(String upc) async {
    if (_handlingBarcode) return;
    _handlingBarcode = true;
    try {
      final upcMap = _upc ?? await UpcMap.load();
      final suggested = upcMap.nameFor(upc);
      await _confirmAndSaveBarcode(suggested);
    } finally {
      _handlingBarcode = false;
      if (mounted) await _barcodeCtrl.start();
    }
  }

  Future<void> _confirmAndSaveBarcode(String name) async {
    final nameCtrl = TextEditingController(text: name);
    final qtyCtrl = TextEditingController(text: '1');
    final rules = _rules ?? await ExpiryRules.load();
    DateTime expiry = DateTime.now().add(Duration(days: rules.guessDays(name)));

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Add from barcode'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
                  TextField(controller: qtyCtrl, decoration: const InputDecoration(labelText: 'Quantity'), keyboardType: TextInputType.number),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: expiry,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 120)),
                      );
                      if (picked != null) setLocal(() => expiry = picked);
                    },
                    icon: const Icon(Icons.calendar_month),
                    label: Text('Expires ${expiry.toLocal().toString().split(' ').first}'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final user = _auth.currentUser!;
                    final col = _db.collection('users').doc(user.uid).collection('items');
                    final doc = col.doc();
                    await doc.set({
                      'name': nameCtrl.text.trim(),
                      'quantity': int.tryParse(qtyCtrl.text) ?? 1,
                      'expiryDate': Timestamp.fromDate(expiry),
                      'createdAt': FieldValue.serverTimestamp(),
                      'updatedAt': FieldValue.serverTimestamp(),
                      'source': 'barcode',
                    });
                    await NotificationsService.instance.scheduleExpiryReminder(
                      id: doc.id.hashCode,
                      title: 'Use soon: ${nameCtrl.text.trim()}',
                      body: 'Expires tomorrow',
                      when: expiry.subtract(const Duration(days: 1)),
                    );
                    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

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
      appBar: AppBar(
        title: const Text('Scan'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [Tab(text: 'Receipt'), Tab(text: 'Barcode')],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildReceiptTab(),
          _buildBarcodeTab(),
        ],
      ),
    );
  }

  Widget _buildReceiptTab() {
    return Column(
      children: [
        if (_err != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        Expanded(
          child: _busy
              ? const Center(child: CircularProgressIndicator())
              : _preview.isEmpty
                  ? const _ScanHint(text: 'Pick or snap a clear photo of your receipt.')
                  : ListView.builder(
                      itemCount: _preview.length,
                      itemBuilder: (_, i) {
                        final it = _preview[i];
                        return ListTile(
                          title: Text(it.name),
                          subtitle: Text('Qty: ${it.quantity}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _editParsedItem(i),
                          ),
                        );
                      },
                    ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.photo),
                  label: const Text('Gallery'),
                  onPressed: () => _pickAndProcess(ImageSource.gallery),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Camera'),
                  onPressed: () => _pickAndProcess(ImageSource.camera),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Save items'),
                  onPressed: _preview.isEmpty ? null : _saveAll,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBarcodeTab() {
    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: MobileScanner(
              controller: _barcodeCtrl,
              onDetect: (capture) async {
                final list = capture.barcodes;
                if (list.isEmpty) return;
                final code = list.first.rawValue;
                if (code == null) return;
                await _barcodeCtrl.stop();
                await _handleBarcode(code);
              },
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Point the camera at a barcode'),
        ),
      ],
    );
  }
}

class _ScanHint extends StatelessWidget {
  const _ScanHint({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
    );
  }
}
