import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/auth.dart';
import '../services/recipes.dart';
import '../services/notifications.dart';
import '../services/llm_service.dart';
import '../widgets/item_tile.dart';
import '../models/grocery_type.dart';
import 'scan.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  User get user => _auth.currentUser!;
  String _status = 'Ready';
  GroceryType? _selectedFilter;
  bool _llmAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkLLMAvailability();
  }

  Future<void> _checkLLMAvailability() async {
    final available = await LLMService().isAvailable();
    if (mounted) {
      setState(() => _llmAvailable = available);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ownerId = user.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fridge'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              await AuthService.instance.signOut();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addItemDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(child: Text('Hi, ${user.isAnonymous ? 'Guest' : (user.displayName ?? 'you')}')),
                Row(
                  children: [
                    Icon(
                      _llmAvailable ? Icons.auto_awesome : Icons.auto_awesome_outlined,
                      size: 16,
                      color: _llmAvailable 
                        ? Theme.of(context).colorScheme.primary 
                        : Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(_status, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                  ],
                ),
              ],
            ),
          ),
          // Filter chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: _selectedFilter == null,
                    onSelected: (selected) {
                      setState(() => _selectedFilter = null);
                    },
                  ),
                  ...GroceryType.allTypes.map((type) => FilterChip(
                    label: Text(type.displayName),
                    selected: _selectedFilter == type,
                    onSelected: (selected) {
                      setState(() => _selectedFilter = selected ? type : null);
                    },
                  )),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _seedTestData,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Seed'),
                ),
                OutlinedButton.icon(
                  onPressed: _recommendRecipes,
                  icon: const Icon(Icons.restaurant_menu),
                  label: const Text('Recipes'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ScanPage()),
                  ),
                  icon: const Icon(Icons.document_scanner),
                  label: const Text('Scan'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _db
                  .collection('users')
                  .doc(ownerId)
                  .collection('items')
                  .orderBy('expiryDate')
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const _EmptyState();
                }
                
                // Filter items by grocery type
                final filteredDocs = _selectedFilter == null 
                    ? docs 
                    : docs.where((doc) {
                        final data = doc.data();
                        final groceryType = GroceryType.fromString(data['groceryType'] ?? 'other');
                        return groceryType == _selectedFilter;
                      }).toList();
                
                if (filteredDocs.isEmpty) {
                  return const Center(
                    child: Text('No items found for this filter'),
                  );
                }
                
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, i) {
                    final ref = filteredDocs[i].reference;
                    final data = filteredDocs[i].data();
                    final groceryType = GroceryType.fromString(data['groceryType'] ?? 'other');
                    return Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ItemTile(
                        name: (data['name'] ?? 'Unknown').toString(),
                        expiry: (data['expiryDate'] as Timestamp?)?.toDate(),
                        quantity: (data['quantity'] ?? 1),
                        groceryType: groceryType,
                        onEdit: () => _editItemDialog(ref, data),
                        onUsedHalf: () async {
                          final q = data['quantity'];
                          final newQ = (q is num) ? (q / 2) : 1;
                          await ref.update({
                            'quantity': newQ,
                            'updatedAt': FieldValue.serverTimestamp(),
                          });
                        },
                        onFinish: () async => ref.delete(),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addItemDialog() async {
    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    DateTime expiry = DateTime.now().add(const Duration(days: 5));
    GroceryType selectedType = GroceryType.other;
    bool isPredicting = false;

    Future<void> predictExpiry() async {
      final name = nameCtrl.text.trim();
      if (name.isEmpty) return;
      
      setState(() => isPredicting = true);
      
      try {
        final prediction = await LLMService().predictExpiryAndType(name);
        if (prediction != null) {
          final days = prediction['days'] as int?;
          final type = prediction['type'] as String?;
          
          if (days != null) {
            setState(() {
              expiry = DateTime.now().add(Duration(days: days));
              if (type != null) {
                selectedType = GroceryType.fromString(type);
              }
            });
          }
        }
      } catch (e) {
        print('Prediction error: $e');
      } finally {
        setState(() => isPredicting = false);
      }
    }

    Future<void> save() async {
      final name = nameCtrl.text.trim();
      if (name.isEmpty) return;
      final ref = _db.collection('users').doc(user.uid).collection('items').doc();
      await ref.set({
        'name': name,
        'quantity': int.tryParse(qtyCtrl.text) ?? 1,
        'expiryDate': Timestamp.fromDate(expiry),
        'groceryType': selectedType.name,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'source': 'manual',
      });
      await NotificationsService.instance.scheduleExpiryReminder(
        id: ref.id.hashCode,
        title: 'Use soon: $name',
        body: 'Expires tomorrow',
        when: expiry.subtract(const Duration(days: 1)),
      );
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return StatefulBuilder(builder: (context, setLocal) {
          return AlertDialog(
            title: const Text('Add Item'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl, 
                  decoration: const InputDecoration(labelText: 'Name'),
                  onChanged: (value) {
                    // Trigger prediction when name changes (with debounce)
                    if (value.trim().isNotEmpty) {
                      Future.delayed(const Duration(milliseconds: 1000), () {
                        if (nameCtrl.text.trim() == value.trim()) {
                          predictExpiry();
                        }
                      });
                    }
                  },
                ),
                TextField(
                  controller: qtyCtrl,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<GroceryType>(
                        value: selectedType,
                        decoration: const InputDecoration(labelText: 'Grocery Type'),
                        items: GroceryType.allTypes.map((type) => DropdownMenuItem(
                          value: type,
                          child: Text(type.displayName),
                        )).toList(),
                        onChanged: (value) {
                          if (value != null) setLocal(() => selectedType = value);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: isPredicting ? null : () async {
                        final name = nameCtrl.text.trim();
                        if (name.isNotEmpty) {
                          await predictExpiry();
                        }
                      },
                      icon: isPredicting 
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                      tooltip: 'Predict expiry with AI',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: expiry,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 120)),
                    );
                    if (picked != null) setLocal(() => expiry = picked); // local state
                  },
                  icon: const Icon(Icons.calendar_month),
                  label: Text('Expires ${expiry.toLocal().toString().split(' ').first}'),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context, rootNavigator: true).pop(), child: const Text('Cancel')),
              FilledButton(onPressed: () async {
                try {
                  final name = nameCtrl.text.trim();
                  if (name.isNotEmpty) {
                    await save();
                  }
                } catch (e) {
                  // Handle any errors during save, but still close the dialog
                  print('Error saving item: $e');
                }
                if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
              }, child: const Text('Save')),
            ],
          );
        });
      },
    );
  }

  Future<void> _editItemDialog(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
  ) async {
    final nameCtrl = TextEditingController(text: (data['name'] ?? '').toString());
    final qtyCtrl = TextEditingController(text: (data['quantity'] ?? 1).toString());
    DateTime expiry =
        (data['expiryDate'] as Timestamp?)?.toDate() ?? DateTime.now().add(const Duration(days: 5));
    GroceryType selectedType = GroceryType.fromString(data['groceryType'] ?? 'other');

    Future<void> save() async {
      await ref.update({
        'name': nameCtrl.text.trim(),
        'quantity': int.tryParse(qtyCtrl.text) ?? 1,
        'expiryDate': Timestamp.fromDate(expiry),
        'groceryType': selectedType.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return StatefulBuilder(builder: (context, setLocal) {
          return AlertDialog(
            title: const Text('Edit Item'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
                TextField(
                  controller: qtyCtrl,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<GroceryType>(
                  value: selectedType,
                  decoration: const InputDecoration(labelText: 'Grocery Type'),
                  items: GroceryType.allTypes.map((type) => DropdownMenuItem(
                    value: type,
                    child: Text(type.displayName),
                  )).toList(),
                  onChanged: (value) {
                    if (value != null) setLocal(() => selectedType = value);
                  },
                ),
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
              TextButton(onPressed: () => Navigator.of(context, rootNavigator: true).pop(), child: const Text('Cancel')),
              FilledButton(onPressed: () async {
                try {
                  await save();
                } catch (e) {
                  // Handle any errors during save, but still close the dialog
                  print('Error updating item: $e');
                }
                if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
              }, child: const Text('Save')),
            ],
          );
        });
      },
    );
  }

  Future<void> _seedTestData() async {
    final ownerId = user.uid;
    final itemsRef = _db.collection('users').doc(ownerId).collection('items');

    final now = DateTime.now();
    final sample = [
      {
        'name': 'Milk',
        'expiryDate': Timestamp.fromDate(now.add(const Duration(days: 7))),
        'quantity': 1,
        'groceryType': GroceryType.dairy.name,
        'source': 'seed'
      },
      {
        'name': 'Eggs',
        'expiryDate': Timestamp.fromDate(now.add(const Duration(days: 35))),
        'quantity': 12,
        'groceryType': GroceryType.dairy.name,
        'source': 'seed'
      },
      {
        'name': 'Berries',
        'expiryDate': Timestamp.fromDate(now.add(const Duration(days: 5))),
        'quantity': 1,
        'groceryType': GroceryType.fruit.name,
        'source': 'seed'
      },
    ];

    final batch = _db.batch();
    for (final item in sample) {
      final doc = itemsRef.doc();
      batch.set(doc, {
        ...item,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final expiry = (item['expiryDate'] as Timestamp).toDate();
      await NotificationsService.instance.scheduleExpiryReminder(
        id: doc.id.hashCode,
        title: 'Use soon: ${item['name']}',
        body: 'Expires tomorrow',
        when: expiry.subtract(const Duration(days: 1)),
      );
    }
    await batch.commit();
    if (mounted) setState(() => _status = 'Seeded ${sample.length} items');
  }

  Future<void> _recommendRecipes() async {
    if (!mounted) return;
    setState(() => _status = 'Getting recipes…');
    try {
      final recipes = await RecipesService(region: 'us-central1').recommend();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(recipes.isEmpty ? 'No matches yet' : recipes.join(' • '))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recipes unavailable: $e')),
      );
    } finally {
      if (mounted) setState(() => _status = 'Ready');
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text('No items yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('Tap “Add item” to get started.', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
