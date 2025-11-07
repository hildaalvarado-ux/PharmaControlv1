// lib/egreso_form_widget.dart
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
  double unitPrice; 

  SaleLine({
    required this.productId,
    required this.name,
    required this.taxable,
    required this.ivaPercent,
    required this.stock,
    this.qty = 1,
    required this.unitPrice,
  });

  double get subtotal => unitPrice * qty;
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

      final basePrice = _toDouble(pdata['price']);
      final requiresRx = (pdata['requiresPrescription'] ?? false) == true;
      final discountPct = await _bestDiscountFor(pid, pdata);
      final finalPrice = basePrice * (1 - discountPct / 100);

      _addLine(
        productId: pid,
        name: pdata['name'] ?? 'Producto',
        unitPrice: finalPrice,
        stock: _toInt(pdata['stock']),
        taxable: (pdata['taxable'] ?? false) == true,
        ivaPercent: _toDouble(pdata['ivaPercent'] ?? 13),
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
    required double unitPrice,
    required int stock,
    required bool taxable,
    required double ivaPercent,
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
        unitPrice: unitPrice,
        stock: stock,
        taxable: taxable,
        ivaPercent: ivaPercent,
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
  double get _ivaTotal {
    double t = 0;
    for (final l in _lines) {
      if (l.taxable) {
        final divider = 1 + (l.ivaPercent / 100);
        final netUnit = l.unitPrice / divider;
        final ivaUnit = l.unitPrice - netUnit;
        t += ivaUnit * l.qty;
      }
    }
    return t;
  }

  double get _subtotalSinIVA => _total - _ivaTotal;

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
    final buyer = buyerCtrl.text.trim().isEmpty ? 'Consumidor final' : buyerCtrl.text.trim();
    final now = when ?? DateTime.now();

    final pdfBytes = await InvoicePdf.build(
      logoAssetPath: kPharmaLogoPath,          // <-- aquí mandamos 'assets/logo.png'
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
      subtotal: _subtotalSinIVA,
      iva: _ivaTotal,
      total: _total,
    );

    await pdf_out.outputPdf(pdfBytes, 'factura_${saleId ?? "venta"}.pdf');
  }

  // ========= Guardar (con ID incremental desde 1000) =========

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
      late String createdId;               // será el número consecutivo como string
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
        final docRef = salesRef.doc(createdId);

        // 3) Validaciones de stock
        for (final l in _lines) {
          final ref = productsRef.doc(l.productId);
          final snap = await tx.get(ref);
          if (!snap.exists) {
            throw Exception('Producto no encontrado: ${l.name}');
          }
          final currentStock = _toInt((snap.data() as Map<String, dynamic>)['stock']);
          if (l.qty > currentStock) {
            throw Exception('Stock insuficiente para "${l.name}". Disponible: $currentStock');
          }
        }

        // 4) Preparar items
        final items = _lines
            .map((l) => {
                  'productId': l.productId,
                  'name': l.name,
                  'qty': l.qty,
                  'unitPrice': l.unitPrice,
                  'subtotal': l.subtotal,
                  'taxable': l.taxable,
                  'ivaPercent': l.ivaPercent,
                })
            .toList();

        // 5) Guardar egreso con ese ID y el número
        tx.set(docRef, {
          'number': nextNumber, // <--- campo número humano
          'userId': FirebaseAuth.instance.currentUser?.uid,
          'buyer': buyerCtrl.text.trim().isEmpty ? 'Consumidor final' : buyerCtrl.text.trim(),
          'notes': notesCtrl.text.trim(),
          'items': items,
          'subtotal': _subtotalSinIVA,
          'ivaTotal': _ivaTotal,
          'total': _total,
          'createdAt': FieldValue.serverTimestamp(),
          'recipeChecked': _anyRequiresRecipe() ? _recipeChecked : null,
        });

        // 6) Descontar stock
        for (final l in _lines) {
          final ref = productsRef.doc(l.productId);
          tx.update(ref, {
            'stock': FieldValue.increment(-l.qty),
            'lastSaleAt': FieldValue.serverTimestamp(),
          });
        }

        // 7) Incrementar contador
        if (counterSnap.exists) {
          tx.update(counterRef, {'next': nextNumber + 1});
        } else {
          tx.set(counterRef, {'next': nextNumber + 1});
        }
      });

      _showSnack('Venta registrada.');
      // Mostrar/descargar/imprimir PDF con el número como invoiceNumber
      await _printCurrentInvoice(saleId: createdId, when: nowWhen);

      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showSnack('No se pudo registrar la venta: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ========= UI =========

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Generar venta (Egreso)'), backgroundColor: kGreen2),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            // Scroll ÚNICO para evitar overflow
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Generar venta (Egreso)',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kGreen1)),
                  const SizedBox(height: 12),

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
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
                          final price = _toDouble(d['price']);
                          final stock = _toInt(d['stock']);
                          final requiresRx = (d['requiresPrescription'] ?? false) == true;
                          final form = (d['pharmForm'] ?? '').toString();
                          final route = (d['route'] ?? '').toString();
                          final strength = (d['strength'] ?? '').toString();
                          final pres = (d['presentation'] ?? '').toString();

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
                                            style: const TextStyle(fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 4),
                                        Wrap(
                                          spacing: 10,
                                          runSpacing: 6,
                                          children: [
                                            if (form.isNotEmpty || route.isNotEmpty)
                                              _pill('${form.isEmpty ? '—' : form} / ${route.isEmpty ? '—' : route}'),
                                            if (strength.isNotEmpty) _pill('Conc.: $strength'),
                                            if (pres.isNotEmpty) _pill('Pres.: $pres'),
                                            _pill('Stock: $stock'),
                                            _pill('Precio: ${_fmt(price)}'),
                                          ],
                                        ),
                                        if (requiresRx) ...[
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: Colors.red.shade50,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: Colors.red.shade300),
                                            ),
                                            child: const Text(
                                              'Este producto requiere receta médica.',
                                              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
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
                                              final disc = await _bestDiscountFor(pdoc.id, d);
                                              final finalPrice = price * (1 - disc / 100);
                                              _addLine(
                                                productId: pdoc.id,
                                                name: name,
                                                unitPrice: finalPrice,
                                                stock: stock,
                                                taxable: (d['taxable'] ?? false) == true,
                                                ivaPercent: _toDouble(d['ivaPercent'] ?? 13),
                                              );
                                              searchCtrl.clear();
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
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          decoration:
                              BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
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
                                  child: Center(child: Text('No hay productos agregados.')))
                              : ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _lines.length,
                                  itemBuilder: (context, i) => _lineTile(_lines[i], isNarrow),
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
                        onPressed: _lines.isEmpty && buyerCtrl.text.isEmpty && notesCtrl.text.isEmpty ? null : _clearAll,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                        child: const Text('L  •  Limpiar'),
                      ),
                      ElevatedButton(
                        onPressed: null, // reservado para "C"
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.black12, foregroundColor: Colors.black54),
                        child: const Text('C  •  Próximamente'),
                      ),
                      ElevatedButton(
                        onPressed: _lines.isEmpty ? null : () => _printCurrentInvoice(),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                        child: const Text('I  •  Imprimir PDF'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  TextFormField(
                    controller: buyerCtrl,
                    decoration: const InputDecoration(labelText: 'Cliente o comprador (opcional)'),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(labelText: 'Notas adicionales'),
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
                            const Text('Hay productos de venta bajo receta en esta venta.',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              activeColor: kGreen2,
                              title: const Text('Receta médica verificada'),
                              value: _recipeChecked,
                              onChanged: (v) => setState(() => _recipeChecked = v),
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
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: kGreen2, foregroundColor: Colors.white),
                          onPressed: _loading ? null : _save,
                          child: _loading
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Registrar venta'),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ====== Item responsivo ======
  Widget _lineTile(SaleLine l, bool isNarrow) {
    if (!isNarrow) {
      // Diseño horizontal (escritorio / tablet)
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  '${l.name}  (Stock: ${l.stock}, ${_fmt(l.unitPrice)})',
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
                    items: List<int>.generate((l.stock > 50 ? 50 : (l.stock == 0 ? 1 : l.stock)), (x) => x + 1)
                        .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => l.qty = v);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 100, child: Text(_fmt(l.unitPrice))),
              const SizedBox(width: 8),
              SizedBox(width: 120, child: Text(_fmt(l.subtotal))),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            l.name,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: Text('Stock: ${l.stock}  •  ${_fmt(l.unitPrice)}')),
              IconButton(
                tooltip: 'Quitar',
                onPressed: () => _removeLine(_lines.indexOf(l)),
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
                    items: List<int>.generate((l.stock > 50 ? 50 : (l.stock == 0 ? 1 : l.stock)), (x) => x + 1)
                        .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => l.qty = v);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text('Subtotal: ${_fmt(l.subtotal)}', textAlign: TextAlign.right)),
            ],
          ),
        ]),
      ),
    );
  }

  // ====== Detalles ======
  Future<void> _showDetailsDialog(Map<String, dynamic> d) async {
    final name = (d['name'] ?? 'Producto').toString();
    final price = _toDouble(d['price']);
    final stock = _toInt(d['stock']);
    final requiresRx = (d['requiresPrescription'] ?? false) == true;
    final form = (d['pharmForm'] ?? '').toString();
    final route = (d['route'] ?? '').toString();
    final strength = (d['strength'] ?? '').toString();
    final pres = (d['presentation'] ?? '').toString();
    final taxable = (d['taxable'] ?? false) == true;
    final iva = _toDouble(d['ivaPercent'] ?? 13);
    final expiry = (d['expiryDate'] as Timestamp?)?.toDate();

    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv('Forma/Vía', '${form.isEmpty ? '—' : form} / ${route.isEmpty ? '—' : route}'),
            _kv('Concentración', strength.isEmpty ? '—' : strength),
            _kv('Presentación', pres.isEmpty ? '—' : pres),
            _kv('Stock', '$stock'),
            _kv('Precio (final)', _fmt(price)),
            _kv('IVA', taxable ? '${iva.toStringAsFixed(0)}%' : 'No grava'),
            if (expiry != null) _kv('Vencimiento', _fmtDate(expiry)),
            if (requiresRx)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  children: const [
                    Icon(Icons.warning_amber, color: Colors.red),
                    SizedBox(width: 6),
                    Expanded(child: Text('Producto bajo receta médica', style: TextStyle(color: Colors.red))),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6.0),
        child: Row(
          children: [
            SizedBox(width: 140, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(child: Text(v)),
          ],
        ),
      );

  Widget _pill(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.green.shade300),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

// Logo a usar desde el egreso
const String kPharmaLogoPath = 'assets/logo.png';
