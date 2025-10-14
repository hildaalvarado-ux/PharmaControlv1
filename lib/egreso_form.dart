// lib/egreso_form.dart
// Versión mejorada: corrige el error de `lowStockNames`, añade filtro/búsqueda por nombre/descr/sku,
// muestra precio unitario en selector y permite agregar automáticamente desde el filtro.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'app_theme.dart';

class EgresoFormPage extends StatefulWidget {
  final String userRole;
  const EgresoFormPage({super.key, this.userRole = 'vendedor'});

  @override
  State<EgresoFormPage> createState() => _EgresoFormPageState();
}

class LineItem {
  String? productId;
  int qty;
  double unitPrice;
  LineItem({this.productId, this.qty = 1, this.unitPrice = 0.0});

  double get subtotal => qty * unitPrice;
}

class _EgresoFormPageState extends State<EgresoFormPage> {
  final CollectionReference productsRef = FirebaseFirestore.instance.collection('products');
  final CollectionReference egresosRef = FirebaseFirestore.instance.collection('egresos');

  List<QueryDocumentSnapshot>? _products; // lista completa de productos
  Map<String, Map<String, dynamic>> _prodMap = {}; // cache id -> data

  final customerCtrl = TextEditingController();
  final refCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  final productFilterCtrl = TextEditingController();

  bool _loading = false;
  List<LineItem> items = [];

  @override
  void initState() {
    super.initState();
    _loadProducts().then((_) {
      setState(() {
        items = [LineItem(productId: _products != null && _products!.isNotEmpty ? _products!.first.id : null)];
      });
    });
    productFilterCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    productFilterCtrl.dispose();
    customerCtrl.dispose();
    refCtrl.dispose();
    notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    final ps = await productsRef.orderBy('name').get();
    setState(() {
      _products = ps.docs;
      _prodMap = {for (var d in ps.docs) d.id: (d.data() as Map<String, dynamic>)};
    });
  }

  void _showSnack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  double get total => items.fold(0.0, (s, it) => s + it.subtotal);

  bool get hasLowStock {
    if (_products == null) return false;
    for (var p in _products!) {
      final d = p.data() as Map<String, dynamic>;
      final stock = _parseIntSafe(d['stock']);
      if (stock < 10) return true;
    }
    return false;
  }

  List<String> lowStockNames() {
    if (_products == null) return [];
    final List<String> out = [];
    for (var p in _products!) {
      final d = p.data() as Map<String, dynamic>;
      final stock = _parseIntSafe(d['stock']);
      if (stock < 10) {
        final name = (d['name'] as String?) ?? p.id;
        out.add(name);
      }
    }
    return out;
  }

  int _parseIntSafe(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    final s = v.toString();
    return int.tryParse(s) ?? 0;
  }

  void _addLineAtTop({String? productId, double unitPrice = 0.0}) {
    setState(() {
      items.insert(0, LineItem(productId: productId, qty: 1, unitPrice: unitPrice));
    });
  }

  void _removeLine(int idx) {
    setState(() => items.removeAt(idx));
  }

  void _updateLineProduct(int idx, String? pid) {
    setState(() => items[idx].productId = pid);
    // if product has price configured, populate unitPrice
    if (pid != null && _prodMap.containsKey(pid)) {
      final p = _prodMap[pid]!;
      final price = (p['price'] is num) ? (p['price'] as num).toDouble() : double.tryParse('${p['price']}') ?? 0.0;
      setState(() => items[idx].unitPrice = price);
    }
  }

  void _updateLineQty(int idx, String v) {
    final val = int.tryParse(v) ?? 0;
    if (val < 0) return;
    setState(() => items[idx].qty = val);
  }

  void _updateLinePrice(int idx, String v) {
    final val = double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
    setState(() => items[idx].unitPrice = val);
  }

