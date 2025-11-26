import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'app_theme.dart';

class AdminProductManager extends StatefulWidget {
  const AdminProductManager({super.key});

  @override
  State<AdminProductManager> createState() => _AdminProductManagerState();
}

class _AdminProductManagerState extends State<AdminProductManager> {
  final CollectionReference productsRef =
      FirebaseFirestore.instance.collection('products');
  final CollectionReference providersRef =
      FirebaseFirestore.instance.collection('providers');

  bool _loadingAction = false;
  List<String> _categories = [];
  Map<String, String> _providers = {}; // providerId -> displayName

  // Hints desde BD (por si luego usas sugerencias)
  final Set<String> _hintStrengths = {};
  final Set<String> _hintPresentations = {};

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadProviders();
    _preloadHints();
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

  Future<void> _loadProviders() async {
    try {
      final snap = await providersRef.get();
      final map = <String, String>{};
      for (final d in snap.docs) {
        final data = d.data() as Map<String, dynamic>;
        map[d.id] =
            (data['name'] ?? data['displayName'] ?? 'Proveedor').toString();
      }
      if (!mounted) return;
      setState(() => _providers = map);
    } catch (_) {
      if (!mounted) return;
      setState(() => _providers = {});
    }
  }

  Future<void> _preloadHints() async {
    try {
      final snap = await productsRef.limit(500).get();
      for (final d in snap.docs) {
        final m = d.data() as Map<String, dynamic>;
        final s = (m['strength'] ?? '').toString().trim();
        final p = (m['presentation'] ?? '').toString().trim();
        if (s.isNotEmpty) _hintStrengths.add(s);
        if (p.isNotEmpty) _hintPresentations.add(p);
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool?> _showConfirmation(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sí'),
          ),
        ],
      ),
    );
  }

  Future<String> _generateNextSku() async {
    try {
      final q =
          await productsRef.orderBy('sku', descending: true).limit(1).get();
      if (q.docs.isEmpty) return '1001';
      final candidate =
          (q.docs.first.data() as Map<String, dynamic>)['sku']?.toString() ??
              '';
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

  // ===== CRUD Firestore =====

  Future<void> _createProductFirestore(Map<String, dynamic> data) async {
    final map = _toFirestoreMap(data, isCreate: true);
    await productsRef.add(map);
  }

  Future<void> _updateProductFirestore(
      String id, Map<String, dynamic> data) async {
    final map = _toFirestoreMap(data, isCreate: false);
    await productsRef.doc(id).update(map);
  }

  Map<String, dynamic> _toFirestoreMap(Map<String, dynamic> data,
      {required bool isCreate}) {
    String nonNullStr(dynamic v) => (v ?? '').toString();

    final map = <String, dynamic>{
      'name': nonNullStr(data['name']),
      'sku': nonNullStr(data['sku']),
      'category': nonNullStr(data['category']),
      'description': nonNullStr(data['description']),
      'purchasePrice': _toNum(data['purchasePrice']), // sin IVA
      'marginPercent': _toNum(data['marginPercent'] ?? 10),
      'taxable': (data['taxable'] ?? false) == true,
      'ivaPercent': _toNum(data['ivaPercent'] ?? 13),
      'salePriceNet': _toNum(data['salePriceNet']), // sin IVA
      'price': _toNum(data['price']), // con IVA (si taxable)
      'priceIsPerUnit': (data['priceIsPerUnit'] ?? true) == true,
      'stock': _toNum(data['stock']),
      'providerId': data['providerId'],
      'requiresPrescription':
          (data['requiresPrescription'] ?? false) == true,
      'pharmForm': nonNullStr(data['pharmForm']),
      'route': nonNullStr(data['route']),
      'strength': nonNullStr(data['strength']),
      'presentation': nonNullStr(data['presentation']),
      'unitsPerPack': _toNum(data['unitsPerPack'] ?? 1),
    };

    map[isCreate ? 'createdAt' : 'updatedAt'] = FieldValue.serverTimestamp();
    return map;
  }

  num _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString().replaceAll(',', '.')) ?? 0;
  }

  Future<void> _deleteProductFirestore(String id) async {
    await productsRef.doc(id).delete();
  }

  // ===== Helpers =====

  DateTime? _parseExpiry(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) {
      try {
        return DateTime.parse(raw);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  bool _isNearExpiry(DateTime expiry) {
    final now = DateTime.now();
    final limit = now.add(const Duration(days: 90));
    return expiry.isBefore(limit);
  }

  // ====== Batches UI ======

  Widget _buildBatchesList(String productId) {
    return StreamBuilder<QuerySnapshot>(
      stream: productsRef
          .doc(productId)
          .collection('batches')
          .orderBy('expiryDate')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const ListTile(title: Text("Error al cargar lotes."));
        }
        if (!snapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: Text("Cargando lotes..."),
            ),
          );
        }
        if (snapshot.data!.docs.isEmpty) {
          return const ListTile(title: Text("No hay lotes registrados."));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child:
                  Text("Lotes", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ...snapshot.data!.docs.map((doc) {
              final batchData = doc.data() as Map<String, dynamic>;
              final expiry = _parseExpiry(batchData['expiryDate']);
              final near = expiry != null ? _isNearExpiry(expiry) : false;
              return ListTile(
                title: Text(
                    "Lote: ${batchData['lot'] ?? 'S/L'} - Cant: ${batchData['qty'] ?? 0}"),
                subtitle: expiry != null
                    ? Text(
                        "Vence: ${_ddmmyyyy(expiry)}",
                        style: TextStyle(
                            color: near ? Colors.red : Colors.black87),
                      )
                    : const Text("Sin fecha de vencimiento"),
                dense: true,
              );
            }).toList(),
          ],
        );
      },
    );
  }

  // ====== UI ======

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Center(
          child: Text(
            'Gestión de productos',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: kGreen1,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Botón NUEVO PRODUCTO
        Center(
          child: ElevatedButton.icon(
            onPressed: _showCreateProductDialog,
            icon: const Icon(Icons.add_box),
            label: const Text('Nuevo producto'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kGreen2,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        StreamBuilder<QuerySnapshot>(
          stream:
              productsRef.orderBy('createdAt', descending: true).snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return const Text('Error al cargar productos');
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data!.docs;

            return LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 900;

                if (isMobile) {
                  // ---- Móvil: Cards
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final d = docs[i];
                      final data = d.data() as Map<String, dynamic>;
                      final taxable = (data['taxable'] ?? false) == true;
                      final requiresRx =
                          (data['requiresPrescription'] ?? false) == true;

                      return Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor: kGreen3,
                            child: Text(
                              (data['name'] ?? 'P')
                                  .toString()
                                  .substring(0, 1)
                                  .toUpperCase(),
                            ),
                          ),
                          title: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            children: [
                              Text(
                                '${data['name'] ?? '—'}  '
                                '(${data['sku'] ?? '—'})',
                              ),
                              if (taxable) _chip('IVA', color: Colors.orange),
                              if (requiresRx)
                                _chip('Bajo receta',
                                    color: Colors.redAccent),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Categoría: ${data['category'] ?? '—'}'),
                              Text(
                                'Precio (venta): ${_fmt(data['price'])} • Stock: ${data['stock'] ?? 0}',
                              ),
                              if ((data['pharmForm'] ?? '')
                                      .toString()
                                      .isNotEmpty ||
                                  (data['route'] ?? '').toString().isNotEmpty)
                                Text(
                                  'Forma/Vía: ${(data['pharmForm'] ?? '—')} / ${(data['route'] ?? '—')}',
                                ),
                              if ((data['strength'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                Text('Concentración: ${data['strength']}'),
                              if ((data['presentation'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                Text('Presentación: ${data['presentation']}'),
                              if ((data['description'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                Text('Descripción: ${data['description']}'),
                            ],
                          ),
                          children: [
                            _buildBatchesList(d.id),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                  onPressed: () => _showEditProductDialog(d),
                                  icon: const Icon(Icons.edit),
                                  label: const Text("Editar"),
                                ),
                                TextButton.icon(
                                  onPressed: () => _tryDeleteProduct(d),
                                  icon: const Icon(Icons.delete),
                                  label: const Text("Eliminar"),
                                ),
                              ],
                            ),
                          ],
                          trailing: const Icon(Icons.keyboard_arrow_down),
                        ),
                      );
                    },
                  );
                } else {
                  // ---- Escritorio: DataTable
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Nombre')),
                        DataColumn(label: Text('SKU')),
                        DataColumn(label: Text('Categoría')),
                        DataColumn(label: Text('Descripción')),
                        DataColumn(label: Text('Precio (venta)')),
                        DataColumn(label: Text('IVA')),
                        DataColumn(label: Text('Receta')),
                        DataColumn(label: Text('Stock')),
                        DataColumn(label: Text('Forma/Vía')),
                        DataColumn(label: Text('Conc.')),
                        DataColumn(label: Text('Presentación')),
                        DataColumn(label: Text('Lotes')),
                        DataColumn(label: Text('Proveedor')),
                        DataColumn(label: Text('Acciones')),
                      ],
                      rows: docs.map((d) {
                        final data = d.data() as Map<String, dynamic>;
                        final taxable = (data['taxable'] ?? false) == true;
                        final requiresRx =
                            (data['requiresPrescription'] ?? false) == true;
                        final providerName = _providers[data['providerId']] ??
                            (data['providerId'] ?? '—');

                        return DataRow(
                          cells: [
                            DataCell(Text(data['name'] ?? '—')),
                            DataCell(Text(data['sku'] ?? '—')),
                            DataCell(Text(data['category'] ?? '—')),
                            DataCell(
                              Text(
                                (data['description'] ?? '—').toString(),
                              ),
                            ),
                            DataCell(Text(_fmt(data['price']))),
                            DataCell(
                              Icon(
                                taxable ? Icons.check_circle : Icons.cancel,
                                color: taxable ? Colors.orange : Colors.grey,
                              ),
                            ),
                            DataCell(
                              Icon(
                                requiresRx
                                    ? Icons.medical_services
                                    : Icons.remove,
                                color: requiresRx
                                    ? Colors.redAccent
                                    : Colors.grey,
                              ),
                            ),
                            DataCell(
                              Text((data['stock'] ?? 0).toString()),
                            ),
                            DataCell(
                              Text(
                                '${data['pharmForm'] ?? '—'} / ${data['route'] ?? '—'}',
                              ),
                            ),
                            DataCell(
                              Text(data['strength']?.toString() ?? '—'),
                            ),
                            DataCell(
                              Text(data['presentation']?.toString() ?? '—'),
                            ),
                            DataCell(
                              IconButton(
                                icon: const Icon(
                                  Icons.inventory_2_outlined,
                                ),
                                tooltip: 'Ver Lotes',
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: Text(
                                        "Lotes para ${data['name'] ?? ''}",
                                      ),
                                      content: SizedBox(
                                        width: 400,
                                        child: _buildBatchesList(d.id),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c),
                                          child: const Text("Cerrar"),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                            DataCell(Text(providerName.toString())),
                            DataCell(
                              Row(
                                children: [
                                  IconButton(
                                    onPressed: () async =>
                                        _showEditProductDialog(d),
                                    icon: const Icon(
                                      Icons.edit,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () async =>
                                        _tryDeleteProduct(d),
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  );
                }
              },
            );
          },
        ),

        if (_loadingAction)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  String _ddmmyyyy(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _fmt(dynamic n) {
    final v = _toNum(n).toDouble();
    return '\$${v.toStringAsFixed(2)}';
  }

  Widget _chip(String txt, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: (color ?? Colors.black54).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color ?? Colors.black54),
      ),
      child: Text(
        txt,
        style: TextStyle(fontSize: 12, color: color ?? Colors.black54),
      ),
    );
  }

  // ====== Acciones ======

  Future<void> _showCreateProductDialog() async {
    final sku = await _generateNextSku();
    await _showProductFormDialog(
      title: 'Nuevo producto',
      initial: {
        'sku': sku,
        'marginPercent': 10,
        'ivaPercent': 13,
        'taxable': false,
        'priceIsPerUnit': true,
        'requiresPrescription': false,
        'unitsPerPack': 1,
        'stock': 0,
      },
      onSubmit: (data) async {
        if (!mounted) return;
        setState(() => _loadingAction = true);
        try {
          await _createProductFirestore(data);
          _showSnack('Producto creado');
        } catch (e) {
          _showSnack('Error al crear: $e');
        } finally {
          if (mounted) setState(() => _loadingAction = false);
        }
      },
    );
  }

  Future<void> _showEditProductDialog(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final initial = Map<String, dynamic>.from(data)..['id'] = doc.id;
    if (initial['expiryDate'] is Timestamp) {
      initial['expiryDate'] =
          (initial['expiryDate'] as Timestamp).toDate();
    }

    await _showProductFormDialog(
      title: 'Editar producto',
      initial: initial,
      onSubmit: (payload) async {
        if (!mounted) return;
        setState(() => _loadingAction = true);
        try {
          await _updateProductFirestore(doc.id, payload);
          _showSnack('Producto actualizado');
        } catch (e) {
          _showSnack('Error al actualizar: $e');
        } finally {
          if (mounted) setState(() => _loadingAction = false);
        }
      },
    );
  }

  Future<void> _tryDeleteProduct(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final name = (data['name'] ?? '').toString();
    final ok = await _showConfirmation(
      'Eliminar',
      '¿Eliminar el producto "$name"?',
    );
    if (ok != true) return;
    if (!mounted) return;
    setState(() => _loadingAction = true);
    try {
      await _deleteProductFirestore(doc.id);
      _showSnack('Producto eliminado');
    } catch (e) {
      _showSnack('Error al eliminar: $e');
    } finally {
      if (mounted) setState(() => _loadingAction = false);
    }
  }

  // ====== Product Form (Create/Edit) en DIALOG personalizado ======
  Future<void> _showProductFormDialog({
    required String title,
    required Map<String, dynamic> initial,
    required Future<void> Function(Map<String, dynamic> data) onSubmit,
  }) async {
    final formKey = GlobalKey<FormState>();

    // Controllers
    final nameCtrl =
        TextEditingController(text: (initial['name'] ?? '').toString());
    final skuCtrl =
        TextEditingController(text: (initial['sku'] ?? '').toString());
    final descCtrl = TextEditingController(
        text: (initial['description'] ?? '').toString());
    final purchasePriceCtrl =
        TextEditingController(text: _numOrEmpty(initial['purchasePrice']));
    final marginCtrl =
        TextEditingController(text: _numOrEmpty(initial['marginPercent'] ?? 10));
    final ivaCtrl =
        TextEditingController(text: _numOrEmpty(initial['ivaPercent'] ?? 13));
    final saleNetCtrl =
        TextEditingController(text: _numOrEmpty(initial['salePriceNet']));
    final priceCtrl =
        TextEditingController(text: _numOrEmpty(initial['price']));
    final stockCtrl =
        TextEditingController(text: _numOrEmpty(initial['stock'] ?? 0));
    final strengthCtrl =
        TextEditingController(text: (initial['strength'] ?? '').toString());
    final presentationCtrl = TextEditingController(
        text: (initial['presentation'] ?? '').toString());
    final unitsPerPackCtrl = TextEditingController(
        text: _numOrEmpty(initial['unitsPerPack'] ?? 1));

    String? category =
        (initial['category'] ?? '').toString().isNotEmpty
            ? initial['category']?.toString()
            : null;
    String? providerId =
        (initial['providerId'] ?? '').toString().isNotEmpty
            ? initial['providerId']?.toString()
            : null;

    bool taxable = (initial['taxable'] ?? false) == true;
    bool requiresRx =
        (initial['requiresPrescription'] ?? false) == true;
    bool priceIsPerUnit = (initial['priceIsPerUnit'] ?? true) == true;

    String pharmForm = (initial['pharmForm'] ?? '').toString();
    String route = (initial['route'] ?? '').toString();

    bool autoPrice = (initial['autoPrice'] ?? true);
    if (initial['price'] == null ||
        initial['price'].toString().isEmpty) {
      autoPrice = true;
    }

    const pharmOptions = <String>[
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
    ];

    const routeOptions = <String>[
      'Oral',
      'Tópica',
      'Oftálmica',
      'Otica',
      'Intravenosa',
      'Intramuscular',
      'Subcutánea',
      'Rectal',
      'Vaginal',
      'Inhalatoria',
    ];

    if (category != null && !_categories.contains(category)) {
      category = null;
    }
    if (providerId != null && !_providers.keys.contains(providerId)) {
      providerId = null;
    }
    if (pharmForm.isNotEmpty && !pharmOptions.contains(pharmForm)) {
      pharmForm = '';
    }
    if (route.isNotEmpty && !routeOptions.contains(route)) {
      route = '';
    }

    void recalcFromPurchaseAndMargin() {
      final purchase = _toNum(purchasePriceCtrl.text).toDouble();
      final margin = _toNum(marginCtrl.text).toDouble();
      final iva = _toNum(ivaCtrl.text).toDouble();
      final net = purchase * (1 + (margin / 100)); // sin IVA
      final gross = taxable ? net * (1 + (iva / 100)) : net;
      saleNetCtrl.text = net.toStringAsFixed(4);
      priceCtrl.text = gross.toStringAsFixed(2);
    }

    void recalcFromPrice() {
      final gross = _toNum(priceCtrl.text).toDouble();
      final iva = _toNum(ivaCtrl.text).toDouble();
      final net = taxable ? (gross / (1 + (iva / 100))) : gross;
      saleNetCtrl.text = net.toStringAsFixed(4);
    }

    if (autoPrice) recalcFromPurchaseAndMargin();
    if (!autoPrice && priceCtrl.text.isNotEmpty) {
      recalcFromPrice();
    }

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setStateSB) {
            return Dialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.9,
                  maxWidth: MediaQuery.of(ctx).size.width * 0.95,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: nameCtrl,
                          decoration:
                              const InputDecoration(labelText: 'Nombre *'),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? 'Requerido'
                                  : null,
                        ),
                        const SizedBox(height: 8),

                        TextFormField(
                          controller: skuCtrl,
                          decoration:
                              const InputDecoration(labelText: 'SKU *'),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? 'Requerido'
                                  : null,
                        ),
                        const SizedBox(height: 8),

                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: category,
                                decoration: const InputDecoration(
                                  labelText: 'Categoría *',
                                ),
                                items: _categories
                                    .map(
                                      (e) => DropdownMenuItem(
                                        value: e,
                                        child: Text(
                                          e,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) {
                                  setStateSB(() {
                                    category = v;
                                  });
                                },
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                        ? 'Requerido'
                                        : null,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Agregar categoría',
                              onPressed: () async {
                                final res =
                                    await _showAddCategoryDialog(dialogContext);
                                if (!mounted) return;
                                if (res != null) {
                                  setStateSB(() {
                                    category = res;
                                  });
                                }
                              },
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        TextFormField(
                          controller: descCtrl,
                          decoration:
                              const InputDecoration(labelText: 'Descripción'),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 8),

                        DropdownButtonFormField<String>(
                          value: providerId,
                          decoration:
                              const InputDecoration(labelText: 'Proveedor'),
                          items: _providers.entries
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(
                                    e.value,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            setStateSB(() {
                              providerId = v;
                            });
                          },
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: purchasePriceCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Precio de COMPRA (sin IVA) *',
                          ),
                          validator: (v) =>
                              (_toNum(v) <= 0) ? 'Monto inválido' : null,
                          onChanged: (_) {
                            if (autoPrice) recalcFromPurchaseAndMargin();
                          },
                        ),
                        const SizedBox(height: 8),

                        TextFormField(
                          controller: marginCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Margen % (por defecto 10)',
                          ),
                          onChanged: (_) {
                            if (autoPrice) recalcFromPurchaseAndMargin();
                          },
                        ),
                        const SizedBox(height: 8),

                        SwitchListTile(
                          title: const Text('Producto grava IVA'),
                          value: taxable,
                          onChanged: (v) {
                            setStateSB(() {
                              taxable = v;
                              if (autoPrice) {
                                recalcFromPurchaseAndMargin();
                              } else {
                                recalcFromPrice();
                              }
                            });
                          },
                        ),

                        TextFormField(
                          controller: ivaCtrl,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'IVA % (13)'),
                          onChanged: (_) {
                            if (autoPrice) {
                              recalcFromPurchaseAndMargin();
                            } else {
                              recalcFromPrice();
                            }
                          },
                        ),
                        const SizedBox(height: 8),

                        SwitchListTile(
                          title: const Text(
                            'Calcular precio automáticamente',
                          ),
                          subtitle: const Text(
                            'Compra + margen (+ IVA si aplica)',
                          ),
                          value: autoPrice,
                          onChanged: (v) {
                            setStateSB(() {
                              autoPrice = v;
                              if (v) recalcFromPurchaseAndMargin();
                            });
                          },
                        ),

                        TextFormField(
                          controller: saleNetCtrl,
                          enabled: false,
                          decoration: const InputDecoration(
                            labelText: 'Precio de VENTA SIN IVA (calc.)',
                          ),
                        ),
                        const SizedBox(height: 8),

                        TextFormField(
                          controller: priceCtrl,
                          keyboardType: TextInputType.number,
                          enabled: !autoPrice,
                          decoration: InputDecoration(
                            labelText: taxable
                                ? 'Precio de VENTA (CON IVA)'
                                : 'Precio de VENTA',
                            helperText: autoPrice
                                ? 'Calculado automáticamente'
                                : 'Editable',
                          ),
                          onChanged: (_) {
                            if (!autoPrice) recalcFromPrice();
                          },
                        ),
                        const SizedBox(height: 8),

                        TextFormField(
                          controller: stockCtrl,
                          enabled: false,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Stock (Calculado)',
                          ),
                        ),
                        const SizedBox(height: 8),

                        SwitchListTile(
                          title: const Text('Precio es por unidad'),
                          value: priceIsPerUnit,
                          onChanged: (v) {
                            setStateSB(() {
                              priceIsPerUnit = v;
                            });
                          },
                        ),

                        SwitchListTile(
                          title: const Text('Producto bajo receta médica'),
                          value: requiresRx,
                          onChanged: (v) {
                            setStateSB(() {
                              requiresRx = v;
                            });
                          },
                        ),
                        const SizedBox(height: 8),

                        DropdownButtonFormField<String>(
                          value: pharmForm.isNotEmpty ? pharmForm : null,
                          decoration: const InputDecoration(
                            labelText: 'Forma farmacéutica',
                            helperText: 'Ej: Tableta, Cápsula, Jarabe…',
                          ),
                          items: pharmOptions
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e,
                                  child: Text(e),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            setStateSB(() {
                              pharmForm = v ?? '';
                            });
                          },
                        ),
                        const SizedBox(height: 8),

                        DropdownButtonFormField<String>(
                          value: route.isNotEmpty ? route : null,
                          decoration: const InputDecoration(
                            labelText: 'Vía de administración',
                            helperText: 'Ej: Oral, Tópica, Oftálmica…',
                          ),
                          items: routeOptions
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e,
                                  child: Text(e),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            setStateSB(() {
                              route = v ?? '';
                            });
                          },
                        ),
                        const SizedBox(height: 8),

                        TextFormField(
                          controller: strengthCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Concentración',
                            helperText: 'Ej: 500 mg • 5 mg/5 mL',
                          ),
                        ),
                        const SizedBox(height: 8),

                        TextFormField(
                          controller: presentationCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Presentación',
                            helperText: 'Ej: Caja x10 • Frasco 120 mL',
                          ),
                        ),
                        const SizedBox(height: 8),

                        TextFormField(
                          controller: unitsPerPackCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Unidades por empaque',
                          ),
                        ),
                        const SizedBox(height: 16),

                        ElevatedButton.icon(
                          icon: const Icon(Icons.save),
                          label: Text(
                            title.toLowerCase().contains('editar')
                                ? 'Actualizar'
                                : 'Agregar',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kGreen2,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) return;

                            final payload = <String, dynamic>{
                              'name': nameCtrl.text.trim(),
                              'sku': skuCtrl.text.trim(),
                              'category': (category ?? '').trim(),
                              'description': descCtrl.text.trim(),
                              'purchasePrice':
                                  _toNum(purchasePriceCtrl.text),
                              'marginPercent': _toNum(
                                marginCtrl.text.isEmpty
                                    ? '10'
                                    : marginCtrl.text,
                              ),
                              'taxable': taxable,
                              'ivaPercent': _toNum(
                                ivaCtrl.text.isEmpty ? '13' : ivaCtrl.text,
                              ),
                              'salePriceNet': _toNum(saleNetCtrl.text),
                              'price': _toNum(priceCtrl.text),
                              'priceIsPerUnit': priceIsPerUnit,
                              'stock': _toNum(stockCtrl.text),
                              'providerId': providerId,
                              'requiresPrescription': requiresRx,
                              'pharmForm': pharmForm.trim(),
                              'route': route.trim(),
                              'strength': strengthCtrl.text.trim(),
                              'presentation': presentationCtrl.text.trim(),
                              'unitsPerPack': _toNum(
                                unitsPerPackCtrl.text.isEmpty
                                    ? '1'
                                    : unitsPerPackCtrl.text,
                              ),
                            };

                            if (autoPrice) {
                              final purchase =
                                  _toNum(purchasePriceCtrl.text).toDouble();
                              final margin =
                                  _toNum(marginCtrl.text.isEmpty
                                              ? '10'
                                              : marginCtrl.text)
                                      .toDouble();
                              final iva =
                                  _toNum(ivaCtrl.text.isEmpty ? '13' : ivaCtrl.text)
                                      .toDouble();
                              final net = purchase * (1 + (margin / 100));
                              final gross =
                                  taxable ? net * (1 + (iva / 100)) : net;
                              payload['salePriceNet'] = net;
                              payload['price'] = gross;
                            } else {
                              final gross = _toNum(priceCtrl.text).toDouble();
                              final iva =
                                  _toNum(ivaCtrl.text.isEmpty ? '13' : ivaCtrl.text)
                                      .toDouble();
                              final net =
                                  taxable ? (gross / (1 + (iva / 100))) : gross;
                              payload['salePriceNet'] = net;
                            }

                            Navigator.of(dialogContext).pop();
                            await onSubmit(payload);
                          },
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(),
                          child: const Text('Cancelar'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Diálogo “Nueva categoría”
  Future<String?> _showAddCategoryDialog(
    BuildContext dialogCtx, {
    String initial = '',
  }) async {
    final TextEditingController newCatCtrl =
        TextEditingController(text: initial);
    final String? res = await showDialog<String>(
      context: dialogCtx,
      barrierDismissible: true,
      useRootNavigator: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva categoría'),
        content: TextField(
          controller: newCatCtrl,
          autofocus: true,
          decoration:
              const InputDecoration(hintText: 'Ej. Analgésicos'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = newCatCtrl.text.trim();
              if (name.isNotEmpty) Navigator.of(ctx).pop(name);
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );

    if (res != null && res.trim().isNotEmpty) {
      final name = res.trim();
      if (!_categories.contains(name)) {
        setState(() {
          _categories = [..._categories, name]
            ..sort((a, b) =>
                a.toLowerCase().compareTo(b.toLowerCase()));
        });
      }
      return name;
    }
    return null;
  }

  String _numOrEmpty(dynamic n) {
    if (n == null) return '';
    if (n is num) return n.toString();
    return n.toString();
  }
}
