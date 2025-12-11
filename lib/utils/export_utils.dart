import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/commercial_group_row.dart';
import '../models/palet.dart';

/// Exporta la lista de palets a CSV y devuelve el fichero temporal generado.
Future<File> exportCsv(List<Palet> palets) async {
  final headers = <String>[
    'P',
    'CAMARA',
    'ESTANTERIA',
    'HUECO',
    'CULTIVO',
    'VARIEDAD',
    'CALIBRE',
    'MARCA',
    'NETO',
    'NIVEL',
    'LINEA',
    'POSICION',
  ];

  final rows = palets.map((palet) {
    return <String>[
      palet.codigo,
      palet.camara,
      palet.estanteria,
      palet.hueco,
      palet.cultivo,
      palet.variedad,
      palet.calibre,
      palet.marca,
      palet.neto.toString(),
      palet.nivel.toString(),
      palet.linea.toString(),
      palet.posicion.toString(),
    ];
  }).toList();

  final csvBuffer = StringBuffer();
  csvBuffer.writeln(headers.join(';'));
  for (final row in rows) {
    csvBuffer.writeln(row.map(_escapeCsv).join(';'));
  }

  final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  final file = File('${Directory.systemTemp.path}/palets_$timestamp.csv');
  await file.writeAsString(csvBuffer.toString(), encoding: utf8);
  return file;
}

String _escapeCsv(String value) {
  final needsQuoting = value.contains(';') || value.contains('\n') || value.contains('"');
  if (!needsQuoting) {
    return value;
  }
  final escaped = value.replaceAll('"', '""');
  return '"$escaped"';
}

/// Genera un PDF con tabla de palets y totales.
Future<File> exportPdf(
  List<Palet> palets, {
  String? title,
  Map<String, int>? totalesPorGrupo,
}) async {
  final doc = pw.Document();
  final now = DateTime.now();
  final formatter = DateFormat('dd/MM/yyyy HH:mm');
  final tableHeaders = <String>[
    'P',
    'Cámara',
    'Estantería',
    'Hueco',
    'Cultivo',
    'Variedad',
    'Calibre',
    'Marca',
    'Neto',
    'Nivel',
    'Línea',
    'Posición',
  ];

  final tableRows = palets.map((palet) {
    return <String>[
      palet.codigo,
      palet.camara,
      palet.estanteria,
      palet.hueco,
      palet.cultivo,
      palet.variedad,
      palet.calibre,
      palet.marca,
      palet.neto.toString(),
      palet.nivel.toString(),
      palet.linea.toString(),
      palet.posicion.toString(),
    ];
  }).toList();

  final totalPalets = palets.length;
  final totalNeto = palets.fold<int>(0, (acc, palet) => acc + palet.neto);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      build: (context) {
        final widgets = <pw.Widget>[];
        if (title != null && title.isNotEmpty) {
          widgets.add(
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
          );
          widgets.add(pw.SizedBox(height: 8));
        }
        widgets.add(
          pw.Text(
            'Generado: ${formatter.format(now)}',
            style: const pw.TextStyle(fontSize: 10),
          ),
        );
        widgets.add(pw.SizedBox(height: 16));
        widgets.add(
          pw.Table.fromTextArray(
            headers: tableHeaders,
            data: tableRows,
            headerStyle:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerLeft,
            columnWidths: {
              0: const pw.FixedColumnWidth(60),
              1: const pw.FixedColumnWidth(40),
              2: const pw.FixedColumnWidth(60),
              3: const pw.FixedColumnWidth(60),
              8: const pw.FixedColumnWidth(50),
            },
          ),
        );
        widgets.add(pw.SizedBox(height: 12));
        widgets.add(
          pw.Text(
            'Totales — Palets: $totalPalets · Neto: $totalNeto kg',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
        );
        if (totalesPorGrupo != null && totalesPorGrupo.isNotEmpty) {
          widgets.add(pw.SizedBox(height: 12));
          widgets.add(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: totalesPorGrupo.entries.map((entry) {
                return pw.Text(
                  '${entry.key}: ${entry.value} kg',
                  style: const pw.TextStyle(fontSize: 10),
                );
              }).toList(),
            ),
          );
        }
        return widgets;
      },
    ),
  );

  final bytes = await doc.save();
  final timestamp = DateFormat('yyyyMMdd_HHmmss').format(now);
  final file = File('${Directory.systemTemp.path}/palets_$timestamp.pdf');
  await file.writeAsBytes(bytes);
  return file;
}

