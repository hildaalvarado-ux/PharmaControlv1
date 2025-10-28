// Formulario para registrar Compras (Ingresos de stock) con el mismo diseño que Egreso.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'app_theme.dart';

class IngresoFormWidget extends StatefulWidget {
  const IngresoFormWidget({super.key});
  @override
  State<IngresoFormWidget> createState() => _IngresoFormWidgetState();
}

class IngresoLine {
  String? productId;
  int qty;
  double purchasePrice; // precio de compra
  double salePrice;     // precio de venta sugerido/definido
  DateTime? manufactureDate;
  DateTime? expiryDate;

  IngresoLine({
    this.productId,
    this.qty = 1,
    this.purchasePrice = 0.0,
    this.salePrice = 0.0,
    this.manufactureDate,
    this.expiryDate,
  });

  double get subtotal => qty * purchasePrice;
}

class _IngresoFormWidgetState extends State<IngresoFormWidget> {
  final CollectionReference productsRef = FirebaseFirestore.instance.collection('products');
  final CollectionReference providersRef = FirebaseFirestore.instance.collection('providers');
  final CollectionReference ingresosRef = FirebaseFirestore.instance.collection('ingresos');

  List<QueryDocumentSnapshot>? _products;
  Map<String, Map<String, dynamic>> _prodMap = {};
  List<QueryDocumentSnapshot>? _providers;

  final providerCtrl = TextEditingController();
  final invoiceCtrl = TextEditingController();
  DateTime? purchaseDate;

  final productFilterCtrl = TextEditingController();

  bool _loading = false;
  List<IngresoLine> lines = [];

