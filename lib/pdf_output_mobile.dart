import 'dart:typed_data';
import 'package:printing/printing.dart';

Future<void> outputPdf(Uint8List bytes, String filename) async {
  // En móvil/escritorio abre el diálogo de impresión/compartir
  await Printing.layoutPdf(onLayout: (_) async => bytes);
}
