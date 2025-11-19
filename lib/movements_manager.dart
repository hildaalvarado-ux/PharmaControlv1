// lib/movements_manager.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'ingreso_form.dart';
import 'egreso_form.dart';

/// Colección 'movements' usada por la UI de Movimientos.

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
    if (_from != null) q = q.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(_from!));
    if (_to != null) {
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
      initialDateRange: (_from != null && _to != null) ? DateTimeRange(start: _from!, end: _to!) : null,
    );
    if (res != null) setState(() { _from = res.start; _to = res.end; });
  }

  // Navegar a formulario en pantalla completa usando wrappers
  Future<void> _openIngresoFullScreen() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IngresoPage()));
    // cuando vuelva, el stream actualiza automáticamente; si quisieras forzar recarga, setState() aquí.
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openEgresoFullScreen() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EgresoPage()));
    if (!mounted) return;
    setState(() {});
  }

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

            // Botones: ahora abren páginas completas (wrappers)
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
                              if ((m['counterpartyName'] ?? '') != '') Text(m['type'] == 'ingreso' ? 'Cliente: ${m['counterpartyName']}' : 'Proveedor: ${m['counterpartyName']}'),
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

/// ----- Wrappers para abrir formularios en pantalla completa -----
/// Las páginas abajo envuelven los widgets de formulario embebibles
/// en un Scaffold con AppBar para evitar errores de Material cuando
/// se navega con Navigator.push(...).

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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: const EgresoFormWidget(), // el widget embebible
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: const IngresoFormWidget(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