Future<File> exportCommercialCsv(List<CommercialGroupRow> rows) async {
  final headers = <String>[
    'VARIEDAD',
    'CALIBRE',
    'CATEGORIA',
    'PEDIDO',
    'MARCA',
    'CULTIVO',
    'PALETS',
    'NETO',
  ];

  final csvBuffer = StringBuffer();
  csvBuffer.writeln(headers.join(';'));
  for (final row in rows) {
    final values = <String>[
      row.variedad ?? '',
      row.calibre ?? '',
      row.categoria ?? '',
      row.pedido ?? '',
      row.marca ?? '',
      row.cultivo ?? '',
      row.countPalets.toString(),
      row.totalNeto.toString(),
    ];
    csvBuffer.writeln(values.map(_escapeCsv).join(';'));
  }

  final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  final file = File('${Directory.systemTemp.path}/informe_comercial_$timestamp.csv');
  await file.writeAsString(csvBuffer.toString(), encoding: utf8);
  return file;
}

Future<File> exportCommercialPdf(
  List<CommercialGroupRow> rows, {
  String? title,
}) async {
  final doc = pw.Document();
  final now = DateTime.now();
  final formatter = DateFormat('dd/MM/yyyy HH:mm');

  final tableHeaders = <String>[
    'Variedad',
    'Calibre',
    'Categoría',
    'Pedido',
    'Marca',
    'Cultivo',
    'Palets',
    'Neto',
  ];

  final tableRows = rows.map((row) {
    return <String>[
      row.variedad ?? '',
      row.calibre ?? '',
      row.categoria ?? '',
      row.pedido ?? '',
      row.marca ?? '',
      row.cultivo ?? '',
      row.countPalets.toString(),
      '${row.totalNeto} kg',
    ];
  }).toList();

  final totalPalets = rows.fold<int>(0, (acc, row) => acc + row.countPalets);
  final totalNeto = rows.fold<int>(0, (acc, row) => acc + row.totalNeto);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      build: (context) {
        final widgets = <pw.Widget>[];
        if (title != null && title.isNotEmpty) {
          widgets.add(
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
          );
          widgets.add(pw.SizedBox(height: 8));
        }
        widgets.add(
          pw.Text(
            'Generado: ${formatter.format(now)}',
            style: const pw.TextStyle(fontSize: 10),
          ),
        );
        widgets.add(pw.SizedBox(height: 16));
        widgets.add(
          pw.Table.fromTextArray(
            headers: tableHeaders,
            data: tableRows,
            headerStyle:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerLeft,
            columnWidths: {
              0: const pw.FixedColumnWidth(80),
              1: const pw.FixedColumnWidth(50),
              2: const pw.FixedColumnWidth(70),
              7: const pw.FixedColumnWidth(60),
            },
          ),
        );
        widgets.add(pw.SizedBox(height: 12));
        widgets.add(
          pw.Text(
            'Totales — Palets: $totalPalets · Neto: $totalNeto kg',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
        );
        return widgets;
      },
    ),
  );

  final bytes = await doc.save();
  final timestamp = DateFormat('yyyyMMdd_HHmmss').format(now);
  final file = File('${Directory.systemTemp.path}/informe_comercial_$timestamp.pdf');
  await file.writeAsBytes(bytes);
  return file;
}
