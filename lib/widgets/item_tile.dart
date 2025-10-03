import 'package:flutter/material.dart';

class ItemTile extends StatelessWidget {
  const ItemTile({
    super.key,
    required this.name,
    required this.expiry,
    required this.quantity,
    required this.onEdit,
    required this.onUsedHalf,
    required this.onFinish,
  });

  final String name;
  final DateTime? expiry;
  final num quantity;
  final VoidCallback onEdit;
  final Future<void> Function() onUsedHalf;
  final Future<void> Function() onFinish;

  @override
  Widget build(BuildContext context) {
    final dateStr = expiry != null ? expiry!.toLocal().toString().split(' ').first : '—';
    int? daysLeft;
    if (expiry != null) {
      final today = DateTime.now();
      daysLeft = DateTime(expiry!.year, expiry!.month, expiry!.day)
          .difference(DateTime(today.year, today.month, today.day)).inDays;
    }
    final chip = daysLeft == null
        ? 'no date'
        : (daysLeft <= 0 ? 'today' : daysLeft == 1 ? 'in 1 day' : 'in $daysLeft days');
    final chipColor = daysLeft == null
        ? Colors.grey
        : (daysLeft <= 1 ? Colors.redAccent : daysLeft <= 3 ? Colors.orange : Colors.green);

    return ListTile(
      title: Text(name),
      subtitle: Text('Qty: $quantity • Expires: $dateStr • $chip',
          style: TextStyle(color: chipColor)),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'edit') onEdit();
          if (v == 'half') onUsedHalf();
          if (v == 'finish') onFinish();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(value: 'half', child: Text('Used ½')),
          PopupMenuItem(value: 'finish', child: Text('Finished')),
        ],
      ),
    );
  }
}
