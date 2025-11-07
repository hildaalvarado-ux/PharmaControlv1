// lib/invoice_pdf.dart
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class InvoiceItem {
  final String name;
  final int qty;
  final double unitPrice;
  final double subtotal;

  InvoiceItem({
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.subtotal,
  });
}

class InvoicePdf {
  // Paleta
  static final PdfColor _green = PdfColor.fromHex('#2E7D32');
  static final PdfColor _greenLight = PdfColor.fromHex('#E8F5E9');
  static final PdfColor _border = PdfColor.fromHex('#D6D6D6');
  static final PdfColor _totalRed = PdfColor.fromHex('#C62828');

  static Future<Uint8List> build({
    required String logoAssetPath,       // p.ej. 'assets/logo.png'
    required String invoiceNumber,       // <-- imprime el ID de la venta
    required DateTime date,
    required String buyer,
    required String notes,
    required List<InvoiceItem> items,
    required double subtotal,
    required double iva,
    required double total,
  }) async {
    final doc = pw.Document();

    // Cargar logo si existe
    final logoBytes = await _tryLoad(logoAssetPath);
    final logo = logoBytes != null ? pw.MemoryImage(logoBytes) : null;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        build: (context) => [
          // Título + meta
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Factura de Venta',
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      color: _green,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text('No.: $invoiceNumber'),
                  pw.Text('Fecha: ${_fmtDate(date)}'),
                ],
              ),
            ],
          ),

          pw.SizedBox(height: 12),

          // Bloque de datos (con logo a la izquierda y marca "PharmaControl")
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
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text('Cliente: $buyer'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 14),

          // Tabla de items (con cebra y envoltura)
          _itemsTable(items),

          pw.SizedBox(height: 10),

          // Totales (separados)
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Container(
                width: 280,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _border),
                  borderRadius: pw.BorderRadius.circular(10),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    _kv('Subtotal:', _fmt(subtotal)),
                    _kv('IVA:', _fmt(iva)),
                    pw.Divider(color: _border),
                    _kv('TOTAL', _fmt(total),
                        bold: true,
                        color: _totalRed,
                        size: 14),
                  ],
                ),
              ),
            ],
          ),

          if (notes.trim().isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text('Notas:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text(notes),
          ],

          pw.SizedBox(height: 22),

          // Pie de página formal
          pw.Divider(color: _border),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text(
                  'PharmaControl',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _green),
                ),
                pw.SizedBox(height: 2),
                pw.Text('Calle Principal #123, Sensuntepeque, Cabañas, El Salvador'),
                pw.Text('Soporte: soporte@pharmacontrol.com  •  +503 7000-0000  /  +503 7111-1111'),
                pw.SizedBox(height: 6),
                pw.Text('© ${date.year} Todos los derechos reservados.'),
              ],
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  // ---------------- helpers UI ----------------

  static pw.Widget _itemsTable(List<InvoiceItem> items) {
    final headerStyle = pw.TextStyle(
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.white,
    );

    // Cabecera
    final header = pw.Container(
      decoration: pw.BoxDecoration(
        color: _green,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        child: pw.Row(children: [
          _cellHeader('Producto', flex: 26, style: headerStyle),
          _cellHeader('Cant.', flex: 8, style: headerStyle, align: pw.TextAlign.center),
          _cellHeader('Precio', flex: 13, style: headerStyle, align: pw.TextAlign.right),
          _cellHeader('Subtotal', flex: 13, style: headerStyle, align: pw.TextAlign.right),
        ]),
      ),
    );

    // Filas
    final rows = <pw.Widget>[header];
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
            padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            child: pw.Row(children: [
              _cell(it.name, flex: 26), // envuelve texto largo
              _cell('${it.qty}', flex: 8, align: pw.TextAlign.center),
              _cell(_fmt(it.unitPrice), flex: 13, align: pw.TextAlign.right),
              _cell(_fmt(it.subtotal), flex: 13, align: pw.TextAlign.right),
            ]),
          ),
        ),
      );
    }

    return pw.Column(children: rows);
  }

  static pw.Widget _cellHeader(String t,
      {required int flex, required pw.TextStyle style, pw.TextAlign? align}) {
    return pw.Expanded(
      flex: flex,
      child: pw.Text(t, style: style, textAlign: align),
    );
  }

  static pw.Widget _cell(String t, {required int flex, pw.TextAlign? align}) {
    return pw.Expanded(
      flex: flex,
      child: pw.Text(
        t,
        textAlign: align,
        softWrap: true,
      ),
    );
  }

  static pw.Widget _kv(String k, String v,
      {bool bold = false, PdfColor? color, double? size}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(k),
          pw.Text(
            v,
            style: pw.TextStyle(
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color,
              fontSize: size,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- util ----------------

  static Future<Uint8List?> _tryLoad(String assetPath) async {
    try {
      final bytes = await rootBundle.load(assetPath);
      return bytes.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  static String _fmt(double v) => '\$${v.toStringAsFixed(2)}';

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
