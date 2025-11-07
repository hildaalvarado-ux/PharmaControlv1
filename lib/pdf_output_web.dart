// lib/pdf_output_web.dart
import 'dart:typed_data';
import 'package:printing/printing.dart';

/// WEB: abre el diálogo de impresión del navegador en la MISMA pestaña,
/// mostrando la vista previa integrada (con botones de Imprimir y Descargar).
Future<void> outputPdf(Uint8List bytes, String filename) async {
  await Printing.layoutPdf(
    name: filename,                       // etiqueta del trabajo
    onLayout: (_) async => bytes,         // bytes ya generados
  );
}
