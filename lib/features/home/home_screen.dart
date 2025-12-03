import 'dart:io' show Platform; // DESKTOP-GUARD

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../map/map_cameras_screen.dart';
import '../ops/qr_scan_screen.dart';
import '../settings/settings_home_screen.dart';
import '../../ui/stock/stock_filter_page.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS; // DESKTOP-GUARD
    final isMobile =
        Platform.isAndroid || Platform.isIOS; // DESKTOP-GUARD

    return Scaffold(
      appBar: AppBar(
        title: const Text('SansebasStock'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth > 900
                ? 3
                : constraints.maxWidth > 600
                    ? 3
                    : 2;

            return GridView.count(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio:
                  constraints.maxWidth > 600 ? 1.1 : 1.05,
              children: <Widget>[
                // --- LECTURA QR ---
                _HomeActionCard(
                  title: 'Iniciar lectura QR',
                  subtitle: 'Escanea palets y revisa su contenido',
                  icon: Icons.qr_code_scanner,
                  color: theme.colorScheme.secondary,
                  onTap: isDesktop
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const QrScanScreen(),
                            ),
                          );
                        },
                  enabled: isMobile,
                  tooltip:
                      isDesktop ? 'Solo disponible en móvil' : null,
                ),

                // --- MAPA ---
                _HomeActionCard(
                  title: 'Mapa',
                  subtitle: 'Consulta ubicaciones en planta',
                  icon: Icons.map_outlined,
                  color: theme.colorScheme.primary,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MapCamerasScreen(),
                      ),
                    );
                  },
                ),

                // --- INFORME DE STOCK ---
                _HomeActionCard(
                  title: 'Informe de stock',
                  subtitle: 'Filtra palets y exporta resultados',
                  icon: Icons.inventory_outlined,
                  color: theme.colorScheme.tertiary,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const StockFilterPage(),
                      ),
                    );
                  },
                ),

                // --- AJUSTES ---
                _HomeActionCard(
                  title: 'Ajustes',
                  subtitle: 'Preferencias de la aplicación',
                  icon: Icons.settings_outlined,
                  color: theme.colorScheme.primary,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SettingsHomeScreen(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HomeActionCard extends StatelessWidget {
  const _HomeActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
    this.enabled = true,
    this.tooltip,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool enabled;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final card = Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                decoration: BoxDecoration(
                  color: (enabled ? color : theme.disabledColor)
                      .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(12),
                child: Icon(
                  icon,
                  size: 28,
                  color: enabled ? color : theme.disabledColor,
                ),
              ),
              const Spacer(),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color:
                      enabled ? theme.colorScheme.primary : theme.disabledColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: enabled
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.disabledColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!enabled && tooltip != null) {
      return Tooltip(message: tooltip, child: card);
    }
    return card;
  }
}
