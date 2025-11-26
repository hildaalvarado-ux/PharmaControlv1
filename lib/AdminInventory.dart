import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'app_theme.dart';
import 'inventory_pdf.dart';

class AdminInventoryPage extends StatefulWidget {
  const AdminInventoryPage({super.key});

  @override
  State<AdminInventoryPage> createState() => _AdminInventoryPageState();
}

class _AdminInventoryPageState extends State<AdminInventoryPage> {
  final CollectionReference productsRef =
      FirebaseFirestore.instance.collection('products');

  // ===== Helpers numéricos / formato =====

  num _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString().replaceAll(',', '.')) ?? 0;
  }

  String _fmt(dynamic n) {
    final v = _toNum(n).toDouble();
    return '\$${v.toStringAsFixed(2)}';
  }

  String _ddmmyyyy(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

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

  // ===== Stock bajo =====

  /// Cambia aquí el umbral si quieres otro valor.
  bool _isLowStock(num stock) => stock < 15;

  // ===== UI helpers =====

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

  // Lotes para un producto (vista compacta para inventario)
  Widget _buildBatchesList(String productId) {
    return StreamBuilder<QuerySnapshot>(
      stream: productsRef
          .doc(productId)
          .collection('batches')
          .orderBy('expiryDate')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const ListTile(
            title: Text("Error al cargar lotes."),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(8.0),
            child: Center(child: Text("Cargando lotes...")),
          );
        }
        if (snapshot.data!.docs.isEmpty) {
          return const ListTile(
            title: Text("No hay lotes registrados."),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                "Lotes",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ...snapshot.data!.docs.map((doc) {
              final batchData = doc.data() as Map<String, dynamic>;
              final expiry = _parseExpiry(batchData['expiryDate']);
              final near = expiry != null ? _isNearExpiry(expiry) : false;

              return ListTile(
                dense: true,
                title: Text(
                    "Lote: ${batchData['lot'] ?? 'S/L'} • Cant: ${batchData['qty'] ?? 0}"),
                subtitle: expiry != null
                    ? Text(
                        "Vence: ${_ddmmyyyy(expiry)}",
                        style: TextStyle(
                          color: near ? Colors.red : Colors.black87,
                          fontWeight:
                              near ? FontWeight.bold : FontWeight.normal,
                        ),
                      )
                    : const Text("Sin fecha de vencimiento"),
              );
            }).toList(),
          ],
        );
      },
    );
  }

  // ===== IMPRESIÓN / PDF =====

  Future<void> _printInventory(List<QueryDocumentSnapshot> docs) async {
    try {
      // Construir lista de items de inventario
      final items = <InventoryPdfItem>[];
      final nearExpiry = <InventoryPdfNearExpiryItem>[];
      double totalValue = 0;

      for (final d in docs) {
        final data = d.data() as Map<String, dynamic>;
        final name = (data['name'] ?? 'Producto').toString();
        final sku = (data['sku'] ?? '—').toString();
        final category = (data['category'] ?? '—').toString();
        final pres = (data['presentation'] ?? '').toString();
        final strength = (data['strength'] ?? '').toString();
        final presentation = [
          if (pres.isNotEmpty) pres,
          if (strength.isNotEmpty) strength,
        ].join(' • ');

        final stock = _toNum(data['stock']).toDouble();
        final purchasePrice = _toNum(data['purchasePrice']).toDouble();
        final salePrice = _toNum(data['price']).toDouble();
        final taxable = (data['taxable'] ?? false) == true;

        final value = stock * purchasePrice;
        totalValue += value;

        items.add(
          InventoryPdfItem(
            name: name,
            sku: sku,
            category: category,
            presentation: presentation,
            stock: stock,
            unitCost: purchasePrice,
            inventoryValue: value,
            salePrice: salePrice,
            taxable: taxable,
          ),
        );

        // Lotes próximos a vencer para este producto
        final batchesSnap = await productsRef
            .doc(d.id)
            .collection('batches')
            .orderBy('expiryDate')
            .get();

        for (final b in batchesSnap.docs) {
          final bd = b.data() as Map<String, dynamic>;
          final expiry = _parseExpiry(bd['expiryDate']);
          if (expiry == null) continue;
          if (_isNearExpiry(expiry)) {
            final qty = _toNum(bd['qty']).toDouble();
            nearExpiry.add(
              InventoryPdfNearExpiryItem(
                productName: name,
                sku: sku,
                lot: (bd['lot'] ?? 'S/L').toString(),
                qty: qty,
                expiryDate: expiry,
              ),
            );
          }
        }
      }

      // Ordenar por nombre para la tabla principal
      items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      // Ordenar próximos a vencer por fecha
      nearExpiry.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));

      final bytes = await InventoryPdf.build(
        title: 'Inventario de productos',
        generatedAt: DateTime.now(),
        totalValue: totalValue,
        totalProducts: items.length,
        items: items,
        nearExpiry: nearExpiry,
        logoAssetPath: 'assets/logo.png',
      );

      await Printing.layoutPdf(
        onLayout: (format) async => bytes,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al generar PDF de inventario: $e')),
      );
    }
  }

  // ===== Vista principal =====

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Center(
          child: Text(
            'Inventario de productos',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: kGreen1,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // STREAM de productos para inventario
        StreamBuilder<QuerySnapshot>(
          stream: productsRef.orderBy('name').snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return const Text('Error al cargar inventario');
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No hay productos en inventario.'),
              );
            }

            // Cálculo del valor total del inventario
            num totalInventoryValue = 0;
            for (final d in docs) {
              final data = d.data() as Map<String, dynamic>;
              final stock = _toNum(data['stock']);
              final purchasePrice = _toNum(data['purchasePrice']);
              totalInventoryValue += stock * purchasePrice;
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 900;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Resumen rápido + botón de impresión arriba
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Productos: ${docs.length}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Valor total (al costo): ${_fmt(totalInventoryValue)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => _printInventory(docs),
                            icon: const Icon(Icons.print),
                            label: const Text('Imprimir'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kGreen2,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // ===== Inventario general (según dispositivo) =====
                    if (isMobile)
                      _buildMobileInventoryList(docs)
                    else
                      _buildDesktopInventoryTable(docs),

                    const SizedBox(height: 24),

                    // ===== Tabla aparte: productos / lotes próximos a vencer =====
                    Text(
                      'Productos / lotes próximos a vencer (≤ 90 días)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: kGreen1,
                      ),
                    ),
                    const SizedBox(height: 8),

                    _buildNearExpirySection(docs),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }

  // ===== Inventario general - móvil =====

  Widget _buildMobileInventoryList(List<QueryDocumentSnapshot> docs) {
    return ListView.separated(
      itemCount: docs.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final d = docs[i];
        final data = d.data() as Map<String, dynamic>;
        final taxable = (data['taxable'] ?? false) == true;
        final stock = _toNum(data['stock']);
        final purchasePrice = _toNum(data['purchasePrice']);
        final value = stock * purchasePrice;
        final isLow = _isLowStock(stock);

        return Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            title: Text(
              '${data['name'] ?? '—'}  (${data['sku'] ?? '—'})',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Categoría: ${data['category'] ?? '—'}'),
                Row(
                  children: [
                    Text(
                      'Stock actual: $stock',
                      style: TextStyle(
                        color: isLow ? Colors.red : null,
                        fontWeight: isLow ? FontWeight.bold : null,
                      ),
                    ),
                    if (isLow) ...[
                      const SizedBox(width: 6),
                      _chip('Stock bajo', color: Colors.red),
                    ],
                  ],
                ),
                Text('Costo unitario: ${_fmt(purchasePrice)}'),
                Text('Valor en existencia: ${_fmt(value)}'),
                Text(
                    'Precio venta: ${_fmt(data['price'])} ${taxable ? "(c/IVA)" : ""}'),
                if ((data['pharmForm'] ?? '').toString().isNotEmpty ||
                    (data['route'] ?? '').toString().isNotEmpty)
                  Text(
                      'Forma/Vía: ${data['pharmForm'] ?? '—'} / ${data['route'] ?? '—'}'),
                if ((data['strength'] ?? '').toString().isNotEmpty)
                  Text('Conc.: ${data['strength']}'),
                if ((data['presentation'] ?? '').toString().isNotEmpty)
                  Text('Presentación: ${data['presentation']}'),
              ],
            ),
            children: [
              _buildBatchesList(d.id),
            ],
          ),
        );
      },
    );
  }

  // ===== Inventario general - escritorio =====

  Widget _buildDesktopInventoryTable(List<QueryDocumentSnapshot> docs) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Nombre')),
          DataColumn(label: Text('SKU')),
          DataColumn(label: Text('Categoría')),
          DataColumn(label: Text('Presentación')),
          DataColumn(label: Text('Stock')),
          DataColumn(label: Text('Costo unitario')),
          DataColumn(label: Text('Valor existencia')),
          DataColumn(label: Text('Precio venta')),
          DataColumn(label: Text('IVA')),
          DataColumn(label: Text('Forma/Vía')),
        ],
        rows: docs.map((d) {
          final data = d.data() as Map<String, dynamic>;
          final taxable = (data['taxable'] ?? false) == true;
          final stock = _toNum(data['stock']);
          final purchasePrice = _toNum(data['purchasePrice']);
          final value = stock * purchasePrice;

          final pres = (data['presentation'] ?? '').toString();
          final strength = (data['strength'] ?? '').toString();
          final presentacionCompleta = [
            if (pres.isNotEmpty) pres,
            if (strength.isNotEmpty) strength,
          ].join(' • ');

          final isLow = _isLowStock(stock);

          return DataRow(
            color: MaterialStateProperty.resolveWith<Color?>(
              (states) =>
                  isLow ? Colors.red.withOpacity(0.08) : null, // fila tenue roja
            ),
            cells: [
              DataCell(Text(data['name'] ?? '—')),
              DataCell(Text(data['sku'] ?? '—')),
              DataCell(Text(data['category'] ?? '—')),
              DataCell(Text(
                  presentacionCompleta.isEmpty ? '—' : presentacionCompleta)),
              DataCell(
                Text(
                  stock.toString(),
                  style: TextStyle(
                    color: isLow ? Colors.red : null,
                    fontWeight: isLow ? FontWeight.bold : null,
                  ),
                ),
              ),
              DataCell(Text(_fmt(purchasePrice))),
              DataCell(Text(_fmt(value))),
              DataCell(Text(_fmt(data['price']))),
              DataCell(
                Icon(
                  taxable ? Icons.check_circle : Icons.cancel,
                  color: taxable ? Colors.orange : Colors.grey,
                ),
              ),
              DataCell(
                Text(
                    '${data['pharmForm'] ?? '—'} / ${data['route'] ?? '—'}'),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ===== Sección de productos / lotes próximos a vencer =====

  Widget _buildNearExpirySection(List<QueryDocumentSnapshot> productDocs) {
    return StreamBuilder<List<_NearExpiryRow>>(
      stream: _buildNearExpiryStream(productDocs),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(8.0),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final rows = snapshot.data!;
        if (rows.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              'No hay productos con lotes próximos a vencer.',
              textAlign: TextAlign.center,
            ),
          );
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Producto')),
              DataColumn(label: Text('SKU')),
              DataColumn(label: Text('Lote')),
              DataColumn(label: Text('Cantidad')),
              DataColumn(label: Text('Fecha vencimiento')),
              DataColumn(label: Text('Días restantes')),
            ],
            rows: rows.map((r) {
              final daysLeft =
                  r.expiryDate.difference(DateTime.now()).inDays;
              return DataRow(
                cells: [
                  DataCell(Text(r.productName)),
                  DataCell(Text(r.sku ?? '—')),
                  DataCell(Text(r.lot ?? 'S/L')),
                  DataCell(Text(r.qty.toString())),
                  DataCell(Text(_ddmmyyyy(r.expiryDate))),
                  DataCell(
                    Text(
                      daysLeft.toString(),
                      style: TextStyle(
                        color: daysLeft <= 0 ? Colors.red : Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        );
      },
    );
  }

  // Stream simple que refresca los lotes próximos a vencer
  Stream<List<_NearExpiryRow>> _buildNearExpiryStream(
      List<QueryDocumentSnapshot> productDocs) {
    return Stream.periodic(const Duration(seconds: 3)).asyncMap((_) async {
      final List<_NearExpiryRow> result = [];

      for (final prod in productDocs) {
        final data = prod.data() as Map<String, dynamic>;
        final prodName = (data['name'] ?? 'Producto').toString();
        final sku = data['sku']?.toString();

        final batchesSnap = await productsRef
            .doc(prod.id)
            .collection('batches')
            .orderBy('expiryDate')
            .get();

        for (final b in batchesSnap.docs) {
          final bd = b.data() as Map<String, dynamic>;
          final expiry = _parseExpiry(bd['expiryDate']);
          if (expiry == null) continue;
          if (_isNearExpiry(expiry)) {
            result.add(
              _NearExpiryRow(
                productName: prodName,
                sku: sku,
                lot: bd['lot']?.toString(),
                qty: _toNum(bd['qty']),
                expiryDate: expiry,
              ),
            );
          }
        }
      }

      result.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
      return result;
    });
  }
}

// Modelo interno para filas de "próximos a vencer"
class _NearExpiryRow {
  final String productName;
  final String? sku;
  final String? lot;
  final num qty;
  final DateTime expiryDate;

  _NearExpiryRow({
    required this.productName,
    required this.sku,
    required this.lot,
    required this.qty,
    required this.expiryDate,
  });
}
