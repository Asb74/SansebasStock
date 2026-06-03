import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cmr/cmr_utils.dart';
import '../../ops/qr_scan_screen.dart';
import '../../../services/pallet_group_service.dart';

final ungroupPalletGroupServiceProvider = Provider<PalletGroupService>((ref) {
  return PalletGroupService();
});

class DesagruparBoxesScreen extends ConsumerStatefulWidget {
  const DesagruparBoxesScreen({super.key});

  @override
  ConsumerState<DesagruparBoxesScreen> createState() =>
      _DesagruparBoxesScreenState();
}

class _DesagruparBoxesScreenState
    extends ConsumerState<DesagruparBoxesScreen> {
  bool _busy = false;

  bool get _isMobile => !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _scanQr() async {
    if (_busy) {
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

    await _handleScannedQr(result);
  }

  Future<void> _handleScannedQr(String raw) async {
    final scannedStockId = parseStockPaletIdFromQr(raw);
    debugPrint('Desagrupar Boxes DEBUG scannedStockId=$scannedStockId');

    if (scannedStockId.isEmpty) {
      _showError('QR no reconocido');
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      final resolution = await ref
          .read(ungroupPalletGroupServiceProvider)
          .resolveGroupForUngroup(scannedStockId);
      if (!mounted) {
        return;
      }

      debugPrint('Desagrupar Boxes DEBUG groupId=${resolution.groupId}');
      debugPrint(
        'Desagrupar Boxes DEBUG '
        'referencePalletId=${resolution.referencePalletId}',
      );
      debugPrint(
        'Desagrupar Boxes DEBUG '
        'memberPalletIds=${resolution.memberPalletIds}',
      );
      debugPrint('Desagrupar Boxes DEBUG stockExists=${resolution.stockExists}');

      if (!resolution.isGrouped) {
        _showError('Este QR no pertenece a ningún grupo');
        return;
      }

      if (!resolution.canUngroup) {
        _showError('El grupo no está actualmente en stock o ya fue expedido');
        return;
      }

      final confirmed = await _showConfirmDialog(resolution);
      if (confirmed != true || !mounted) {
        return;
      }

      debugPrint(
        'Desagrupar Boxes DEBUG action=ungroup '
        'groupId=${resolution.groupId} '
        'referencePalletId=${resolution.referencePalletId}',
      );
      await ref.read(ungroupPalletGroupServiceProvider).ungroup(resolution);
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Grupo ${resolution.groupId} desagrupado.')),
      );
      Navigator.of(context).pop();
    } on FirebaseException catch (error) {
      debugPrint('Desagrupar Boxes FirebaseException: $error');
      _showError('No se pudo desagrupar el grupo.');
    } on Exception catch (error) {
      debugPrint('Desagrupar Boxes Exception: $error');
      _showError('No se pudo desagrupar el grupo.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<bool?> _showConfirmDialog(PalletGroupUngroupResolution resolution) {
    final theme = Theme.of(context);
    final group = resolution.group;

    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          icon: Icon(
            Icons.warning_amber_rounded,
            color: theme.colorScheme.error,
          ),
          title: const Text('Desagrupar boxes'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DialogRow(
                  label: 'Referencia',
                  value: resolution.referencePalletId,
                ),
                _DialogRow(label: 'Boxes', value: '${group?.boxesCount ?? 0}'),
                _DialogRow(
                  label: 'Neto total',
                  value: (group?.netoTotal ?? 0).toStringAsFixed(0),
                ),
                _DialogRow(
                  label: 'Bruto total',
                  value: (group?.brutoTotal ?? 0).toStringAsFixed(0),
                ),
                _DialogRow(
                  label: 'Miembros',
                  value: resolution.memberPalletIds.join(', '),
                ),
                const SizedBox(height: 16),
                Text(
                  'Esta operación eliminará el grupo y borrará su stock. '
                  'Deberás volver a ubicar los boxes si procede.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('Desagrupar'),
            ),
          ],
        );
      },
    );
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
        title: const Text('Desagrupar Boxes'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Herramienta peligrosa',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Escanea cualquier QR del grupo. Si confirmas, se '
                      'eliminará el grupo, sus miembros y el stock del palet '
                      'de referencia. No se recrearán stocks individuales.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                        foregroundColor: theme.colorScheme.onError,
                      ),
                      onPressed: _isMobile && !_busy ? _scanQr : null,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.qr_code_scanner),
                      label: const Text('Escanear QR'),
                    ),
                    if (!_isMobile) ...[
                      const SizedBox(height: 8),
                      Text(
                        'El escaneo con cámara solo está disponible en móvil.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogRow extends StatelessWidget {
  const _DialogRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value.isEmpty ? '—' : value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
