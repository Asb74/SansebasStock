import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class PaletTile extends StatelessWidget {
  const PaletTile({
    super.key,
    required this.camara,
    required this.estanteria,
    required this.posicion,
    required this.document,
  });

  final String camara;
  final int estanteria;
  final int posicion;
  final QueryDocumentSnapshot<Map<String, dynamic>> document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = 'E$estanteria\nP$posicion';

    return GestureDetector(
      onTap: () => _showDetails(context),
      child: Container(
        width: 72,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer.withOpacity(0.8),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.error),
        ),
        child: Center(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onErrorContainer,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    final data = document.data();
    final entries = data.entries
        .where((entry) => !_excludedKeys.contains(entry.key))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cámara $camara · E$estanteria · P$posicion'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          entry.key,
                          style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: Text(
                          _formatValue(entry.value),
                          style: Theme.of(ctx).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  static const Set<String> _excludedKeys = {
    'CAMARA',
    'ESTANTERIA',
    'NIVEL',
    'POSICION',
    'HUECO',
  };

  static String _formatValue(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toString();
    }
    return value?.toString() ?? '';
  }
}
