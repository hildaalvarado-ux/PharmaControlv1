// lib/movements_manager.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'app_theme.dart';

class MovementItem {
  final String type;
  final Map<String, dynamic> data;
  final DateTime date;
  final String? productId;
  final int qty;
  final double total;
  final String? party;
  final String id;

  MovementItem(this.type, this.data, this.date, this.productId, this.qty, this.total, this.party, this.id);
}

class MovementsManager extends StatefulWidget {
  /// initialTab: 'ingresos' o 'egresos' (opcional)
  final String initialTab;
  const MovementsManager({super.key, this.initialTab = 'ingresos'});

  @override
  State<MovementsManager> createState() => _MovementsManagerState();
}

class _MovementsManagerState extends State<MovementsManager> {
  final CollectionReference productsRef = FirebaseFirestore.instance.collection('products');
  final CollectionReference providersRef = FirebaseFirestore.instance.collection('providers');
  final CollectionReference ingresosRef = FirebaseFirestore.instance.collection('ingresos');
  final CollectionReference egresosRef = FirebaseFirestore.instance.collection('egresos');

  String _activeTab = 'ingresos';
  bool _loadingAction = false;

  // Filters
  DateTime? _from;
  DateTime? _to;
  String? _filterProductId;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab == 'egresos' ? 'egresos' : 'ingresos';
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --- Create ingreso (compra / entrada) ---
  Future<void> _showCreateIngresoDialog() async {
    final productsSnap = await productsRef.orderBy('name').get();
    final providersSnap = await providersRef.orderBy('name').get();
    if (productsSnap.docs.isEmpty) {
      _showSnack('No hay productos. Registra productos antes de crear ingresos.');
      return;
    }
    if (providersSnap.docs.isEmpty) {
      _showSnack('No hay proveedores. Registra proveedores antes de crear ingresos.');
      return;
    }

    String selectedProductId = productsSnap.docs.first.id;
    String selectedProviderId = providersSnap.docs.first.id;
    final qtyCtrl = TextEditingController(text: '1');
    final unitPriceCtrl = TextEditingController(text: '0.00');
    final refCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (context, setState) {
        final productName = (productsSnap.docs.firstWhere((d) => d.id == selectedProductId).data() as Map)['name'] ?? '';
        return AlertDialog(
          title: const Text('Nuevo Ingreso (Compra / Entrada)'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: selectedProviderId,
                items: providersSnap.docs.map((p) {
                  final d = p.data() as Map<String, dynamic>;
                  return DropdownMenuItem(value: p.id, child: Text(d['name'] ?? '—'));
                }).toList(),
                onChanged: (v) => setState(() => selectedProviderId = v!),
                decoration: const InputDecoration(labelText: 'Proveedor'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedProductId,
                items: productsSnap.docs.map((p) {
                  final d = p.data() as Map<String, dynamic>;
                  return DropdownMenuItem(value: p.id, child: Text('${d['name'] ?? '—'} (${d['sku'] ?? '—'})'));
                }).toList(),
                onChanged: (v) => setState(() => selectedProductId = v!),
                decoration: const InputDecoration(labelText: 'Producto'),
              ),
              const SizedBox(height: 8),
              TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad')),
              const SizedBox(height: 8),
              TextField(controller: unitPriceCtrl, keyboardType: TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Precio unitario')),
              const SizedBox(height: 8),
              TextField(controller: refCtrl, decoration: const InputDecoration(labelText: 'Referencia (opcional)')),
              const SizedBox(height: 8),
              TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notas (opcional)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            TextButton(onPressed: () {
              final qty = int.tryParse(qtyCtrl.text) ?? 0;
              final p = double.tryParse(unitPriceCtrl.text.replaceAll(',', '.')) ?? -1;
              if (qty <= 0) {
                _showSnack('Cantidad inválida');
                return;
              }
              if (p < 0) {
                _showSnack('Precio unitario inválido');
                return;
              }
              Navigator.pop(c, true);
            }, child: const Text('Guardar')),
          ],
        );
      }),
    );

