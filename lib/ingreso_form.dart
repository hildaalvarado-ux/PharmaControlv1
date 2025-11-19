// lib/ingreso_form_widget.dart
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'invoice_pdf.dart';

// ⬇️ Salida PDF multiplataforma: móvil/escritorio vs web
import 'pdf_output_mobile.dart' if (dart.library.html) 'pdf_output_web.dart' as pdf_out;

class IngresoLine {
  String? productId;
  // Estos campos se llenarán al seleccionar un producto
  String productName;
  String productSku;

  int qty;
  double purchasePrice;
  double salePrice;
  String lot;
  DateTime? expiryDate;

  IngresoLine({
    this.productId,
    this.productName = '',
    this.productSku = '',
    this.qty = 1,
    this.purchasePrice = 0.0,
    this.salePrice = 0.0,
    this.lot = '',
    this.expiryDate,
  });

  double get subtotal => qty * purchasePrice;
}

class IngresoFormWidget extends StatefulWidget {
  const IngresoFormWidget({super.key});
  @override
  State<IngresoFormWidget> createState() => _IngresoFormWidgetState();
}

class _IngresoFormWidgetState extends State<IngresoFormWidget> {
  final CollectionReference productsRef = FirebaseFirestore.instance.collection('products');
  final CollectionReference providersRef = FirebaseFirestore.instance.collection('providers');
  final CollectionReference ingresosRef = FirebaseFirestore.instance.collection('ingresos');

  List<QueryDocumentSnapshot>? _products;
  Map<String, Map<String, dynamic>> _prodMap = {};
  List<QueryDocumentSnapshot>? _providersList;

  // categorías de ejemplo (puedes sustituir por una colección si la tienes)
  List<String> _categories = ['Medicamento', 'Aseo', 'Veterinaria', 'Otro'];

  final providerCtrl = TextEditingController();
  final invoiceCtrl = TextEditingController();
  DateTime? purchaseDate;

