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
  String? category;

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
    this.category,
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
  final CollectionReference productsRef =
      FirebaseFirestore.instance.collection('products');
  final CollectionReference providersRef =
      FirebaseFirestore.instance.collection('providers');
  final CollectionReference ingresosRef =
      FirebaseFirestore.instance.collection('ingresos');

  List<QueryDocumentSnapshot>? _products;
  Map<String, Map<String, dynamic>> _prodMap = {};
  List<QueryDocumentSnapshot>? _providers;
  List<String> _categories = [];

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
        _lines.add(
          IngresoLine(
            productId:
                _products != null && _products!.isNotEmpty ? _products!.first.id : null,
          ),
        );
      });
    });
    _loadCategories();
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
    _prodMap = {
      for (var d in ps.docs) d.id: (d.data() as Map<String, dynamic>),
    };
    _providers = provs.docs;
    if (mounted) setState(() {});
  }

  Future<void> _loadCategories() async {
    try {
      final snap = await productsRef.get();
      final Set<String> set = {};
      for (final d in snap.docs) {
        final data = d.data() as Map<String, dynamic>;
        final cat = (data['category'] ?? '').toString().trim();
        if (cat.isNotEmpty) set.add(cat);
      }
      final list = set.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (!mounted) return;
      setState(() => _categories = list);
    } catch (_) {
      if (!mounted) return;
      setState(() => _categories = []);
    }
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
      _lines.add(
        IngresoLine(
          productId:
              _products != null && _products!.isNotEmpty ? _products!.first.id : null,
        ),
      );
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
        ln.category = p['category'] ?? '';
      }
    });
  }

  // Búsqueda superior
  List<QueryDocumentSnapshot> get _filteredProducts {
    if ((_products == null) || (_products!.isEmpty)) return [];
    final q = productFilterCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return [];
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

  // ==== Generar siguiente SKU simple
  Future<String> _generateNextSku() async {
    try {
      final q = await productsRef.orderBy('sku', descending: true).limit(1).get();
      if (q.docs.isEmpty) return '1001';
      final candidate =
          (q.docs.first.data() as Map<String, dynamic>)['sku']?.toString() ?? '';
      final n = int.tryParse(candidate);
      if (n == null) {
        final all = await productsRef.get();
        int maxN = 1000;
        for (final d in all.docs) {
          final sku =
              (d.data() as Map<String, dynamic>)['sku']?.toString();
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

  // ==== Modal: crear producto rápido
  Future<String?> _showNewProductModal({
    String? suggestedName,
    int? defaultStock,
    Map<String, dynamic>? baseProduct,
  }) async {
    final nameCtrl = TextEditingController(text: suggestedName ?? '');
    final skuCtrl = TextEditingController(text: await _generateNextSku());
    final purchaseCtrl = TextEditingController(
      text: baseProduct != null
          ? _toDouble(baseProduct['purchasePrice']).toStringAsFixed(2)
          : '',
    );
    final marginCtrl = TextEditingController(
      text: (baseProduct != null
              ? _toDouble(baseProduct['marginPercent'] ?? 10)
              : 10.0)
          .toStringAsFixed(0),
    );
    final priceCtrl = TextEditingController(
      text: baseProduct != null
          ? _toDouble(baseProduct['price']).toStringAsFixed(2)
          : '',
    );
    final unitsCtrl =
        TextEditingController(text: '${baseProduct?['unitsPerPack'] ?? 1}');
    String pharmForm = (baseProduct?['pharmForm'] ?? '').toString();
    String route = (baseProduct?['route'] ?? '').toString();
    String strength = (baseProduct?['strength'] ?? '').toString();
    String presentation = (baseProduct?['presentation'] ?? '').toString();
    String lot = (baseProduct?['lot'] ?? '').toString();
    DateTime? expiry = (baseProduct?['expiryDate'] as Timestamp?)?.toDate();
    bool taxable = (baseProduct?['taxable'] ?? false) == true;
    bool requiresRx =
        (baseProduct?['requiresPrescription'] ?? false) == true;
    String? providerId;
    String? category =
        (baseProduct?['category'] ?? '').toString().isNotEmpty
            ? baseProduct!['category']
            : null;

    final formKey = GlobalKey<FormState>();

    final res = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Widget labeled(Widget child) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: child,
                );
            return AlertDialog(
              title: const Text('Nuevo producto'),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.75,
                ),
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        labeled(
                          TextFormField(
                            controller: nameCtrl,
                            decoration:
                                const InputDecoration(labelText: 'Nombre *'),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Requerido'
                                : null,
                          ),
                        ),
                        labeled(
                          TextFormField(
                            controller: skuCtrl,
                            decoration:
                                const InputDecoration(labelText: 'SKU *'),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Requerido'
                                : null,
                          ),
                        ),
                        labeled(
                          DropdownButtonFormField<String>(
                            value: category,
                            decoration:
                                const InputDecoration(labelText: 'Categoría *'),
                            items: _categories
                                .map((e) => DropdownMenuItem(
                                      value: e,
                                      child: Text(e),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setLocal(() => category = v),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Requerido'
                                    : null,
                          ),
                        ),
                        labeled(
                          TextFormField(
                            controller: purchaseCtrl,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            decoration: const InputDecoration(
                                labelText: 'Precio compra (sin IVA)'),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Requerido'
                                : null,
                          ),
                        ),
                        labeled(
                          TextFormField(
                            controller: marginCtrl,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            decoration:
                                const InputDecoration(labelText: 'Margen %'),
                          ),
                        ),
                        labeled(
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: priceCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: 'Precio venta (opcional)'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: unitsCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      labelText: 'Unidades/emp'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        labeled(
                          DropdownButtonFormField<String>(
                            value: providerId,
                            decoration: const InputDecoration(
                                labelText: 'Proveedor (opcional)'),
                            items: (_providers ?? [])
                                .map(
                                  (p) => DropdownMenuItem(
                                    value: p.id,
                                    child: Text(
                                      (p.data()
                                              as Map<String, dynamic>)['name'] ??
                                          '—',
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setLocal(() => providerId = v),
                          ),
                        ),
                        labeled(
                          TextFormField(
                            controller: TextEditingController(text: lot),
                            decoration: const InputDecoration(
                                labelText: 'Lote (opcional)'),
                            onChanged: (v) => lot = v,
                          ),
                        ),
                        labeled(
                          Row(
                            children: [
                              Expanded(
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                      labelText: 'Vencimiento (opcional)'),
                                  child: Text(
                                    expiry != null
                                        ? _fmtDate(expiry!)
                                        : '—',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                children: [
                                  TextButton(
                                    onPressed: () async {
                                      final now = DateTime.now();
                                      final d =
                                          await showDatePicker(
                                        context: context,
                                        initialDate:
                                            expiry ?? now,
                                        firstDate:
                                            DateTime(now.year - 5),
                                        lastDate:
                                            DateTime(now.year + 15),
                                      );
                                      if (d != null) {
                                        setLocal(() => expiry = d);
                                      }
                                    },
                                    child:
                                        const Text('Seleccionar'),
                                  ),
                                  if (expiry != null)
                                    TextButton(
                                      onPressed: () => setLocal(
                                          () => expiry = null),
                                      child: const Text('Borrar'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        labeled(
                          TextFormField(
                            controller:
                                TextEditingController(text: strength),
                            decoration: const InputDecoration(
                                labelText: 'Concentración (opcional)'),
                            onChanged: (v) => strength = v,
                          ),
                        ),
                        labeled(
                          TextFormField(
                            controller: TextEditingController(
                                text: presentation),
                            decoration: const InputDecoration(
                                labelText: 'Presentación (opcional)'),
                            onChanged: (v) => presentation = v,
                          ),
                        ),
                        labeled(
                          DropdownButtonFormField<String>(
                            value: pharmForm.isNotEmpty
                                ? pharmForm
                                : null,
                            decoration:
                                const InputDecoration(labelText: 'Forma'),
                            items: const [
                              'Tableta',
                              'Cápsula',
                              'Jarabe',
                              'Gotas',
                              'Suspensión',
                              'Ungüento',
                              'Crema',
                              'Solución inyectable',
                              'Aerosol',
                              'Parche',
                            ]
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(e),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setLocal(() => pharmForm = v ?? ''),
                          ),
                        ),
                        labeled(
                          DropdownButtonFormField<String>(
                            value:
                                route.isNotEmpty ? route : null,
                            decoration:
                                const InputDecoration(labelText: 'Vía'),
                            items: const [
                              'Oral',
                              'Tópica',
                              'Oftálmica',
                              'Intravenosa',
                              'Intramuscular',
                              'Subcutánea',
                              'Rectal',
                              'Vaginal',
                              'Inhalatoria',
                            ]
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(e),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setLocal(() => route = v ?? ''),
                          ),
                        ),
                        labeled(
                          Row(
                            children: [
                              Checkbox(
                                value: taxable,
                                onChanged: (v) => setLocal(
                                    () => taxable = v ?? false),
                              ),
                              const SizedBox(width: 6),
                              const Text('Grava IVA'),
                              const SizedBox(width: 16),
                              Checkbox(
                                value: requiresRx,
                                onChanged: (v) => setLocal(() =>
                                    requiresRx = v ?? false),
                              ),
                              const SizedBox(width: 6),
                              const Text('Bajo receta'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Guardar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kGreen2,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    final payload = {
                      'name': nameCtrl.text.trim(),
                      'sku': skuCtrl.text.trim(),
                      'category': category,
                      'purchasePrice':
                          double.tryParse(purchaseCtrl.text
                                  .replaceAll(',', '.')) ??
                              0.0,
                      'marginPercent':
                          double.tryParse(marginCtrl.text
                                  .replaceAll(',', '.')) ??
                              10,
                      'price': double.tryParse(
                              priceCtrl.text.replaceAll(',', '.')) ??
                          0.0,
                      'stock': defaultStock ?? 0,
                      'lot': lot.trim(),
                      'expiryDate': expiry,
                      'pharmForm': pharmForm,
                      'route': route,
                      'strength': strength,
                      'presentation': presentation,
                      'taxable': taxable,
                      'requiresPrescription': requiresRx,
                      'providerId': providerId,
                      'unitsPerPack':
                          int.tryParse(unitsCtrl.text) ?? 1,
                      'createdAt': FieldValue.serverTimestamp(),
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
          },
        );
      },
    );

    return res;
  }

  // ====== GUARDAR ingreso con batches + movements ======
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
        _showSnack(
            'Escribe el nombre del producto nuevo en la fila ${i + 1}');
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

    // Determinar proveedor para ingreso y movements
    String? providerIdForDb;
    String providerNameForMovement = 'Proveedor';

    if (providerCtrl.text.trim().isNotEmpty) {
      providerIdForDb = providerCtrl.text.trim();
      QueryDocumentSnapshot? provDoc;
      if (_providers != null && _providers!.isNotEmpty) {
        try {
          provDoc = _providers!.firstWhere(
              (p) => p.id == providerIdForDb);
        } catch (_) {}
      }
      if (provDoc != null) {
        final data =
            provDoc.data() as Map<String, dynamic>;
        providerNameForMovement =
            (data['name'] ?? providerNameForMovement).toString();
      } else {
        providerNameForMovement = providerIdForDb;
      }
    } else if (_providers != null && _providers!.isNotEmpty) {
      providerIdForDb = _providers!.first.id;
      final data =
          _providers!.first.data() as Map<String, dynamic>;
      providerNameForMovement =
          (data['name'] ?? 'Proveedor').toString();
    }

    setState(() => _loading = true);

    try {
      await FirebaseFirestore.instance
          .runTransaction((tx) async {
        // 1) Crear productos nuevos (si los hay)
        for (final l in _lines.where((x) => x.isNew)) {
          final newRef = productsRef.doc();
          tx.set(newRef, {
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
          });
          l.productId = newRef.id;
          l.isNew = false;
        }

        // 2) Validar productos existentes y guardar snapshot
        final Map<String, Map<String, dynamic>> productSnapshots = {};
        for (final l in _lines) {
          final prodRef = productsRef.doc(l.productId);
          final prodSnap = await tx.get(prodRef);
          if (!prodSnap.exists) {
            throw Exception('Producto no encontrado: ${l.productId}');
          }
          productSnapshots[l.productId!] =
              prodSnap.data() as Map<String, dynamic>;
        }

        // 3) Crear documento de ingreso
        final ingresoRef = ingresosRef.doc();

        // para calcular stockBefore / stockAfter por producto
        final Map<String, int> accumulatedByProduct = {};

        final itemsForDb = _lines.map((l) {
          final pid = l.productId!;
          final existingData =
              productSnapshots[pid] ?? {};
          final baseStock =
              _toInt(existingData['stock']);
          final alreadyAdded =
              accumulatedByProduct[pid] ?? 0;
          final stockBefore = baseStock + alreadyAdded;
          final stockAfter = stockBefore + l.qty;
          accumulatedByProduct[pid] =
              alreadyAdded + l.qty;

          Map<String, dynamic> productData;
          if (_prodMap.containsKey(pid)) {
            productData = _prodMap[pid]!;
          } else if (l.newName.trim().isNotEmpty ||
              l.newSku.trim().isNotEmpty) {
            productData = {
              'name': l.newName.trim(),
              'sku': l.newSku.trim(),
            };
          } else {
            productData = existingData;
          }

          return {
            'productId': pid,
            'productName': productData['name'],
            'sku': productData['sku'],
            'qty': l.qty, // int
            'purchasePrice':
                _toDouble(l.purchasePrice.toStringAsFixed(2)),
            'salePrice':
                _toDouble(l.salePrice.toStringAsFixed(2)),
            'subtotal':
                _toDouble(l.subtotal.toStringAsFixed(2)),
            'lot':
                l.lot.trim().isEmpty ? null : l.lot.trim(),
            'manufactureDate': l.manufactureDate != null
                ? Timestamp.fromDate(l.manufactureDate!)
                : null,
            'expiryDate': l.expiryDate != null
                ? Timestamp.fromDate(l.expiryDate!)
                : null,
            // ⬇️ para detalle de movimientos
            'stockBefore': stockBefore,
            'stockAfter': stockAfter,
          };
        }).toList();

        tx.set(ingresoRef, {
          'userId': FirebaseAuth.instance.currentUser?.uid,
          'items': itemsForDb,
          'total': _total,
          'providerId': providerIdForDb,
          'invoice': invoiceCtrl.text.trim(),
          'purchaseDate': purchaseDate != null
              ? Timestamp.fromDate(purchaseDate!)
              : FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        });

        // 3b) Crear resumen en 'movements'
        final movementsRef =
            FirebaseFirestore.instance.collection('movements');
        final movementDocRef = movementsRef.doc();

        final currentUser = FirebaseAuth.instance.currentUser;
        final createdByName = currentUser?.displayName ??
            currentUser?.email ??
            'Usuario';
        final totalItems = itemsForDb.fold<int>(
          0,
          (s, it) => s + (it['qty'] as int),
        );

        tx.set(movementDocRef, {
          'type': 'ingreso',
          'ingresoId': ingresoRef.id,
          'createdAt': FieldValue.serverTimestamp(),
          'createdByUid': currentUser?.uid,
          'createdByName': createdByName,
          'note': invoiceCtrl.text.trim(),
          'counterpartyType': 'proveedor',
          'counterpartyName': providerNameForMovement,
          'totalItems': totalItems,
          'totalAmount': _total,
          'items': itemsForDb,
        });

        // 4) Para cada línea: crear batch en subcollection y actualizar stock/precios
        for (final l in _lines) {
          final prodRef = productsRef.doc(l.productId);

          // crear batch
          final batchRef = prodRef.collection('batches').doc();
          tx.set(batchRef, {
            'lot': l.lot.trim().isNotEmpty ? l.lot.trim() : null,
            'qty': l.qty, // int
            'expiryDate': l.expiryDate != null
                ? Timestamp.fromDate(l.expiryDate!)
                : null,
            'purchasePrice': l.purchasePrice,
            'ingresoId': ingresoRef.id,
            'createdAt': FieldValue.serverTimestamp(),
          });

          // actualizar producto (incrementando stock)
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

  // ====== IMPRIMIR ingreso ======
  Future<void> _print() async {
    if (_lines.isEmpty) {
      _showSnack('No hay ítems para imprimir.');
      return;
    }
    final now = DateTime.now();
    final items = _lines.map((l) {
      final baseName = l.isNew
          ? l.newName
          : (_prodMap[l.productId]?['name'] ?? 'Producto');
      final lotPart =
          (l.lot.trim().isNotEmpty ? 'Lote: ${l.lot.trim()}' : '');
      final expiryPart = (l.expiryDate != null
          ? 'Vence: ${_fmtDate(l.expiryDate!)}'
          : '');
      final extra = [lotPart, expiryPart]
          .where((s) => s.isNotEmpty)
          .join(' • ');
      final displayName =
          extra.isEmpty ? baseName : '$baseName  ($extra)';
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
      buyer: providerCtrl.text.trim().isEmpty
          ? 'Proveedor'
          : providerCtrl.text.trim(),
      notes: invoiceCtrl.text.trim().isEmpty
          ? ''
          : 'Factura: ${invoiceCtrl.text.trim()}',
      items: items,
      subtotal: _total,
      iva: 0,
      total: _total,
    );

    await pdf_out.outputPdf(
      bytes,
      'ingreso_${now.millisecondsSinceEpoch}.pdf',
    );
  }

  // ====== UI ======
  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    // Detectar si ya hay Scaffold/Material
    final hasMaterialAncestor =
        context.findAncestorWidgetOfExactType<Material>() != null;
    final hasScaffoldAncestor =
        context.findAncestorWidgetOfExactType<Scaffold>() != null;

    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: _products == null
              ? const Center(child: CircularProgressIndicator())
              : Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Gestión de Compras',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: kGreen1,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // BUSCADOR tipo egresos
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius:
                                BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.green.shade100),
                          ),
                          child: TextField(
                            controller: productFilterCtrl,
                            decoration:
                                const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText:
                                  'Buscar producto (nombre, descripción o SKU)...',
                              border: InputBorder.none,
                              contentPadding:
                                  EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 14),
                            ),
                          ),
                        ),

                        if (_filteredProducts.isNotEmpty)
                          const SizedBox(height: 10),

                        // SUGERENCIAS
                        if (_filteredProducts.isNotEmpty)
                          Container(
                            constraints:
                                const BoxConstraints(
                                    maxHeight: 220),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount:
                                  _filteredProducts.length,
                              itemBuilder:
                                  (context, i) {
                                final p =
                                    _filteredProducts[i];
                                final d = p.data()
                                    as Map<String, dynamic>;
                                final stock =
                                    _toInt(d['stock']);
                                final purchase =
                                    _toDouble(
                                        d['purchasePrice']);
                                final margin = _toDouble(
                                    d['marginPercent'] ??
                                        10);
                                final suggestedSale =
                                    purchase *
                                        (1 +
                                            (margin / 100));
                                final name =
                                    (d['name']
                                            as String?) ??
                                        p.id;
                                final form =
                                    (d['pharmForm'] ?? '')
                                        .toString();
                                final route =
                                    (d['route'] ?? '')
                                        .toString();
                                final strength =
                                    (d['strength'] ?? '')
                                        .toString();
                                final pres =
                                    (d['presentation'] ??
                                            '')
                                        .toString();

                                return Padding(
                                  padding:
                                      const EdgeInsets
                                          .only(
                                              bottom:
                                                  8.0),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment
                                            .start,
                                    children: [
                                      Expanded(
                                        child:
                                            Container(
                                          padding:
                                              const EdgeInsets
                                                  .all(
                                                      12),
                                          decoration:
                                              BoxDecoration(
                                            color: Colors
                                                .green
                                                .shade100,
                                            borderRadius:
                                                BorderRadius
                                                    .circular(
                                                        8),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment
                                                    .start,
                                            children: [
                                              Text(
                                                name,
                                                maxLines:
                                                    2,
                                                overflow:
                                                    TextOverflow
                                                        .ellipsis,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold),
                                              ),
                                              const SizedBox(
                                                  height:
                                                      4),
                                              Wrap(
                                                spacing:
                                                    10,
                                                runSpacing:
                                                    6,
                                                children: [
                                                  if (form.isNotEmpty ||
                                                      route.isNotEmpty)
                                                    _pill(
                                                        '${form.isEmpty ? '—' : form} / ${route.isEmpty ? '—' : route}'),
                                                  if (strength
                                                      .isNotEmpty)
                                                    _pill(
                                                        'Conc.: $strength'),
                                                  if (pres
                                                      .isNotEmpty)
                                                    _pill(
                                                        'Pres.: $pres'),
                                                  _pill(
                                                      'Stock: $stock'),
                                                  _pill(
                                                      'Compra: \$${purchase.toStringAsFixed(2)}'),
                                                  _pill(
                                                      'Venta sug.: \$${suggestedSale.toStringAsFixed(2)}'),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(
                                          width: 8),
                                      Column(
                                        children: [
                                          ElevatedButton(
                                            onPressed:
                                                () =>
                                                    _showDetailsDialog(d),
                                            style:
                                                ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Colors.green,
                                              foregroundColor:
                                                  Colors.white,
                                            ),
                                            child: const Text(
                                                'Detalles'),
                                          ),
                                          const SizedBox(
                                              height:
                                                  8),
                                          ElevatedButton(
                                            onPressed:
                                                () => _addFromQuickList(p),
                                            style:
                                                ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Colors.green,
                                              foregroundColor:
                                                  Colors.white,
                                            ),
                                            child: const Text(
                                                'Agregar'),
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

                        // Acciones sobre líneas
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: _addEmptyLine,
                              icon: const Icon(Icons.add),
                              label:
                                  const Text('Agregar línea'),
                              style:
                                  ElevatedButton.styleFrom(
                                backgroundColor: kGreen2,
                                foregroundColor:
                                    Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () async {
                                final newId =
                                    await _showNewProductModal();
                                if (newId != null) {
                                  await _loadData();
                                  _showSnack(
                                      'Producto creado y listo para seleccionar.');
                                }
                              },
                              icon: const Icon(
                                  Icons.add_box_outlined),
                              label: const Text(
                                  'Nuevo producto'),
                              style:
                                  ElevatedButton.styleFrom(
                                backgroundColor: kGreen2,
                                foregroundColor:
                                    Colors.white,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Encabezado (solo en pantallas medianas/anchas)
                        if (isWide)
                          Container(
                            padding:
                                const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius:
                                  BorderRadius.circular(
                                      6),
                            ),
                            child: Row(
                              children: const [
                                Expanded(
                                    child:
                                        Text('Producto')),
                                SizedBox(
                                    width: 80,
                                    child: Text('Cant.')),
                                SizedBox(
                                    width: 140,
                                    child: Text('Compra')),
                                SizedBox(
                                    width: 140,
                                    child: Text(
                                        'Venta sug.')),
                                SizedBox(width: 40, child: Text('')),
                              ],
                            ),
                          ),
                        if (isWide) const SizedBox(height: 8),

                        // Líneas
                        ListView.builder(
                          shrinkWrap: true,
                          physics:
                              const NeverScrollableScrollPhysics(),
                          itemCount: _lines.length,
                          itemBuilder: (context, idx) =>
                              _lineTile(
                                  _lines[idx], idx, isWide),
                        ),

                        const SizedBox(height: 12),

                        // Proveedor, factura, fecha
                        Row(
                          children: [
                            Expanded(
                              child:
                                  DropdownButtonFormField<
                                      String>(
                                value: _providers != null &&
                                        _providers!
                                            .isNotEmpty
                                    ? _providers!.first.id
                                    : null,
                                items: _providers
                                    ?.map((p) {
                                      final d = p.data()
                                          as Map<String,
                                              dynamic>;
                                      return DropdownMenuItem(
                                        value: p.id,
                                        child:
                                            Text(d['name'] ??
                                                '—'),
                                      );
                                    })
                                    .toList(),
                                onChanged: (v) =>
                                    providerCtrl.text =
                                        v ?? '',
                                decoration:
                                    const InputDecoration(
                                  labelText: 'Proveedor',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 220,
                              child: TextFormField(
                                controller: invoiceCtrl,
                                decoration:
                                    const InputDecoration(
                                  labelText:
                                      'N° factura / serie',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                purchaseDate == null
                                    ? 'Fecha de compra: —'
                                    : 'Compra: ${purchaseDate!.day.toString().padLeft(2, '0')}/${purchaseDate!.month.toString().padLeft(2, '0')}/${purchaseDate!.year}',
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                final now =
                                    DateTime.now();
                                final d =
                                    await showDatePicker(
                                  context: context,
                                  initialDate:
                                      purchaseDate ??
                                          now,
                                  firstDate:
                                      DateTime(
                                          now.year -
                                              5),
                                  lastDate:
                                      DateTime(
                                          now.year +
                                              1),
                                );
                                if (d != null) {
                                  setState(() =>
                                      purchaseDate =
                                          d);
                                }
                              },
                              child:
                                  const Text('Seleccionar'),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Acciones rápidas + total
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          crossAxisAlignment:
                              WrapCrossAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed: _lines.isEmpty &&
                                      providerCtrl
                                          .text.isEmpty &&
                                      invoiceCtrl
                                          .text.isEmpty &&
                                      purchaseDate ==
                                          null
                                  ? null
                                  : _clearAll,
                              style:
                                  ElevatedButton.styleFrom(
                                backgroundColor:
                                    Colors.green,
                                foregroundColor:
                                    Colors.white,
                              ),
                              child:
                                  const Text('L  •  Limpiar'),
                            ),
                            ElevatedButton(
                              onPressed:
                                  _lines.isEmpty
                                      ? null
                                      : _print,
                              style:
                                  ElevatedButton.styleFrom(
                                backgroundColor:
                                    Colors.green,
                                foregroundColor:
                                    Colors.white,
                              ),
                              child: const Text(
                                  'I  •  Imprimir PDF'),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Total: \$${_total.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                            ElevatedButton(
                              onPressed: _loading
                                  ? null
                                  : _save,
                              style:
                                  ElevatedButton.styleFrom(
                                backgroundColor: kGreen2,
                                foregroundColor:
                                    Colors.white,
                              ),
                              child: _loading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child:
                                          CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      'Registrar compra'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );

    if (hasMaterialAncestor && hasScaffoldAncestor) {
      return content;
    }

    // Ruta independiente
    return Material(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Registrar compra (Ingreso)'),
          backgroundColor: kGreen2,
        ),
        body: SafeArea(child: content),
      ),
    );
  }

  // ====== Tile de línea ======
  Widget _lineTile(IngresoLine ln, int idx, bool isWide) {
    final nameForExisting = ln.productId != null
        ? (_prodMap[ln.productId]?['name'] ?? 'Producto')
        : 'Producto';
    final titleText =
        ln.isNew ? 'Nuevo producto' : nameForExisting;

    final productSelector =
        DropdownButtonFormField<String>(
      value: ln.productId,
      items: (_products ?? []).map((p) {
        final d = p.data() as Map<String, dynamic>;
        final stock = _toInt(d['stock']);
        final label =
            '${d['name'] ?? '—'} • ${d['sku'] ?? '—'} • Stock: $stock';
        return DropdownMenuItem(
          value: p.id,
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: (v) => _onChooseProduct(idx, v),
      decoration: const InputDecoration(
        labelText: 'Producto',
        border: InputBorder.none,
      ),
    );

    final categoryDisplay = Text(
      'Categoría: ${ln.category ?? 'N/A'}',
      style: const TextStyle(
        fontSize: 12,
        color: Colors.grey,
      ),
    );

    final productNewFields = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          initialValue: ln.newName,
          decoration: const InputDecoration(
            labelText: 'Nombre del nuevo producto *',
            border: InputBorder.none,
          ),
          onChanged: (v) => ln.newName = v,
        ),
        const SizedBox(height: 6),
        TextFormField(
          initialValue: ln.newSku,
          decoration: const InputDecoration(
            labelText: 'SKU (opcional)',
            border: InputBorder.none,
          ),
          onChanged: (v) => ln.newSku = v,
        ),
      ],
    );

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ln.isNew ? productNewFields : productSelector,
            ),
            const SizedBox(width: 8),
          ],
        ),
        if (ln.category != null) categoryDisplay,
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
            decoration: const InputDecoration(
              labelText: 'Cant.',
              border: InputBorder.none,
            ),
            onChanged: (v) => setState(
              () => ln.qty = int.tryParse(v) ?? ln.qty,
            ),
          ),
        ),
        SizedBox(
          width: 130,
          child: TextFormField(
            key: ValueKey('purchasePrice_$idx'),
            initialValue:
                ln.purchasePrice.toStringAsFixed(2),
            keyboardType:
                const TextInputType.numberWithOptions(
                    decimal: true),
            decoration: const InputDecoration(
              labelText: 'Compra',
              border: InputBorder.none,
            ),
            onChanged: (v) {
              setState(() {
                ln.purchasePrice = _toDouble(v);
                final margin = 10.0;
                if (ln.salePrice == 0) {
                  ln.salePrice = ln.purchasePrice *
                      (1 + (margin / 100));
                }
              });
            },
          ),
        ),
        SizedBox(
          width: 130,
          child: TextFormField(
            key: ValueKey('salePrice_$idx'),
            initialValue:
                ln.salePrice.toStringAsFixed(2),
            keyboardType:
                const TextInputType.numberWithOptions(
                    decimal: true),
            decoration: const InputDecoration(
              labelText: 'Venta sug.',
              border: InputBorder.none,
            ),
            onChanged: (v) =>
                setState(() => ln.salePrice = _toDouble(v)),
          ),
        ),
        SizedBox(
          width: 120,
          child: TextFormField(
            initialValue: ln.lot,
            keyboardType: TextInputType.text,
            decoration: const InputDecoration(
              labelText: 'Lote',
              border: InputBorder.none,
            ),
            onChanged: (v) =>
                setState(() => ln.lot = v),
          ),
        ),
        IconButton(
          onPressed: () => _removeLine(idx),
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: isWide
            ? Column(
                children: [
                  Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Expanded(child: left),
                      const SizedBox(width: 8),
                      right,
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          ln.manufactureDate == null
                              ? 'Fab.: —'
                              : 'Fab.: ${_fmtDate(ln.manufactureDate!)}',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          ln.expiryDate == null
                              ? 'Vence: —'
                              : 'Vence: ${_fmtDate(ln.expiryDate!)}',
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            _pickDateForLine(idx,
                                isManufacture: true),
                        child: const Text('Fab.'),
                      ),
                      TextButton(
                        onPressed: () =>
                            _pickDateForLine(idx,
                                isManufacture: false),
                        child: const Text('Vence'),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Subtotal: \$${ln.subtotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              )
            : Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    titleText,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  left,
                  const SizedBox(height: 8),
                  right,
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Subtotal: \$${ln.subtotal.toStringAsFixed(2)}',
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          ln.manufactureDate == null
                              ? 'Fab.: —'
                              : 'Fab.: ${_fmtDate(ln.manufactureDate!)}',
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            _pickDateForLine(idx,
                                isManufacture: true),
                        child: const Text('Seleccionar'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          ln.expiryDate == null
                              ? 'Vence: —'
                              : 'Vence: ${_fmtDate(ln.expiryDate!)}',
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            _pickDateForLine(idx,
                                isManufacture: false),
                        child: const Text('Seleccionar'),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _pickDateForLine(
    int idx, {
    required bool isManufacture,
  }) async {
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

  // ====== Detalles ======
  Future<void> _showDetailsDialog(
      Map<String, dynamic> d) async {
    if (d.isEmpty) return;
    final name = (d['name'] ?? 'Producto').toString();
    final price = _toDouble(d['price']);
    final purchase = _toDouble(d['purchasePrice']);
    final stock = _toInt(d['stock']);
    final taxable = (d['taxable'] ?? false) == true;
    final iva = _toDouble(d['ivaPercent'] ?? 13);
    final expiry =
        (d['expiryDate'] as Timestamp?)?.toDate();
    final form = (d['pharmForm'] ?? '').toString();
    final route = (d['route'] ?? '').toString();
    final strength =
        (d['strength'] ?? '').toString();
    final pres =
        (d['presentation'] ?? '').toString();
    final requiresRx =
        (d['requiresPrescription'] ?? false) == true;

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
            _kv('Precio compra',
                '\$${purchase.toStringAsFixed(2)}'),
            _kv('Precio venta',
                '\$${price.toStringAsFixed(2)}'),
            _kv('IVA',
                taxable ? '${iva.toStringAsFixed(0)}%' : 'No grava'),
            if (expiry != null)
              _kv('Vencimiento', _fmtDate(expiry)),
            if (form.isNotEmpty || route.isNotEmpty)
              _kv(
                'Forma/Vía',
                '${form.isEmpty ? '—' : form} / ${route.isEmpty ? '—' : route}',
              ),
            if (strength.isNotEmpty)
              _kv('Concentración', strength),
            if (pres.isNotEmpty)
              _kv('Presentación', pres),
            if (requiresRx)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber,
                        color: Colors.red),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Producto bajo receta médica',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cerrar'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Nuevo producto similar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kGreen2,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final newId = await _showNewProductModal(
                suggestedName: name,
                baseProduct: d,
              );
              if (newId != null) {
                await _loadData();
                Navigator.pop(c);
                final basePurchase =
                    _toDouble(d['purchasePrice']);
                final baseMargin =
                    _toDouble(d['marginPercent'] ?? 10);
                final suggestedSale =
                    basePurchase * (1 + baseMargin / 100);
                setState(() {
                  _lines.insert(
                    0,
                    IngresoLine(
                      productId: newId,
                      qty: 1,
                      purchasePrice: basePurchase,
                      salePrice: suggestedSale,
                    ),
                  );
                });
                _showSnack(
                    'Producto similar creado y agregado a la compra.');
              }
            },
          ),
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
              child: Text(
                k,
                style: const TextStyle(
                    fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(child: Text(v)),
          ],
        ),
      );

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Widget _pill(String t) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          border:
              Border.all(color: Colors.green.shade300),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          t,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}