    if (saved != true) return;

    // perform save
    setState(() => _loadingAction = true);
    try {
      final qty = int.tryParse(qtyCtrl.text) ?? 0;
      final unitPrice = double.parse(unitPriceCtrl.text.replaceAll(',', '.'));
      final subtotal = qty * unitPrice;

      final batch = FirebaseFirestore.instance.batch();
      final doc = ingresosRef.doc();
      batch.set(doc, {
        'providerId': selectedProviderId,
        'productId': selectedProductId,
        'qty': qty,
        'unitPrice': unitPrice,
        'subtotal': subtotal,
        'reference': refCtrl.text.trim(),
        'notes': notesCtrl.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'userId': null,
      });

      // incrementar stock
      final prodRef = productsRef.doc(selectedProductId);
      batch.update(prodRef, {'stock': FieldValue.increment(qty)});

      await batch.commit();
      _showSnack('Ingreso registrado y stock actualizado.');
      if (mounted) setState(() {});
    } catch (e) {
      _showSnack('Error al registrar ingreso: $e');
    } finally {
      setState(() => _loadingAction = false);
    }
  }

  // --- Create egreso (venta / salida) ---
  Future<void> _showCreateEgresoDialog() async {
    final productsSnap = await productsRef.orderBy('name').get();
    if (productsSnap.docs.isEmpty) {
      _showSnack('No hay productos. Registra productos antes de crear egresos.');
      return;
    }

    String selectedProductId = productsSnap.docs.first.id;
    final qtyCtrl = TextEditingController(text: '1');
    final unitPriceCtrl = TextEditingController(text: '0.00'); // precio de venta
    final customerCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (context, setState) {
        return AlertDialog(
          title: const Text('Nuevo Egreso (Venta / Salida)'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: selectedProductId,
                items: productsSnap.docs.map((p) {
                  final d = p.data() as Map<String, dynamic>;
                  return DropdownMenuItem(value: p.id, child: Text('${d['name'] ?? '—'} (${d['sku'] ?? '—'}) • Stock: ${d['stock'] ?? 0}'));
                }).toList(),
                onChanged: (v) => setState(() => selectedProductId = v!),
                decoration: const InputDecoration(labelText: 'Producto'),
              ),
              const SizedBox(height: 8),
              TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad')),
              const SizedBox(height: 8),
              TextField(controller: unitPriceCtrl, keyboardType: TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Precio unitario (venta)')),
              const SizedBox(height: 8),
              TextField(controller: customerCtrl, decoration: const InputDecoration(labelText: 'Cliente (opcional)')),
              const SizedBox(height: 8),
              TextField(controller: refCtrl, decoration: const InputDecoration(labelText: 'Referencia (opcional)')),
              const SizedBox(height: 8),
              TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notas (opcional)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            TextButton(onPressed: () {
              final qty = int.tryParse(qtyCtrl.text) ?? 0;
              final p = double.tryParse(unitPriceCtrl.text.replaceAll(',', '.')) ?? -1;
              if (qty <= 0) {
                _showSnack('Cantidad inválida');
                return;
              }
              if (p < 0) {
                _showSnack('Precio unitario inválido');
                return;
              }
              Navigator.pop(c, true);
            }, child: const Text('Guardar')),
          ],
        );
      }),
    );

    if (saved != true) return;

    // perform save with transaction to avoid negative stock
    setState(() => _loadingAction = true);
    try {
      final qty = int.tryParse(qtyCtrl.text) ?? 0;
      final unitPrice = double.parse(unitPriceCtrl.text.replaceAll(',', '.'));
      final subtotal = qty * unitPrice;

      final docRef = egresosRef.doc();

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final prodRef = productsRef.doc(selectedProductId);
        final prodSnap = await tx.get(prodRef);
        if (!prodSnap.exists) throw Exception('Producto no encontrado');
        final currentStock = (prodSnap.data() as Map<String, dynamic>)['stock'] ?? 0;
        final curr = (currentStock is int) ? currentStock : int.tryParse(currentStock.toString()) ?? 0;
        if (curr < qty) throw Exception('Stock insuficiente (${curr}) para realizar la venta.');

        tx.set(docRef, {
          'productId': selectedProductId,
          'qty': qty,
          'unitPrice': unitPrice,
          'subtotal': subtotal,
          'customer': customerCtrl.text.trim(),
          'reference': refCtrl.text.trim(),
          'notes': notesCtrl.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'userId': null,
        });
        tx.update(prodRef, {'stock': FieldValue.increment(-qty)});
      });

      _showSnack('Egreso registrado y stock actualizado.');
    } catch (e) {
      _showSnack('Error al registrar egreso: ${e.toString()}');
    } finally {
      setState(() => _loadingAction = false);
    }
  }

  // --- Build query stream for the active tab with filters ---
  Query _buildQueryForActiveTab() {
    final col = _activeTab == 'ingresos' ? ingresosRef : egresosRef;
    Query q = col.orderBy('createdAt', descending: true);
    if (_filterProductId != null && _filterProductId!.isNotEmpty) {
      q = q.where('productId', isEqualTo: _filterProductId);
    }
    if ((_from != null) || (_to != null)) {
      if (_from != null && _to != null) {
        q = q.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(_from!));
        q = q.where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(_to!.add(const Duration(days:1))));
      } else if (_from != null) {
        q = q.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(_from!));
      } else if (_to != null) {
        q = q.where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(_to!.add(const Duration(days:1))));
      }
    }
    if (_searchCtrl.text.trim().isNotEmpty) {
      final s = _searchCtrl.text.trim();
      q = q.where('reference', isEqualTo: s);
    }
    return q;
  }

  Widget _buildFiltersBar() {
    return Column(
      children: [
        Row(children: [
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por referencia exacta'),
              onSubmitted: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Fecha desde',
            onPressed: () async {
              final picked = await showDatePicker(context: context, initialDate: _from ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
              if (picked != null) setState(() => _from = picked);
            },
            icon: const Icon(Icons.date_range),
          ),
          IconButton(
            tooltip: 'Fecha hasta',
            onPressed: () async {
              final picked = await showDatePicker(context: context, initialDate: _to ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
              if (picked != null) setState(() => _to = picked);
            },
            icon: const Icon(Icons.date_range_outlined),
          ),
          IconButton(
            tooltip: 'Limpiar filtros',
            onPressed: () => setState(() {
              _from = null;
              _to = null;
              _filterProductId = null;
              _searchCtrl.clear();
            }),
            icon: const Icon(Icons.clear),
          ),
        ]),
        const SizedBox(height: 8),
        FutureBuilder<QuerySnapshot>(
          future: productsRef.orderBy('name').get(),
          builder: (context, snap) {
            if (!snap.hasData) return const SizedBox();
            final docs = snap.data!.docs;
            return Row(children: [
              const Text('Producto:'),
              const SizedBox(width: 8),
DropdownButton<String?>(
  value: _filterProductId,
  hint: const Text('Todos'),
  items: [null, ...docs.map((d) => d.id)].map((pid) {
    if (pid == null) {
      return const DropdownMenuItem<String?>(value: null, child: Text('Todos'));
    }
    final m = (docs.firstWhere((x) => x.id == pid).data() as Map<String, dynamic>);
    return DropdownMenuItem<String?>(value: pid, child: Text('${m['name'] ?? '—'} (${m['sku'] ?? '—'})'));
  }).toList(),
  onChanged: (String? v) => setState(() => _filterProductId = v),
),
              const SizedBox(width: 12),
              Expanded(child: Container()),
              ElevatedButton.icon(
                onPressed: _activeTab == 'ingresos' ? _showCreateIngresoDialog : _showCreateEgresoDialog,
                icon: Icon(_activeTab == 'ingresos' ? Icons.add_shopping_cart : Icons.sell),
                label: Text(_activeTab == 'ingresos' ? 'Nuevo ingreso' : 'Nuevo egreso'),
                style: ElevatedButton.styleFrom(backgroundColor: kGreen2),
              ),
            ]);
          },
        ),
      ],
    );
  }

  Widget _buildList() {
    final query = _buildQueryForActiveTab();
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return const Text('Error al cargar movimientos');
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) return const Text('No hay movimientos para los filtros seleccionados.');

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) {
            final d = docs[i];
            final data = d.data() as Map<String, dynamic>;
            final date = data['createdAt'] is Timestamp ? (data['createdAt'] as Timestamp).toDate() : null;
            final qty = data['qty'] ?? 0;
            final unitPrice = data['unitPrice'] ?? 0;
            final total = (data['subtotal'] ?? (qty * unitPrice));
            final productId = data['productId'] ?? '';
            final party = _activeTab == 'ingresos' ? (data['providerId'] ?? '—') : (data['customer'] ?? data['party'] ?? '—');

            return FutureBuilder<DocumentSnapshot>(
              future: productId != null && productId.toString().isNotEmpty ? productsRef.doc(productId).get() : Future.value(null),
              builder: (context, prodSnap) {
                String prodLabel = productId;
                if (prodSnap.hasData && prodSnap.data != null && prodSnap.data!.exists) {
                  final pd = prodSnap.data!.data() as Map<String, dynamic>;
                  prodLabel = '${pd['name'] ?? '—'} (${pd['sku'] ?? '—'})';
                }
                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: kGreen3, child: Text(prodLabel.isNotEmpty ? prodLabel.substring(0,1).toUpperCase() : '?')),
                    title: Text('${_activeTab == 'ingresos' ? 'Ingreso' : 'Egreso'} • $prodLabel'),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Cantidad: $qty • Precio unitario: ${unitPrice.toString()} • Total: ${total.toString()}'),
                      Text('Parte: $party'),
                      Text('Referencia: ${data['reference'] ?? '—'}'),
                      if ((data['notes'] ?? '').toString().isNotEmpty) Text('Notas: ${data['notes']}'),
                      Text('Fecha: ${date?.toString() ?? '—'}'),
                    ]),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) async {
                        if (action == 'view') {
                          await showDialog(context: context, builder: (c) => AlertDialog(
                            title: Text('${_activeTab == 'ingresos' ? 'Ingreso' : 'Egreso'} detalle'),
                            content: SingleChildScrollView(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Producto: $prodLabel'),
                                Text('Cantidad: $qty'),
                                Text('Precio unitario: ${unitPrice.toString()}'),
                                Text('Total: ${total.toString()}'),
                                Text('Parte: $party'),
                                Text('Referencia: ${data['reference'] ?? '—'}'),
                                Text('Notas: ${data['notes'] ?? ''}'),
                                Text('Fecha: ${date?.toString() ?? '—'}'),
                              ],
                            ))),
                          );
                        } else if (action == 'delete') {
                          final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
                            title: const Text('Confirmar eliminación'),
                            content: const Text('Eliminar este movimiento no revertirá el stock automáticamente. ¿Deseas continuar?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Eliminar')),
                            ],
                          ));
                          if (ok == true) {
                            try {
                              await ( _activeTab == 'ingresos' ? ingresosRef.doc(d.id).delete() : egresosRef.doc(d.id).delete() );
                              _showSnack('Movimiento eliminado. Ten en cuenta que el stock no fue revertido automáticamente.');
                            } catch (e) {
                              _showSnack('Error al eliminar: $e');
                            }
                          }
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'view', child: ListTile(leading: Icon(Icons.visibility), title: Text('Ver'))),
                        const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete), title: Text('Eliminar'))),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildInitialTable() {
    return StreamBuilder<List<MovementItem>>(
      stream: _getAllMovementsStream(),
      builder: (context, snap) {
        if (snap.hasError) return const Text('Error al cargar movimientos');
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final movements = snap.data!;
        if (movements.isEmpty) {
          return const Center(
            child: Text('Aún no existen movimientos registrados.', style: TextStyle(fontSize: 16, color: Colors.grey)),
          );
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Tipo')),
              DataColumn(label: Text('Producto')),
              DataColumn(label: Text('Cantidad')),
              DataColumn(label: Text('Precio Unitario')),
              DataColumn(label: Text('Total')),
              DataColumn(label: Text('Parte')),
              DataColumn(label: Text('Fecha')),
            ],
            rows: movements.map((m) {
              return DataRow(cells: [
                DataCell(Text(m.type == 'ingreso' ? 'Ingreso' : 'Egreso')),
                DataCell(FutureBuilder<DocumentSnapshot>(
                  future: m.productId != null && m.productId!.isNotEmpty ? productsRef.doc(m.productId).get() : Future.value(null),
                  builder: (context, prodSnap) {
                    String prodLabel = m.productId ?? '—';
                    if (prodSnap.hasData && prodSnap.data != null && prodSnap.data!.exists) {
                      final pd = prodSnap.data!.data() as Map<String, dynamic>;
                      prodLabel = '${pd['name'] ?? '—'} (${pd['sku'] ?? '—'})';
                    }
                    return Text(prodLabel);
                  },
                )),
                DataCell(Text(m.qty.toString())),
                DataCell(Text(m.data['unitPrice']?.toString() ?? '—')),
                DataCell(Text(m.total.toStringAsFixed(2))),
                DataCell(Text(m.party ?? '—')),
                DataCell(Text('${m.date.day}/${m.date.month}/${m.date.year}')),
              ]);
            }).toList(),
          ),
        );
      },
    );
  }

  Stream<List<MovementItem>> _getAllMovementsStream() {
    final ingresosStream = ingresosRef.orderBy('createdAt', descending: true).snapshots();
    final egresosStream = egresosRef.orderBy('createdAt', descending: true).snapshots();

    // Usamos Future.wait para obtener los primeros snapshots de ambas colecciones,
    // y luego lo convertimos a Stream con Stream.fromFuture. Esto devuelve un Stream
    // de un único evento con la lista de QuerySnapshot (lo que esperábamos originalmente).
    return Stream.fromFuture(Future.wait([ingresosStream.first, egresosStream.first]))
        .asyncMap((snapshotsList) {
      final ingresosSnap = snapshotsList[0] as QuerySnapshot;
      final egresosSnap = snapshotsList[1] as QuerySnapshot;

      final movements = <MovementItem>[];

      for (var doc in ingresosSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final date = data['createdAt'] is Timestamp ? (data['createdAt'] as Timestamp).toDate() : DateTime.now();
        final qty = data['qty'] ?? 0;
        final total = (data['subtotal'] ?? 0.0).toDouble();
        final party = data['providerId'] ?? '—';
        movements.add(MovementItem('ingreso', data, date, data['productId'], qty, total, party, doc.id));
      }

      for (var doc in egresosSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final date = data['createdAt'] is Timestamp ? (data['createdAt'] as Timestamp).toDate() : DateTime.now();
        final qty = data['qty'] ?? 0;
        final total = (data['subtotal'] ?? 0.0).toDouble();
        final party = data['customer'] ?? '—';
        movements.add(MovementItem('egreso', data, date, data['productId'], qty, total, party, doc.id));
      }

      movements.sort((a, b) => b.date.compareTo(a.date));
      return movements;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header con botones principales
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Movimientos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kGreen1)),
            Row(children: [
              ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, '/ingresos'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGreen2,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Ingresos'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, '/egresos'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGreen2,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Egresos'),
              ),
            ]),
          ],
        ),
        const SizedBox(height: 12),
        // Tabla inicial con todos los registros
        _buildInitialTable(),
        const SizedBox(height: 12),
        // Filtros y lista filtrada (opcional, para vista detallada)
        ExpansionTile(
          title: const Text('Vista Detallada con Filtros'),
          children: [
            _buildFiltersBar(),
            const SizedBox(height: 12),
            _buildList(),
          ],
        ),
        if (_loadingAction) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
      ],
    );
  }
}
