// lib/movements_manager.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Colección principal usada por tu app para productos
/// ya existe como 'products'. Aquí agregamos 'movements'.
///
/// Estructura sugerida de un documento en 'movements':
/// {
///   type: 'ingreso' | 'egreso',
///   createdAt: Timestamp,
///   createdByUid: String,
///   createdByName: String,
///   note: String?,
///   counterpartyType: 'cliente' | 'proveedor' | null,
///   counterpartyName: String?,
///   totalItems: int,
///   totalAmount: double,
///   items: [
///     {
///       productId: String,
///       productName: String,
///       sku: String,
///       qty: int,
///       unitPrice: double, // precio al momento del movimiento
///       subtotal: double,
///       stockBefore: int,
///       stockAfter: int
///     }, ...
///   ]
/// }

class MovementsManager extends StatefulWidget {
  const MovementsManager({super.key});

  @override
  State<MovementsManager> createState() => _MovementsManagerState();
}

enum _View { all, ingresos, egresos }

class _MovementsManagerState extends State<MovementsManager> {
  final _movementsRef = FirebaseFirestore.instance.collection('movements');
  final _productsRef = FirebaseFirestore.instance.collection('products');

  _View _view = _View.all;
  bool _busy = false;

  // Filtro rápido por rango de fechas (opcional)
  DateTime? _from;
  DateTime? _to;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Query _buildQuery() {
    Query q = _movementsRef.orderBy('createdAt', descending: true);
    switch (_view) {
      case _View.ingresos:
        q = q.where('type', isEqualTo: 'ingreso');
        break;
      case _View.egresos:
        q = q.where('type', isEqualTo: 'egreso');
        break;
      case _View.all:
        break;
    }
    if (_from != null) {
      q = q.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(_from!));
    }
    if (_to != null) {
      // incluir todo el día de _to
      final toEnd = DateTime(_to!.year, _to!.month, _to!.day, 23, 59, 59, 999);
      q = q.where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(toEnd));
    }
    return q;
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final res = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
      initialDateRange: (_from != null && _to != null)
          ? DateTimeRange(start: _from!, end: _to!)
          : null,
    );
    if (res != null) {
      setState(() {
        _from = res.start;
        _to = res.end;
      });
    }
  }

  // --- CREAR MOVIMIENTO ---
  Future<void> _showNewMovementSheet(String type) async {
    assert(type == 'ingreso' || type == 'egreso');

    final items = <_MovementItemDraft>[];
    final noteCtrl = TextEditingController();
    final counterpartyCtrl = TextEditingController();

    // Cargamos productos una sola vez para el picker
    final productsSnap = await _productsRef.orderBy('name').get();
    final products = productsSnap.docs.map((d) {
      final data = d.data() as Map<String, dynamic>;
      return _ProductOption(
        id: d.id,
        name: (data['name'] ?? '') as String,
        sku: (data['sku'] ?? '') as String,
        price: ((data['price'] ?? 0) as num).toDouble(),
        stock: (data['stock'] ?? 0) is int ? data['stock'] as int : int.tryParse('${data['stock']}') ?? 0,
      );
    }).toList();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) {
          Future<void> addItem() async {
            _ProductOption? selected;
            final qtyCtrl = TextEditingController(text: '1');
            final priceCtrl = TextEditingController();

            final ok = await showDialog<bool>(
              context: context,
              builder: (cx) {
                return AlertDialog(
                  title: Text(type == 'ingreso' ? 'Agregar línea (Venta)' : 'Agregar línea (Compra)'),
                  content: SizedBox(
                    width: 500,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<_ProductOption>(
                          value: selected,
                          isExpanded: true,
                          items: products
                              .map((p) => DropdownMenuItem(value: p, child: Text('${p.name}  (SKU: ${p.sku})  • Stock: ${p.stock}')))
                              .toList(),
                          onChanged: (v) {
                            selected = v;
                            priceCtrl.text = v?.price.toStringAsFixed(2) ?? '';
                          },
                          decoration: const InputDecoration(labelText: 'Producto'),
                          validator: (v) => v == null ? 'Seleccione producto' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: qtyCtrl,
                          keyboardType: const TextInputType.numberWithOptions(),
                          decoration: const InputDecoration(labelText: 'Cantidad'),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: priceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: type == 'ingreso' ? 'Precio de venta (unidad)' : 'Precio de compra (unidad)',
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(cx, false), child: const Text('Cancelar')),
                    ElevatedButton(onPressed: () => Navigator.pop(cx, true), child: const Text('Agregar')),
                  ],
                );
              },
            );

            if (ok == true && selected != null) {
              final qty = int.tryParse(qtyCtrl.text) ?? 0;
              final price = double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? selected!.price;
              if (qty <= 0) {
                _snack('Cantidad inválida');
                return;
              }
              setSheet(() {
                items.add(_MovementItemDraft(
                  product: selected!,
                  qty: qty,
                  unitPrice: price,
                ));
              });
            }
          }

          double total = 0;
          for (final it in items) {
            total += it.qty * it.unitPrice;
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              top: 12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      type == 'ingreso' ? 'Nuevo Ingreso (Venta)' : 'Nuevo Egreso (Compra)',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    FilledButton.icon(
                      onPressed: addItem,
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar línea'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (items.isEmpty)
                  const Text('Sin líneas. Agrega una para continuar.')
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final it = items[i];
                        return ListTile(
                          title: Text('${it.product.name} (SKU: ${it.product.sku})'),
                          subtitle: Text('Cant: ${it.qty} • P. unidad: ${it.unitPrice.toStringAsFixed(2)}'),
                          trailing: Text('Subtotal: ${(it.qty * it.unitPrice).toStringAsFixed(2)}'),
                          leading: IconButton(
                            onPressed: () => setSheet(() => items.removeAt(i)),
                            icon: const Icon(Icons.delete, color: Colors.redAccent),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: counterpartyCtrl,
                  decoration: InputDecoration(
                    labelText: type == 'ingreso' ? 'Cliente (opcional)' : 'Proveedor (opcional)',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(labelText: 'Nota (opcional)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Total: ${total.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: items.isEmpty ? null : () async {
                        Navigator.of(context).pop();
                        await _commitMovement(type: type, items: items, note: noteCtrl.text.trim(), counterpartyName: counterpartyCtrl.text.trim());
                      },
                      icon: const Icon(Icons.save),
                      label: const Text('Guardar'),
                    )
                  ],
                )
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _commitMovement({
    required String type, // 'ingreso' o 'egreso'
    required List<_MovementItemDraft> items,
    String? note,
    String? counterpartyName,
  }) async {
    setState(() => _busy = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? 'unknown';
      final uname = (user?.displayName?.trim().isNotEmpty == true)
          ? user!.displayName!
          : (user?.email ?? 'Usuario');

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final movementItems = <Map<String, dynamic>>[];
        double total = 0;

        for (final draft in items) {
          final prodRef = _productsRef.doc(draft.product.id);
          final prodSnap = await tx.get(prodRef);
          if (!prodSnap.exists) {
            throw Exception('Producto no encontrado: ${draft.product.name}');
          }
          final pData = prodSnap.data() as Map<String, dynamic>;
          final currentStock = (pData['stock'] ?? 0) is int
              ? pData['stock'] as int
              : int.tryParse('${pData['stock']}') ?? 0;

          // Calcular nuevo stock según el tipo
          int newStock = currentStock;
          if (type == 'ingreso') {
            // Venta = sale -> disminuye stock
            if (draft.qty > currentStock) {
              throw Exception('Stock insuficiente para ${draft.product.name} (disponible: $currentStock)');
            }
            newStock = currentStock - draft.qty;
          } else {
            // Egreso = compra -> aumenta stock
            newStock = currentStock + draft.qty;
          }

          tx.update(prodRef, {
            'stock': newStock,
            'updatedAt': FieldValue.serverTimestamp(),
          });

          final lineSubtotal = draft.qty * draft.unitPrice;
          total += lineSubtotal;

          movementItems.add({
            'productId': draft.product.id,
            'productName': draft.product.name,
            'sku': draft.product.sku,
            'qty': draft.qty,
            'unitPrice': draft.unitPrice,
            'subtotal': lineSubtotal,
            'stockBefore': currentStock,
            'stockAfter': newStock,
          });
        }

        final movRef = _movementsRef.doc();
        tx.set(movRef, {
          'type': type,
          'createdAt': FieldValue.serverTimestamp(),
          'createdByUid': uid,
          'createdByName': uname,
          'note': (note ?? '').isEmpty ? null : note,
          'counterpartyType': type == 'ingreso' ? 'cliente' : 'proveedor',
          'counterpartyName': (counterpartyName ?? '').isEmpty ? null : counterpartyName,
          'totalItems': items.length,
          'totalAmount': total,
          'items': movementItems,
        });
      });

      _snack('Movimiento guardado y stock actualizado.');
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cabecera con acciones principales
        Row(
          children: [
            Text(
              'Movimientos',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            // Toggle de vistas: Todos / Ingresos / Egresos
            SegmentedButton<_View>(
              segments: const [
                ButtonSegment(value: _View.all, label: Text('Todos'), icon: Icon(Icons.all_inbox)),
                ButtonSegment(value: _View.ingresos, label: Text('Ingresos'), icon: Icon(Icons.trending_up)),
                ButtonSegment(value: _View.egresos, label: Text('Egresos'), icon: Icon(Icons.trending_down)),
              ],
              selected: <_View>{_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
            const SizedBox(width: 12),
            // Rango de fechas
            OutlinedButton.icon(
              onPressed: _pickDateRange,
              icon: const Icon(Icons.date_range),
              label: Text(
                (_from == null || _to == null)
                    ? 'Rango de fechas'
                    : '${_from!.day}/${_from!.month}/${_from!.year} - ${_to!.day}/${_to!.month}/${_to!.year}',
              ),
            ),
            if (_from != null || _to != null)
              IconButton(
                tooltip: 'Limpiar filtro de fecha',
                onPressed: () => setState(() { _from = null; _to = null; }),
                icon: const Icon(Icons.clear),
              ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: () => _showNewMovementSheet('ingreso'),
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Nuevo ingreso'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _showNewMovementSheet('egreso'),
              icon: const Icon(Icons.move_to_inbox),
              label: const Text('Nuevo egreso'),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (_busy) const LinearProgressIndicator(minHeight: 2),

        // Lista/Tabla de movimientos
        StreamBuilder<QuerySnapshot>(
          stream: _buildQuery().snapshots(),
          builder: (context, snap) {
            if (snap.hasError) return const Text('Error al cargar movimientos');
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snap.data!.docs;

            return LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 800;

                if (isMobile) {
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemBuilder: (_, i) {
                      final d = docs[i];
                      final m = d.data() as Map<String, dynamic>;
                      final ts = m['createdAt'];
                      DateTime? dt; if (ts is Timestamp) dt = ts.toDate();
                      final items = (m['items'] as List<dynamic>? ?? []).cast<Map>();

                      return Card(
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            child: Icon(m['type'] == 'ingreso' ? Icons.trending_up : Icons.trending_down),
                          ),
                          title: Text('${m['type'] == 'ingreso' ? 'Ingreso' : 'Egreso'}  •  ${m['createdByName'] ?? '—'}'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (dt != null) Text('${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}'),
                              Text('Líneas: ${m['totalItems'] ?? items.length} • Total: ${(m['totalAmount'] ?? 0).toString()}'),
                              if ((m['counterpartyName'] ?? '') != '')
                                Text(m['type'] == 'ingreso' ? 'Cliente: ${m['counterpartyName']}' : 'Proveedor: ${m['counterpartyName']}'),
                              if ((m['note'] ?? '') != '') Text('Nota: ${m['note']}'),
                            ],
                          ),
                          children: [
                            const Divider(height: 1),
                            ...items.map((it) {
                              return ListTile(
                                dense: true,
                                title: Text('${it['productName']} (SKU: ${it['sku']})'),
                                subtitle: Text('Cant: ${it['qty']} • P. unidad: ${it['unitPrice']} • Subtotal: ${it['subtotal']}'),
                                trailing: Text('Stock: ${it['stockBefore']} → ${it['stockAfter']}'),
                              );
                            }),
                          ],
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemCount: docs.length,
                  );
                }

                // Escritorio: DataTable simple
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Fecha')),
                      DataColumn(label: Text('Tipo')),
                      DataColumn(label: Text('Usuario')),
                      DataColumn(label: Text('Contraparte')),
                      DataColumn(label: Text('Líneas')),
                      DataColumn(label: Text('Total')),
                      DataColumn(label: Text('Detalle')),
                    ],
                    rows: docs.map((d) {
                      final m = d.data() as Map<String, dynamic>;
                      final ts = m['createdAt'];
                      DateTime? dt; if (ts is Timestamp) dt = ts.toDate();
                      final items = (m['items'] as List<dynamic>? ?? []).cast<Map>();
                      return DataRow(cells: [
                        DataCell(Text(dt == null ? '—' : '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}')),
                        DataCell(Chip(label: Text(m['type'] == 'ingreso' ? 'Ingreso' : 'Egreso'))),
                        DataCell(Text(m['createdByName'] ?? '—')),
                        DataCell(Text((m['counterpartyName'] ?? '—').toString())),
                        DataCell(Text((m['totalItems'] ?? items.length).toString())),
                        DataCell(Text((m['totalAmount'] ?? 0).toString())),
                        DataCell(
                          IconButton(
                            tooltip: 'Ver líneas',
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (cx) => AlertDialog(
                                  title: const Text('Detalle del movimiento'),
                                  content: SizedBox(
                                    width: 600,
                                    child: ListView(
                                      shrinkWrap: true,
                                      children: [
                                        if ((m['note'] ?? '') != '') Padding(
                                          padding: const EdgeInsets.only(bottom: 8.0),
                                          child: Text('Nota: ${m['note']}'),
                                        ),
                                        ...items.map((it) => ListTile(
                                          dense: true,
                                          title: Text('${it['productName']} (SKU: ${it['sku']})'),
                                          subtitle: Text('Cant: ${it['qty']} • P. unidad: ${it['unitPrice']} • Subtotal: ${it['subtotal']}'),
                                          trailing: Text('Stock: ${it['stockBefore']} → ${it['stockAfter']}'),
                                        )),
                                      ],
                                    ),
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(cx), child: const Text('Cerrar')),
                                  ],
                                ),
                              );
                            },
                            icon: const Icon(Icons.list),
                          ),
                        ),
                      ]);
                    }).toList(),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

// --- Helpers ---
class _ProductOption {
  final String id;
  final String name;
  final String sku;
  final double price;
  final int stock;
  _ProductOption({required this.id, required this.name, required this.sku, required this.price, required this.stock});
}

class _MovementItemDraft {
  final _ProductOption product;
  final int qty;
  final double unitPrice;
  _MovementItemDraft({required this.product, required this.qty, required this.unitPrice});
}
