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

  _View _view = _View.all;
  bool _busy = false;

  DateTime? _from;
  DateTime? _to;

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

  /// Solo filtra por fechas en Firestore para evitar problemas de índices.
  Query _buildQuery() {
    Query q = _movementsRef.orderBy('createdAt', descending: true);

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

  /// Retorna si un movimiento coincide con el filtro de tipo actual (_view).
  bool _matchesView(Map<String, dynamic> m) {
    final type = (m['type'] ?? '').toString().toLowerCase();
    switch (_view) {
      case _View.ingresos:
        return type == 'ingreso';
      case _View.egresos:
        return type == 'egreso';
      case _View.all:
      default:
        return true;
    }
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

  // ====== ELIMINAR movimiento con SOFT DELETE y motivo obligatorio ======
  Future<void> _softDeleteMovement(DocumentSnapshot movementDoc) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _snack('No hay usuario autenticado.');
      return;
    }

    final reasonCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: reasonCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Motivo de la eliminación',
              hintText: 'Ej: venta anulada, error de registro...',
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'El motivo es obligatorio';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white, // texto blanco
            ),
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

      await movementDoc.reference.update({
        'deleted': true,
        'deleteReason': reasonCtrl.text.trim(),
        'deletedAt': FieldValue.serverTimestamp(),
        'deletedByUid': currentUser.uid,
        'deletedByEmail': currentUser.email,
      });

      _snack('Movimiento marcado como eliminado.');
    } catch (e) {
      _snack('Error al eliminar movimiento: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreMovement(DocumentSnapshot movementDoc) async {
    try {
      setState(() => _busy = true);

      await movementDoc.reference.update({
        'deleted': false,
      });

      _snack('Movimiento restaurado.');
    } catch (e) {
      _snack('Error al restaurar movimiento: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ====== IMPRIMIR movimientos según filtros actuales (solo activos) ======
  Future<void> _printCurrentMovements() async {
    try {
      setState(() => _busy = true);
      final snap = await _buildQuery().get();

      final docs = snap.docs.where((d) {
        final m = d.data() as Map<String, dynamic>;
        final isDeleted = m['deleted'] == true;
        if (isDeleted) return false;
        return _matchesView(m);
      }).toList();

      if (docs.isEmpty) {
        _snack('No hay movimientos para imprimir con los filtros actuales.');
        return;
      }

      final movements = docs.map((d) {
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

  // ====== REPORTE / VISTA DE IVA RETENIDO ======

  Future<void> _openIvaRetenidoDialog() async {
    try {
      setState(() => _busy = true);

      final snap = await _buildQuery().get();
      final now = DateTime.now();
      final currentMonthStart = DateTime(now.year, now.month, 1);
      final nextMonthStart =
          (now.month == 12) ? DateTime(now.year + 1, 1, 1) : DateTime(now.year, now.month + 1, 1);

      final pending = <Map<String, dynamic>>[];
      final current = <Map<String, dynamic>>[];

      for (final d in snap.docs) {
        final m = d.data() as Map<String, dynamic>;

        // ignorar eliminados
        if (m['deleted'] == true) continue;

        final type = (m['type'] ?? '').toString().toLowerCase();
        if (type != 'egreso') continue;

        final ivaRetenido = _toMoney(m['ivaRetenido'] ?? 0);
        if (ivaRetenido <= 0) continue;

        final ts = m['createdAt'];
        if (ts is! Timestamp) continue;
        final dt = ts.toDate();

        final subtotal = _toMoney(m['subtotal'] ?? m['subtotalAmount'] ?? 0);
        final iva = _toMoney(m['iva'] ?? m['ivaAmount'] ?? 0);
        final total = _toMoney(m['totalAmount'] ?? m['total'] ?? 0);

        final full = {
          ...m,
          'id': d.id,
          'createdAtDateTime': dt,
          '_subtotal': subtotal,
          '_iva': iva,
          '_ivaRetenido': ivaRetenido,
          '_total': total,
        };

        if (dt.isBefore(currentMonthStart)) {
          pending.add(full);
        } else if (dt.isBefore(nextMonthStart)) {
          current.add(full);
        } else {
          // por si acaso hay movimientos a futuro, los tratamos como mes actual
          current.add(full);
        }
      }

      if (pending.isEmpty && current.isEmpty) {
        _snack('No hay egresos con IVA retenido en los filtros actuales.');
        return;
      }

      await showDialog(
        context: context,
        builder: (ctx) => _IvaRetenidoDialog(
          pendientes: pending,
          mesActual: current,
          onPrint: () => _printIvaRetenido([...pending, ...current]),
        ),
      );
    } catch (e) {
      _snack('Error al cargar IVA retenido: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _printIvaRetenido(List<Map<String, dynamic>> ivaMovs) async {
    if (ivaMovs.isEmpty) {
      _snack('No hay datos de IVA retenido para imprimir.');
      return;
    }

    try {
      setState(() => _busy = true);

      final bytes = await MovementsPdf.build(
        title: 'Reporte de IVA retenido',
        filterLabel: 'Egresos con IVA retenido',
        from: _from,
        to: _to,
        movements: ivaMovs,
      );

      final now = DateTime.now();
      await pdf_out.outputPdf(
        bytes,
        'iva_retenido_${now.year}${now.month}${now.day}_${now.hour}${now.minute}.pdf',
      );
    } catch (e) {
      _snack('Error al generar PDF de IVA: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ====== UI ======
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 800;

        // -------- TOOLBAR ESCRITORIO --------
        final desktopToolbar = Row(
          children: [
            Text(
              'Movimientos',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _openIvaRetenidoDialog,
              icon: const Icon(Icons.receipt_long),
              label: const Text('IVA retenido'),
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
              onSelectionChanged: (s) => setState(() => _view = s.first),
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
        );

        // -------- TOOLBAR MÓVIL --------
        final mobileToolbar = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Movimientos',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _openIvaRetenidoDialog,
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('IVA retenido'),
                  ),
                  const SizedBox(width: 8),
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
                  const SizedBox(width: 8),
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
                      tooltip: 'Limpiar',
                      onPressed: () => setState(() {
                        _from = null;
                        _to = null;
                      }),
                      icon: const Icon(Icons.clear),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _printCurrentMovements,
                    icon: const Icon(Icons.print),
                    label: const Text('Imprimir'),
                  ),
                  const SizedBox(width: 8),
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
            ),
          ],
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            isMobile ? mobileToolbar : desktopToolbar,
            const SizedBox(height: 12),
            if (_busy) const LinearProgressIndicator(minHeight: 2),

            // ====== LISTADOS ======
            StreamBuilder<QuerySnapshot>(
              stream: _buildQuery().snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return const Text('Error al cargar movimientos');
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allDocs = snap.data!.docs;

                // Separamos activos y eliminados
                final activeDocs = allDocs.where((d) {
                  final m = d.data() as Map<String, dynamic>;
                  final isDeleted = m['deleted'] == true;
                  if (isDeleted) return false;
                  return _matchesView(m);
                }).toList();

                final deletedDocs = allDocs.where((d) {
                  final m = d.data() as Map<String, dynamic>;
                  final isDeleted = m['deleted'] == true;
                  if (!isDeleted) return false;
                  return _matchesView(m);
                }).toList();

                return LayoutBuilder(
                  builder: (context, constraints2) {
                    final isMobile2 = constraints2.maxWidth < 800;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildMovementsSection(
                          context,
                          isMobile: isMobile2,
                          documents: activeDocs,
                          deletedSection: false,
                        ),
                        const SizedBox(height: 16),
                        if (deletedDocs.isNotEmpty) ...[
                          const Divider(),
                          Text(
                            'Movimientos eliminados',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: Colors.grey[700]),
                          ),
                          const SizedBox(height: 8),
                          _buildMovementsSection(
                            context,
                            isMobile: isMobile2,
                            documents: deletedDocs,
                            deletedSection: true,
                          ),
                        ],
                      ],
                    );
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildMovementsSection(
    BuildContext context, {
    required bool isMobile,
    required List<QueryDocumentSnapshot> documents,
    required bool deletedSection,
  }) {
    if (documents.isEmpty) {
      return Text(
        deletedSection
            ? 'No hay movimientos eliminados con los filtros actuales.'
            : 'No hay movimientos con los filtros actuales.',
      );
    }

    if (isMobile) {
      // ====== MODO MÓVIL ======
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: documents.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final d = documents[i];
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

          String? counterpartyLabel;
          if (counterparty.isNotEmpty) {
            counterpartyLabel = type == 'egreso'
                ? 'Cliente: $counterparty'
                : 'Proveedor: $counterparty';
          }

          final deleteReason = (m['deleteReason'] ?? '').toString();

          return Card(
            color: deletedSection ? Colors.grey.shade200 : null,
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
                  if (counterpartyLabel != null) Text(counterpartyLabel),
                  if ((m['note'] ?? '').toString().isNotEmpty)
                    Text('Nota: ${m['note']}'),
                  if (deletedSection && deleteReason.isNotEmpty)
                    Text('Motivo eliminación: $deleteReason'),
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
                  final subtotal = _toMoney(it['subtotal']);

                  final stockBefore = it['stockBefore'];
                  final stockAfter = it['stockAfter'];
                  String stockText = '';
                  if (stockBefore is num && stockAfter is num) {
                    stockText =
                        'Stock: ${_toInt(stockBefore)} → ${_toInt(stockAfter)}';
                  }

                  return ListTile(
                    dense: true,
                    title: Text('${it['productName']} (SKU: ${it['sku']})'),
                    subtitle: Text(
                      'Cant: $qty • '
                      'P. unidad: ${unitPrice.toStringAsFixed(2)} • '
                      'Subtotal: ${subtotal.toStringAsFixed(2)}',
                    ),
                    trailing: stockText.isEmpty ? null : Text(stockText),
                  );
                }).toList(),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: deletedSection
                      ? TextButton.icon(
                          onPressed: () => _restoreMovement(d),
                          icon: const Icon(Icons.restore),
                          label: const Text('Restaurar'),
                        )
                      : TextButton.icon(
                          onPressed: () => _softDeleteMovement(d),
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
        columns: [
          const DataColumn(label: Text('Fecha')),
          const DataColumn(label: Text('Tipo')),
          const DataColumn(label: Text('Usuario')),
          const DataColumn(label: Text('Contraparte')),
          const DataColumn(label: Text('Líneas')),
          const DataColumn(label: Text('Total')),
          if (deletedSection)
            const DataColumn(label: Text('Motivo eliminación')),
          const DataColumn(label: Text('Acciones')),
        ],
        rows: documents.map((d) {
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
          final counterparty =
              (m['counterpartyName'] ?? '—').toString();

          String? counterpartyLabel;
          if (counterparty != '—' && counterparty.isNotEmpty) {
            counterpartyLabel = type == 'egreso'
                ? 'Cliente: $counterparty'
                : 'Proveedor: $counterparty';
          }

          final deleteReason = (m['deleteReason'] ?? '').toString();

          return DataRow(
            color: deletedSection
                ? MaterialStateProperty.all(Colors.grey.shade200)
                : null,
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
                  label: Text(type == 'ingreso' ? 'Ingreso' : 'Egreso'),
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
              if (deletedSection)
                DataCell(
                  Text(deleteReason.isEmpty ? '—' : deleteReason),
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
                                onPressed: () => Navigator.pop(cx),
                                child: const Text('Cerrar'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    deletedSection
                        ? IconButton(
                            icon: const Icon(Icons.restore),
                            tooltip: 'Restaurar',
                            onPressed: () => _restoreMovement(d),
                          )
                        : IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Eliminar',
                            onPressed: () => _softDeleteMovement(d),
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
}

// ====== DIÁLOGO DE IVA RETENIDO (solo UI / sin BD) ======

class _IvaRetenidoDialog extends StatefulWidget {
  final List<Map<String, dynamic>> pendientes;
  final List<Map<String, dynamic>> mesActual;
  final Future<void> Function()? onPrint;

  const _IvaRetenidoDialog({
    super.key,
    required this.pendientes,
    required this.mesActual,
    this.onPrint,
  });

  @override
  State<_IvaRetenidoDialog> createState() => _IvaRetenidoDialogState();
}

class _IvaRetenidoDialogState extends State<_IvaRetenidoDialog> {
  final Map<String, bool> _pagado = {};
  final Map<String, String> _comprobantes = {};

  double _totalIvaPendiente() {
    double total = 0;
    for (final m in widget.pendientes) {
      final id = (m['id'] ?? '').toString();
      if (_pagado[id] == true) continue;
      final ivaRet = (m['_ivaRetenido'] ?? 0.0) as double;
      total += ivaRet;
    }
    return total;
  }

  double _totalIvaMesActual() {
    double total = 0;
    for (final m in widget.mesActual) {
      final ivaRet = (m['_ivaRetenido'] ?? 0.0) as double;
      total += ivaRet;
    }
    return total;
  }

  Future<void> _marcarComoPagado(Map<String, dynamic> mov) async {
    final id = (mov['id'] ?? '').toString();
    final ctrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Registrar pago de IVA'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'Número de comprobante',
              hintText: 'Ej: 000123-ABC',
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'El comprobante es obligatorio';
              }
              return null;
            },
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
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (ok == true) {
      setState(() {
        _pagado[id] = true;
        _comprobantes[id] = ctrl.text.trim();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return AlertDialog(
      title: const Text('IVA retenido'),
      content: SizedBox(
        width: 1000,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Mes actual: ${now.month.toString().padLeft(2, '0')}/${now.year}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Aquí se muestran solo EGRESOS que tienen IVA retenido (13%) calculado al momento de la venta.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),

              // -------- PENDIENTES --------
              Text(
                'Pendiente de pago (meses anteriores)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              _buildTable(widget.pendientes, allowMarkPaid: true),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Total IVA retenido pendiente: ${_totalIvaPendiente().toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),

              const SizedBox(height: 20),

              // -------- MES ACTUAL --------
              Text(
                'Mes actual (en curso)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              _buildTable(widget.mesActual, allowMarkPaid: false),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Total IVA retenido del mes actual: ${_totalIvaMesActual().toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'La opción de marcar como pagado para el mes actual estará disponible al cierre del mes.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey[700]),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        if (widget.pendientes.isNotEmpty || widget.mesActual.isNotEmpty)
          OutlinedButton.icon(
            onPressed: widget.onPrint == null ? null : () => widget.onPrint!(),
            icon: const Icon(Icons.print),
            label: const Text('Imprimir'),
          ),
      ],
    );
  }

  Widget _buildTable(List<Map<String, dynamic>> items,
      {required bool allowMarkPaid}) {
    if (items.isEmpty) {
      return Text(
        'No hay registros en esta sección.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 16,
        columns: const [
          DataColumn(label: Text('Fecha')),
          DataColumn(label: Text('Usuario')),
          DataColumn(label: Text('Cliente')),
          DataColumn(label: Text('Subtotal')),
          DataColumn(label: Text('IVA')),
          DataColumn(label: Text('IVA retenido')),
          DataColumn(label: Text('Total')),
          DataColumn(label: Text('Estado')),
          DataColumn(label: Text('Acciones')),
        ],
        rows: items.map((m) {
          final id = (m['id'] ?? '').toString();
          final dt = m['createdAtDateTime'] as DateTime;
          final user = (m['createdByName'] ?? '—').toString();
          final client = (m['counterpartyName'] ?? '—').toString();

          final subtotal = (m['_subtotal'] ?? 0.0) as double;
          final iva = (m['_iva'] ?? 0.0) as double;
          final ivaRet = (m['_ivaRetenido'] ?? 0.0) as double;
          final total = (m['_total'] ?? 0.0) as double;

          final pagado = _pagado[id] == true;
          final comp = _comprobantes[id];

          return DataRow(
            cells: [
              DataCell(
                Text(
                  '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}',
                ),
              ),
              DataCell(Text(user)),
              DataCell(Text(client)),
              DataCell(Text(subtotal.toStringAsFixed(2))),
              DataCell(Text(iva.toStringAsFixed(2))),
              DataCell(Text(ivaRet.toStringAsFixed(2))),
              DataCell(Text(total.toStringAsFixed(2))),
              DataCell(
                pagado
                    ? Text('Pagado\nComp: $comp')
                    : const Text('Pendiente'),
              ),
              DataCell(
                allowMarkPaid
                    ? TextButton(
                        onPressed: pagado ? null : () => _marcarComoPagado(m),
                        child: Text(pagado ? 'Pagado' : 'Marcar como pagado'),
                      )
                    : const Text(
                        'Solo al\nfinal del mes',
                        textAlign: TextAlign.center,
                      ),
              ),
            ],
          );
        }).toList(),
      ),
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
