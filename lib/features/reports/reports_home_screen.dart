import 'package:flutter/material.dart';

import '../../ui/stock/stock_filter_page.dart';
import '../cmr/cmr_home_screen.dart';
import 'commercial_dashboard_screen.dart';

class ReportsHomeScreen extends StatelessWidget {
  const ReportsHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Informes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: const Text('Informe general'),
              subtitle: const Text('Filtros avanzados de stock'),
              leading: const Icon(Icons.inventory_outlined),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const StockFilterPage(),
                  ),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Informe comercial (dashboard)'),
              subtitle:
                  const Text('KPIs, filtros dinámicos y tabla configurable'),
              leading: const Icon(Icons.dashboard_customize_outlined),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CommercialDashboardScreen(),
                  ),
                );
              },
            ),
          ),
          const _ReportPlaceholder(
            title: 'Producción',
            subtitle: 'Próximamente',
            icon: Icons.factory_outlined,
          ),
          const _ReportPlaceholder(
            title: 'Comercial',
            subtitle: 'Próximamente',
            icon: Icons.storefront_outlined,
          ),
          const _ReportPlaceholder(
            title: 'Materiales',
            subtitle: 'Próximamente',
            icon: Icons.inventory_2_outlined,
          ),
          Card(
            child: ListTile(
              title: const Text('CMR'),
              subtitle: const Text('Expedir pedidos y generar CMR'),
              leading: const Icon(Icons.local_shipping_outlined),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CmrHomeScreen(),
                  ),
                );
              },
            ),
          ),
          const _ReportPlaceholder(
            title: 'Estadísticos',
            subtitle: 'Próximamente',
            icon: Icons.bar_chart_outlined,
          ),
        ],
      ),
    );
  }
}

class _ReportPlaceholder extends StatelessWidget {
  const _ReportPlaceholder({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        enabled: false,
        title: Text(title),
        subtitle: Text(subtitle),
        leading: Icon(icon),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