  bool _loading = false;
  final List<IngresoLine> _lines = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    providerCtrl.dispose();
    invoiceCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final ps = await productsRef.orderBy('name').get();
    final provs = await providersRef.orderBy('name').get();
    _products = ps.docs;
    _prodMap = {for (var d in ps.docs) d.id: (d.data() as Map<String, dynamic>)};
    _providersList = provs.docs;
    if (mounted) setState(() {});
  }

  // --- helpers numéricos
  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse((v?.toString() ?? '').replaceAll(',', '.')) ?? 0.0;
  }

  num _toNum(dynamic v) {
    if (v is num) return v;
    return num.tryParse((v?.toString() ?? '').replaceAll(',', '.')) ?? 0;
  }

  String _numOrEmpty(dynamic v) => v == null ? '' : v.toString();

  void _showSnack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  double get _total => _lines.fold(0.0, (s, l) => s + l.subtotal);

  // UI helpers
  void _removeLine(int idx) => setState(() => _lines.removeAt(idx));
  void _clearAll() {
    setState(() {
      _lines.clear();
      providerCtrl.clear();
      invoiceCtrl.clear();
      purchaseDate = null;
    });
  }

  // ==== Generar siguiente SKU simple (similar al admin)
  Future<String> _generateNextSku() async {
    try {
      final q = await productsRef.orderBy('sku', descending: true).limit(1).get();
      if (q.docs.isEmpty) return '1001';
      final candidate = (q.docs.first.data() as Map<String, dynamic>)['sku']?.toString() ?? '';
      final n = int.tryParse(candidate);
      if (n == null) {
        final all = await productsRef.get();
        int maxN = 1000;
        for (final d in all.docs) {
          final sku = (d.data() as Map<String, dynamic>)['sku']?.toString();
          if (sku == null) continue;
          final v = int.tryParse(sku);
          if (v != null && v > maxN) maxN = v;
        }
        return (maxN + 1).toString();
      }
      return (n + 1).toString();
    } catch (_) {
      return '1001';
    }
  }

  Future<void> _showAddEditLoteDialog({IngresoLine? existingLine, int? editIndex}) async {
    final formKey = GlobalKey<FormState>();

    // Controllers
    final qtyCtrl = TextEditingController(text: _numOrEmpty(existingLine?.qty));
    final purchasePriceCtrl = TextEditingController(text: _numOrEmpty(existingLine?.purchasePrice));
    final lotCtrl = TextEditingController(text: existingLine?.lot ?? '');

    // State variables for the dialog
    String? selectedProductId = existingLine?.productId;
    DateTime? expiryDate = existingLine?.expiryDate;

    // Pre-fill sale price if we have the data
    final salePriceCtrl = TextEditingController(text: _numOrEmpty(existingLine?.salePrice));

    await showDialog(
      context: context,
      builder: (c) {
        return StatefulBuilder(builder: (c, setDialogState) {
          return AlertDialog(
            title: Text(existingLine == null ? 'Agregar Lote' : 'Editar Lote'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedProductId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Producto *'),
                      items: (_products ?? []).map((p) {
                        final d = p.data() as Map<String, dynamic>;
                        return DropdownMenuItem(value: p.id, child: Text(d['name'] ?? 'N/A'));
                      }).toList(),
                      onChanged: (v) {
                        setDialogState(() {
                          selectedProductId = v;
                          if (v != null && _prodMap.containsKey(v)) {
                            final p = _prodMap[v]!;
                            purchasePriceCtrl.text = _numOrEmpty(p['purchasePrice']);
                            final margin = _toDouble(p['marginPercent'] ?? 10);
                            final suggestedSale = _toDouble(p['purchasePrice']) * (1 + (margin / 100));
                            salePriceCtrl.text = suggestedSale.toStringAsFixed(2);
                          }
                        });
                      },
                      validator: (v) => v == null ? 'Seleccione un producto' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad *'), validator: (v) => (_toInt(v) <= 0) ? 'Cantidad inválida' : null),
                    const SizedBox(height: 12),
                    TextFormField(controller: purchasePriceCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Precio de Compra *'), validator: (v) => (_toDouble(v) <= 0) ? 'Precio inválido' : null),
                    const SizedBox(height: 12),
                    TextFormField(controller: salePriceCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Precio de Venta (sugerido)')),
                    const SizedBox(height: 12),
                    TextFormField(controller: lotCtrl, decoration: const InputDecoration(labelText: 'Lote')),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: Text(expiryDate == null ? 'Vencimiento: —' : 'Vence: ${_fmtDate(expiryDate!)}')),
                        IconButton(
                          icon: const Icon(Icons.calendar_today),
                          onPressed: () async {
                            final now = DateTime.now();
                            final d = await showDatePicker(context: context, initialDate: expiryDate ?? now, firstDate: now, lastDate: DateTime(now.year + 10));
                            if (d != null) setDialogState(() => expiryDate = d);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    final productData = _prodMap[selectedProductId];
                    final newLine = IngresoLine(
                      productId: selectedProductId,
                      productName: productData?['name'] ?? 'N/A',
                      productSku: productData?['sku'] ?? 'N/A',
                      qty: _toInt(qtyCtrl.text),
                      purchasePrice: _toDouble(purchasePriceCtrl.text),
                      salePrice: _toDouble(salePriceCtrl.text),
                      lot: lotCtrl.text.trim(),
                      expiryDate: expiryDate,
                    );

                    setState(() {
                      if (editIndex != null) {
                        _lines[editIndex] = newLine;
                      } else {
                        _lines.add(newLine);
                      }
                    });
                    Navigator.pop(c);
                  }
                },
                child: const Text('Guardar'),
              ),
            ],
          );
        });
      },
    );
  }

  // ====== GUARDAR ingreso con batches (mejorado) ======
  Future<void> _save() async {
    if (_lines.isEmpty) {
      _showSnack('Agrega al menos un lote de producto.');
      return;
    }

    setState(() => _loading = true);

    try {
      final ingresoRef = ingresosRef.doc();
      final itemsForDb = <Map<String, dynamic>>[];
      final providerId = _providersList?.firstWhere((p) => (p.data() as Map)['name'] == providerCtrl.text, orElse: () => _providersList!.first).id;

      await FirebaseFirestore.instance.runTransaction((tx) async {
        for (final l in _lines) {
          final prodRef = productsRef.doc(l.productId);
          final lote = l.lot.trim();

          DocumentReference batchRef;
          final batchQuery = await prodRef.collection('batches').where('lot', isEqualTo: lote.isNotEmpty ? lote : null).limit(1).get();

          if (batchQuery.docs.isNotEmpty) {
            batchRef = batchQuery.docs.first.reference;
            tx.update(batchRef, {'qty': FieldValue.increment(l.qty)});
          } else {
            batchRef = prodRef.collection('batches').doc();
            tx.set(batchRef, {
              'lot': lote.isEmpty ? null : lote,
              'qty': l.qty,
              'expiryDate': l.expiryDate != null ? Timestamp.fromDate(l.expiryDate!) : null,
              'purchasePrice': l.purchasePrice,
              'createdAt': FieldValue.serverTimestamp(),
            });
          }

          tx.update(prodRef, {
            'stock': FieldValue.increment(l.qty),
            'purchasePrice': l.purchasePrice,
            'price': l.salePrice,
            'lastPurchaseAt': FieldValue.serverTimestamp(),
          });

          itemsForDb.add({
            'productId': l.productId,
            'productName': l.productName,
            'qty': l.qty,
            'purchasePrice': l.purchasePrice,
            'subtotal': l.subtotal,
            'lot': lote.isEmpty ? null : lote,
            'expiryDate': l.expiryDate != null ? Timestamp.fromDate(l.expiryDate!) : null,
            'batchId': batchRef.id,
          });
        }

        tx.set(ingresoRef, {
          'userId': FirebaseAuth.instance.currentUser?.uid,
          'items': itemsForDb,
          'total': _total,
          'providerId': providerId,
          'invoice': invoiceCtrl.text.trim(),
          'purchaseDate': purchaseDate != null ? Timestamp.fromDate(purchaseDate!) : FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

      _showSnack('Compra registrada y stock actualizado.');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showSnack('Error al registrar compra: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ====== IMPRIMIR ingreso (incluye lotes/vencimiento en descripción) ======
  Future<void> _print() async {
    if (_lines.isEmpty) {
      _showSnack('No hay ítems para imprimir.');
      return;
    }
    final now = DateTime.now();
    final items = _lines.map((l) {
      final lotPart = (l.lot.trim().isNotEmpty ? 'Lote: ${l.lot.trim()}' : '');
      final expiryPart = (l.expiryDate != null ? 'Vence: ${_fmtDate(l.expiryDate!)}' : '');
      final extra = [lotPart, expiryPart].where((s) => s.isNotEmpty).join(' • ');
      final displayName = extra.isEmpty ? l.productName : '${l.productName} ($extra)';
      return InvoiceItem(
        name: displayName,
        qty: l.qty,
        unitPrice: l.purchasePrice,
        subtotal: l.subtotal,
      );
    }).toList();

    final bytes = await InvoicePdf.build(
      logoAssetPath: 'assets/logo.png',
      invoiceNumber: 'COMPRA',
      date: now,
      buyer: providerCtrl.text.trim().isEmpty ? 'Proveedor' : providerCtrl.text.trim(),
      notes: invoiceCtrl.text.trim().isEmpty ? '' : 'Factura: ${invoiceCtrl.text.trim()}',
      items: items,
      subtotal: _total,
      iva: 0,
      total: _total,
    );

    await pdf_out.outputPdf(bytes, 'ingreso_${now.millisecondsSinceEpoch}.pdf');
  }

  // ====== UI ======
  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      appBar: AppBar(title: const Text('Registrar compra (Ingreso)'), backgroundColor: kGreen2),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: _products == null
                ? const Center(child: CircularProgressIndicator())
                : Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Gestión de Compras', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kGreen1)),
                        const SizedBox(height: 12),

                        // Proveedor, factura, fecha
                        Row(children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _providersList != null && _providersList!.isNotEmpty ? _providersList!.first.id : null,
                              items: _providersList?.map((p) {
                                final d = p.data() as Map<String, dynamic>;
                                return DropdownMenuItem(value: p.id, child: Text(d['name'] ?? '—'));
                              }).toList(),
                              onChanged: (v) => providerCtrl.text = v ?? '',
                              decoration: const InputDecoration(labelText: 'Proveedor'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 220,
                            child: TextFormField(
                              controller: invoiceCtrl,
                              decoration: const InputDecoration(labelText: 'N° factura / serie'),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: Text(
                              purchaseDate == null
                                  ? 'Fecha de compra: —'
                                  : 'Compra: ${purchaseDate!.day.toString().padLeft(2, '0')}/${purchaseDate!.month.toString().padLeft(2, '0')}/${purchaseDate!.year}',
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final now = DateTime.now();
                              final d = await showDatePicker(
                                context: context,
                                initialDate: purchaseDate ?? now,
                                firstDate: DateTime(now.year - 5),
                                lastDate: DateTime(now.year + 1),
                              );
                              if (d != null) setState(() => purchaseDate = d);
                            },
                            child: const Text('Seleccionar'),
                          )
                        ]),

                        const SizedBox(height: 16),

                        // Acciones rápidas + total
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed: _lines.isEmpty &&
                                      providerCtrl.text.isEmpty &&
                                      invoiceCtrl.text.isEmpty &&
                                      purchaseDate == null
                                  ? null
                                  : _clearAll,
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                              child: const Text('L  •  Limpiar'),
                            ),
                            ElevatedButton(
                              onPressed: _lines.isEmpty ? null : _print,
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                              child: const Text('I  •  Imprimir PDF'),
                            ),
                            const SizedBox(width: 12),
                            Text('Total: \$${_total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            ElevatedButton(
                              onPressed: _loading ? null : _save,
                              style: ElevatedButton.styleFrom(backgroundColor: kGreen2, foregroundColor: Colors.white),
                              child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Registrar compra'),
                            ),
                          ],
                        ),
                      ]),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

                        Row(children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _providersList != null && _providersList!.isNotEmpty ? _providersList!.first.id : null,
                              items: _providersList?.map((p) {
                                final d = p.data() as Map<String, dynamic>;
                                return DropdownMenuItem(value: p.id, child: Text(d['name'] ?? '—'));
                              }).toList(),
                              onChanged: (v) => providerCtrl.text = v ?? '',
                              decoration: const InputDecoration(labelText: 'Proveedor'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 220,
                            child: TextFormField(
                              controller: invoiceCtrl,
                              decoration: const InputDecoration(labelText: 'N° factura / serie'),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: Text(
                              purchaseDate == null
                                  ? 'Fecha de compra: —'
                                  : 'Compra: ${purchaseDate!.day.toString().padLeft(2, '0')}/${purchaseDate!.month.toString().padLeft(2, '0')}/${purchaseDate!.year}',
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final now = DateTime.now();
                              final d = await showDatePicker(
                                context: context,
                                initialDate: purchaseDate ?? now,
                                firstDate: DateTime(now.year - 5),
                                lastDate: DateTime(now.year + 1),
                              );
                              if (d != null) setState(() => purchaseDate = d);
                            },
                            child: const Text('Seleccionar'),
                          )
                        ]),
                        const SizedBox(height: 16),
                        Center(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Agregar Producto/Lote'),
                            onPressed: () => _showAddEditLoteDialog(),
                            style: ElevatedButton.styleFrom(backgroundColor: kGreen2, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text('Lotes a Ingresar', style: Theme.of(context).textTheme.titleMedium),
                        const Divider(),
                        _lines.isEmpty
                          ? const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("Aún no has agregado productos.")))
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _lines.length,
                              itemBuilder: (context, idx) {
                                final line = _lines[idx];
                                return ListTile(
                                  title: Text('${line.productName} (${line.productSku})'),
                                  subtitle: Text('Cant: ${line.qty} • Precio Compra: \$${line.purchasePrice.toStringAsFixed(2)} • Lote: ${line.lot} • Vence: ${line.expiryDate != null ? _fmtDate(line.expiryDate!) : "N/A"}'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _showAddEditLoteDialog(existingLine: line, editIndex: idx)),
                                      IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _removeLine(idx)),
                                    ],
                                  ),
                                );
                              },
                            ),
                        const SizedBox(height: 16),
                        const Divider(),
                        // Acciones rápidas + total
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed: _lines.isEmpty && providerCtrl.text.isEmpty && invoiceCtrl.text.isEmpty && purchaseDate == null
                                  ? null
                                  : _clearAll,
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.grey, foregroundColor: Colors.white),
                              child: const Text('Limpiar Todo'),
                            ),
                            ElevatedButton(
                              onPressed: _lines.isEmpty ? null : _print,
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white),
                              child: const Text('Imprimir PDF'),
                            ),
                            const SizedBox(width: 12),
                            Text('Total: \$${_total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            ElevatedButton(
                              onPressed: _loading ? null : _save,
                              style: ElevatedButton.styleFrom(backgroundColor: kGreen2, foregroundColor: Colors.white),
                              child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Registrar Compra'),
                            ),
                          ],
                        ),
                      ]),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // ====== Detalles por producto (incluye lista de batches) ======
  Future<void> _showProductDetails(String productId) async {
    final prodRef = productsRef.doc(productId);
    final prodSnap = await prodRef.get();
    if (!prodSnap.exists) return;
    final d = prodSnap.data() as Map<String, dynamic>;
    final batchesSnap = await prodRef.collection('batches').orderBy('expiry').get();

    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(d['name'] ?? 'Producto'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv('SKU', (d['sku'] ?? '—').toString()),
              _kv('Stock', ((d['stock'] ?? 0).toString())),
              _kv('Precio venta', '\$${_toDouble(d['price']).toStringAsFixed(2)}'),
              _kv('IVA', (d['taxable'] == true) ? '${(d['ivaPercent'] ?? 13).toString()}%' : 'No grava'),
              if ((d['pharmForm'] ?? '').toString().isNotEmpty || (d['route'] ?? '').toString().isNotEmpty)
                _kv('Forma/Vía', '${d['pharmForm'] ?? '—'} / ${d['route'] ?? '—'}'),
              if ((d['strength'] ?? '').toString().isNotEmpty) _kv('Concentración', (d['strength'] ?? '—').toString()),
              if ((d['presentation'] ?? '').toString().isNotEmpty) _kv('Presentación', (d['presentation'] ?? '—').toString()),
              const SizedBox(height: 12),
              const Text('Batches / Lotes', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              if (batchesSnap.docs.isEmpty)
                const Text('No hay lotes registrados'),
              for (final b in batchesSnap.docs)
                Builder(builder: (ctx) {
                  final bd = b.data() as Map<String, dynamic>;
                  final expiry = (bd['expiry'] as Timestamp?)?.toDate();
                  return ListTile(
                    title: Text('Lote: ${bd['lot'] ?? '—'}  •  Cant: ${bd['qty'] ?? 0}'),
                    subtitle: Text('Compra: \$${(_toDouble(bd['purchasePrice'])).toStringAsFixed(2)} ${expiry != null ? ' • Vence: ${_fmtDate(expiry)}' : ''}'),
                    dense: true,
                  );
                }),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cerrar'))],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6.0),
        child: Row(children: [SizedBox(width: 140, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))), Expanded(child: Text(v))]),
      );

  String _fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  // ====== Opcional: función auxiliar para consumir stock en ventas (FIFO por expiry) ======
  // Uso: en proceso de venta, dentro de una transacción o batch, llamar a consumeStock para decrementar por lotes.
  Future<void> consumeStock(String productId, int qtyToConsume, WriteBatch batch) async {
    final prodRef = productsRef.doc(productId);
    final batchesSnap = await prodRef.collection('batches').orderBy('expiry').get();
    int remain = qtyToConsume;
    for (final b in batchesSnap.docs) {
      if (remain <= 0) break;
      final bd = b.data() as Map<String, dynamic>;
      final int available = (bd['qty'] ?? 0) as int;
      if (available <= 0) continue;
      final take = (available >= remain) ? remain : available;
      final newQty = available - take;
      final batchRef = prodRef.collection('batches').doc(b.id);
      batch.update(batchRef, {'qty': newQty});
      remain -= take;
    }
    if (remain > 0) throw Exception('Stock insuficiente');
    batch.update(prodRef, {'stock': FieldValue.increment(-qtyToConsume)});
  }
}