  String _productLabel(QueryDocumentSnapshot p) {
    final d = p.data() as Map<String, dynamic>;
    final stock = _parseIntSafe(d['stock']);
    final name = d['name'] ?? '—';
    final sku = d['sku'] ?? '—';
    final price = (d['price'] is num) ? (d['price'] as num).toDouble() : double.tryParse('${d['price']}') ?? 0.0;
    return '$name • $sku • Stock: $stock • ${price.toStringAsFixed(2)} u';
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

  Future<void> _save() async {
    if (_products == null) {
      _showSnack('Cargando productos...');
      return;
    }
    if (items.isEmpty) {
      _showSnack('Agrega al menos un producto.');
      return;
    }

    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      if (it.productId == null) {
        _showSnack('Selecciona un producto en la fila ${i + 1}');
        return;
      }
      if (it.qty <= 0) {
        _showSnack('Cantidad inválida en la fila ${i + 1}');
        return;
      }
      if (it.unitPrice < 0) {
        _showSnack('Precio inválido en la fila ${i + 1}');
        return;
      }
      final prodData = _prodMap[it.productId!];
      final stock = _parseIntSafe(prodData?['stock']);
      if (it.qty > stock) {
        _showSnack('Stock insuficiente para ${prodData?['name'] ?? it.productId} (disponible: $stock)');
        return;
      }
    }

    setState(() => _loading = true);

    try {
      final docRef = egresosRef.doc();

      await FirebaseFirestore.instance.runTransaction((tx) async {
        for (var it in items) {
          final prodRef = productsRef.doc(it.productId);
          final prodSnap = await tx.get(prodRef);
          if (!prodSnap.exists) throw Exception('Producto no encontrado: ${it.productId}');
          final data = prodSnap.data() as Map<String, dynamic>;
          final currentStock = _parseIntSafe(data['stock']);
          if (currentStock < it.qty) throw Exception('Stock insuficiente (${currentStock}) para ${data['name'] ?? prodRef.id}');
        }

        final itemsForDb = items.map((it) => {
              'productId': it.productId,
              'qty': it.qty,
              'unitPrice': it.unitPrice,
              'subtotal': it.subtotal,
              'name': _prodMap[it.productId!]?['name'] ?? ''
            }).toList();

        final customerName = customerCtrl.text.trim().isEmpty ? 'Consumidor Final' : customerCtrl.text.trim();

        tx.set(docRef, {
          'items': itemsForDb,
          'total': total,
          'customer': customerName,
          'reference': refCtrl.text.trim(),
          'notes': notesCtrl.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'userRole': widget.userRole,
          'userId': null,
        });

        for (var it in items) {
          final prodRef = productsRef.doc(it.productId);
          tx.update(prodRef, {'stock': FieldValue.increment(-it.qty)});
        }
      });

      if (!mounted) return;
      await showDialog(
          context: context,
          builder: (_) {
            return AlertDialog(
              title: const Text('Comprobante de venta'),
              content: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Cliente: ${customerCtrl.text.trim().isEmpty ? 'Consumidor Final' : customerCtrl.text.trim()}'),
                  const SizedBox(height: 8),
                  ...items.map((it) {
                    final name = _prodMap[it.productId!]?['name'] ?? it.productId;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Expanded(child: Text('$name x${it.qty}')),
                        Text('${it.subtotal.toStringAsFixed(2)}')
                      ]),
                    );
                  }),
                  const Divider(),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(total.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold))
                  ])
                ]),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cerrar')),
              ],
            );
          });

      _showSnack('Venta registrada correctamente. Stock actualizado.');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showSnack('Error al registrar la venta: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _loading = false);
      _loadProducts();
    }
  }

  // Si el usuario selecciona un producto desde el filtro, añadirlo automáticamente
  void _onSelectFilteredProduct(QueryDocumentSnapshot p) {
    final d = p.data() as Map<String, dynamic>;
    final id = p.id;
    final price = (d['price'] is num) ? (d['price'] as num).toDouble() : double.tryParse('${d['price']}') ?? 0.0;
    _addLineAtTop(productId: id, unitPrice: price);
    // limpiar filtro
    productFilterCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar Venta (Egreso)'), backgroundColor: kGreen2),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: _products == null
                ? const Center(child: CircularProgressIndicator())
                : Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        if (hasLowStock)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                            child: Row(children: [
                              const Icon(Icons.warning_amber_rounded, color: Colors.red),
                              const SizedBox(width: 8),
                              Expanded(child: Text('Stock bajo: ${lowStockNames().join(', ')}', style: const TextStyle(color: Colors.red))),
                            ]),
                          ),

                        // FILTRO de productos (busca por nombre, descripción, sku o precio)
                        Row(children: [
                          Expanded(
                            child: TextField(
                              controller: productFilterCtrl,
                              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Buscar producto por nombre, descripción, sku o precio'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                              onPressed: () => _addLineAtTop(),
                              icon: const Icon(Icons.add),
                              label: const Text('Agregar producto vacio'),
                              style: ElevatedButton.styleFrom(backgroundColor: kGreen2)),
                        ]),

                        const SizedBox(height: 8),

                        // Si hay texto en filtro, mostrar resultados
                        if (productFilterCtrl.text.trim().isNotEmpty)
                          Container(
                            constraints: const BoxConstraints(maxHeight: 220),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _filteredProducts.length,
                              itemBuilder: (context, i) {
                                final p = _filteredProducts[i];
                                final d = p.data() as Map<String, dynamic>;
                                final price = (d['price'] is num) ? (d['price'] as num).toDouble() : double.tryParse('${d['price']}') ?? 0.0;
                                final stock = _parseIntSafe(d['stock']);
                                return ListTile(
                                  title: Text((d['name'] as String?) ?? p.id),
                                  subtitle: Text('${(d['description'] as String?) ?? ''} • Stock: $stock • ${price.toStringAsFixed(2)} u'),
                                  trailing: ElevatedButton(onPressed: () => _onSelectFilteredProduct(p), child: const Text('Agregar')),
                                  onTap: () => _onSelectFilteredProduct(p),
                                );
                              },
                            ),
                          ),

                        const SizedBox(height: 12),

                        // tabla de lineas
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
                          child: Row(children: const [Expanded(child: Text('Producto')), SizedBox(width: 80, child: Text('Cant.')), SizedBox(width: 140, child: Text('Precio unit.')), SizedBox(width: 80, child: Text('Subtotal')), SizedBox(width: 40, child: Text(''))]),
                        ),

                        const SizedBox(height: 8),

                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: items.length,
                            itemBuilder: (context, idx) {
                              final it = items[idx];
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        value: it.productId,
                                        items: _products!.map((p) {
                                          final label = _productLabel(p);
                                          final d = p.data() as Map<String, dynamic>;
                                          final stock = _parseIntSafe(d['stock']);
                                          final low = stock < 10;
                                          return DropdownMenuItem(
                                              value: p.id,
                                              child: Row(children: [
                                                Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
                                                if (low) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(8)), child: const Text('STOCK BAJO', style: TextStyle(color: Colors.red, fontSize: 11)))
                                              ]));
                                        }).toList(),
                                        onChanged: (v) => _updateLineProduct(idx, v),
                                        decoration: const InputDecoration(border: InputBorder.none),
                                      ),
                                    ),

                                    const SizedBox(width: 8),

                                    SizedBox(
                                      width: 80,
                                      child: TextFormField(
                                        initialValue: it.qty.toString(),
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(border: InputBorder.none),
                                        onChanged: (v) => _updateLineQty(idx, v),
                                      ),
                                    ),

                                    const SizedBox(width: 8),

                                    SizedBox(
                                      width: 140,
                                      child: TextFormField(
                                        initialValue: it.unitPrice.toStringAsFixed(2),
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(border: InputBorder.none),
                                        onChanged: (v) => _updateLinePrice(idx, v),
                                      ),
                                    ),

                                    const SizedBox(width: 8),

                                    SizedBox(width: 80, child: Text(it.subtotal.toStringAsFixed(2))),

                                    const SizedBox(width: 8),

                                    Column(children: [
                                      IconButton(onPressed: () => _removeLine(idx), icon: const Icon(Icons.delete_outline)),
                                    ])
                                  ]),
                                ),
                              );
                            },
                          ),
                        ),

                        const SizedBox(height: 12),

                        TextField(controller: customerCtrl, decoration: const InputDecoration(labelText: 'Cliente (si es factura comercial)'),),
                        const SizedBox(height: 8),
                        TextField(controller: refCtrl, decoration: const InputDecoration(labelText: 'Referencia (opcional)'),),
                        const SizedBox(height: 8),
                        TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notas (opcional)'),),

                        const SizedBox(height: 16),

                        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                          Text('Total: ${total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: _loading ? null : _save,
                            style: ElevatedButton.styleFrom(backgroundColor: kGreen2),
                            child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator()) : const Text('Realizar venta'),
                          )
                        ])
                      ]),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