  @override
  void initState() {
    super.initState();
    _loadData().then((_) {
      setState(() {
        lines = [IngresoLine(productId: _products != null && _products!.isNotEmpty ? _products!.first.id : null)];
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
    _providers = provs.docs;
    setState(() {});
  }

  int _parseIntSafe(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  double _parseDoubleSafe(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  double get total => lines.fold(0.0, (s, l) => s + l.subtotal);

  void _showSnack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _addLineAtTop({String? productId, double purchasePrice = 0.0, double salePrice = 0.0}) {
    setState(() => lines.insert(0, IngresoLine(productId: productId, purchasePrice: purchasePrice, salePrice: salePrice)));
  }

  void _removeLine(int idx) => setState(() => lines.removeAt(idx));

  void _updateLineProduct(int idx, String? pid) {
    setState(() => lines[idx].productId = pid);
    if (pid != null && _prodMap.containsKey(pid)) {
      final p = _prodMap[pid]!;
      final prevPurchase = _parseDoubleSafe(p['purchasePrice']);
      final margin = _parseDoubleSafe(p['marginPercent']);
      final suggestedSale = prevPurchase * (1 + (margin > 0 ? margin : 10) / 100);
      setState(() {
        if (lines[idx].purchasePrice == 0.0) lines[idx].purchasePrice = prevPurchase;
        lines[idx].salePrice = suggestedSale;
      });
    }
  }

  void _updateLineQty(int idx, String v) {
    final val = int.tryParse(v) ?? 0;
    if (val < 0) return;
    setState(() => lines[idx].qty = val);
  }

  void _updateLinePurchasePrice(int idx, String v) {
    final val = double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
    setState(() {
      lines[idx].purchasePrice = val;
      final pid = lines[idx].productId;
      final margin = pid != null && _prodMap.containsKey(pid) ? _parseDoubleSafe(_prodMap[pid]!['marginPercent']) : 10.0;
      lines[idx].salePrice = val * (1 + (margin / 100));
    });
  }

  void _updateLineSalePrice(int idx, String v) {
    final val = double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
    setState(() => lines[idx].salePrice = val);
  }

  List<QueryDocumentSnapshot> get _filteredProducts {
    if ((_products == null) || (_products!.isEmpty)) return [];
    final q = productFilterCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _products!;
    return _products!.where((p) {
      final d = p.data() as Map<String, dynamic>;
      final name = (d['name'] as String?)?.toLowerCase() ?? '';
      final desc = (d['description'] as String?)?.toLowerCase() ?? '';
      final sku = (d['sku'] as String?)?.toLowerCase() ?? '';
      final price = (d['price'] != null) ? '${d['price']}'.toLowerCase() : '';
      return name.contains(q) || desc.contains(q) || sku.contains(q) || price.contains(q);
    }).toList();
  }

  void _onSelectFilteredProduct(QueryDocumentSnapshot p) {
    final d = p.data() as Map<String, dynamic>;
    final id = p.id;
    final purchase = _parseDoubleSafe(d['purchasePrice']);
    final margin = _parseDoubleSafe(d['marginPercent']);
    final suggestedSale = purchase * (1 + (margin > 0 ? margin : 10) / 100);
    _addLineAtTop(productId: id, purchasePrice: purchase, salePrice: suggestedSale);
    productFilterCtrl.clear();
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
        lines[idx].manufactureDate = picked;
      } else {
        lines[idx].expiryDate = picked;
      }
    });
  }

  Future<void> _save() async {
    if (_products == null) {
      _showSnack('Cargando productos...');
      return;
    }
    if (lines.isEmpty) {
      _showSnack('Agrega al menos un producto.');
      return;
    }

    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (l.productId == null) {
        _showSnack('Selecciona un producto en la fila ${i + 1}');
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
      final docRef = ingresosRef.doc();
      final providerId = _providers != null && _providers!.isNotEmpty ? _providers!.first.id : null;

      await FirebaseFirestore.instance.runTransaction((tx) async {
        for (var l in lines) {
          final prodRef = productsRef.doc(l.productId);
          final prodSnap = await tx.get(prodRef);
          if (!prodSnap.exists) throw Exception('Producto no encontrado: ${l.productId}');
        }

        final itemsForDb = lines.map((l) => {
              'productId': l.productId,
              'qty': l.qty,
              'purchasePrice': l.purchasePrice,
              'salePrice': l.salePrice,
              'subtotal': l.subtotal,
              'manufactureDate': l.manufactureDate != null ? Timestamp.fromDate(l.manufactureDate!) : null,
              'expiryDate': l.expiryDate != null ? Timestamp.fromDate(l.expiryDate!) : null,
            }).toList();

        tx.set(docRef, {
          'userId': FirebaseAuth.instance.currentUser?.uid,
          'items': itemsForDb,
          'total': total,
          'providerId': providerCtrl.text.trim().isEmpty ? providerId : providerCtrl.text.trim(),
          'invoice': invoiceCtrl.text.trim(),
          'purchaseDate': purchaseDate != null ? Timestamp.fromDate(purchaseDate!) : FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        });

        for (var l in lines) {
          final prodRef = productsRef.doc(l.productId);
          tx.update(prodRef, {
            'stock': FieldValue.increment(l.qty),
            'purchasePrice': l.purchasePrice,
            'price': l.salePrice,
            'lastPurchaseAt': FieldValue.serverTimestamp(),
          });
        }
      });

      _showSnack('Compra registrada y stock actualizado.');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showSnack('Error al registrar compra: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _loading = false);
      _loadData();
    }
  }

  Future<void> _showCreateProductModal() async {
    final nameCtrl = TextEditingController();
    final skuCtrl = TextEditingController();
    final purchaseCtrl = TextEditingController();
    final marginCtrl = TextEditingController(text: '10');
    final stockCtrl = TextEditingController(text: '0');

    final created = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Crear producto rápido'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
            TextField(controller: skuCtrl, decoration: const InputDecoration(labelText: 'SKU')),
            TextField(controller: purchaseCtrl, decoration: const InputDecoration(labelText: 'Precio de compra')),
            TextField(controller: marginCtrl, decoration: const InputDecoration(labelText: 'Margen % (sugerido)')),
            TextField(controller: stockCtrl, decoration: const InputDecoration(labelText: 'Stock inicial')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Crear')),
        ],
      ),
    );

    if (created != true) return;
    try {
      final purchase = double.tryParse(purchaseCtrl.text.replaceAll(',', '.')) ?? 0.0;
      final margin = double.tryParse(marginCtrl.text.replaceAll(',', '.')) ?? 10.0;
      await productsRef.add({
        'name': nameCtrl.text.trim(),
        'sku': skuCtrl.text.trim(),
        'purchasePrice': purchase,
        'marginPercent': margin,
        'price': purchase * (1 + (margin / 100)),
        'stock': int.tryParse(stockCtrl.text) ?? 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _showSnack('Producto creado rápido');
      _loadData();
    } catch (e) {
      _showSnack('Error creando producto: $e');
    }
  }

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
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Gestión de Compras', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kGreen1)),
                        const SizedBox(height: 12),

                        // Filtro + crear producto
                        Row(children: [
                          Expanded(
                            child: TextField(
                              controller: productFilterCtrl,
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.search),
                                labelText: 'Buscar producto existente (nombre, sku, desc)',
                                filled: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: _showCreateProductModal,
                            icon: const Icon(Icons.add_box),
                            label: const Text('Nuevo producto'),
                            style: ElevatedButton.styleFrom(backgroundColor: kGreen2, foregroundColor: Colors.white),
                          ),
                        ]),

                        if (productFilterCtrl.text.trim().isNotEmpty) const SizedBox(height: 8),
                        if (productFilterCtrl.text.trim().isNotEmpty)
                          Container(
                            constraints: const BoxConstraints(maxHeight: 200),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _filteredProducts.length,
                              itemBuilder: (context, i) {
                                final p = _filteredProducts[i];
                                final d = p.data() as Map<String, dynamic>;
                                final purchase = _parseDoubleSafe(d['purchasePrice']);
                                final stock = _parseIntSafe(d['stock']);
                                return ListTile(
                                  title: Text((d['name'] as String?) ?? p.id),
                                  subtitle: Text('${(d['description'] as String?) ?? ''} • Stock: $stock • Compra: ${purchase.toStringAsFixed(2)}'),
                                  trailing: ElevatedButton(
                                    onPressed: () => _onSelectFilteredProduct(p),
                                    style: ElevatedButton.styleFrom(foregroundColor: Colors.white),
                                    child: const Text('Agregar'),
                                  ),
                                  onTap: () => _onSelectFilteredProduct(p),
                                );
                              },
                            ),
                          ),

                        const SizedBox(height: 12),

                        // Encabezado
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
                          child: Row(children: const [
                            Expanded(child: Text('Producto')),
                            SizedBox(width: 80, child: Text('Cant.')),
                            SizedBox(width: 140, child: Text('Precio compra')),
                            SizedBox(width: 140, child: Text('Precio venta sug.')),
                            SizedBox(width: 40, child: Text('')),
                          ]),
                        ),
                        const SizedBox(height: 8),

                        // Líneas
                        Expanded(
                          child: ListView.builder(
                            itemCount: lines.length,
                            itemBuilder: (context, idx) {
                              final ln = lines[idx];
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Column(children: [
                                    Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          value: ln.productId,
                                          items: _products!.map((p) {
                                            final d = p.data() as Map<String, dynamic>;
                                            final stock = _parseIntSafe(d['stock']);
                                            final label = '${d['name'] ?? '—'} • ${d['sku'] ?? '—'} • Stock: $stock';
                                            return DropdownMenuItem(value: p.id, child: Text(label, overflow: TextOverflow.ellipsis));
                                          }).toList(),
                                          onChanged: (v) => _updateLineProduct(idx, v),
                                          decoration: const InputDecoration(border: InputBorder.none),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 80,
                                        child: TextFormField(
                                          initialValue: ln.qty.toString(),
                                          keyboardType: TextInputType.number,
                                          decoration: const InputDecoration(border: InputBorder.none, hintText: 'Cant.'),
                                          onChanged: (v) => _updateLineQty(idx, v),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 140,
                                        child: TextFormField(
                                          initialValue: ln.purchasePrice.toStringAsFixed(2),
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          decoration: const InputDecoration(border: InputBorder.none, hintText: 'Compra'),
                                          onChanged: (v) => _updateLinePurchasePrice(idx, v),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 140,
                                        child: TextFormField(
                                          initialValue: ln.salePrice.toStringAsFixed(2),
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          decoration: const InputDecoration(border: InputBorder.none, hintText: 'Venta sug.'),
                                          onChanged: (v) => _updateLineSalePrice(idx, v),
                                        ),
                                      ),
                                      IconButton(onPressed: () => _removeLine(idx), icon: const Icon(Icons.delete_outline)),
                                    ]),
                                    const SizedBox(height: 8),
                                    // Fechas
                                    Row(children: [
                                      Expanded(child: Text(ln.manufactureDate == null ? 'Fecha de fabricación: —' : 'Fab: ${ln.manufactureDate!.day}/${ln.manufactureDate!.month}/${ln.manufactureDate!.year}')),
                                      TextButton(onPressed: () => _pickDateForLine(idx, isManufacture: true), child: const Text('Seleccionar')),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(ln.expiryDate == null ? 'Vencimiento: —' : 'Vence: ${ln.expiryDate!.day}/${ln.expiryDate!.month}/${ln.expiryDate!.year}')),
                                      TextButton(onPressed: () => _pickDateForLine(idx, isManufacture: false), child: const Text('Seleccionar')),
                                    ]),
                                  ]),
                                ),
                              );
                            },
                          ),
                        ),

                        const SizedBox(height: 12),

                        // proveedor, factura y fecha compra
                        Row(children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _providers != null && _providers!.isNotEmpty ? _providers!.first.id : null,
                              items: _providers?.map((p) {
                                final d = p.data() as Map<String, dynamic>;
                                return DropdownMenuItem(value: p.id, child: Text(d['name'] ?? '—'));
                              }).toList(),
                              onChanged: (v) => providerCtrl.text = v ?? '',
                              decoration: const InputDecoration(labelText: 'Proveedor'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(width: 220, child: TextFormField(controller: invoiceCtrl, decoration: const InputDecoration(labelText: 'N° factura/serie'))),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(child: Text(purchaseDate == null ? 'Fecha de compra: —' : 'Compra: ${purchaseDate!.day}/${purchaseDate!.month}/${purchaseDate!.year}')),
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

                        // Total + botón
                        Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                            Text('Total: ${total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            ElevatedButton(
                              onPressed: _loading ? null : _save,
                              style: ElevatedButton.styleFrom(backgroundColor: kGreen2, foregroundColor: Colors.white),
                              child: _loading
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Text('Registrar compra'),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
