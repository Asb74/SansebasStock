import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'cmr_detail_screen.dart';
import 'cmr_models.dart';

class CmrHomeScreen extends StatefulWidget {
  const CmrHomeScreen({super.key});

  @override
  State<CmrHomeScreen> createState() => _CmrHomeScreenState();
}

class _CmrHomeScreenState extends State<CmrHomeScreen> {
  bool _onlyPedidosP = false;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _pedidosStream;

  @override
  void initState() {
    super.initState();
    _pedidosStream = _buildPedidosStream(_onlyPedidosP);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _buildPedidosStream(
    bool soloPedidosP,
  ) {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('Pedidos')
        .where('Estado', isEqualTo: 'Pendiente');

    if (soloPedidosP) {
      query = query
          .where('IdPedidoLora', isGreaterThanOrEqualTo: 'P')
          .where('IdPedidoLora', isLessThan: 'Q');
    }

    return query.snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CMR'),
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
                  final errorText = snapshot.error is FirebaseException
                      ? 'Firestore: ${(snapshot.error as FirebaseException).code}'
                          ' - ${(snapshot.error as FirebaseException).message}'
                      : 'Error: ${snapshot.error}';
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            errorText,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
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

                final docs = snapshot.data?.docs ?? [];
                final pedidos = docs
                    .map(CmrPedido.fromSnapshot)
                    .where((pedido) {
                      if (!_onlyPedidosP) return true;
                      return pedido.idPedidoLora.toUpperCase().startsWith('P');
                    })
                    .toList();

                if (pedidos.isEmpty) {
                  return const Center(
                    child: Text('No hay pedidos pendientes.'),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: pedidos.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final pedido = pedidos[index];
                    return Card(
                      child: ListTile(
                        title: Text(pedido.idPedidoLora),
                        subtitle: Text(
                          pedido.cliente.isNotEmpty
                              ? pedido.cliente
                              : 'Cliente sin nombre',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CmrDetailScreen(pedidoRef: pedido.ref),
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
}
