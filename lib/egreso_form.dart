import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'app_theme.dart';

class EgresoFormWidget extends StatefulWidget {
  final String userRole;
  const EgresoFormWidget({super.key, this.userRole = 'vendedor'});

  @override
  State<EgresoFormWidget> createState() => _EgresoFormWidgetState();
}

class LineItem {
  String? productId;
  int qty;
  double unitPrice;
  LineItem({this.productId, this.qty = 1, this.unitPrice = 0.0});
  double get subtotal => qty * unitPrice;
}

class _EgresoFormWidgetState extends State<EgresoFormWidget> {
  final productsRef = FirebaseFirestore.instance.collection('products');
  final egresosRef = FirebaseFirestore.instance.collection('egresos');

  List<QueryDocumentSnapshot>? _products;
  Map<String, Map<String, dynamic>> _prodMap = {};

  final customerCtrl = TextEditingController();
  final refCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  final productFilterCtrl = TextEditingController();

  bool _loading = false;
  List<LineItem> items = [];

  @override
  void initState() {
    super.initState();
    _initLoad();
    productFilterCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    customerCtrl.dispose();
    refCtrl.dispose();
    notesCtrl.dispose();
    productFilterCtrl.dispose();
    super.dispose();
  }

  Future<void> _initLoad() async {
    await _loadProducts();
    if (!mounted) return;
    setState(() => items = []);
  }

