import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class IvaRetenidoPdf {
  static final PdfColor _green = PdfColor.fromHex('#2E7D32');
  static final PdfColor _greenLight = PdfColor.fromHex('#E8F5E9');
  static final PdfColor _border = PdfColor.fromHex('#D6D6D6');
  static final PdfColor _totalRed = PdfColor.fromHex('#C62828');

  static Future<Uint8List> build({
    required DateTime? from,
    required DateTime? to,
    required List<Map<String, dynamic>> ivaMovs,
    String? logoAssetPath,
  }) async {
    final doc = pw.Document();

    final logoBytes = await _tryLoad(logoAssetPath ?? 'assets/logo.png');
    final logo = logoBytes != null ? pw.MemoryImage(logoBytes) : null;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        build: (context) => [
          // ===== ENCABEZADO =====
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Reporte de IVA retenido',
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      color: _green,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text('Generado: ${_fmtDateTime(DateTime.now())}'),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Tipo: Egresos con IVA retenido (13%)'),
                  if (from != null || to != null)
                    pw.Text(_dateRangeLabel(from, to)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 12),

          // ===== BLOQUE MEMBRETE =====
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: _greenLight,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logo != null)
                  pw.Container(
                    width: 42,
                    height: 42,
                    margin: const pw.EdgeInsets.only(right: 10),
                    child: pw.Image(logo, fit: pw.BoxFit.contain),
                  ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'PharmaControl',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          color: _green,
                          fontSize: 14,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Detalle de ventas (egresos) que generan IVA retenido del 13%.',
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        from == null && to == null
                            ? 'Período: todos los movimientos con IVA retenido'
                            : 'Período: ${_dateRangeLabel(from, to)}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 16),

          // ===== TABLAS PENDIENTE / MES ACTUAL =====
          _buildIvaTable(ivaMovs),

          pw.SizedBox(height: 22),

          // ===== PIE DE PÁGINA =====
          pw.Divider(color: _border),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text(
                  'PharmaControl',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: _green,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Calle Principal #123, Sensuntepeque, Cabañas, El Salvador',
                ),
                pw.Text(
                  'Soporte: soporte@pharmacontrol.com  •  +503 7000-0000  /  +503 7111-1111',
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  '© ${DateTime.now().year} Todos los derechos reservados.',
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  // ============ TABLAS DE IVA (pendiente / mes actual) ============

  static pw.Widget _buildIvaTable(List<Map<String, dynamic>> ivaMovs) {
    if (ivaMovs.isEmpty) {
      return pw.Center(
        child: pw.Text('No hay movimientos con IVA retenido para mostrar.'),
      );
    }

    // Separamos: pendiente (meses anteriores) vs mes actual
    final now = DateTime.now();
    final currentMonthStart = DateTime(now.year, now.month, 1);
    final nextMonthStart =
        now.month == 12 ? DateTime(now.year + 1, 1, 1) : DateTime(now.year, now.month + 1, 1);

    final pendiente = <Map<String, dynamic>>[];
    final mesActual = <Map<String, dynamic>>[];

    for (final m in ivaMovs) {
      DateTime? dt;

      final dtAny = m['createdAtDateTime'];
      if (dtAny is DateTime) {
        dt = dtAny;
      } else if (m['createdAt'] is DateTime) {
        dt = m['createdAt'] as DateTime;
      }

      dt ??= DateTime.now();

      if (dt.isBefore(currentMonthStart)) {
        pendiente.add(m);
      } else if (dt.isBefore(nextMonthStart)) {
        mesActual.add(m);
      } else {
        // por si hay registros a futuro, los tratamos como mes actual
        mesActual.add(m);
      }
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _buildIvaSection(
          title: 'IVA retenido pendiente de pago (meses anteriores)',
          ivaMovs: pendiente,
        ),
        pw.SizedBox(height: 16),
        _buildIvaSection(
          title: 'IVA retenido del mes actual (en curso)',
          ivaMovs: mesActual,
        ),
      ],
    );
  }

  static pw.Widget _buildIvaSection({
    required String title,
    required List<Map<String, dynamic>> ivaMovs,
  }) {
    final headerStyle = pw.TextStyle(
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.white,
      fontSize: 10,
    );

    final rows = <pw.TableRow>[];
    double totalIvaRetenido = 0;

    // Encabezado
    rows.add(
      pw.TableRow(
        decoration: pw.BoxDecoration(color: _green),
        children: [
          _cellHeader('Fecha', headerStyle),
          _cellHeader('Usuario', headerStyle),
          _cellHeader('Cliente', headerStyle),
          _cellHeader('Total venta', headerStyle, align: pw.TextAlign.right),
          _cellHeader(
            'IVA retenido (13%)',
            headerStyle,
            align: pw.TextAlign.right,
          ),
        ],
      ),
    );

    for (var i = 0; i < ivaMovs.length; i++) {
      final m = ivaMovs[i];
      final dt = (m['createdAtDateTime'] as DateTime?) ?? DateTime.now();
      final user = (m['createdByName'] ?? '—').toString();
      final client = (m['counterpartyName'] ?? '—').toString();
      final ivaRet = _toMoney(m['_ivaRetenido']);
      final total = _toMoney(m['_total']);

      totalIvaRetenido += ivaRet;

      final zebra =
          i % 2 == 1 ? PdfColor.fromHex('#FAFAFA') : PdfColors.white;

      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: zebra,
            border: pw.Border(
              left: pw.BorderSide(color: _border, width: 0.5),
              right: pw.BorderSide(color: _border, width: 0.5),
              bottom: pw.BorderSide(color: _border, width: 0.5),
            ),
          ),
          children: [
            _cell(_fmtDate(dt)),
            _cell(user),
            _cell(client),
            _cell(_fmtMoney(total), align: pw.TextAlign.right),
            _cell(
              _fmtMoney(ivaRet),
              align: pw.TextAlign.right,
              isTotal: true,
            ),
          ],
        ),
      );
    }

    final table = pw.Table(
      border: pw.TableBorder(
        top: pw.BorderSide(color: _border, width: 0.5),
        left: pw.BorderSide(color: _border, width: 0.5),
        right: pw.BorderSide(color: _border, width: 0.5),
        bottom: pw.BorderSide(color: _border, width: 0.5),
      ),
      columnWidths: {
        0: const pw.FlexColumnWidth(12), // Fecha
        1: const pw.FlexColumnWidth(16), // Usuario
        2: const pw.FlexColumnWidth(18), // Cliente
        3: const pw.FlexColumnWidth(12), // Total venta
        4: const pw.FlexColumnWidth(12), // IVA retenido
      },
      children: rows,
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 6),
        if (ivaMovs.isEmpty)
          pw.Text(
            'No hay movimientos en esta sección.',
            style: pw.TextStyle(fontSize: 10),
          )
        else ...[
          table,
          pw.SizedBox(height: 8),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Total IVA retenido: ${_fmtMoney(totalIvaRetenido)}',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: _totalRed,
              ),
            ),
          ),
        ],
      ],
    );
  }

  static pw.Widget _cellHeader(
    String text,
    pw.TextStyle style, {
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: pw.Text(
        text,
        style: style,
        textAlign: align,
      ),
    );
  }

  static pw.Widget _cell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    bool isTotal = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: isTotal ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isTotal ? _totalRed : PdfColors.black,
        ),
      ),
    );
  }

  // ============ helpers numéricos / fecha ============

  static double _toMoney(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse((v?.toString() ?? '').replaceAll(',', '.')) ?? 0.0;
  }

  static String _fmtMoney(double v) => '\$${v.toStringAsFixed(2)}';

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _fmtDateTime(DateTime d) =>
      '${_fmtDate(d)} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String _dateRangeLabel(DateTime? from, DateTime? to) {
    if (from == null && to == null) return 'Todos los movimientos';
    if (from != null && to != null) {
      return '${_fmtDate(from)} - ${_fmtDate(to)}';
    }
    if (from != null) {
      return 'Desde ${_fmtDate(from)}';
    }
    return 'Hasta ${_fmtDate(to!)}';
  }

  static Future<Uint8List?> _tryLoad(String assetPath) async {
    try {
      final bytes = await rootBundle.load(assetPath);
      return bytes.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }
}
