import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// ⬇️ Salida PDF multiplataforma: móvil/escritorio vs web
import 'pdf_output_mobile.dart'
    if (dart.library.html) 'pdf_output_web.dart' as pdf_out;

import 'app_theme.dart';
import 'invoice_pdf.dart'; // utilitario que construye el PDF

class EgresoFormWidget extends StatefulWidget {
  const EgresoFormWidget({super.key});

  @override
  State<EgresoFormWidget> createState() => _EgresoFormWidgetState();
}

class SaleLine {
  String productId;
  String name;
  bool taxable;
  double ivaPercent;
  int stock;
  int qty;
  double unitPriceWithoutVat;
  double unitPriceWithVat; // unit price INCLUYE IVA
  double discountPercent; // porcentaje de descuento aplicado

  SaleLine({
    required this.productId,
    required this.name,
    required this.taxable,
    required this.ivaPercent,
    required this.stock,
    this.qty = 1,
    required this.unitPriceWithoutVat,
    required this.unitPriceWithVat,
    this.discountPercent = 0.0,
  });

  double get subtotal => unitPriceWithVat * qty;
}

class _EgresoFormWidgetState extends State<EgresoFormWidget> {
  final productsRef = FirebaseFirestore.instance.collection('products');
  final salesRef = FirebaseFirestore.instance.collection('egresos');

  List<QueryDocumentSnapshot>? _products;
  Map<String, Map<String, dynamic>> _pmap = {};

  final searchCtrl = TextEditingController();
  final buyerCtrl = TextEditingController();
  final notesCtrl = TextEditingController();

  bool _loading = false;
  bool _recipeChecked = false;

  final List<SaleLine> _lines = [];

  @override
  void initState() {
    super.initState();
    _loadProducts();
    searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    buyerCtrl.dispose();
    notesCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tryAddFromCarouselOnce();
  }

  // ========= Carga inicial / carrusel =========

  Future<void> _loadProducts() async {
    final snap = await productsRef.orderBy('name').get();
    _products = snap.docs;
    _pmap = {for (final d in snap.docs) d.id: (d.data() as Map<String, dynamic>)};
    if (mounted) setState(() {});
  }

