import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ops/qr_scan_screen.dart';
import '../../qr/qr_parser.dart' as qr;
import '../../../models/pallet_group.dart';
import '../../../services/pallet_group_service.dart';

final palletGroupServiceProvider = Provider<PalletGroupService>((ref) {
  return PalletGroupService();
});

class AgruparBoxesScreen extends ConsumerStatefulWidget {
  const AgruparBoxesScreen({super.key});

  @override
  ConsumerState<AgruparBoxesScreen> createState() => _AgruparBoxesScreenState();
}

class _AgruparBoxesScreenState extends ConsumerState<AgruparBoxesScreen> {
  static const int _maxBoxes = 6;

  final TextEditingController _manualQrController = TextEditingController();
  final List<_ScannedBox> _boxes = <_ScannedBox>[];
  bool _busy = false;

  int get _boxesCount => _boxes.length;

  double get _netoTotal => _boxes.fold<double>(
        0,
        (total, box) => total + box.neto,
      );

  double get _brutoTotal => _boxes.fold<double>(
        0,
        (total, box) => total + box.bruto,
      );

  int get _cajasTotal => _boxes.fold<int>(
        0,
        (total, box) => total + box.cajas,
      );

  bool get _canScan => !_busy && _boxesCount < _maxBoxes;
  bool get _isMobile => !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void dispose() {
    _manualQrController.dispose();
    super.dispose();
  }

