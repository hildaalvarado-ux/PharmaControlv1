import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'ingreso_form.dart';
import 'egreso_form.dart';
import 'movements_pdf.dart';
import 'pdf_output_mobile.dart'
    if (dart.library.html) 'pdf_output_web.dart' as pdf_out;

class MovementsManager extends StatefulWidget {
  const MovementsManager({super.key});

  @override
  State<MovementsManager> createState() => _MovementsManagerState();
}

enum _View { all, ingresos, egresos }

class _MovementsManagerState extends State<MovementsManager> {
  final _movementsRef = FirebaseFirestore.instance.collection('movements');
  final _trashRef = FirebaseFirestore.instance.collection('movements_trash');

  _View _view = _View.all;
  bool _busy = false;

  DateTime? _from;
  DateTime? _to;

  // último movimiento borrado (para mostrar card y poder deshacer)
  Map<String, dynamic>? _lastDeletedData;
  String? _lastDeletedId;

  // ==== helpers numéricos ====
  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  double _toMoney(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse((v?.toString() ?? '').replaceAll(',', '.')) ?? 0.0;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Query _buildQuery() {
    Query q = _movementsRef.orderBy('createdAt', descending: true);

    // filtro por tipo
    switch (_view) {
      case _View.ingresos:
        // admite 'ingreso' o 'Ingreso' por si hay datos viejos
        q = q.where('type', whereIn: ['ingreso', 'Ingreso']);
        break;
      case _View.egresos:
        q = q.where('type', whereIn: ['egreso', 'Egreso']);
        break;
      case _View.all:
        break;
    }

    // filtro por rango de fechas
    if (_from != null) {
      q = q.where(
        'createdAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(_from!),
      );
    }
    if (_to != null) {
      final toEnd =
          DateTime(_to!.year, _to!.month, _to!.day, 23, 59, 59, 999);
      q = q.where(
        'createdAt',
        isLessThanOrEqualTo: Timestamp.fromDate(toEnd),
      );
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

  Future<void> _openIngresoFullScreen() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const IngresoPage()));
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openEgresoFullScreen() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const EgresoPage()));
    if (!mounted) return;
    setState(() {});
  }

  // ====== ELIMINAR movimiento con confirmación de contraseña ======
  Future<void> _deleteMovementWithPassword(
      DocumentSnapshot movementDoc) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _snack('No hay usuario autenticado.');
      return;
    }
    final email = currentUser.email;
    if (email == null) {
      _snack('El usuario no tiene email asociado.');
      return;
    }

    final passCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: passCtrl,
            obscureText: true,
            decoration:
                const InputDecoration(labelText: 'Contraseña de inicio de sesión'),
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Ingresa tu contraseña' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      setState(() => _busy = true);

      final cred = EmailAuthProvider.credential(
        email: email,
        password: passCtrl.text.trim(),
      );
      await currentUser.reauthenticateWithCredential(cred);

      final data = movementDoc.data() as Map<String, dynamic>;

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final trashDoc = _trashRef.doc(movementDoc.id);
        tx.set(trashDoc, {
          ...data,
          'deletedAt': FieldValue.serverTimestamp(),
          'deletedByUid': currentUser.uid,
        });
        tx.delete(movementDoc.reference);
      });

      setState(() {
        _lastDeletedData = data;
        _lastDeletedId = movementDoc.id;
      });

      _snack('Movimiento eliminado. Puedes deshacer desde la tarjeta inferior.');
    } on FirebaseAuthException catch (e) {
      _snack('Error de autenticación: ${e.message ?? e.code}');
    } catch (e) {
      _snack('Error al eliminar movimiento: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undoLastDelete() async {
    if (_lastDeletedId == null || _lastDeletedData == null) return;

    try {
      setState(() => _busy = true);

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final mainDoc = _movementsRef.doc(_lastDeletedId);
        final trashDoc = _trashRef.doc(_lastDeletedId);

        tx.set(mainDoc, {
          ..._lastDeletedData!,
          'restoredAt': FieldValue.serverTimestamp(),
        });
        tx.delete(trashDoc);
      });

      _snack('Movimiento restaurado.');
      setState(() {
        _lastDeletedData = null;
        _lastDeletedId = null;
      });
    } catch (e) {
      _snack('Error al restaurar movimiento: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ====== IMPRIMIR movimientos según filtros actuales ======
  Future<void> _printCurrentMovements() async {
    try {
      setState(() => _busy = true);
      final snap = await _buildQuery().get();

      if (snap.docs.isEmpty) {
        _snack('No hay movimientos para imprimir con los filtros actuales.');
        return;
      }

      final movements = snap.docs.map((d) {
        final m = d.data() as Map<String, dynamic>;
        return {
          ...m,
          'id': d.id,
        };
      }).toList();

      String filtro;
      switch (_view) {
        case _View.ingresos:
          filtro = 'Ingresos';
          break;
        case _View.egresos:
          filtro = 'Egresos';
          break;
        case _View.all:
        default:
          filtro = 'Todos';
      }

      final bytes = await MovementsPdf.build(
        title: 'Reporte de movimientos',
        filterLabel: filtro,
        from: _from,
        to: _to,
        movements: movements,
      );

      final now = DateTime.now();
      await pdf_out.outputPdf(
        bytes,
        'movimientos_${now.year}${now.month}${now.day}_${now.hour}${now.minute}.pdf',
      );
    } catch (e) {
      _snack('Error al generar PDF: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Movimientos',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const Spacer(),
            SegmentedButton<_View>(
              segments: const [
                ButtonSegment(
                  value: _View.all,
                  label: Text('Todos'),
                  icon: Icon(Icons.all_inbox),
                ),
                ButtonSegment(
                  value: _View.ingresos,
                  label: Text('Ingresos'),
                  icon: Icon(Icons.trending_up),
                ),
                ButtonSegment(
                  value: _View.egresos,
                  label: Text('Egresos'),
                  icon: Icon(Icons.trending_down),
                ),
              ],
              selected: <_View>{_view},
              onSelectionChanged: (s) =>
                  setState(() => _view = s.first),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _pickDateRange,
              icon: const Icon(Icons.date_range),
              label: Text(
                (_from == null || _to == null)
                    ? 'Rango de fechas'
                    : '${_from!.day}/${_from!.month}/${_from!.year} - '
                        '${_to!.day}/${_to!.month}/${_to!.year}',
              ),
            ),
            if (_from != null || _to != null)
              IconButton(
                tooltip: 'Limpiar filtro de fecha',
                onPressed: () => setState(() {
                  _from = null;
                  _to = null;
                }),
                icon: const Icon(Icons.clear),
              ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _printCurrentMovements,
              icon: const Icon(Icons.print),
              label: const Text('Imprimir'),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _openIngresoFullScreen,
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Nuevo ingreso'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _openEgresoFullScreen,
              icon: const Icon(Icons.move_to_inbox),
              label: const Text('Nuevo egreso'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_busy) const LinearProgressIndicator(minHeight: 2),

        // ====== LISTADO principal ======
        StreamBuilder<QuerySnapshot>(
          stream: _buildQuery().snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return const Text('Error al cargar movimientos');
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snap.data!.docs;

            return LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 800;

                if (isMobile) {
                  // ====== MODO MÓVIL ======
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final d = docs[i];
                      final m = d.data() as Map<String, dynamic>;
                      final ts = m['createdAt'];
                      DateTime? dt;
                      if (ts is Timestamp) dt = ts.toDate();

                      final rawItems = (m['items'] as List<dynamic>? ?? []);
                      final items = rawItems
                          .map<Map<String, dynamic>>(
                              (e) => Map<String, dynamic>.from(e as Map))
                          .toList();

                      final totalAmount = _toMoney(m['totalAmount']);
                      final type = (m['type'] ?? '').toString().toLowerCase();
                      final counterparty = (m['counterpartyName'] ?? '').toString();

                      // etiqueta de contraparte correcta
                      String? counterpartyLabel;
                      if (counterparty.isNotEmpty) {
                        counterpartyLabel = type == 'egreso'
                            ? 'Cliente: $counterparty'
                            : 'Proveedor: $counterparty';
                      }

                      return Card(
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            child: Icon(
                              type == 'ingreso'
                                  ? Icons.trending_up
                                  : Icons.trending_down,
                            ),
                          ),
                          title: Text(
                            '${type == "ingreso" ? "Ingreso" : "Egreso"} • ${m['createdByName'] ?? '—'}',
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (dt != null)
                                Text(
                                  '${dt.day}/${dt.month}/${dt.year} '
                                  '${dt.hour.toString().padLeft(2, '0')}:'
                                  '${dt.minute.toString().padLeft(2, '0')}',
                                ),
                              Text(
                                'Líneas: ${(m['totalItems'] ?? items.length).toString()} • '
                                'Total: ${totalAmount.toStringAsFixed(2)}',
                              ),
                              if (counterpartyLabel != null)
                                Text(counterpartyLabel),
                              if ((m['note'] ?? '').toString().isNotEmpty)
                                Text('Nota: ${m['note']}'),
                            ],
                          ),
                          children: [
                            const Divider(height: 1),
                            ...items.map((it) {
                              final qty = _toInt(it['qty']);
                              final unitPrice = _toMoney(
                                it['unitPrice'] ??
                                    it['purchasePrice'] ??
                                    it['salePrice'],
                              );
                              final subtotal =
                                  _toMoney(it['subtotal']);

                              final stockBefore = it['stockBefore'];
                              final stockAfter = it['stockAfter'];
                              String stockText = '';
                              if (stockBefore is num &&
                                  stockAfter is num) {
                                stockText =
                                    'Stock: ${_toInt(stockBefore)} → ${_toInt(stockAfter)}';
                              }

                              return ListTile(
                                dense: true,
                                title: Text(
                                    '${it['productName']} (SKU: ${it['sku']})'),
                                subtitle: Text(
                                  'Cant: $qty • '
                                  'P. unidad: ${unitPrice.toStringAsFixed(2)} • '
                                  'Subtotal: ${subtotal.toStringAsFixed(2)}',
                                ),
                                trailing: stockText.isEmpty
                                    ? null
                                    : Text(stockText),
                              );
                            }).toList(),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () => _deleteMovementWithPassword(d),
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Eliminar'),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                }

                // ====== ESCRITORIO ======
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
                      DataColumn(label: Text('Acciones')),
                    ],
                    rows: docs.map((d) {
                      final m = d.data() as Map<String, dynamic>;
                      final ts = m['createdAt'];
                      DateTime? dt;
                      if (ts is Timestamp) dt = ts.toDate();

                      final rawItems =
                          (m['items'] as List<dynamic>? ?? []);
                      final items = rawItems
                          .map<Map<String, dynamic>>(
                              (e) => Map<String, dynamic>.from(e as Map))
                          .toList();

                      final totalAmount =
                          _toMoney(m['totalAmount']);
                      final type =
                          (m['type'] ?? '').toString().toLowerCase();
                      final counterparty =
                          (m['counterpartyName'] ?? '—').toString();

                      String? counterpartyLabel;
                      if (counterparty != '—' && counterparty.isNotEmpty) {
                        counterpartyLabel = type == 'egreso'
                            ? 'Cliente: $counterparty'
                            : 'Proveedor: $counterparty';
                      }

                      return DataRow(
                        cells: [
                          DataCell(
                            Text(
                              dt == null
                                  ? '—'
                                  : '${dt.day}/${dt.month}/${dt.year} '
                                      '${dt.hour.toString().padLeft(2, '0')}:'
                                      '${dt.minute.toString().padLeft(2, '0')}',
                            ),
                          ),
                          DataCell(
                            Chip(
                              label: Text(
                                  type == 'ingreso' ? 'Ingreso' : 'Egreso'),
                            ),
                          ),
                          DataCell(
                            Text(m['createdByName'] ?? '—'),
                          ),
                          DataCell(
                            Text(counterpartyLabel ?? '—'),
                          ),
                          DataCell(
                            Text(
                              (m['totalItems'] ?? items.length).toString(),
                            ),
                          ),
                          DataCell(
                            Text(totalAmount.toStringAsFixed(2)),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.list),
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
                                              if ((m['note'] ?? '')
                                                  .toString()
                                                  .isNotEmpty)
                                                Padding(
                                                  padding: const EdgeInsets.only(
                                                      bottom: 8.0),
                                                  child: Text('Nota: ${m['note']}'),
                                                ),
                                              ...items.map((it) {
                                                final qty = _toInt(it['qty']);
                                                final unitPrice = _toMoney(
                                                  it['unitPrice'] ??
                                                      it['purchasePrice'] ??
                                                      it['salePrice'],
                                                );
                                                final subtotal =
                                                    _toMoney(it['subtotal']);

                                                final stockBefore =
                                                    it['stockBefore'];
                                                final stockAfter =
                                                    it['stockAfter'];
                                                String stockText = '';
                                                if (stockBefore is num &&
                                                    stockAfter is num) {
                                                  stockText =
                                                      'Stock: ${_toInt(stockBefore)} → ${_toInt(stockAfter)}';
                                                }

                                                return ListTile(
                                                  dense: true,
                                                  title: Text(
                                                    '${it['productName']} (SKU: ${it['sku']})',
                                                  ),
                                                  subtitle: Text(
                                                    'Cant: $qty • '
                                                    'P. unidad: ${unitPrice.toStringAsFixed(2)} • '
                                                    'Subtotal: ${subtotal.toStringAsFixed(2)}',
                                                  ),
                                                  trailing: stockText.isEmpty
                                                      ? null
                                                      : Text(stockText),
                                                );
                                              }).toList(),
                                            ],
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(cx),
                                            child: const Text('Cerrar'),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: 'Eliminar',
                                  onPressed: () =>
                                      _deleteMovementWithPassword(d),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                );
              },
            );
          },
        ),

        const SizedBox(height: 12),

        // ====== CARD de último borrado (para deshacer) ======
        if (_lastDeletedData != null)
          Card(
            color: Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Movimiento eliminado recientemente',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Builder(builder: (context) {
                          final m = _lastDeletedData!;
                          final type =
                              (m['type'] ?? '').toString().toLowerCase();
                          final total =
                              _toMoney(m['totalAmount']).toStringAsFixed(2);
                          final counterparty =
                              (m['counterpartyName'] ?? '—').toString();
                          return Text(
                            '${type == 'ingreso' ? 'Ingreso' : 'Egreso'} '
                            '• Total: $total • Contraparte: $counterparty',
                          );
                        }),
                        const SizedBox(height: 4),
                        const Text(
                          'Puedes restaurar este movimiento si la eliminación fue un error.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    children: [
                      TextButton(
                        onPressed: _undoLastDelete,
                        child: const Text('Deshacer'),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _lastDeletedData = null;
                            _lastDeletedId = null;
                          });
                        },
                        child: const Text('Descartar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Wrappers de formularios
class EgresoPage extends StatelessWidget {
  const EgresoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Generar venta (Egreso)'),
        backgroundColor: Colors.green,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 4,
              child: const Padding(
                padding: EdgeInsets.all(16.0),
                child: EgresoFormWidget(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class IngresoPage extends StatelessWidget {
  const IngresoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo ingreso'),
        backgroundColor: Colors.green,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 4,
              child: const Padding(
                padding: EdgeInsets.all(16.0),
                child: IngresoFormWidget(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
