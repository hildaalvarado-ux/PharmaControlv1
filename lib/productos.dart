// lib/admin_product_manager.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'app_theme.dart';

class AdminProductManager extends StatefulWidget {
  const AdminProductManager({super.key});

  @override
  State<AdminProductManager> createState() => _AdminProductManagerState();
}

class _AdminProductManagerState extends State<AdminProductManager> {
  final CollectionReference productsRef = FirebaseFirestore.instance.collection('products');
  final CollectionReference providersRef = FirebaseFirestore.instance.collection('providers');

  bool _loadingAction = false;

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
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Si')),
        ],
      ),
    );
  }

  // Genera un sku secuencial (empieza en 1001)
  Future<String> _generateNextSku() async {
    try {
      final q = await productsRef.orderBy('sku', descending: true).limit(1).get();
      if (q.docs.isEmpty) return '1001';
      final candidate = (q.docs.first.data() as Map<String, dynamic>)['sku']?.toString() ?? '';
      final n = int.tryParse(candidate);
      if (n == null) {
        // Si el sku más alto no es numérico, fallback a buscar el mayor numérico entre todos
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

  // --- CRUD Firestore ---
  Future<void> _createProductFirestore(Map<String, dynamic> data) async {
    // Construimos el mapa y añadimos expiryDate solo si existe y es DateTime
    final Map<String, dynamic> map = {
      'name': data['name'],
      'sku': data['sku'],
      'category': data['category'],
      'description': data['description'] ?? '',
      'purchasePrice': data['purchasePrice'],
      'price': data['price'],
      'marginPercent': data['marginPercent'] ?? 10,
      'priceIsPerUnit': data['priceIsPerUnit'] ?? true,
      'stock': data['stock'],
      'providerId': data['providerId'],
      'createdAt': FieldValue.serverTimestamp(),
    };

    // --- expiry ---
    if (data.containsKey('expiryDate') && data['expiryDate'] is DateTime) {
      map['expiryDate'] = Timestamp.fromDate(data['expiryDate'] as DateTime);
    }
    // ---

    await productsRef.add(map);
  }

  Future<void> _updateProductFirestore(String id, Map<String, dynamic> data) async {
    final Map<String, dynamic> map = {
      'name': data['name'],
      'sku': data['sku'],
      'category': data['category'],
      'description': data['description'] ?? '',
      'purchasePrice': data['purchasePrice'],
      'price': data['price'],
      'marginPercent': data['marginPercent'] ?? 10,
      'priceIsPerUnit': data['priceIsPerUnit'] ?? true,
      'stock': data['stock'],
      'providerId': data['providerId'],
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // --- expiry ---
    // Si se pasa expiryDate como DateTime lo guardamos; si está explícitamente null,
    // borramos el campo en Firestore (para permitir quitar una fecha). Si no se incluye la clave, no la tocamos.
    if (data.containsKey('expiryDate')) {
      final v = data['expiryDate'];
      if (v is DateTime) {
        map['expiryDate'] = Timestamp.fromDate(v);
      } else if (v == null) {
        // Para borrar el campo expiryDate en Firestore:
        map['expiryDate'] = FieldValue.delete();
      }
    }
    // ---

    await productsRef.doc(id).update(map);
  }

  Future<void> _deleteProductFirestore(String id) async {
    await productsRef.doc(id).delete();
  }

  // --- Dialog: crear producto ---
  Future<void> _showCreateProductDialog() async {
    final _formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final categoryCtrl = TextEditingController();
    final descriptionCtrl = TextEditingController();
    final purchasePriceCtrl = TextEditingController(); // precio de compra
    final priceCtrl = TextEditingController(); // precio de venta (calculado o editable)
    final stockCtrl = TextEditingController(text: '0');
    bool priceIsPerUnit = true;
    bool manualPrice = false; // si true, el usuario editará price manualmente
    double marginPercent = 10.0;
    String? selectedProviderId;

    // --- expiry ---
    DateTime? pickedExpiry;
    // ---

    // load providers for dropdown
    final providersSnap = await providersRef.orderBy('name').get();
    final providers = providersSnap.docs;

    // generate sku
    final nextSku = await _generateNextSku();
    final skuCtrl = TextEditingController(text: nextSku);

    final created = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (context, setState) {
        void _recalcPriceFromPurchase() {
          final p = double.tryParse(purchasePriceCtrl.text.replaceAll(',', '.')) ?? 0.0;
          final calculated = (p * (1 + marginPercent / 100));
          priceCtrl.text = calculated.toStringAsFixed(2);
        }

        return AlertDialog(
          title: const Text('Crear producto'),
          content: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre'), validator: (v) => v == null || v.trim().isEmpty ? 'Ingrese nombre' : null),
                const SizedBox(height: 8),
                // SKU es autogenerado, pero editable si quieres ajustar
                TextFormField(controller: skuCtrl, decoration: const InputDecoration(labelText: 'SKU (id)'), validator: (v) => v == null || v.trim().isEmpty ? 'SKU requerido' : null),
                const SizedBox(height: 8),
                TextFormField(controller: categoryCtrl, decoration: const InputDecoration(labelText: 'Categoría'), validator: (v) => v == null || v.trim().isEmpty ? 'Ingrese categoría' : null),
                const SizedBox(height: 8),
                TextFormField(controller: descriptionCtrl, decoration: const InputDecoration(labelText: 'Descripción (uso, indicación, presentaciones)'), maxLines: 2),
                const SizedBox(height: 8),
                // --- picker expiry ---
                Row(
                  children: [
                    Expanded(
                      child: Text(pickedExpiry == null ? 'Fecha de vencimiento: —' : 'Fecha de vencimiento: ${pickedExpiry!.day}/${pickedExpiry!.month}/${pickedExpiry!.year}'),
                    ),
                    TextButton(
                      onPressed: () async {
                        final now = DateTime.now();
                        final d = await showDatePicker(
                          context: context,
                          initialDate: pickedExpiry ?? now,
                          firstDate: DateTime(now.year - 5),
                          lastDate: DateTime(now.year + 10),
                        );
                        if (d != null) setState(() => pickedExpiry = d);
                      },
                      child: const Text('Seleccionar'),
                    ),
                    if (pickedExpiry != null)
                      IconButton(
                        onPressed: () => setState(() => pickedExpiry = null),
                        icon: const Icon(Icons.clear),
                        tooltip: 'Remover fecha',
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                // Precio de compra (que usamos para calcular precio de venta)
                TextFormField(
                  controller: purchasePriceCtrl,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Precio de compra (por unidad)'),
                  onChanged: (_) {
                    _recalcPriceFromPurchase();
                    setState(() {});
                  },
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Ingrese precio de compra';
                    if (double.tryParse(v.replaceAll(',', '.')) == null) return 'Precio inválido';
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                // Margen (editable)
                Row(children: [
                  const Text('Margen %:'),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 80,
                    child: TextFormField(
                      initialValue: marginPercent.toString(),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      onChanged: (v) {
                        marginPercent = double.tryParse(v.replaceAll(',', '.')) ?? 10.0;
                        _recalcPriceFromPurchase();
                        setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Precio de venta sugerido = compra × (1 + margen)')),
                ]),
                const SizedBox(height: 8),
                // Precio de venta (calculado por defecto, editable si manualPrice true)
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: priceCtrl,
                        enabled: manualPrice,
                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Precio de venta (por unidad)'),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Ingrese precio de venta';
                          if (double.tryParse(v.replaceAll(',', '.')) == null) return 'Precio inválido';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(children: [
                      const Text('Editar'),
                      Checkbox(value: manualPrice, onChanged: (v) => setState(() => manualPrice = v ?? false)),
                    ]),
                  ],
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Checkbox(value: priceIsPerUnit, onChanged: (v) => setState(() => priceIsPerUnit = v ?? true)),
                  const Expanded(child: Text('Precio registrado es por unidad (precio de venta)')),
                ]),
                const SizedBox(height: 8),
                TextFormField(controller: stockCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock inicial'), validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Ingrese stock';
                  if (int.tryParse(v) == null) return 'Stock inválido';
                  return null;
                }),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: providers.isNotEmpty ? providers.first.id : null,
                  items: providers.map((p) {
                    final data = p.data() as Map<String, dynamic>;
                    return DropdownMenuItem(value: p.id, child: Text(data['name'] ?? '—'));
                  }).toList(),
                  onChanged: (v) => selectedProviderId = v,
                  decoration: const InputDecoration(labelText: 'Proveedor (opcional)'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Nota: Registrar un producto no crea una compra. Las compras se registran desde la sección Compras (Movimientos).',
                  style: TextStyle(fontSize: 12),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            TextButton(onPressed: () {
              if (!_formKey.currentState!.validate()) return;
              Navigator.pop(c, true);
            }, child: const Text('Crear')),
          ],
        );
      }),
    );

    if (created != true) return;

    setState(() => _loadingAction = true);
    try {
      // Si priceCtrl está vacío (por alguna razón) recalcular
      if (priceCtrl.text.trim().isEmpty) {
        final p = double.tryParse(purchasePriceCtrl.text.replaceAll(',', '.')) ?? 0.0;
        priceCtrl.text = (p * (1 + marginPercent / 100)).toStringAsFixed(2);
      }

      await _createProductFirestore({
        'name': nameCtrl.text.trim(),
        'sku': skuCtrl.text.trim(),
        'category': categoryCtrl.text.trim(),
        'description': descriptionCtrl.text.trim(),
        'purchasePrice': double.parse(purchasePriceCtrl.text.replaceAll(',', '.')),
        'price': double.parse(priceCtrl.text.replaceAll(',', '.')),
        'marginPercent': marginPercent,
        'priceIsPerUnit': priceIsPerUnit,
        'stock': int.parse(stockCtrl.text),
        'providerId': selectedProviderId,
        // --- expiry ---
        if (pickedExpiry != null) 'expiryDate': pickedExpiry,
        // ---
      });
      _showSnack('Producto creado.');
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      setState(() => _loadingAction = false);
    }
  }

  // --- Dialog: editar producto ---
  Future<void> _showEditProductDialog(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final _formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: data['name'] ?? '');
    final skuCtrl = TextEditingController(text: data['sku'] ?? '');
    final categoryCtrl = TextEditingController(text: data['category'] ?? '');
    final descriptionCtrl = TextEditingController(text: data['description'] ?? '');
    final purchasePriceCtrl = TextEditingController(text: (data['purchasePrice'] ?? '').toString());
    final priceCtrl = TextEditingController(text: (data['price'] ?? '').toString());
    final stockCtrl = TextEditingController(text: (data['stock'] ?? '').toString());
    bool priceIsPerUnit = (data['priceIsPerUnit'] ?? true) as bool;
    double marginPercent = (data['marginPercent'] ?? 10.0) is double ? (data['marginPercent'] ?? 10.0) as double : double.parse((data['marginPercent'] ?? 10.0).toString());
    bool manualPrice = false;
    String? selectedProviderId = data['providerId'] as String?;

    // --- expiry: leer valor si existe (puede venir como Timestamp)
    DateTime? pickedExpiry;
    final rawExpiry = data['expiryDate'];
    if (rawExpiry != null) {
      if (rawExpiry is Timestamp) {
        pickedExpiry = (rawExpiry as Timestamp).toDate();
      } else if (rawExpiry is DateTime) {
        pickedExpiry = rawExpiry as DateTime;
      } else if (rawExpiry is String) {
        try {
          pickedExpiry = DateTime.parse(rawExpiry as String);
        } catch (_) {}
      }
    }
    // ---

    final providersSnap = await providersRef.orderBy('name').get();
    final providers = providersSnap.docs;

    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (context, setState) {
        void _recalcPriceFromPurchase() {
          final p = double.tryParse(purchasePriceCtrl.text.replaceAll(',', '.')) ?? 0.0;
          final calculated = (p * (1 + marginPercent / 100));
          if (!manualPrice) priceCtrl.text = calculated.toStringAsFixed(2);
        }

        return AlertDialog(
          title: const Text('Editar producto'),
          content: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre'), validator: (v) => v == null || v.trim().isEmpty ? 'Ingrese nombre' : null),
                const SizedBox(height: 8),
                TextFormField(controller: skuCtrl, decoration: const InputDecoration(labelText: 'SKU (id)'), validator: (v) => v == null || v.trim().isEmpty ? 'SKU requerido' : null),
                const SizedBox(height: 8),
                TextFormField(controller: categoryCtrl, decoration: const InputDecoration(labelText: 'Categoría'), validator: (v) => v == null || v.trim().isEmpty ? 'Ingrese categoría' : null),
                const SizedBox(height: 8),
                TextFormField(controller: descriptionCtrl, decoration: const InputDecoration(labelText: 'Descripción (uso, indicación, presentaciones)'), maxLines: 2),
                const SizedBox(height: 8),
                // --- expiry picker (editar)
                Row(
                  children: [
                    Expanded(
                      child: Text(pickedExpiry == null ? 'Fecha de vencimiento: —' : 'Fecha de vencimiento: ${pickedExpiry!.day}/${pickedExpiry!.month}/${pickedExpiry!.year}'),
                    ),
                    TextButton(
                      onPressed: () async {
                        final now = DateTime.now();
                        final d = await showDatePicker(
                          context: context,
                          initialDate: pickedExpiry ?? now,
                          firstDate: DateTime(now.year - 5),
                          lastDate: DateTime(now.year + 10),
                        );
                        if (d != null) setState(() => pickedExpiry = d);
                      },
                      child: const Text('Seleccionar'),
                    ),
                    if (pickedExpiry != null)
                      IconButton(
                        onPressed: () => setState(() => pickedExpiry = null),
                        icon: const Icon(Icons.clear),
                        tooltip: 'Remover fecha',
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: purchasePriceCtrl,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Precio de compra (por unidad)'),
                  onChanged: (_) {
                    _recalcPriceFromPurchase();
                    setState(() {});
                  },
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Ingrese precio de compra';
                    if (double.tryParse(v.replaceAll(',', '.')) == null) return 'Precio inválido';
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                Row(children: [
                  const Text('Margen %:'),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 80,
                    child: TextFormField(
                      initialValue: marginPercent.toString(),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      onChanged: (v) {
                        marginPercent = double.tryParse(v.replaceAll(',', '.')) ?? 10.0;
                        _recalcPriceFromPurchase();
                        setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Precio de venta sugerido = compra × (1 + margen)')),
                ]),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: priceCtrl,
                        enabled: manualPrice,
                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Precio de venta (por unidad)'),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Ingrese precio de venta';
                          if (double.tryParse(v.replaceAll(',', '.')) == null) return 'Precio inválido';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(children: [
                      const Text('Editar'),
                      Checkbox(value: manualPrice, onChanged: (v) => setState(() => manualPrice = v ?? false)),
                    ]),
                  ],
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Checkbox(value: priceIsPerUnit, onChanged: (v) => setState(() => priceIsPerUnit = v ?? true)),
                  const Expanded(child: Text('Precio registrado es por unidad (precio de venta)')),
                ]),
                const SizedBox(height: 8),
                TextFormField(controller: stockCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock'), validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Ingrese stock';
                  if (int.tryParse(v) == null) return 'Stock inválido';
                  return null;
                }),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedProviderId ?? (providers.isNotEmpty ? providers.first.id : null),
                  items: providers.map((p) {
                    final pd = p.data() as Map<String, dynamic>;
                    return DropdownMenuItem(value: p.id, child: Text(pd['name'] ?? '—'));
                  }).toList(),
                  onChanged: (v) => selectedProviderId = v,
                  decoration: const InputDecoration(labelText: 'Proveedor'),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            TextButton(onPressed: () {
              if (!_formKey.currentState!.validate()) return;
              Navigator.pop(c, true);
            }, child: const Text('Guardar')),
          ],
        );
      }),
    );

    if (saved != true) return;

    setState(() => _loadingAction = true);
    try {
      await _updateProductFirestore(doc.id, {
        'name': nameCtrl.text.trim(),
        'sku': skuCtrl.text.trim(),
        'category': categoryCtrl.text.trim(),
        'description': descriptionCtrl.text.trim(),
        'purchasePrice': double.parse(purchasePriceCtrl.text.replaceAll(',', '.')),
        'price': double.parse(priceCtrl.text.replaceAll(',', '.')),
        'marginPercent': marginPercent,
        'priceIsPerUnit': priceIsPerUnit,
        'stock': int.parse(stockCtrl.text),
        'providerId': selectedProviderId,
        // --- expiry: si pickedExpiry es null y quieres mantener la fecha tal como está,
        // no incluyas la clave. Si quieres eliminar la fecha, incluye 'expiryDate': null.
        'expiryDate': pickedExpiry, // si null => removerá el campo (según lógica en update)
      });
      _showSnack('Producto actualizado.');
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      setState(() => _loadingAction = false);
    }
  }

  Future<void> _tryDeleteProduct(QueryDocumentSnapshot doc) async {
    final confirm = await _showConfirmation('Eliminar producto', '¿Seguro que deseas eliminar ${ (doc.data() as Map<String,dynamic>)['name'] ?? 'este producto'}?');
    if (confirm != true) return;

    setState(() => _loadingAction = true);
    try {
      await _deleteProductFirestore(doc.id);
      _showSnack('Producto eliminado.');
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      setState(() => _loadingAction = false);
    }
  }

  // helper: convierte el campo expiry a DateTime si es posible
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
    final limit = now.add(const Duration(days: 90)); // 3 meses ≈ 90 días
    return expiry.isBefore(limit);
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header y botón crear
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Gestión de productos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kGreen1)),
            ElevatedButton.icon(
              onPressed: _showCreateProductDialog,
              icon: const Icon(Icons.add_box),
              label: const Text('Nuevo producto', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: kGreen2),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // StreamBuilder lista productos
        StreamBuilder<QuerySnapshot>(
          stream: productsRef.orderBy('createdAt', descending: true).snapshots(),
          builder: (context, snap) {
            if (snap.hasError) return const Text('Error al cargar productos');
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snap.data!.docs;

            return LayoutBuilder(builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 750;

              if (isMobile) {
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final d = docs[i];
                    final data = d.data() as Map<String, dynamic>;
                    final expiry = _parseExpiry(data['expiryDate']);
                    final near = expiry != null ? _isNearExpiry(expiry) : false;

                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: kGreen3,
                          child: Text((data['name'] ?? 'P').toString().substring(0, 1).toUpperCase()),
                        ),
                        title: Text('${data['name'] ?? '—'}  (${data['sku'] ?? '—'})'),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Categoria: ${data['category'] ?? '—'}'),
                          Text('Precio: ${data['price']?.toString() ?? '—'} • Stock: ${data['stock'] ?? 0}'),
                          if ((data['description'] ?? '').toString().isNotEmpty) Text('Descripción: ${data['description']}'),
                          const SizedBox(height: 4),
                          if (expiry != null)
                            Text(
                              'Vence: ${expiry.day}/${expiry.month}/${expiry.year}',
                              style: TextStyle(color: near ? Colors.red : Colors.black87),
                            ),
                        ]),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) async {
                            if (action == 'edit') await _showEditProductDialog(d);
                            if (action == 'delete') await _tryDeleteProduct(d);
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit), title: Text('Editar'))),
                            const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete), title: Text('Eliminar'))),
                          ],
                        ),
                      ),
                    );
                  },
                );
              } else {
                // Desktop: tabla con columna descripción y vencimiento
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Nombre')),
                      DataColumn(label: Text('SKU')),
                      DataColumn(label: Text('Categoria')),
                      DataColumn(label: Text('Descripción')),
                      DataColumn(label: Text('Precio')),
                      DataColumn(label: Text('Stock')),
                      DataColumn(label: Text('Vencimiento')),
                      DataColumn(label: Text('Proveedor')),
                      DataColumn(label: Text('Acciones')),
                    ],
                    rows: docs.map((d) {
                      final data = d.data() as Map<String, dynamic>;
                      final expiry = _parseExpiry(data['expiryDate']);
                      final expiryText = expiry != null ? '${expiry.day}/${expiry.month}/${expiry.year}' : '—';
                      final near = expiry != null ? _isNearExpiry(expiry) : false;

                      return DataRow(cells: [
                        DataCell(Text(data['name'] ?? '—')),
                        DataCell(Text(data['sku'] ?? '—')),
                        DataCell(Text(data['category'] ?? '—')),
                        DataCell(SizedBox(width: 200, child: Text((data['description'] ?? '—').toString(), overflow: TextOverflow.ellipsis))),
                        DataCell(Text(data['price']?.toString() ?? '—')),
                        DataCell(Text((data['stock'] ?? 0).toString())),
                        DataCell(Text(expiryText, style: TextStyle(color: near ? Colors.red : Colors.black87))),
                        DataCell(Text(data['providerId'] ?? '—')),
                        DataCell(Row(children: [
                          IconButton(onPressed: () => _showEditProductDialog(d), icon: const Icon(Icons.edit, color: Colors.black54)),
                          IconButton(onPressed: () => _tryDeleteProduct(d), icon: const Icon(Icons.delete, color: Colors.redAccent)),
                        ])),
                      ]);
                    }).toList(),
                  ),
                );
              }
            });
          },
        ),
        if (_loadingAction) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
      ],
    );
  }
}