  Future<void> _scanQr() async {
    if (!_canScan) {
      return;
    }

    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const QrScanScreen(
          returnScanResult: true,
          scanResultMode: QrScanResultMode.raw,
        ),
      ),
    );

    if (result == null || result.trim().isEmpty) {
      return;
    }

    await _addRawQr(result);
  }

  Future<void> _addManualQr() async {
    final raw = _manualQrController.text;
    await _addRawQr(raw);
    if (mounted && raw.trim().isNotEmpty) {
      _manualQrController.clear();
    }
  }

  Future<void> _addRawQr(String raw) async {
    if (!_canScan) {
      _showError('El grupo no puede tener más de $_maxBoxes QR.');
      return;
    }

    final parsed = _parse(raw);
    if (parsed == null) {
      return;
    }

    final palletId = _palletIdFromParsed(parsed);
    if (_boxes.any((box) => box.palletId == palletId)) {
      _showError('El QR $palletId ya está en este grupo.');
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      final exists = await ref
          .read(palletGroupServiceProvider)
          .memberExists(palletId);
      if (!mounted) {
        return;
      }
      if (exists) {
        _showError('El QR $palletId ya pertenece a otro grupo.');
        return;
      }

      setState(() {
        _boxes.add(_ScannedBox.fromParsed(palletId, parsed));
      });
    } on FirebaseException {
      _showError('No se pudo comprobar si el QR ya pertenece a un grupo.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  qr.ParsedQr? _parse(String raw) {
    try {
      return qr.parseQr(raw);
    } on FormatException catch (error) {
      _showError(error.message);
    } on Exception {
      _showError('QR de palet/box no válido.');
    }
    return null;
  }

  String _palletIdFromParsed(qr.ParsedQr parsed) {
    return '${parsed.linea}${parsed.p}';
  }

  void _removeLast() {
    if (_busy || _boxes.isEmpty) {
      return;
    }
    setState(() {
      _boxes.removeLast();
    });
  }

  Future<void> _closeGroup() async {
    if (_boxes.isEmpty) {
      _showError('Escanea al menos un QR antes de cerrar el grupo.');
      return;
    }

    final referencePalletId = _boxes.first.palletId;
    final group = PalletGroup(
      groupId: referencePalletId,
      referencePalletId: referencePalletId,
      memberPalletIds: _boxes
          .map((box) => box.palletId)
          .toList(growable: false),
      boxesCount: _boxesCount,
      netoTotal: _netoTotal,
      brutoTotal: _brutoTotal,
      cajasTotal: _cajasTotal,
      status: 'closed',
    );

    setState(() {
      _busy = true;
    });

    try {
      await ref.read(palletGroupServiceProvider).closeGroup(group);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Grupo $referencePalletId cerrado.')),
      );
      Navigator.of(context).pop();
    } on PalletGroupConflictException catch (error) {
      _showError('El QR ${error.palletId} ya pertenece a otro grupo.');
    } on FirebaseException {
      _showError('No se pudo cerrar el grupo.');
    } on Exception catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _cancel() async {
    if (_boxes.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    final discard = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cancelar agrupación'),
          content: const Text('Se descartarán los QR escaneados sin guardar.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Seguir editando'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );

    if (discard == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agrupar Boxes'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancelar',
          onPressed: _busy ? null : _cancel,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Escanea de 1 a $_maxBoxes QR de box',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'El primer QR será la referencia del grupo. Los QR no tienen que ser consecutivos.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _isMobile && _canScan ? _scanQr : null,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Escanear QR'),
                    ),
                    if (!_isMobile) ...[
                      const SizedBox(height: 8),
                      Text(
                        'El escaneo con cámara solo está disponible en móvil. Puedes pegar un QR para pruebas o escritorio.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: _manualQrController,
                      minLines: 1,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'QR manual',
                        hintText: 'Pega aquí el contenido del QR',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: 'Añadir QR manual',
                          onPressed: _canScan ? _addManualQr : null,
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ),
                      onSubmitted: (_) {
                        if (_canScan) {
                          _addManualQr();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _TotalsCard(
              boxesCount: _boxesCount,
              maxBoxes: _maxBoxes,
              netoTotal: _netoTotal,
              cajasTotal: _cajasTotal,
              referencePalletId: _boxes.isEmpty ? null : _boxes.first.palletId,
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'QR escaneados',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        TextButton.icon(
                          onPressed:
                              _boxes.isNotEmpty && !_busy ? _removeLast : null,
                          icon: const Icon(Icons.undo),
                          label: const Text('Eliminar último'),
                        ),
                      ],
                    ),
                  ),
                  if (_boxes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                      child: Text(
                        'Todavía no hay QR escaneados.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    ..._boxes.indexed.map((entry) {
                      final index = entry.$1;
                      final box = entry.$2;
                      return ListTile(
                        leading: CircleAvatar(child: Text('${index + 1}')),
                        title: Text(box.palletId),
                        subtitle: Text(
                          'Neto ${box.neto.toStringAsFixed(0)} · Cajas ${box.cajas}',
                        ),
                        trailing: index == 0
                            ? Chip(
                                label: const Text('Referencia'),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: theme.colorScheme.primaryContainer,
                              )
                            : null,
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _cancel,
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _boxes.isNotEmpty && !_busy ? _closeGroup : null,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Cerrar grupo'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({
    required this.boxesCount,
    required this.maxBoxes,
    required this.netoTotal,
    required this.cajasTotal,
    required this.referencePalletId,
  });

  final int boxesCount;
  final int maxBoxes;
  final double netoTotal;
  final int cajasTotal;
  final String? referencePalletId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Resumen', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricChip(label: 'Boxes', value: '$boxesCount/$maxBoxes'),
                _MetricChip(
                  label: 'Neto total',
                  value: netoTotal.toStringAsFixed(0),
                ),
                _MetricChip(label: 'Cajas total', value: '$cajasTotal'),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Referencia: ${referencePalletId ?? 'primer QR escaneado'}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannedBox {
  const _ScannedBox({
    required this.palletId,
    required this.neto,
    required this.bruto,
    required this.cajas,
  });

  final String palletId;
  final double neto;
  final double bruto;
  final int cajas;

  factory _ScannedBox.fromParsed(String palletId, qr.ParsedQr parsed) {
    double asDouble(String key) {
      final raw = parsed.rawFields[key] ?? parsed.rawFields[key.toUpperCase()];
      if (raw == null || raw.trim().isEmpty) {
        return 0;
      }
      return double.tryParse(raw.replaceAll(',', '.')) ?? 0;
    }

    return _ScannedBox(
      palletId: palletId,
      neto: parsed.neto.toDouble(),
      bruto: asDouble('BRUTO'),
      cajas: parsed.cajas,
    );
  }
}
