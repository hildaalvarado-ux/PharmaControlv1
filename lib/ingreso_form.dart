// lib/ingreso_form_widget.dart
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'invoice_pdf.dart';

// ⬇️ Salida PDF multiplataforma: móvil/escritorio vs web
import 'pdf_output_mobile.dart'
    if (dart.library.html) 'pdf_output_web.dart' as pdf_out;

class IngresoFormWidget extends StatefulWidget {
  const IngresoFormWidget({super.key});
  @override
  State<IngresoFormWidget> createState() => _IngresoFormWidgetState();
}

class IngresoLine {
  // si es existente
  String? productId;

  // si es nuevo
  bool isNew;
  String newName;
  String newSku;

  int qty;
  double purchasePrice; // precio de compra (sin IVA normalmente)
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
    this.isNew = false,
    this.newName = '',
    this.newSku = '',
  });

  double get subtotal => qty * purchasePrice;
}

class _IngresoFormWidgetState extends State<IngresoFormWidget> {
  final productsRef = FirebaseFirestore.instance.collection('products');
  final providersRef = FirebaseFirestore.instance.collection('providers');
  final ingresosRef  = FirebaseFirestore.instance.collection('ingresos');

  List<QueryDocumentSnapshot>? _products;
  Map<String, Map<String, dynamic>> _prodMap = {};
  List<QueryDocumentSnapshot>? _providers;

