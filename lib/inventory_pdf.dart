// lib/inventory_pdf.dart
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class InventoryPdfItem {
  final String name;
  final String sku;
  final String category;
  final String presentation;
  final double stock;
  final double unitCost;
  final double inventoryValue;
  final double salePrice;
  final bool taxable;

  InventoryPdfItem({
    required this.name,
    required this.sku,
    required this.category,
    required this.presentation,
    required this.stock,
    required this.unitCost,
    required this.inventoryValue,
    required this.salePrice,
    required this.taxable,
  });
}

class InventoryPdfNearExpiryItem {
  final String productName;
  final String sku;
  final String lot;
  final double qty;
  final DateTime expiryDate;

  InventoryPdfNearExpiryItem({
    required this.productName,
    required this.sku,
    required this.lot,
    required this.qty,
    required this.expiryDate,
  });
}

class InventoryPdf {
  // Paleta igual que invoice/movements
  static final PdfColor _green = PdfColor.fromHex('#2E7D32');
  static final PdfColor _greenLight = PdfColor.fromHex('#E8F5E9');
  static final PdfColor _border = PdfColor.fromHex('#D6D6D6');
  static final PdfColor _totalRed = PdfColor.fromHex('#C62828');

  /// Construye el PDF de inventario.
  static Future<Uint8List> build({
    required String title,
    required DateTime generatedAt,
    required double totalValue,
    required int totalProducts,
    required List<InventoryPdfItem> items,
    required List<InventoryPdfNearExpiryItem> nearExpiry,
    String? logoAssetPath,
  }) async {
    final doc = pw.Document();

    // Cargar logo (si existe el asset)
    final logoBytes =
        await _tryLoad(logoAssetPath ?? 'assets/logo.png');
    final logo = logoBytes != null ? pw.MemoryImage(logoBytes) : null;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        build: (context) => [
          // ===== ENCABEZADO / TÍTULO =====
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
                  pw.Text('Generado: ${_fmtDateTime(generatedAt)}'),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Total de productos: $totalProducts'),
                  pw.Text('Valor total (al costo): ${_fmtMoney(totalValue)}'),
                ],
              ),
            ],
          ),

          pw.SizedBox(height: 12),

          // ===== BLOQUE TIPO MEMBRETE =====
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
                        'Reporte detallado de existencias de productos en inventario.',
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Incluye cantidades, costos, valores en existencia y productos próximos a vencer.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 16),

          // ===== TABLA PRINCIPAL DE INVENTARIO =====
          _inventoryTable(items),

          // ===== SECCIÓN DE PRÓXIMOS A VENCER =====
          if (nearExpiry.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            pw.Text(
              'Lotes próximos a vencer (dentro de 90 días)',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: _green,
              ),
            ),
            pw.SizedBox(height: 8),
            _nearExpiryTable(nearExpiry),
          ] else ...[
            pw.SizedBox(height: 18),
            pw.Text(
              'No hay lotes próximos a vencer.',
              style: const pw.TextStyle(fontSize: 11),
            ),
          ],

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
                  style: const pw.TextStyle(fontSize: 10),
                ),
                pw.Text(
                  'Soporte: soporte@pharmacontrol.com  •  +503 7000-0000  /  +503 7111-1111',
                  style: const pw.TextStyle(fontSize: 10),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  '© ${generatedAt.year} Todos los derechos reservados.',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  // ========= TABLA PRINCIPAL DE INVENTARIO =========

  static pw.Widget _inventoryTable(List<InventoryPdfItem> items) {
    if (items.isEmpty) {
      return pw.Text(
        'No hay productos en inventario para mostrar.',
        style: const pw.TextStyle(fontSize: 11),
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
              _cellHeader('Producto', flex: 26, style: headerStyle),
              _cellHeader('Categoría', flex: 16, style: headerStyle),
              _cellHeader('Stock', flex: 8, style: headerStyle, align: pw.TextAlign.right),
              _cellHeader('C. unit.', flex: 12, style: headerStyle, align: pw.TextAlign.right),
              _cellHeader('Valor exist.', flex: 14, style: headerStyle, align: pw.TextAlign.right),
              _cellHeader('P. venta', flex: 12, style: headerStyle, align: pw.TextAlign.right),
              _cellHeader('IVA', flex: 6, style: headerStyle, align: pw.TextAlign.center),
            ],
          ),
        ),
      ),
    );

    // Filas
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final zebra = i % 2 == 1 ? PdfColor.fromHex('#FAFAFA') : PdfColors.white;

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
                // Columna de producto mejor ordenada: nombre, SKU y presentación en líneas separadas
                pw.Expanded(
                  flex: 26,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
  it.name,
  style: pw.TextStyle(
    fontSize: 10,
    fontWeight: pw.FontWeight.bold,
  ),
),

                      pw.Text(
                        'SKU: ${it.sku}',
                        style: const pw.TextStyle(
                          fontSize: 9,
                        ),
                      ),
                      if (it.presentation.trim().isNotEmpty)
                        pw.Text(
                          it.presentation,
                          style: const pw.TextStyle(
                            fontSize: 9,
                          ),
                        ),
                    ],
                  ),
                ),
                _cell(
                  it.category,
                  flex: 16,
                  align: pw.TextAlign.left,
                ),
                _cell(
                  _fmtNumber(it.stock),
                  flex: 8,
                  align: pw.TextAlign.right,
                ),
                _cell(
                  _fmtMoney(it.unitCost),
                  flex: 12,
                  align: pw.TextAlign.right,
                ),
                _cell(
                  _fmtMoney(it.inventoryValue),
                  flex: 14,
                  align: pw.TextAlign.right,
                ),
                _cell(
                  _fmtMoney(it.salePrice),
                  flex: 12,
                  align: pw.TextAlign.right,
                ),
                _cell(
                  it.taxable ? 'Sí' : 'No',
                  flex: 6,
                  align: pw.TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return pw.Column(children: rows);
  }

  // ========= TABLA DE PRÓXIMOS A VENCER =========

  static pw.Widget _nearExpiryTable(List<InventoryPdfNearExpiryItem> items) {
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
              _cellHeader('Producto', flex: 30, style: headerStyle),
              _cellHeader('SKU', flex: 10, style: headerStyle),
              _cellHeader('Lote', flex: 10, style: headerStyle),
              _cellHeader('Cant.', flex: 8, style: headerStyle, align: pw.TextAlign.right),
              _cellHeader('Vence', flex: 12, style: headerStyle, align: pw.TextAlign.center),
              _cellHeader('Días', flex: 8, style: headerStyle, align: pw.TextAlign.right),
            ],
          ),
        ),
      ),
    );

    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final zebra = i % 2 == 1 ? PdfColor.fromHex('#FAFAFA') : PdfColors.white;
      final daysLeft = it.expiryDate.difference(DateTime.now()).inDays;

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
                  it.productName,
                  flex: 30,
                  align: pw.TextAlign.left,
                ),
                _cell(
                  it.sku,
                  flex: 10,
                  align: pw.TextAlign.left,
                ),
                _cell(
                  it.lot,
                  flex: 10,
                  align: pw.TextAlign.left,
                ),
                _cell(
                  _fmtNumber(it.qty),
                  flex: 8,
                  align: pw.TextAlign.right,
                ),
                _cell(
                  _fmtDate(it.expiryDate),
                  flex: 12,
                  align: pw.TextAlign.center,
                ),
                _cell(
                  daysLeft.toString(),
                  flex: 8,
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

  static String _fmtMoney(double v) => '\$${v.toStringAsFixed(2)}';

  static String _fmtNumber(double v) =>
      v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _fmtDateTime(DateTime d) =>
      '${_fmtDate(d)} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

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
