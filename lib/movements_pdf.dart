import 'dart:typed_data';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';

class MovementsPdf {
  static Future<Uint8List> build({
    required String title,
    required String filterLabel,
    required List<Map<String, dynamic>> movements,
    DateTime? from,
    DateTime? to,
  }) async {
    final pdf = pw.Document();

    String _fmtDate(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    String _fmtDateTime(DateTime d) =>
        '${_fmtDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    double _money(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? 0.0;
    }

    int _toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    title,
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'Filtro: $filterLabel',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
            if (from != null || to != null)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Text(
                  'Rango: '
                  '${from != null ? _fmtDate(from) : '—'} - '
                  '${to != null ? _fmtDate(to) : '—'}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ),
            pw.SizedBox(height: 8),
            ...movements.map((m) {
              final ts = m['createdAt'];
              DateTime? dt;
              if (ts is DateTime) {
                dt = ts;
              } else if (ts is int) {
                dt = DateTime.fromMillisecondsSinceEpoch(ts);
              }

              final type =
                  (m['type'] ?? '').toString().toLowerCase();
              final total = _money(m['totalAmount']);
              final counterparty =
                  (m['counterpartyName'] ?? '—').toString();
              final itemsRaw = (m['items'] as List<dynamic>? ?? []);
              final items = itemsRaw
                  .map<Map<String, dynamic>>(
                      (e) => Map<String, dynamic>.from(e as Map))
                  .toList();

              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        vertical: 4, horizontal: 6),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey300,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          '${type == 'ingreso' ? 'Ingreso' : 'Egreso'} '
                          '• ${m['createdByName'] ?? '—'}',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                        pw.Text(
                          dt == null
                              ? '—'
                              : _fmtDateTime(dt),
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Contraparte: $counterparty   |   '
                    'Líneas: ${m['totalItems'] ?? items.length}   |   '
                    'Total: ${total.toStringAsFixed(2)}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                  if ((m['note'] ?? '').toString().isNotEmpty)
                    pw.Text(
                      'Nota: ${m['note']}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  pw.SizedBox(height: 4),
                  pw.Table(
                    border: pw.TableBorder.all(width: 0.2),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(3),
                      1: const pw.FlexColumnWidth(1),
                      2: const pw.FlexColumnWidth(1),
                      3: const pw.FlexColumnWidth(1),
                      4: const pw.FlexColumnWidth(2),
                    },
                    children: [
                      pw.TableRow(
                        decoration:
                            const pw.BoxDecoration(color: PdfColors.grey200),
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(2),
                            child: pw.Text('Producto',
                                style: pw.TextStyle(
                                    fontSize: 9,
                                    fontWeight: pw.FontWeight.bold)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(2),
                            child: pw.Text('Cant.',
                                style: pw.TextStyle(
                                    fontSize: 9,
                                    fontWeight: pw.FontWeight.bold)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(2),
                            child: pw.Text('P. unidad',
                                style: pw.TextStyle(
                                    fontSize: 9,
                                    fontWeight: pw.FontWeight.bold)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(2),
                            child: pw.Text('Subtotal',
                                style: pw.TextStyle(
                                    fontSize: 9,
                                    fontWeight: pw.FontWeight.bold)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(2),
                            child: pw.Text('Stock',
                                style: pw.TextStyle(
                                    fontSize: 9,
                                    fontWeight: pw.FontWeight.bold)),
                          ),
                        ],
                      ),
                      ...items.map((it) {
                        final qty = _toInt(it['qty']);
                        final unitPrice = _money(
                          it['unitPrice'] ??
                              it['purchasePrice'] ??
                              it['salePrice'],
                        );
                        final subtotal = _money(it['subtotal']);
                        final sb = it['stockBefore'];
                        final sa = it['stockAfter'];
                        String stockText = '';
                        if (sb is num && sa is num) {
                          stockText =
                              '${_toInt(sb)} → ${_toInt(sa)}';
                        }

                        return pw.TableRow(
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(2),
                              child: pw.Text(
                                '${it['productName']} (SKU: ${it['sku']})',
                                style: const pw.TextStyle(fontSize: 8),
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(2),
                              child: pw.Text(
                                qty.toString(),
                                style: const pw.TextStyle(fontSize: 8),
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(2),
                              child: pw.Text(
                                unitPrice.toStringAsFixed(2),
                                style: const pw.TextStyle(fontSize: 8),
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(2),
                              child: pw.Text(
                                subtotal.toStringAsFixed(2),
                                style: const pw.TextStyle(fontSize: 8),
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(2),
                              child: pw.Text(
                                stockText,
                                style: const pw.TextStyle(fontSize: 8),
                              ),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                ],
              );
            }).toList(),
          ];
        },
      ),
    );

    return pdf.save();
  }
}
