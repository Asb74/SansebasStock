import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sansebas_stock/features/settings/storage/models/camera_storage.dart';
import 'package:sansebas_stock/features/settings/storage/storage_providers.dart';

import 'widgets/camera_plan.dart';

class CameraMapScreen extends ConsumerStatefulWidget {
  const CameraMapScreen({super.key, required this.camara});

  final String camara;

  @override
  ConsumerState<CameraMapScreen> createState() => _CameraMapScreenState();
}

class _CameraMapScreenState extends ConsumerState<CameraMapScreen> {
  int _nivelActual = 1;

  @override
  Widget build(BuildContext context) {
    final cameraAsync = ref.watch(cameraByIdProvider(widget.camara));

    return cameraAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: Text('Cámara ${widget.camara}')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Error al cargar la cámara.\\n$error', textAlign: TextAlign.center),
          ),
        ),
      ),
      data: (camera) {
        if (camera == null) {
          return Scaffold(
            appBar: AppBar(title: Text('Cámara ${widget.camara}')),
            body: const Center(child: Text('La cámara no existe.')),
          );
        }

        final adjustedLevel = _nivelActual.clamp(1, camera.niveles == 0 ? 1 : camera.niveles);
        if (adjustedLevel != _nivelActual) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _nivelActual = adjustedLevel);
            }
          });
        }

        final theme = Theme.of(context);

        return Scaffold(
          appBar: AppBar(title: Text('Cámara ${camera.camara}')),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Niveles', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(camera.niveles, (index) {
                    final nivel = index + 1;
                    final selected = _nivelActual == nivel;
                    return ChoiceChip(
                      label: Text('Nivel $nivel'),
                      selected: selected,
                      onSelected: (_) {
                        if (!selected) {
                          setState(() => _nivelActual = nivel);
                        }
                      },
                    );
                  }),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: _PaletsView(
                    camara: camera,
                    nivelActual: _nivelActual,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PaletsView extends StatelessWidget {
  const _PaletsView({required this.camara, required this.nivelActual});

  final CameraStorage camara;
  final int nivelActual;

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('Stock')
        .where('CAMARA', isEqualTo: camara.camara)
        .where('NIVEL', isEqualTo: nivelActual)
        .where('HUECO', isEqualTo: 'Ocupado')
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No se pudieron cargar los palets.\\n${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
          snapshot.data?.docs ?? const [],
        )
          ..sort((a, b) {
            final estA = (a.data()['ESTANTERIA'] as num?)?.toInt() ?? 0;
            final estB = (b.data()['ESTANTERIA'] as num?)?.toInt() ?? 0;
            if (estA != estB) return estA.compareTo(estB);
            final posA = (a.data()['POSICION'] as num?)?.toInt() ?? 0;
            final posB = (b.data()['POSICION'] as num?)?.toInt() ?? 0;
            return posA.compareTo(posB);
          });
        final ocupados = docs.map((doc) {
          final data = Map<String, dynamic>.from(doc.data());
          final estanteria = (data['ESTANTERIA'] as num?)?.toInt() ?? 0;
          final posicion = (data['POSICION'] as num?)?.toInt() ?? 0;
          final pallet = (data['P'] as String?)?.trim() ?? '';
          return HuecoOcupado(
            estanteria: estanteria,
            posicion: posicion,
            pallet: pallet,
            data: data,
            documentId: doc.id,
          );
        }).toList();

        return CameraPlan(
          estanterias: camara.estanterias,
          huecosPorEst: camara.huecosPorEstanteria,
          ocupados: ocupados,
        );
      },
    );
  }
}
