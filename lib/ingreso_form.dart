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
  // si es existente
  String? productId;

  // si es nuevo
  bool isNew;
  String newName;
  String newSku;

  int qty;
  double purchasePrice;
  double salePrice;
  String lot;
  DateTime? manufactureDate;
  DateTime? expiryDate;

  IngresoLine({
    this.productId,
    this.qty = 1,
    this.purchasePrice = 0.0,
    this.salePrice = 0.0,
    this.lot = '',
    this.manufactureDate,
    this.expiryDate,
    this.isNew = false,
    this.newName = '',
    this.newSku = '',
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

  final productFilterCtrl = TextEditingController();

  bool _loading = false;
  final List<IngresoLine> _lines = [];

  @override
  void initState() {
    super.initState();
    _loadData().then((_) {
      setState(() {
        _lines.add(IngresoLine(
          productId: _products != null && _products!.isNotEmpty ? _products!.first.id : null,
        ));
      });
    });
    productFilterCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    providerCtrl.dispose();
    invoiceCtrl.dispose();
    productFilterCtrl.dispose();
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
  void _addEmptyLine() => setState(() => _lines.insert(0, IngresoLine()));
  void _removeLine(int idx) => setState(() => _lines.removeAt(idx));
  void _clearAll() {
    setState(() {
      _lines.clear();
      providerCtrl.clear();
      invoiceCtrl.clear();
      purchaseDate = null;
      productFilterCtrl.clear();
      _lines.add(IngresoLine(productId: _products != null && _products!.isNotEmpty ? _products!.first.id : null));
    });
  }

  // Al elegir producto existente, precargar compra y venta sugerida
  void _onChooseProduct(int idx, String? pid) {
    setState(() {
      final ln = _lines[idx];
      ln.productId = pid;
      ln.isNew = false;
      ln.newName = '';
      ln.newSku = '';
      if (pid != null && _prodMap.containsKey(pid)) {
        final p = _prodMap[pid]!;
        final prevPurchase = _toDouble(p['purchasePrice']);
        final margin = _toDouble(p['marginPercent'] ?? 10);
        final suggestedSale = prevPurchase * (1 + (margin / 100));
        if (ln.purchasePrice == 0.0) ln.purchasePrice = prevPurchase;
        ln.salePrice = suggestedSale;
      }
    });
  }

  // Búsqueda superior
  List<QueryDocumentSnapshot> get _filteredProducts {
    if ((_products == null) || (_products!.isEmpty)) return [];
    final q = productFilterCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _products!;
    return _products!.where((p) {
      final d = p.data() as Map<String, dynamic>;
      final name = (d['name'] as String? ?? '').toLowerCase();
      final desc = (d['description'] as String? ?? '').toLowerCase();
      final sku = (d['sku'] as String? ?? '').toLowerCase();
      return name.contains(q) || desc.contains(q) || sku.contains(q);
    }).toList();
  }

  void _addFromQuickList(QueryDocumentSnapshot p) {
    final d = p.data() as Map<String, dynamic>;
    final id = p.id;
    final purchase = _toDouble(d['purchasePrice']);
    final margin = _toDouble(d['marginPercent'] ?? 10);
    final suggestedSale = purchase * (1 + (margin / 100));
    setState(() {
      _lines.insert(
        0,
        IngresoLine(
          productId: id,
          purchasePrice: purchase,
          salePrice: suggestedSale,
          qty: 1,
        ),
      );
    });
    productFilterCtrl.clear();
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

  // ==== Modal: crear producto rápido (reutilizable dentro de ingresos)
  Future<String?> _showNewProductModal({String? suggestedName, int? defaultStock}) async {
    final nameCtrl = TextEditingController(text: suggestedName ?? '');
    final skuCtrl = TextEditingController(text: await _generateNextSku());
    final purchaseCtrl = TextEditingController();
    final marginCtrl = TextEditingController(text: '10');
    final priceCtrl = TextEditingController();
    final unitsCtrl = TextEditingController(text: '1');
    String pharmForm = '';
    String route = '';
    String strength = '';
    String presentation = '';
    String lot = '';
    DateTime? expiry;
    bool taxable = false;
    bool requiresRx = false;
    String? providerId;

    final formKey = GlobalKey<FormState>();

    final res = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          Widget labeled(Widget child) => Padding(padding: const EdgeInsets.symmetric(vertical: 6.0), child: child);
          return AlertDialog(
            title: Text('Nuevo producto'),
            content: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    labeled(TextFormField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre *'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null)),
                    labeled(TextFormField(controller: skuCtrl, decoration: const InputDecoration(labelText: 'SKU *'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null)),
                    labeled(TextFormField(controller: purchaseCtrl, keyboardType: TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Precio compra (sin IVA)'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null)),
                    labeled(TextFormField(controller: marginCtrl, keyboardType: TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Margen %'))),
                    labeled(Row(children: [
                      Expanded(child: TextFormField(controller: priceCtrl, keyboardType: TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Precio venta (opcional)'))),
                      const SizedBox(width: 8),
                      Expanded(child: TextFormField(controller: unitsCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Unidades/emp'))),
                    ])),
                    labeled(DropdownButtonFormField<String>(value: providerId, decoration: const InputDecoration(labelText: 'Proveedor (opcional)'), items: (_providersList ?? []).map((p) => DropdownMenuItem(value: p.id, child: Text((p.data() as Map<String, dynamic>)['name'] ?? '—'))).toList(), onChanged: (v) => setLocal(() => providerId = v))),
                    labeled(TextFormField(controller: TextEditingController(text: lot), decoration: const InputDecoration(labelText: 'Lote (opcional)'), onChanged: (v) => lot = v)),
                    labeled(Row(children: [
                      Expanded(
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Vencimiento (opcional)'),
                          child: Text(expiry != null ? _fmtDate(expiry!) : '—'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        children: [
                          TextButton(
                            onPressed: () async {
                              final now = DateTime.now();
                              final d = await showDatePicker(context: context, initialDate: expiry ?? now, firstDate: DateTime(now.year - 5), lastDate: DateTime(now.year + 15));
                              if (d != null) setLocal(() => expiry = d);
                            },
                            child: const Text('Seleccionar'),
                          ),
                          // Botón para limpiar la fecha seleccionada
                          if (expiry != null)
                            TextButton(
                              onPressed: () => setLocal(() => expiry = null),
                              child: const Text('Borrar'),
                            ),
                        ],
                      ),
                    ])),
                    labeled(TextFormField(controller: TextEditingController(text: strength), decoration: const InputDecoration(labelText: 'Concentración (opcional)'), onChanged: (v) => strength = v)),
                    labeled(TextFormField(controller: TextEditingController(text: presentation), decoration: const InputDecoration(labelText: 'Presentación (opcional)'), onChanged: (v) => presentation = v)),
                    labeled(DropdownButtonFormField<String>(value: pharmForm.isNotEmpty ? pharmForm : null, decoration: const InputDecoration(labelText: 'Forma'), items: const ['Tableta','Cápsula','Jarabe','Gotas','Suspensión','Ungüento','Crema','Solución inyectable','Aerosol','Parche'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setLocal(() => pharmForm = v ?? ''))),
                    labeled(DropdownButtonFormField<String>(value: route.isNotEmpty ? route : null, decoration: const InputDecoration(labelText: 'Vía'), items: const ['Oral','Tópica','Oftálmica','Intravenosa','Intramuscular','Subcutánea','Rectal','Vaginal','Inhalatoria'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setLocal(() => route = v ?? ''))),
                    labeled(Row(children: [
                      Checkbox(value: taxable, onChanged: (v) => setLocal(() => taxable = v ?? false)),
                      const SizedBox(width: 6),
                      const Text('Grava IVA'),
                      const SizedBox(width: 16),
                      Checkbox(value: requiresRx, onChanged: (v) => setLocal(() => requiresRx = v ?? false)),
                      const SizedBox(width: 6),
                      const Text('Bajo receta'),
                    ])),
                  ]),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancelar')),
              ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('Guardar'),
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  // crear producto (rápido)
                  final payload = {
  'name': nameCtrl.text.trim(),
  'sku': skuCtrl.text.trim(),
  'purchasePrice': double.tryParse(purchaseCtrl.text.replaceAll(',', '.')) ?? 0.0,
  'marginPercent': double.tryParse(marginCtrl.text.replaceAll(',', '.')) ?? 10,
  'price': double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0.0,
  'stock': defaultStock ?? 0,
  'lot': lot.trim().isEmpty ? null : lot.trim(),
  // uso de expiry! para garantizar al compilador que no es null en la rama verdadera
  'expiryDate': expiry != null ? Timestamp.fromDate(expiry!) : null,
  'pharmForm': pharmForm,
  'route': route,
  'strength': strength,
  'presentation': presentation,
  'taxable': taxable,
  'requiresPrescription': requiresRx,
  'providerId': providerId,
  'unitsPerPack': int.tryParse(unitsCtrl.text) ?? 1,
  'createdAt': FieldValue.serverTimestamp(),
  'batchesCount': lot.trim().isEmpty ? 0 : 1,
  'lastLot': lot.trim().isEmpty ? null : lot.trim(),
  'lastExpiry': expiry != null ? Timestamp.fromDate(expiry!) : null,
};

try {
  final docRef = await productsRef.add(payload);
  Navigator.pop(ctx, docRef.id);
} catch (e) {
  _showSnack('Error creando producto: $e');
}

                },
              ),
            ],
          );
        });
      },
    );

    return res;
  }

  // ====== GUARDAR ingreso con batches (mejorado) ======
  Future<void> _save() async {
    if (_products == null) {
      _showSnack('Cargando productos...');
      return;
    }
    if (_lines.isEmpty) {
      _showSnack('Agrega al menos un producto.');
      return;
    }

    // Validaciones por línea
    for (var i = 0; i < _lines.length; i++) {
      final l = _lines[i];
      if (!l.isNew && (l.productId == null || l.productId!.isEmpty)) {
        _showSnack('Selecciona un producto en la fila ${i + 1}');
        return;
      }
      if (l.isNew && l.newName.trim().isEmpty) {
        _showSnack('Escribe el nombre del producto nuevo en la fila ${i + 1}');
        return;
      }
      if (l.qty <= 0) {
        _showSnack('Cantidad inválida en la fila ${i + 1}');
        return;
      }
      if (l.purchasePrice < 0) {
        _showSnack('Precio de compra inválido en la fila ${i + 1}');
        return;
      }
    }

    setState(() => _loading = true);

    try {
      // 1) Pre-crear productos nuevos (fuera de la transacción para obtener ids)
      for (final l in _lines.where((x) => x.isNew)) {
        final newRef = productsRef.doc();
        await newRef.set({
          'name': l.newName.trim(),
          'sku': l.newSku.trim(),
          'purchasePrice': l.purchasePrice,
          'marginPercent': 10,
          'price': l.salePrice,
          'stock': 0,
          'pharmForm': '',
          'route': '',
          'strength': '',
          'presentation': '',
          'createdAt': FieldValue.serverTimestamp(),
          // campos nuevos de resumen
          'lastLot': l.lot.trim().isEmpty ? null : l.lot.trim(),
          'lastExpiry': l.expiryDate != null ? Timestamp.fromDate(l.expiryDate!) : null,
          'batchesCount': 0,
        });
        l.productId = newRef.id;
        l.isNew = false;
      }

      // 2) Preparar ingreso (crear doc)
      final ingresoRef = ingresosRef.doc();
      final itemsForDb = <Map<String, dynamic>>[];

      final providerId = providerCtrl.text.trim().isNotEmpty
          ? providerCtrl.text.trim()
          : (_providersList != null && _providersList!.isNotEmpty ? _providersList!.first.id : null);

      // 3) Pre-buscar batches por lote para cada línea (reduce riesgo de duplicado)
      final Map<String, String?> preBatchInfo = {}; // clave: productId#lineIndex -> batchId
      for (var i = 0; i < _lines.length; i++) {
        final l = _lines[i];
        final prodId = l.productId!;
        final lote = l.lot.trim();
        String key = '$prodId#$i';
        preBatchInfo[key] = null;
        if (lote.isNotEmpty) {
          final q = await productsRef.doc(prodId).collection('batches').where('lot', isEqualTo: lote).limit(1).get();
          if (q.docs.isNotEmpty) preBatchInfo[key] = q.docs.first.id;
        }
      }

      // 4) Ejecutar transacción: crea/actualiza batches y actualiza stock + crea ingreso
      await FirebaseFirestore.instance.runTransaction((tx) async {
        // Validar existencia de productos
        for (final l in _lines) {
          final prodRef = productsRef.doc(l.productId);
          final prodSnap = await tx.get(prodRef);
          if (!prodSnap.exists) throw Exception('Producto no encontrado: ${l.productId}');
        }

        // Procesar cada línea
        for (var i = 0; i < _lines.length; i++) {
          final l = _lines[i];
          final prodRef = productsRef.doc(l.productId);
          final prodSnap = await tx.get(prodRef);
          final prodData = prodSnap.data() as Map<String, dynamic>? ?? {};

          final lote = l.lot.trim();
          String? key = '${l.productId}#$i';
          String? batchId = preBatchInfo[key];

          if (batchId != null) {
            // actualizar batch existente
            final batchRef = prodRef.collection('batches').doc(batchId);
            tx.update(batchRef, {
              'qty': FieldValue.increment(l.qty),
              if (l.expiryDate != null) 'expiry': Timestamp.fromDate(l.expiryDate!),
              'purchasePrice': l.purchasePrice,
              'ingresoId': ingresoRef.id,
            });
          } else {
            // crear nuevo batch
            final newBatchRef = prodRef.collection('batches').doc();
            tx.set(newBatchRef, {
              'lot': lote.isEmpty ? null : lote,
              'qty': l.qty,
              'expiry': l.expiryDate != null ? Timestamp.fromDate(l.expiryDate!) : null,
              'purchasePrice': l.purchasePrice,
              'ingresoId': ingresoRef.id,
              'createdAt': FieldValue.serverTimestamp(),
            });
            batchId = newBatchRef.id;

            // incrementar batchesCount si aplica
            final prevCount = (prodData['batchesCount'] is int) ? prodData['batchesCount'] as int : 0;
            tx.update(prodRef, {
              'batchesCount': prevCount + 1,
            });
          }

          // actualizar producto (stock y precios y resumen)
          tx.update(prodRef, {
            'stock': FieldValue.increment(l.qty),
            'purchasePrice': l.purchasePrice,
            'price': l.salePrice,
            'lastPurchaseAt': FieldValue.serverTimestamp(),
            'lastLot': lote.isEmpty ? FieldValue.delete() : lote,
            'lastExpiry': l.expiryDate != null ? Timestamp.fromDate(l.expiryDate!) : FieldValue.delete(),
          });

          // preparar item para ingreso
          itemsForDb.add({
            'productId': l.productId,
            'qty': l.qty,
            'purchasePrice': l.purchasePrice,
            'salePrice': l.salePrice,
            'subtotal': l.subtotal,
            'lot': lote.isEmpty ? null : lote,
            'manufactureDate': l.manufactureDate != null ? Timestamp.fromDate(l.manufactureDate!) : null,
            'expiryDate': l.expiryDate != null ? Timestamp.fromDate(l.expiryDate!) : null,
            'batchId': batchId,
          });
        }

        // Crear documento de ingreso
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
      _loadData();
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
      final baseName = l.isNew ? l.newName : (_prodMap[l.productId]?['name'] ?? 'Producto');
      final lotPart = (l.lot.trim().isNotEmpty ? 'Lote: ${l.lot.trim()}' : '');
      final expiryPart = (l.expiryDate != null ? 'Vence: ${_fmtDate(l.expiryDate!)}' : '');
      final extra = [lotPart, expiryPart].where((s) => s.isNotEmpty).join(' • ');
      final displayName = extra.isEmpty ? baseName : '$baseName  ($extra)';
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
                        Text('Gestión de Compras',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kGreen1)),
                        const SizedBox(height: 12),

                        // Filtro superior + agregar línea vacía + botón "Nuevo producto" global
                        Row(children: [
                          Expanded(
                            child: TextField(
                              controller: productFilterCtrl,
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.search),
                                labelText: 'Buscar producto (nombre, SKU, descripción)',
                                filled: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Wrap para evitar amontonamiento de botones en pantallas pequeñas
                          Wrap(
                            spacing: 8,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _addEmptyLine,
                                icon: const Icon(Icons.add),
                                label: const Text('Agregar línea'),
                                style: ElevatedButton.styleFrom(backgroundColor: kGreen2, foregroundColor: Colors.white),
                              ),
                              ElevatedButton.icon(
                                onPressed: () async {
                                  final newId = await _showNewProductModal();
                                  if (newId != null) {
                                    await _loadData();
                                    _showSnack('Producto creado y listo para seleccionar.');
                                  }
                                },
                                icon: const Icon(Icons.add_box_outlined),
                                label: const Text('Nuevo producto'),
                                style: ElevatedButton.styleFrom(backgroundColor: kGreen2, foregroundColor: Colors.white),
                              ),
                            ],
                          ),
                        ]),

                        if (productFilterCtrl.text.trim().isNotEmpty) const SizedBox(height: 8),
                        if (productFilterCtrl.text.trim().isNotEmpty)
                          Container(
                            constraints: const BoxConstraints(maxHeight: 220),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _filteredProducts.length,
                              itemBuilder: (context, i) {
                                final p = _filteredProducts[i];
                                final d = p.data() as Map<String, dynamic>;
                                final stock = _toInt(d['stock']);
                                final purchase = _toDouble(d['purchasePrice']);
                                return ListTile(
                                  title: Text((d['name'] as String?) ?? p.id, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(
                                    'SKU: ${(d['sku'] ?? '—')}  •  Stock: $stock  •  Compra: \$${purchase.toStringAsFixed(2)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: ElevatedButton(
                                    onPressed: () => _addFromQuickList(p),
                                    style: ElevatedButton.styleFrom(foregroundColor: Colors.white),
                                    child: const Text('Agregar'),
                                  ),
                                  onTap: () => _addFromQuickList(p),
                                );
                              },
                            ),
                          ),

                        const SizedBox(height: 12),

                        // Encabezado (solo en pantallas medianas/anchas)
                        if (isWide)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
                            child: Row(children: const [
                              Expanded(child: Text('Producto')),
                              SizedBox(width: 80, child: Text('Cant.')),
                              SizedBox(width: 140, child: Text('Compra')),
                              SizedBox(width: 140, child: Text('Venta sug.')),
                              SizedBox(width: 40, child: Text('')),
                            ]),
                          ),
                        if (isWide) const SizedBox(height: 8),

                        // Líneas
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _lines.length,
                          itemBuilder: (context, idx) => _lineTile(_lines[idx], idx, isWide),
                        ),

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

  // ====== Tile de línea (responsivo + modo selector o nuevo) ======
  Widget _lineTile(IngresoLine ln, int idx, bool isWide) {
    final nameForExisting = ln.productId != null ? (_prodMap[ln.productId]?['name'] ?? 'Producto') : 'Producto';
    final titleText = ln.isNew ? 'Nuevo producto' : nameForExisting;

    final productSelector = DropdownButtonFormField<String>(
      value: ln.productId,
      items: (_products ?? []).map((p) {
        final d = p.data() as Map<String, dynamic>;
        final stock = _toInt(d['stock']);
        final label = '${d['name'] ?? '—'} • ${d['sku'] ?? '—'} • Stock: $stock';
        return DropdownMenuItem(value: p.id, child: Text(label, overflow: TextOverflow.ellipsis));
      }).toList(),
      onChanged: (v) => _onChooseProduct(idx, v),
      decoration: const InputDecoration(labelText: 'Producto', border: InputBorder.none),
    );

    final productNewFields = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          initialValue: ln.newName,
          decoration: const InputDecoration(labelText: 'Nombre del nuevo producto *', border: InputBorder.none),
          onChanged: (v) => ln.newName = v,
        ),
        const SizedBox(height: 6),
        TextFormField(
          initialValue: ln.newSku,
          decoration: const InputDecoration(labelText: 'SKU (opcional)', border: InputBorder.none),
          onChanged: (v) => ln.newSku = v,
        ),
      ],
    );

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: ln.isNew ? productNewFields : productSelector),
          const SizedBox(width: 8),
          Column(children: [
            // Botón para alternar "Nuevo" (inline)
            TextButton.icon(
              onPressed: () async {
                if (!ln.isNew) {
                  // Abrir modal de nuevo producto pre-llenando nombre sugerido (si hay producto seleccionado)
                  final suggested = ln.productId != null ? (_prodMap[ln.productId]?['name'] ?? '') : '';
                  final newId = await _showNewProductModal(suggestedName: suggested);
                  if (newId != null) {
                    // reload products and select new created in this line
                    await _loadData();
                    setState(() {
                      ln.productId = newId;
                      ln.isNew = false;
                    });
                    _showSnack('Producto creado y seleccionado.');
                  }
                } else {
                  // Toggle a usar existente
                  setState(() {
                    ln.isNew = !ln.isNew;
                    if (ln.isNew) ln.productId = null;
                  });
                }
              },
              icon: Icon(ln.isNew ? Icons.undo : Icons.add_box_outlined),
              label: Text(ln.isNew ? 'Usar existente' : 'Nuevo'),
            ),
            // NOTE: Eliminado botón duplicado "Nuevo producto" para evitar UI confusa.
          ]),
        ]),
        if (!ln.isNew && ln.productId != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.info_outline),
              onPressed: () => _showProductDetails(ln.productId!),
              label: const Text('Detalles'),
            ),
          ),
      ],
    );

    final right = Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 90,
          child: TextFormField(
            initialValue: ln.qty.toString(),
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Cant.', border: InputBorder.none),
            onChanged: (v) => setState(() => ln.qty = int.tryParse(v) ?? ln.qty),
          ),
        ),
        SizedBox(
          width: 130,
          child: TextFormField(
            initialValue: ln.purchasePrice.toStringAsFixed(2),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Compra', border: InputBorder.none),
            onChanged: (v) {
              setState(() {
                ln.purchasePrice = _toDouble(v);
                final margin = 10.0;
                if (ln.salePrice == 0) {
                  ln.salePrice = ln.purchasePrice * (1 + (margin / 100));
                }
              });
            },
          ),
        ),
        SizedBox(
          width: 130,
          child: TextFormField(
            initialValue: ln.salePrice.toStringAsFixed(2),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Venta sug.', border: InputBorder.none),
            onChanged: (v) => setState(() => ln.salePrice = _toDouble(v)),
          ),
        ),
        SizedBox(
          width: 120,
          child: TextFormField(
            initialValue: ln.lot,
            keyboardType: TextInputType.text,
            decoration: const InputDecoration(labelText: 'Lote', border: InputBorder.none),
            onChanged: (v) => setState(() => ln.lot = v),
          ),
        ),
        IconButton(onPressed: () => _removeLine(idx), icon: const Icon(Icons.delete_outline)),
      ],
    );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: isWide
            ? Column(children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: left),
                  const SizedBox(width: 8),
                  right,
                ]),
                const SizedBox(height: 8),
                // Fechas y subtotal
                Row(children: [
                  Expanded(
                    child: Text(ln.manufactureDate == null ? 'Fab.: —' : 'Fab.: ${_fmtDate(ln.manufactureDate!)}'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(ln.expiryDate == null ? 'Vence: —' : 'Vence: ${_fmtDate(ln.expiryDate!)}')),
                  TextButton(onPressed: () => _pickDateForLine(idx, isManufacture: true), child: const Text('Fab.')),
                  TextButton(onPressed: () => _pickDateForLine(idx, isManufacture: false), child: const Text('Vence')),
                  const SizedBox(width: 12),
                  Text('Subtotal: \$${ln.subtotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ]),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titleText, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                left,
                const SizedBox(height: 8),
                right,
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: Text('Subtotal: \$${ln.subtotal.toStringAsFixed(2)}', textAlign: TextAlign.right)),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(child: Text(ln.manufactureDate == null ? 'Fab.: —' : 'Fab.: ${_fmtDate(ln.manufactureDate!)}')),
                  TextButton(onPressed: () => _pickDateForLine(idx, isManufacture: true), child: const Text('Seleccionar')),
                  const SizedBox(width: 8),
                  Expanded(child: Text(ln.expiryDate == null ? 'Vence: —' : 'Vence: ${_fmtDate(ln.expiryDate!)}')),
                  TextButton(onPressed: () => _pickDateForLine(idx, isManufacture: false), child: const Text('Seleccionar')),
                ]),
              ]),
      ),
    );
  }

  Future<void> _pickDateForLine(int idx, {required bool isManufacture}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null) return;
    setState(() {
      if (isManufacture) {
        _lines[idx].manufactureDate = picked;
      } else {
        _lines[idx].expiryDate = picked;
      }
    });
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
