import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'cmr_detail_screen.dart';
import 'cmr_models.dart';
import 'cmr_scan_screen.dart';

class CmrHomeScreen extends StatefulWidget {
  const CmrHomeScreen({super.key});

  @override
  State<CmrHomeScreen> createState() => _CmrHomeScreenState();
}

class _CmrHomeScreenState extends State<CmrHomeScreen> {
  bool _onlyPedidosP = false;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _pedidosStream;
  bool _loggedPedidosError = false;

  @override
  void initState() {
    super.initState();
    _pedidosStream = _buildPedidosStream(_onlyPedidosP);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _buildPedidosStream(
    bool soloPedidosP,
  ) {
    Query<Map<String, dynamic>> query =
        FirebaseFirestore.instance.collection('Pedidos');

    query = query.where(
      'Estado',
      whereIn: ['En_Curso', 'En_Curso_Manual'],
    );

    if (soloPedidosP) {
      query = query
          .where('IdPedidoLora', isGreaterThanOrEqualTo: 'P')
          .where('IdPedidoLora', isLessThan: 'Q');
    }

    return query.orderBy('updatedAt', descending: true).snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('CMR'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const CmrScanScreen(
                pedido: null,
                expectedPalets: <String>[],
                lineaByPalet: <String, int?>{},
                initialScanned: <String>{},
                initialInvalid: <String>{},
              ),
            ),
          );
        },
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Iniciar CMR'),
      ),
      body: Column(
        children: [
          SwitchListTile.adaptive(
            value: _onlyPedidosP,
            title: const Text('Solo pedidos tipo P*'),
            subtitle: const Text('Filtra IdPedidoLora que empieza por P'),
            onChanged: (value) {
              setState(() {
                _onlyPedidosP = value;
                _loggedPedidosError = false;
                _pedidosStream = _buildPedidosStream(_onlyPedidosP);
              });
            },
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _pedidosStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  if (!_loggedPedidosError) {
                    final error = snapshot.error;
                    if (error is FirebaseException) {
                      debugPrint(
                        'Firestore error [${error.code}]: ${error.message}',
                      );
                    } else {
                      debugPrint('Error al cargar pedidos: $error');
                    }
                    _loggedPedidosError = true;
                  }
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'No se pudieron cargar los pedidos.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _loggedPedidosError = false;
                                _pedidosStream =
                                    _buildPedidosStream(_onlyPedidosP);
                              });
                            },
                            child: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                _loggedPedidosError = false;
                final docs = snapshot.data?.docs ?? [];
                final pedidos = docs
                    .map(CmrPedido.fromSnapshot)
                    .where((pedido) {
                      if (_onlyPedidosP &&
                          !pedido.idPedidoLora.toUpperCase().startsWith('P')) {
                        return false;
                      }
                      final estado = _normalizeEstado(pedido.estado);
                      return estado == 'En_Curso';
                    })
                    .toList();

                if (pedidos.isEmpty) {
                  return const Center(
                    child: Text('No hay pedidos.'),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: pedidos.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final pedido = pedidos[index];
                    final estado = _normalizeEstado(pedido.estado);
                    final isEnCurso = estado == 'En_Curso';
                    final isExpedido = estado == 'Expedido';
                    final badge = _buildEstadoBadge(estado, theme);
                    final Color? cardColor = isEnCurso
                        ? theme.colorScheme.primaryContainer.withOpacity(0.35)
                        : isExpedido
                            ? theme.colorScheme.surfaceVariant.withOpacity(0.4)
                            : null;
                    final TextStyle? mutedStyle = isExpedido
                        ? theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          )
                        : null;
                    return Card(
                      color: cardColor,
                      child: ListTile(
                        title: Text(
                          pedido.idPedidoLora,
                          style: isExpedido
                              ? theme.textTheme.titleMedium?.copyWith(
                                  color:
                                      theme.colorScheme.onSurface.withOpacity(
                                    0.7,
                                  ),
                                )
                              : null,
                        ),
                        subtitle: Text(
                          pedido.cliente.isNotEmpty
                              ? pedido.cliente
                              : 'Cliente sin nombre',
                          style: mutedStyle,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (badge != null) ...[
                              badge,
                              const SizedBox(width: 8),
                            ],
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  CmrDetailScreen(pedidoRef: pedido.ref),
                            ),
                          );
                        },
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

  String _normalizeEstado(String? estado) {
    final normalized = estado?.trim() ?? '';
    if (normalized.isEmpty) {
      return 'Pendiente';
    }
    switch (normalized) {
      case 'En_Curso_Manual':
        return 'En_Curso';
      case 'Pendiente':
      case 'En_Curso':
      case 'Expedido':
        return normalized;
      default:
        return normalized;
    }
  }

  Widget? _buildEstadoBadge(String estado, ThemeData theme) {
    switch (estado) {
      case 'En_Curso':
        return Chip(
          label: const Text('EN CURSO'),
          labelStyle: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSecondaryContainer,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
          backgroundColor: theme.colorScheme.secondaryContainer,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
      case 'Expedido':
        return Chip(
          label: const Text('EXPEDIDO'),
          labelStyle: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
          backgroundColor: theme.colorScheme.surfaceVariant,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
      default:
        return null;
    }
  }
}