  Future<void> _loadProducts() async {
    final snapshot = await productsRef.orderBy('name').get();
    final loaded = snapshot.docs;
    final map = {for (var d in loaded) d.id: d.data() as Map<String, dynamic>};
    if (!mounted) return;
    setState(() {
      _products = loaded;     // <--- importante: avisar al framework
      _prodMap = map;
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  double get total => items.fold(0.0, (s, it) => s + it.subtotal);

  int _parseIntSafe(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  void _addLineAtTop({String? productId, double unitPrice = 0.0}) {
    setState(() => items.insert(0, LineItem(productId: productId, unitPrice: unitPrice)));
  }

  void _removeLine(int idx) => setState(() => items.removeAt(idx));

  void _updateLineProduct(int idx, String? pid) {
    if (pid == null) return;
    final product = _prodMap[pid];
    if (product == null) return;

    final stock = _parseIntSafe(product['stock']);
    if (stock <= 0) {
      _showSnack('Producto sin stock disponible.');
      return;
    }

    final price = (product['price'] is num)
        ? (product['price'] as num).toDouble()
        : double.tryParse('${product['price']}') ?? 0.0;

    setState(() {
      items[idx].productId = pid;
      items[idx].unitPrice = price;
      if (items[idx].qty > stock) items[idx].qty = stock;
    });
  }

  void _updateLineQty(int idx, String v) {
    final val = int.tryParse(v) ?? 0;
    if (val < 0) return;
    final product = _prodMap[items[idx].productId];
    if (product == null) return;
    final stock = _parseIntSafe(product['stock']);
    if (val > stock) {
      _showSnack('Cantidad supera el stock disponible ($stock).');
      return;
    }
    setState(() => items[idx].qty = val);
  }

  void _updateLinePrice(int idx, String v) {
    final val = double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
    setState(() => items[idx].unitPrice = val);
  }

  List<QueryDocumentSnapshot> get _filteredProducts {
    if (_products == null) return [];
    final query = productFilterCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return _products!;
    return _products!.where((p) {
      final d = p.data() as Map<String, dynamic>;
      final name = (d['name'] ?? '').toString().toLowerCase();
      final desc = (d['description'] ?? '').toString().toLowerCase();
      final sku = (d['sku'] ?? '').toString().toLowerCase();
      return name.contains(query) || desc.contains(query) || sku.contains(query);
    }).toList();
  }

  void _onSelectFilteredProduct(QueryDocumentSnapshot p) {
    final d = p.data() as Map<String, dynamic>;
    final id = p.id;
    final stock = _parseIntSafe(d['stock']);
    if (stock <= 0) {
      _showSnack('No hay stock disponible para este producto.');
      return;
    }
    final price = (d['price'] is num) ? (d['price'] as num).toDouble() : double.tryParse('${d['price']}') ?? 0.0;
    _addLineAtTop(productId: id, unitPrice: price);
    productFilterCtrl.clear();
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
      final prodData = _prodMap[it.productId!];
      final stock = _parseIntSafe(prodData?['stock']);
      if (it.qty > stock) {
        _showSnack('Stock insuficiente para ${prodData?['name'] ?? it.productId}');
        return;
      }
    }

    setState(() => _loading = true);
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final docRef = egresosRef.doc();

        // Revalidar stock dentro de la transacción
        for (var it in items) {
          final prodRef = productsRef.doc(it.productId);
          final snap = await tx.get(prodRef);
          final data = snap.data() as Map<String, dynamic>;
          final stock = _parseIntSafe(data['stock']);
          if (stock < it.qty) throw Exception('Stock insuficiente para ${data['name']}');
        }

        tx.set(docRef, {
          'createdAt': FieldValue.serverTimestamp(),
          'userId': FirebaseAuth.instance.currentUser?.uid,
          'userRole': widget.userRole,
          'customer': customerCtrl.text.trim().isEmpty ? 'Consumidor Final' : customerCtrl.text.trim(),
          'reference': refCtrl.text.trim(),
          'notes': notesCtrl.text.trim(),
          'total': total,
          'items': items
              .map((it) => {
                    'productId': it.productId,
                    'qty': it.qty,
                    'unitPrice': it.unitPrice,
                    'subtotal': it.subtotal,
                    'name': _prodMap[it.productId!]?['name'] ?? ''
                  })
              .toList(),
        });

        for (var it in items) {
          final prodRef = productsRef.doc(it.productId);
          tx.update(prodRef, {'stock': FieldValue.increment(-it.qty)});
        }
      });

      _showSnack('Venta registrada correctamente.');
      setState(() {
        items.clear();
        customerCtrl.clear();
        refCtrl.clear();
        notesCtrl.clear();
      });
      await _loadProducts();
    } catch (e) {
      _showSnack('Error al registrar: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_products == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Contenido embebible (sin Scaffold) para el Dashboard
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Generar venta (Egreso)',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kGreen1)),
                const SizedBox(height: 12),

                // Filtro
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: productFilterCtrl,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Buscar producto por nombre, descripción o SKU...',
                        filled: true,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),

                // Resultados del filtro
                if (productFilterCtrl.text.trim().isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _filteredProducts.length,
                      itemBuilder: (context, i) {
                        final p = _filteredProducts[i];
                        final d = p.data() as Map<String, dynamic>;
                        final stock = _parseIntSafe(d['stock']);
                        final price = (d['price'] is num)
                            ? (d['price'] as num).toDouble()
                            : double.tryParse('${d['price']}') ?? 0.0;
                        return ListTile(
                          title: Text('${d['name']}'),
                          subtitle: Text('Stock: $stock | \$${price.toStringAsFixed(2)}'),
                          trailing: ElevatedButton(
                            onPressed: stock > 0 ? () => _onSelectFilteredProduct(p) : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: stock > 0 ? kGreen2 : Colors.grey,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Agregar'),
                          ),
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 16),

                // Encabezado tabla
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
                  child: Row(children: const [
                    Expanded(child: Text('Producto')),
                    SizedBox(width: 80, child: Text('Cant.')),
                    SizedBox(width: 120, child: Text('Precio')),
                    SizedBox(width: 100, child: Text('Subtotal')),
                    SizedBox(width: 40, child: Text('')),
                  ]),
                ),
                const SizedBox(height: 8),

                // Líneas
                Expanded(
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, idx) {
                      final it = items[idx];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: it.productId,
                                items: _products!.map((p) {
                                  final data = p.data() as Map<String, dynamic>;
                                  final stock = _parseIntSafe(data['stock']);
                                  final name = data['name'] ?? '—';
                                  final price = data['price'] is num
                                      ? (data['price'] as num).toDouble()
                                      : double.tryParse('${data['price']}') ?? 0.0;
                                  return DropdownMenuItem(
                                    value: p.id,
                                    enabled: stock > 0,
                                    child: Text(
                                      '$name (Stock: $stock, \$${price.toStringAsFixed(2)})',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: stock > 0 ? Colors.black : Colors.red),
                                    ),
                                  );
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
                                decoration: const InputDecoration(border: InputBorder.none, hintText: 'Cant'),
                                onChanged: (v) => _updateLineQty(idx, v),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 120,
                              child: TextFormField(
                                initialValue: it.unitPrice.toStringAsFixed(2),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(border: InputBorder.none, hintText: 'Precio'),
                                onChanged: (v) => _updateLinePrice(idx, v),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(width: 100, child: Text(it.subtotal.toStringAsFixed(2))),
                            IconButton(onPressed: () => _removeLine(idx), icon: const Icon(Icons.delete_outline))
                          ]),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 8),

                // Datos cliente y notas
                Row(children: [
                  Expanded(child: TextField(controller: customerCtrl, decoration: const InputDecoration(labelText: 'Cliente o comprador'))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: refCtrl, decoration: const InputDecoration(labelText: 'Referencia del pedido'))),
                ]),
                const SizedBox(height: 8),
                TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notas adicionales')),
                const SizedBox(height: 12),

                // Barra de total + botón
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text('Total: \$${total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ElevatedButton(
                      onPressed: _loading ? null : _save,
                      style: ElevatedButton.styleFrom(backgroundColor: kGreen2, foregroundColor: Colors.white),
                      child: _loading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Registrar venta'),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