  bool _handledArgs = false;
  Future<void> _tryAddFromCarouselOnce() async {
    if (_handledArgs) return;
    _handledArgs = true;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['from'] == 'carousel' && args['productId'] != null) {
      final pid = args['productId'] as String;
      if (_products == null) await _loadProducts();
      final pdata = await _fetchProduct(pid);
      if (pdata == null) return;

      final requiresRx = (pdata['requiresPrescription'] ?? false) == true;
      final discountPct = await _bestDiscountFor(pid, pdata);

      // Calculamos precio de venta (partiendo de precio SIN IVA) + aplicamos descuento y luego IVA
      final priceWithoutVat = _computeSaleUnitPrice(pdata, discountPct);
      final ivaPercent = _toDouble(pdata['ivaPercent'] ?? 13);
      final taxable = (pdata['taxable'] ?? false) == true;
      final priceWithVat =
          taxable ? priceWithoutVat * (1 + ivaPercent / 100) : priceWithoutVat;

      _addLine(
        productId: pid,
        name: pdata['name'] ?? 'Producto',
        unitPriceWithoutVat: priceWithoutVat,
        unitPriceWithVat: priceWithVat,
        stock: _toInt(pdata['stock']),
        taxable: (pdata['taxable'] ?? false) == true,
        ivaPercent: _toDouble(pdata['ivaPercent'] ?? 13),
        discountPct: discountPct,
      );

      if (requiresRx) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showSnack('Este producto es de venta bajo receta médica.');
        });
      }
      setState(() {});
    }
  }

  Future<Map<String, dynamic>?> _fetchProduct(String id) async {
    if (_pmap.containsKey(id)) return _pmap[id];
    final doc = await productsRef.doc(id).get();
    if (!doc.exists) return null;
    final data = doc.data() as Map<String, dynamic>;
    _pmap[id] = data;
    return data;
  }

  // ========= Helpers numéricos / formateo =========

  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString().replaceAll(',', '.') ?? '') ?? 0.0;
  }

  String _fmt(double v) => '\$${v.toStringAsFixed(2)}';
  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  void _showSnack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  /// Estima un descuento a partir de los datos del producto (sin consultar promos).
  /// Prioriza un campo 'discount' si existe; si el producto tiene expiry <= 90 días, devuelve 45.
  double _discountFromData(Map<String, dynamic> d) {
    final explicit = _toDouble(d['discount'] ?? d['discountPct'] ?? 0);
    if (explicit > 0) return explicit;

    final expiry = (d['expiryDate'] as Timestamp?)?.toDate();
    if (expiry != null) {
      final now = DateTime.now();
      if (expiry.difference(now).inDays <= 90) return 45;
    }
    return 0.0;
  }

  // ========= LÓGICA PRECIO DE VENTA (SIN IVA) =========
  //
  // Reglas (inventario almacenado SIN IVA):
  // - 'salePriceNet' o 'salePrice'  -> precio de venta NETO (sin IVA).
  // - Si no existen, 'price' se toma como precio de venta NETO (sin IVA).
  // - Si hay marginPercent/profitMargin/markup, se aplica sobre ese base.
  // - Luego se aplica descuento.
  // - El valor retornado es el precio NETO (sin IVA). El IVA se calcula aparte.
  double _computeSaleUnitPrice(Map<String, dynamic> pdata, double discountPct) {
    // 1) Determinar base neta (sin IVA)
    double baseNet;

    if (pdata.containsKey('salePriceNet')) {
      baseNet = _toDouble(pdata['salePriceNet']);
    } else if (pdata.containsKey('salePrice')) {
      baseNet = _toDouble(pdata['salePrice']);
    } else {
      // Usamos 'price' como precio neto o costo + margen
      final priceField = _toDouble(pdata['price']);
      final margin =
          _toDouble(pdata['marginPercent'] ?? pdata['profitMargin'] ?? pdata['markup'] ?? 0);
      if (margin != 0) {
        // priceField como costo y margin como % de ganancia
        baseNet = priceField * (1 + margin / 100);
      } else {
        // si no hay margen, tomamos 'price' directamente como precio NETO de venta
        baseNet = priceField;
      }
    }

    // 2) Aplicar descuento sobre el precio neto
    if (discountPct > 0) {
      baseNet = baseNet * (1 - discountPct / 100);
    }

    // Resultado: precio NETO sin IVA
    return baseNet;
  }

  // ========= Descuentos =========

  Future<double> _bestDiscountFor(String productId, Map<String, dynamic> pdata) async {
    double best = 0;

    final now = DateTime.now();
    final promosSnap = await FirebaseFirestore.instance
        .collection('promotions')
        .where('productId', isEqualTo: productId)
        .get();

    for (final doc in promosSnap.docs) {
      final d = doc.data();
      final start = (d['startDate'] as Timestamp?)?.toDate();
      final end = (d['endDate'] as Timestamp?)?.toDate();
      if (start != null && end != null && now.isAfter(start) && now.isBefore(end)) {
        final pct = _toDouble(d['discount']);
        if (pct > best) best = pct;
      }
    }

    // Próximo a vencer (<= 90 días) → 45%
    final expiry = (pdata['expiryDate'] as Timestamp?)?.toDate();
    if (expiry != null) {
      if (expiry.difference(now).inDays <= 90) {
        if (45 > best) best = 45;
      }
    }
    return best;
  }

  // ========= Filtro =========

  List<QueryDocumentSnapshot> get _filtered {
    if (_products == null) return const [];
    final q = searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _products!.where((p) {
      final d = p.data() as Map<String, dynamic>;
      final name = (d['name'] ?? '').toString().toLowerCase();
      final desc = (d['description'] ?? '').toString().toLowerCase();
      final sku = (d['sku'] ?? '').toString().toLowerCase();
      return name.contains(q) || desc.contains(q) || sku.contains(q);
    }).toList();
  }

  // ========= Líneas =========

  void _addLine({
    required String productId,
    required String name,
    required double unitPriceWithoutVat,
    required double unitPriceWithVat,
    required int stock,
    required bool taxable,
    required double ivaPercent,
    double discountPct = 0,
  }) {
    final i = _lines.indexWhere((l) => l.productId == productId);
    if (i >= 0) {
      final l = _lines[i];
      if (l.qty < stock) l.qty += 1;
      setState(() {});
      return;
    }
    _lines.insert(
      0,
      SaleLine(
        productId: productId,
        name: name,
        unitPriceWithoutVat: unitPriceWithoutVat,
        unitPriceWithVat: unitPriceWithVat,
        stock: stock,
        taxable: taxable,
        ivaPercent: ivaPercent,
        discountPercent: discountPct,
      ),
    );
    setState(() {});
  }

  void _removeLine(int i) {
    _lines.removeAt(i);
    setState(() {});
  }

  void _clearAll() {
    setState(() {
      _lines.clear();
      buyerCtrl.clear();
      notesCtrl.clear();
      _recipeChecked = false;
      searchCtrl.clear();
    });
  }

  double get _total => _lines.fold(0.0, (s, l) => s + l.subtotal);

  // _ivaTotal asume que l.unitPrice incluye IVA (por eso despejamos la porción IVA)
  double get _ivaTotal => _lines.fold(
      0.0,
      (s, l) =>
          s +
          (l.taxable
              ? (l.unitPriceWithVat - l.unitPriceWithoutVat) * l.qty
              : 0.0));

  double get _subtotalSinIVA =>
      _lines.fold(0.0, (s, l) => s + l.unitPriceWithoutVat * l.qty);

  // Por ahora consideramos que el IVA retenido es igual al IVA generado.
  // Si más adelante la retención es un porcentaje diferente, aquí se ajusta.
  double get _ivaRetenido => _ivaTotal;

  bool _anyRequiresRecipe() {
    for (final l in _lines) {
      final p = _pmap[l.productId];
      if (p != null && (p['requiresPrescription'] ?? false) == true) return true;
      }
    return false;
  }

  // ========= PDF =========

  Future<void> _printCurrentInvoice({String? saleId, DateTime? when}) async {
    if (_lines.isEmpty) {
      _showSnack('No hay productos para imprimir.');
      return;
    }
    final buyer =
        buyerCtrl.text.trim().isEmpty ? 'Consumidor final' : buyerCtrl.text.trim();
    final now = when ?? DateTime.now();

    // Nota: por petición, el PDF mostrará el total y dejará la línea IVA en 0 para evitar confusiones
    final pdfBytes = await InvoicePdf.build(
      logoAssetPath: kPharmaLogoPath,
      invoiceNumber: saleId ?? 'N/A',
      date: now,
      buyer: buyer,
      notes: notesCtrl.text.trim(),
      items: _lines
          .map((l) => InvoiceItem(
                name: l.name,
                qty: l.qty,
                unitPrice: l.unitPrice,
                subtotal: l.subtotal,
              ))
          .toList(),
      subtotal: _total, // mostramos el total directamente para que el cliente vea lo cobrado
      iva: 0.0, // forzar 0 en la línea IVA en el PDF (según tu requerimiento)
      total: _total,
    );

    await pdf_out.outputPdf(pdfBytes, 'factura_${saleId ?? "venta"}.pdf');
  }

  // ========= Guardar (transaccional, crea 'egresos' y 'movements') =========

  Future<void> _save() async {
    if (_lines.isEmpty) {
      _showSnack('Agrega al menos un producto.');
      return;
    }
    if (_anyRequiresRecipe() && !_recipeChecked) {
      _showSnack('Confirma la receta médica con el botón deslizante.');
      return;
    }

    setState(() => _loading = true);
    try {
      late String createdId;
      final nowWhen = DateTime.now();

      await FirebaseFirestore.instance.runTransaction((tx) async {
        // 1) Obtener/inicializar contador
        final counterRef =
            FirebaseFirestore.instance.collection('counters').doc('egresos');
        final counterSnap = await tx.get(counterRef);

        int nextNumber;
        if (counterSnap.exists) {
          final data = counterSnap.data() as Map<String, dynamic>;
          nextNumber = (data['next'] ?? 1000) as int;
        } else {
          nextNumber = 1000; // inicia en 1000
        }

        // 2) Usar ese número como ID del egreso
        createdId = nextNumber.toString();
        final egresoDocRef = salesRef.doc(createdId);

        // 3) Preparar items con stockBefore/After y validaciones
        final List<Map<String, dynamic>> itemsForSave = [];
        for (final l in _lines) {
          final prodRef = productsRef.doc(l.productId);
          final prodSnap = await tx.get(prodRef);
          if (!prodSnap.exists) {
            throw Exception('Producto no encontrado: ${l.name}');
          }
          final prodData = prodSnap.data() as Map<String, dynamic>;
          final currentStock = _toInt(prodData['stock']);
          if (l.qty > currentStock) {
            throw Exception(
                'Stock insuficiente para "${l.name}". Disponible: $currentStock');
          }
          final stockAfter = currentStock - l.qty;

          itemsForSave.add({
            'productId': l.productId,
            'productName': l.name,
            'qty': l.qty,
            'unitPriceWithoutVat': l.unitPriceWithoutVat,
            'unitPriceWithVat': l.unitPriceWithVat, // incluye IVA
            'subtotal': l.subtotal,
            'taxable': l.taxable,
            'ivaPercent': l.ivaPercent,
            'discountPercent': l.discountPercent, // guardamos el descuento aplicado
            'stockBefore': currentStock,
            'stockAfter': stockAfter,
            'sku': prodData['sku'] ?? '',
          });
        }

        // 4) Guardar egreso
        tx.set(egresoDocRef, {
          'number': nextNumber,
          'userId': FirebaseAuth.instance.currentUser?.uid,
          'buyer': buyerCtrl.text.trim().isEmpty
              ? 'Consumidor final'
              : buyerCtrl.text.trim(),
          'notes': notesCtrl.text.trim(),
          'items': itemsForSave,
          'subtotal': _subtotalSinIVA,
          'ivaTotal': _ivaTotal,
          'ivaRetenido': _ivaRetenido,
          'total': _total,
          'createdAt': FieldValue.serverTimestamp(),
          'recipeChecked': _anyRequiresRecipe() ? _recipeChecked : null,
        });

        // 5) Actualizar stock
        for (final it in itemsForSave) {
          final ref = productsRef.doc(it['productId'] as String);
          tx.update(ref, {
            'stock': it['stockAfter'],
            'lastSaleAt': FieldValue.serverTimestamp(),
          });
        }

        // 6) Crear resumen en 'movements' (para que MovementsManager lo muestre)
        final movementsRef =
            FirebaseFirestore.instance.collection('movements');
        final movementDocRef = movementsRef.doc();

        final currentUser = FirebaseAuth.instance.currentUser;
        final createdByName =
            currentUser?.displayName ?? currentUser?.email ?? 'Usuario';

        tx.set(movementDocRef, {
          'type': 'egreso',
          'egresoId': createdId,
          'createdAt': FieldValue.serverTimestamp(),
          'createdByUid': currentUser?.uid,
          'createdByName': createdByName,
          'note': notesCtrl.text.trim(),
          'counterpartyType': 'cliente',
          'counterpartyName': buyerCtrl.text.trim().isEmpty
              ? 'Consumidor final'
              : buyerCtrl.text.trim(),
          'totalItems':
              itemsForSave.fold<int>(0, (s, it) => s + (it['qty'] as int)),
          'totalAmount': _total,
          'ivaTotal': _ivaTotal,
          'ivaRetenido': _ivaRetenido,
          'items': itemsForSave,
          'recipeChecked': _anyRequiresRecipe() ? _recipeChecked : null,
        });

        // 7) Incrementar contador
        if (counterSnap.exists) {
          tx.update(counterRef, {'next': nextNumber + 1});
        } else {
          tx.set(counterRef, {'next': nextNumber + 1});
        }
      });

      _showSnack('Venta registrada.');
      await _printCurrentInvoice(saleId: createdId, when: nowWhen);

      // Si la forma está embebida en el Dashboard: limpiar, si fue push: pop con resultado.
      if (mounted) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context, {'createdId': createdId});
        } else {
          _clearAll();
        }
      }
    } catch (e) {
      _showSnack('No se pudo registrar la venta: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ========= UI =========

  @override
  Widget build(BuildContext context) {
    // detectamos si ya hay un Scaffold/Material que provea el "look & feel"
    final hasMaterialAncestor =
        context.findAncestorWidgetOfExactType<Material>() != null;
    final hasScaffoldAncestor =
        context.findAncestorWidgetOfExactType<Scaffold>() != null;

    // El contenido real del formulario (tu Column completo)
    final content = Center(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        // Permitimos que el widget ocupe todo el ancho disponible del Card del Dashboard.
        child: SingleChildScrollView(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // <-- Encabezado removido intencionalmente (lo pediste)
            const SizedBox(height: 4),

            // BUSCADOR
            Container(
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade100),
              ),
              child: TextField(
                controller: searchCtrl,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar producto por nombre, descripción o SKU...',
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
              ),
            ),

            if (_filtered.isNotEmpty) const SizedBox(height: 10),

            // SUGERENCIAS
            if (_filtered.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _filtered.length,
                  itemBuilder: (context, i) {
                    final pdoc = _filtered[i];
                    final d = pdoc.data() as Map<String, dynamic>;
                    final name = (d['name'] ?? 'Producto').toString();
                    // AHORA interpretamos 'price' como precio SIN IVA
                    final displayPriceNet = _toDouble(d['price']);
                    final stock = _toInt(d['stock']);
                    final requiresRx =
                        (d['requiresPrescription'] ?? false) == true;
                    final form = (d['pharmForm'] ?? '').toString();
                    final route = (d['route'] ?? '').toString();
                    final strength = (d['strength'] ?? '').toString();
                    final pres = (d['presentation'] ?? '').toString();

                    final inferredDisc = _discountFromData(d);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 6,
                                    children: [
                                      if (form.isNotEmpty || route.isNotEmpty)
                                        _pill(
                                            '${form.isEmpty ? '—' : form} / ${route.isEmpty ? '—' : route}'),
                                      if (strength.isNotEmpty)
                                        _pill('Conc.: $strength'),
                                      if (pres.isNotEmpty)
                                        _pill('Pres.: $pres'),
                                      _pill('Stock: $stock'),
                                      _pill(
                                          'Precio (sin IVA): ${_fmt(displayPriceNet)}'),
                                      if (inferredDisc > 0)
                                        _pill(
                                            'Oferta: ${inferredDisc.toStringAsFixed(0)}%'),
                                    ],
                                  ),
                                  if (requiresRx) ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: Colors.red.shade300),
                                      ),
                                      child: const Text(
                                        'Este producto requiere receta médica.',
                                        style: TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            children: [
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => _showDetailsDialog(d),
                                child: const Text('Detalles'),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: stock <= 0
                                    ? null
                                    : () async {
                                        final disc =
                                            await _bestDiscountFor(pdoc.id, d);

                                        final priceWithoutVat =
                                            _computeSaleUnitPrice(d, disc);
                                        final ivaPercent =
                                            _toDouble(d['ivaPercent'] ?? 13);
                                        final taxable =
                                            (d['taxable'] ?? false) == true;
                                        final priceWithVat = taxable
                                            ? priceWithoutVat *
                                                (1 + ivaPercent / 100)
                                            : priceWithoutVat;

                                        _addLine(
                                          productId: pdoc.id,
                                          name: name,
                                          unitPriceWithoutVat: priceWithoutVat,
                                          unitPriceWithVat: priceWithVat,
                                          stock: stock,
                                          taxable:
                                              (d['taxable'] ?? false) == true,
                                          ivaPercent:
                                              _toDouble(d['ivaPercent'] ?? 13),
                                          discountPct: disc,
                                        );
                                        searchCtrl.clear();

                                        if (disc > 0) {
                                          _showSnack(
                                              'Se aplicó oferta: ${disc.toStringAsFixed(0)}% sobre $name');
                                        }
                                      },
                                child: const Text('Agregar'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

            const SizedBox(height: 12),

            // ENCABEZADO (solo en ancho medio/alto)
            LayoutBuilder(builder: (context, cons) {
              final isNarrow = cons.maxWidth < 560;
              return Column(children: [
                if (!isNarrow)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 6, horizontal: 8),
                    decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6)),
                    child: Row(children: const [
                      Expanded(child: Text('Producto')),
                      SizedBox(width: 100, child: Text('Cant.')),
                      SizedBox(width: 100, child: Text('Precio')),
                      SizedBox(width: 120, child: Text('Subtotal')),
                      SizedBox(width: 40, child: Text('')),
                    ]),
                  ),
                const SizedBox(height: 8),

                // ÁREA VERDE con las líneas
                Container(
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade100),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: _lines.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(
                                child:
                                    Text('No hay productos agregados.')))
                        : ListView.builder(
                            shrinkWrap: true,
                            physics:
                                const NeverScrollableScrollPhysics(),
                            itemCount: _lines.length,
                            itemBuilder: (context, i) =>
                                _lineTile(_lines[i], isNarrow),
                          ),
                  ),
                ),
              ]);
            }),

            const SizedBox(height: 12),

            // L / C / I  (acciones rápidas)
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _lines.isEmpty &&
                          buyerCtrl.text.isEmpty &&
                          notesCtrl.text.isEmpty
                      ? null
                      : _clearAll,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white),
                  child: const Text('L  •  Limpiar'),
                ),
                ElevatedButton(
                  onPressed: null, // reservado para "C"
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black12,
                      foregroundColor: Colors.black54),
                  child: const Text('C  •  Próximamente'),
                ),
                ElevatedButton(
                  onPressed:
                      _lines.isEmpty ? null : () => _printCurrentInvoice(),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white),
                  child: const Text('I  •  Imprimir PDF'),
                ),
              ],
            ),

            const SizedBox(height: 12),

            TextFormField(
              controller: buyerCtrl,
              decoration: const InputDecoration(
                  labelText: 'Cliente o comprador (opcional)'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: notesCtrl,
              decoration:
                  const InputDecoration(labelText: 'Notas adicionales'),
            ),

            if (_anyRequiresRecipe())
              Padding(
                padding: const EdgeInsets.only(top: 10.0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                          'Hay productos de venta bajo receta en esta venta.',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeColor: kGreen2,
                        title: const Text('Receta médica verificada'),
                        value: _recipeChecked,
                        onChanged: (v) =>
                            setState(() => _recipeChecked = v),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 12),

            // Totales + botón guardar
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Subtotal (sin IVA): ${_fmt(_subtotalSinIVA)}'),
                      Text('IVA: ${_fmt(_ivaTotal)}'),
                      Text('Total: ${_fmt(_total)}',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: kGreen2,
                        foregroundColor: Colors.white),
                    onPressed: _loading ? null : _save,
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Registrar venta'),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );

    // Si ya estamos dentro de un Scaffold/Material del dashboard, devolvemos el contenido tal cual.
    if (hasMaterialAncestor && hasScaffoldAncestor) {
      return content;
    }

    // Si NO hay ancestro Material/Scaffold (p. ej. abriste la ruta directa desde el carrusel),
    // devolvemos el mismo contenido envuelto en Material + Scaffold para que TextField y demás funcionen.
    return Material(
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: kGreen2,
          title: const Text('Generar venta (Egreso)'),
          leading:
              Navigator.canPop(context) ? null : const SizedBox.shrink(),
        ),
        body: SafeArea(child: content),
      ),
    );
  }

  // ====== Item responsivo ======
  Widget _lineTile(SaleLine l, bool isNarrow) {
    if (!isNarrow) {
      // Diseño horizontal (escritorio / tablet)
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  '${l.name}  (Stock: ${l.stock}, ${_fmt(l.unitPriceWithVat)}${l.discountPercent > 0 ? ' • -${l.discountPercent.toStringAsFixed(0)}%' : ''})',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: l.qty,
                    items: List<int>.generate(
                            (l.stock > 50 ? 50 : (l.stock == 0 ? 1 : l.stock)),
                            (x) => x + 1)
                        .map((v) =>
                            DropdownMenuItem(value: v, child: Text('$v')))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => l.qty = v);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 100, child: Text(_fmt(l.unitPriceWithVat))), // ya con IVA
              const SizedBox(width: 8),
              SizedBox(width: 120, child: Text(_fmt(l.subtotal))), // ya con IVA
              IconButton(
                tooltip: 'Quitar',
                onPressed: () => _removeLine(_lines.indexOf(l)),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      );
    }

    // Diseño compacto (móvil)
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.name,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                      child: Text(
                          'Stock: ${l.stock}  •  ${_fmt(l.unitPriceWithVat)}${l.discountPercent > 0 ? ' • -${l.discountPercent.toStringAsFixed(0)}%' : ''}')),
                  IconButton(
                    tooltip: 'Quitar',
                    onPressed: () =>
                        _removeLine(_lines.indexOf(l)),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: l.qty,
                        items: List<int>.generate(
                                (l.stock > 50
                                    ? 50
                                    : (l.stock == 0 ? 1 : l.stock)),
                                (x) => x + 1)
                            .map((v) => DropdownMenuItem(
                                value: v, child: Text('$v')))
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => l.qty = v);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text('Subtotal: ${_fmt(l.subtotal)}',
                          textAlign: TextAlign.right)),
                ],
              ),
            ]),
      ),
    );
  }

  // ====== Detalles ======
  Future<void> _showDetailsDialog(Map<String, dynamic> d) async {
    final name = (d['name'] ?? 'Producto').toString();
    final priceNet = _toDouble(d['price']); // sin IVA
    final stock = _toInt(d['stock']);
    final requiresRx = (d['requiresPrescription'] ?? false) == true;
    final form = (d['pharmForm'] ?? '').toString();
    final route = (d['route'] ?? '').toString();
    final strength = (d['strength'] ?? '').toString();
    final pres = (d['presentation'] ?? '').toString();
    final taxable = (d['taxable'] ?? false) == true;
    final iva = _toDouble(d['ivaPercent'] ?? 13);
    final expiry = (d['expiryDate'] as Timestamp?)?.toDate();

    final inferredDisc = _discountFromData(d);

    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv('Forma/Vía',
                '${form.isEmpty ? '—' : form} / ${route.isEmpty ? '—' : route}'),
            _kv('Concentración', strength.isEmpty ? '—' : strength),
            _kv('Presentación', pres.isEmpty ? '—' : pres),
            _kv('Stock', '$stock'),
            _kv('Precio (sin IVA)', _fmt(priceNet)),
            _kv('IVA', taxable ? '${iva.toStringAsFixed(0)}%' : 'No grava'),
            if (expiry != null) _kv('Vencimiento', _fmtDate(expiry)),
            if (inferredDisc > 0)
              _kv('Oferta', '${inferredDisc.toStringAsFixed(0)}%'),
            if (expiry != null &&
                expiry.difference(DateTime.now()).inDays <= 90)
              _kv('Observación',
                  'Producto próximo a vencer — oferta aplicada'),
            if (requiresRx)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  children: const [
                    Icon(Icons.warning_amber, color: Colors.red),
                    SizedBox(width: 6),
                    Expanded(
                        child: Text('Producto bajo receta médica',
                            style: TextStyle(color: Colors.red))),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6.0),
        child: Row(
          children: [
            SizedBox(
                width: 140,
                child:
                    Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(child: Text(v)),
          ],
        ),
      );

  Widget _pill(String t) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.green.shade300),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(t,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

// Logo a usar desde el egreso
const String kPharmaLogoPath = 'assets/logo.png';