  final providerCtrl = TextEditingController();
  final invoiceCtrl  = TextEditingController();
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
    final ps    = await productsRef.orderBy('name').get();
    final provs = await providersRef.orderBy('name').get();
    _products = ps.docs;
    _prodMap  = {for (var d in ps.docs) d.id: (d.data() as Map<String, dynamic>)};
    _providers = provs.docs;
    if (mounted) setState(() {});
  }

  // Helpers numéricos
  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse((v?.toString() ?? '').replaceAll(',', '.')) ?? 0.0;
  }

  void _showSnack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  double get _total => _lines.fold(0.0, (s, l) => s + l.subtotal);

  // ===== UI helpers =====
  void _addEmptyLine() => setState(() => _lines.insert(0, IngresoLine()));
  void _removeLine(int idx) => setState(() => _lines.removeAt(idx));
  void _clearAll() {
    setState(() {
      _lines.clear();
      providerCtrl.clear();
      invoiceCtrl.clear();
      purchaseDate = null;
      productFilterCtrl.clear();
    });
  }

  // Al elegir producto existente, precargar compra y venta sugerida
  void _onChooseProduct(int idx, String? pid) {
    setState(() {
      final ln = _lines[idx];
      ln.productId = pid;
      ln.isNew = false;
      ln.newName = '';
      ln.newSku  = '';
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

  // Sugerencias del buscador superior
  List<QueryDocumentSnapshot> get _filteredProducts {
    if ((_products == null) || (_products!.isEmpty)) return [];
    final q = productFilterCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _products!;
    return _products!.where((p) {
      final d = p.data() as Map<String, dynamic>;
      final name = (d['name'] as String? ?? '').toLowerCase();
      final desc = (d['description'] as String? ?? '').toLowerCase();
      final sku  = (d['sku'] as String? ?? '').toLowerCase();
      return name.contains(q) || desc.contains(q) || sku.contains(q);
    }).toList();
  }

  void _addFromQuickList(QueryDocumentSnapshot p) {
    final d = p.data() as Map<String, dynamic>;
    final id = p.id;
    final purchase = _toDouble(d['purchasePrice']);
    final margin   = _toDouble(d['marginPercent'] ?? 10);
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

  // ====== GUARDAR ======
  Future<void> _save() async {
    if (_products == null) {
      _showSnack('Cargando productos...');
      return;
    }
    if (_lines.isEmpty) {
      _showSnack('Agrega al menos un producto.');
      return;
    }
    // Validaciones
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
      await FirebaseFirestore.instance.runTransaction((tx) async {
        // 1) Crear productos nuevos (si hay)
        for (final l in _lines.where((x) => x.isNew)) {
          final newRef = productsRef.doc();
          tx.set(newRef, {
            'name': l.newName.trim(),
            'sku':  l.newSku.trim(),
            'purchasePrice': l.purchasePrice,
            'marginPercent': 10, // valor base; el usuario podrá editar luego
            'price': l.salePrice, // precio de venta sugerido
            'stock': 0,
            'createdAt': FieldValue.serverTimestamp(),
          });
          // reemplazar por id real para continuar el flujo
          l.productId = newRef.id;
          l.isNew = false;
        }

        // 2) Validar existencia de productos y preparar items
        for (final l in _lines) {
          final prodRef = productsRef.doc(l.productId);
          final prodSnap = await tx.get(prodRef);
          if (!prodSnap.exists) {
            throw Exception('Producto no encontrado: ${l.productId}');
          }
        }

        // 3) Crear documento de ingreso
        final ingresoRef = ingresosRef.doc();
        final itemsForDb = _lines.map((l) => {
              'productId': l.productId,
              'qty': l.qty,
              'purchasePrice': l.purchasePrice,
              'salePrice': l.salePrice,
              'subtotal': l.subtotal,
              'manufactureDate': l.manufactureDate != null ? Timestamp.fromDate(l.manufactureDate!) : null,
              'expiryDate': l.expiryDate != null ? Timestamp.fromDate(l.expiryDate!) : null,
            }).toList();

        final providerId = providerCtrl.text.trim().isNotEmpty
            ? providerCtrl.text.trim()
            : (_providers != null && _providers!.isNotEmpty ? _providers!.first.id : null);

        tx.set(ingresoRef, {
          'userId': FirebaseAuth.instance.currentUser?.uid,
          'items': itemsForDb,
          'total': _total,
          'providerId': providerId,
          'invoice': invoiceCtrl.text.trim(),
          'purchaseDate': purchaseDate != null ? Timestamp.fromDate(purchaseDate!) : FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        });

        // 4) Actualizar stock y precios base de producto
        for (final l in _lines) {
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
      _showSnack('Error al registrar compra: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
      _loadData();
    }
  }

  // ====== IMPRIMIR (recibo de compra simple con tu InvoicePdf) ======
  Future<void> _print() async {
    if (_lines.isEmpty) {
      _showSnack('No hay ítems para imprimir.');
      return;
    }
    final now = DateTime.now();
    final items = _lines.map((l) => InvoiceItem(
      name: l.isNew ? l.newName : (_prodMap[l.productId]?['name'] ?? 'Producto'),
      qty: l.qty,
      unitPrice: l.purchasePrice,
      subtotal: l.subtotal,
    )).toList();

    final bytes = await InvoicePdf.build(
      logoAssetPath: 'assets/logo.png',
      invoiceNumber: 'COMPRA',
      date: now,
      buyer: providerCtrl.text.trim().isEmpty ? 'Proveedor' : providerCtrl.text.trim(),
      notes: invoiceCtrl.text.trim().isEmpty ? '' : 'Factura: ${invoiceCtrl.text.trim()}',
      items: items,
      subtotal: _total, // compras: tratamos todo como neto
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

                        // Filtro superior + agregar línea vacía
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
                          ElevatedButton.icon(
                            onPressed: _addEmptyLine,
                            icon: const Icon(Icons.add),
                            label: const Text('Agregar línea'),
                            style: ElevatedButton.styleFrom(backgroundColor: kGreen2, foregroundColor: Colors.white),
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
                                  title: Text((d['name'] as String?) ?? p.id,
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(
                                    'SKU: ${(d['sku'] ?? '—')}  •  Stock: $stock  •  Compra: \$${purchase.toStringAsFixed(2)}',
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
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
                            Text('Total: \$${_total.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            ElevatedButton(
                              onPressed: _loading ? null : _save,
                              style: ElevatedButton.styleFrom(backgroundColor: kGreen2, foregroundColor: Colors.white),
                              child: _loading
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Text('Registrar compra'),
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
      decoration: const InputDecoration(
        labelText: 'Producto',
        border: InputBorder.none,
      ),
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
          TextButton.icon(
            onPressed: () => setState(() {
              ln.isNew = !ln.isNew;
              if (ln.isNew) {
                ln.productId = null;
              } else {
                ln.newName = '';
                ln.newSku  = '';
              }
            }),
            icon: Icon(ln.isNew ? Icons.undo : Icons.add_box_outlined),
            label: Text(ln.isNew ? 'Usar existente' : 'Nuevo'),
          ),
        ]),
        if (!ln.isNew && ln.productId != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.info_outline),
              onPressed: () => _showDetailsDialog(_prodMap[ln.productId!] ?? {}),
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
                // sugerencia rápida: 10% margen si no hay producto
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
        IconButton(onPressed: () => _removeLine(idx), icon: const Icon(Icons.delete_outline)),
      ],
    );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: isWide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: left),
                const SizedBox(width: 8),
                right,
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titleText, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                left,
                const SizedBox(height: 8),
                right,
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: Text(
                      'Subtotal: \$${ln.subtotal.toStringAsFixed(2)}',
                      textAlign: TextAlign.right,
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                // Fechas (móvil)
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

  // ====== Detalles (reusa esquema de egresos) ======
  Future<void> _showDetailsDialog(Map<String, dynamic> d) async {
    if (d.isEmpty) return;
    final name = (d['name'] ?? 'Producto').toString();
    final price = _toDouble(d['price']);
    final stock = _toInt(d['stock']);
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
            _kv('SKU', (d['sku'] ?? '—').toString()),
            _kv('Stock', '$stock'),
            _kv('Precio venta', '\$${price.toStringAsFixed(2)}'),
            _kv('IVA', taxable ? '${iva.toStringAsFixed(0)}%' : 'No grava'),
            if (expiry != null) _kv('Vencimiento', _fmtDate(expiry)),
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

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
