// lib/movements_pdf.dart
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class MovementsPdf {
  // Paleta igual que la de invoice_pdf.dart
  static final PdfColor _green = PdfColor.fromHex('#2E7D32');
  static final PdfColor _greenLight = PdfColor.fromHex('#E8F5E9');
  static final PdfColor _border = PdfColor.fromHex('#D6D6D6');
  static final PdfColor _totalRed = PdfColor.fromHex('#C62828');

  /// Construye el PDF de movimientos.
  ///
  /// - [title] normalmente "Reporte de movimientos".
  /// - [filterLabel] "Todos", "Ingresos", "Egresos".
  /// - [from], [to] rango de fechas (pueden ser null).
  /// - [movements] es la lista de mapas que mandas desde `MovementsManager`.
  /// - [logoAssetPath] opcional, por defecto intenta `assets/logo.png`.
  static Future<Uint8List> build({
    required String title,
    required String filterLabel,
    required DateTime? from,
    required DateTime? to,
    required List<Map<String, dynamic>> movements,
    String? logoAssetPath,
  }) async {
    final doc = pw.Document();

    // Cargar logo (si existe el asset)
    final logoBytes = await _tryLoad(logoAssetPath ?? 'assets/logo.png');
    final logo = logoBytes != null ? pw.MemoryImage(logoBytes) : null;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        build: (context) => [
          // ===== ENCABEZADO / MEMBRETE =====
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    title,
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
                  pw.Text('Filtro: $filterLabel'),
                  if (from != null || to != null)
                    pw.Text(_dateRangeLabel(from, to)),
                ],
              ),
            ],
          ),

          pw.SizedBox(height: 12),

          // Bloque tipo membrete de factura
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
                        'Reporte detallado de ingresos y egresos de inventario.',
                      ),
                      if (from == null && to == null) ...[
                        pw.SizedBox(height: 2),
                        pw.Text('Período: todos los movimientos'),
                      ] else ...[
                        pw.SizedBox(height: 2),
                        pw.Text('Período: ${_dateRangeLabel(from, to)}'),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 16),

          // ===== LISTA DE MOVIMIENTOS =====
          ..._buildMovements(movements),

          pw.SizedBox(height: 22),

          // ===== PIE DE PÁGINA ESTILO FACTURA =====
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
                pw.Text('© ${DateTime.now().year} Todos los derechos reservados.'),
              ],
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  // ========= CONSTRUCCIÓN DE BLOQUES =========

  static List<pw.Widget> _buildMovements(
    List<Map<String, dynamic>> movements,
  ) {
    final widgets = <pw.Widget>[];

    for (var idx = 0; idx < movements.length; idx++) {
      final m = movements[idx];

      final type = (m['type'] ?? '').toString().toLowerCase();
      final tipoLabel = type == 'ingreso' ? 'Ingreso' : 'Egreso';

      final createdBy = (m['createdByName'] ?? '—').toString();
      final createdByEmail = (m['createdByEmail'] ?? '').toString();
      final counterparty = (m['counterpartyName'] ?? '').toString();
      final note = (m['note'] ?? '').toString();
      final totalAmount = _toMoney(m['totalAmount']);
      final totalItems = (m['totalItems'] ?? 0).toString();

      DateTime? dt;
      final createdAt = m['createdAt'];
      if (createdAt is DateTime) {
        dt = createdAt;
      }

      // items
      final rawItems = (m['items'] as List<dynamic>? ?? []);
      final items = rawItems
          .map<Map<String, dynamic>>(
              (e) => Map<String, dynamic>.from(e as Map))
          .toList();

      widgets.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 12),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _border),
            borderRadius: pw.BorderRadius.circular(10),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Encabezado del movimiento
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // Usuario + etiqueta de tipo
                      pw.Row(
                        mainAxisSize: pw.MainAxisSize.min,
                        children: [
                          pw.Text(
                            createdBy,
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              color: _green,
                            ),
                          ),
                          pw.SizedBox(width: 8),
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: pw.BoxDecoration(
                              color: _greenLight,
                              borderRadius: pw.BorderRadius.circular(6),
                            ),
                            child: pw.Text(
                              tipoLabel,
                              style: pw.TextStyle(
                                color: _green,
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (createdByEmail.isNotEmpty)
                        pw.Text(
                          createdByEmail,
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      if (dt != null)
                        pw.Text(
                          _fmtDateTime(dt),
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                      if (counterparty.isNotEmpty) ...[
                        pw.SizedBox(height: 3),
                        pw.Text(
                          type == 'egreso'
                              ? 'Cliente: $counterparty'
                              : 'Proveedor: $counterparty',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                      ],
                      if (note.isNotEmpty)
                        pw.Text(
                          'Nota: $note',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Líneas: $totalItems',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Total: ${_fmtMoney(totalAmount)}',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          color: _totalRed,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              pw.SizedBox(height: 8),

              // Tabla de líneas
              _itemsTable(items),
            ],
          ),
        ),
      );
    }

    if (widgets.isEmpty) {
      widgets.add(
        pw.Center(
          child: pw.Text('No hay movimientos para mostrar.'),
        ),
      );
    }

    return widgets;
  }

  /// Tabla de líneas para cada movimiento:
  /// Producto | Cant. | P. unidad | Subtotal | Stock
  static pw.Widget _itemsTable(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return pw.Text(
        'Sin líneas de detalle.',
        style: const pw.TextStyle(fontSize: 10),
      );
    }

    final headerStyle = pw.TextStyle(
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.white,
      fontSize: 10,
    );

    final rows = <pw.Widget>[];

    // Cabecera
    rows.add(
      pw.Container(
        decoration: pw.BoxDecoration(
          color: _green,
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: pw.Row(
            children: [
              _cellHeader('Producto',
                  flex: 30, style: headerStyle, align: pw.TextAlign.left),
              _cellHeader('Cant.',
                  flex: 8, style: headerStyle, align: pw.TextAlign.center),
              _cellHeader('P. unidad',
                  flex: 13, style: headerStyle, align: pw.TextAlign.right),
              _cellHeader('Subtotal',
                  flex: 13, style: headerStyle, align: pw.TextAlign.right),
              _cellHeader('Stock',
                  flex: 16, style: headerStyle, align: pw.TextAlign.right),
            ],
          ),
        ),
      ),
    );

    // Filas
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final zebra = i % 2 == 1 ? PdfColor.fromHex('#FAFAFA') : PdfColors.white;

      final qty = _toInt(it['qty']);

      // ⬇️ AQUÍ EL CAMBIO IMPORTANTE
      // Primero intentamos leer unitPriceWithVat (precio con IVA),
      // luego otros posibles campos para no quedarnos en 0.00.
      final unitPrice = _toMoney(
        it['unitPriceWithVat'] ??
            it['unitPrice'] ??
            it['unitPriceWithoutVat'] ??
            it['salePrice'] ??
            it['purchasePrice'],
      );

      final subtotal = _toMoney(it['subtotal']);

      final stockBefore = it['stockBefore'];
      final stockAfter = it['stockAfter'];
      String stockText = '';
      if (stockBefore is num && stockAfter is num) {
        stockText =
            'Antes: ${_toInt(stockBefore)} / Después: ${_toInt(stockAfter)}';
      }

      rows.add(
        pw.Container(
          decoration: pw.BoxDecoration(
            color: zebra,
            border: pw.Border.all(color: _border),
            borderRadius: i == items.length - 1
                ? pw.BorderRadius.only(
                    bottomLeft: const pw.Radius.circular(6),
                    bottomRight: const pw.Radius.circular(6),
                  )
                : null,
          ),
          child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: pw.Row(
              children: [
                _cell(
                  '${it['productName']} (SKU: ${it['sku']})',
                  flex: 30,
                  align: pw.TextAlign.left,
                ),
                _cell(
                  '$qty',
                  flex: 8,
                  align: pw.TextAlign.center,
                ),
                _cell(
                  _fmtMoney(unitPrice),
                  flex: 13,
                  align: pw.TextAlign.right,
                ),
                _cell(
                  _fmtMoney(subtotal),
                  flex: 13,
                  align: pw.TextAlign.right,
                ),
                _cell(
                  stockText,
                  flex: 16,
                  align: pw.TextAlign.right,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return pw.Column(children: rows);
  }

  // ========= Helpers de celdas =========

  static pw.Widget _cellHeader(
    String t, {
    required int flex,
    required pw.TextStyle style,
    pw.TextAlign? align,
  }) {
    return pw.Expanded(
      flex: flex,
      child: pw.Text(
        t,
        style: style,
        textAlign: align,
      ),
    );
  }

  static pw.Widget _cell(
    String t, {
    required int flex,
    pw.TextAlign? align,
  }) {
    return pw.Expanded(
      flex: flex,
      child: pw.Text(
        t,
        textAlign: align,
        softWrap: true,
        style: const pw.TextStyle(fontSize: 10),
      ),
    );
  }

  // ========= Utils numéricos / formato =========

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

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

  // ========= Carga segura de assets =========

  static Future<Uint8List?> _tryLoad(String assetPath) async {
    try {
      final bytes = await rootBundle.load(assetPath);
      return bytes.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }
}
