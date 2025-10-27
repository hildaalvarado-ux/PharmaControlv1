// carrusel.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HomeCarousel extends StatefulWidget {
  const HomeCarousel({super.key});

  @override
  State<HomeCarousel> createState() => _HomeCarouselState();
}

class _HomeCarouselState extends State<HomeCarousel> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  Timer? _timer;

  String? _currentRole; // 'admin' | 'farmaceutico' | 'vendedor' | null

  final List<String> _images = const [
    'assets/oferta1.png',
    'assets/oferta2.png',
    'assets/oferta3.png',
  ];

  @override
  void initState() {
    super.initState();
    _startAutoPlay();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _currentRole = null);
        return;
      }
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        setState(() => _currentRole = (doc.data()?['role'] ?? '').toString().toLowerCase());
      } else {
        setState(() => _currentRole = null);
      }
    } catch (_) {
      setState(() => _currentRole = null);
    }
  }

  void _startAutoPlay() {
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _images.isEmpty) return;
      final nextPage = (_currentIndex + 1) % _images.length;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _goToPrevious() {
    final prevPage = _currentIndex > 0 ? _currentIndex - 1 : _images.length - 1;
    _pageController.animateToPage(
      prevPage,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
    );
  }

  void _goToNext() {
    final nextPage = (_currentIndex + 1) % _images.length;
    _pageController.animateToPage(
      nextPage,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
    );
  }

  bool get _canManagePromotions {
    final r = _currentRole?.toLowerCase();
    return r == 'admin' || r == 'farmaceutico';
  }

  bool get _canSendToEgreso {
    // Admin/Farmacéutico también pueden, Vendedor SOLO esto.
    final r = _currentRole?.toLowerCase();
    return r == 'admin' || r == 'farmaceutico' || r == 'vendedor';
  }

  Future<void> _showAddOrEditPromotionDialog({DocumentSnapshot? editingPromotion, String? preselectedProductId}) async {
    final productosSnap = await FirebaseFirestore.instance.collection('products').orderBy('name').get();
    final productos = productosSnap.docs;

    String? selectedProductId = preselectedProductId;
    double? price;
    final descuentoCtrl = TextEditingController();
    DateTime? fechaInicio;
    DateTime? fechaFin;

    if (editingPromotion != null) {
      final data = editingPromotion.data() as Map<String, dynamic>;
      selectedProductId = data['productId'];
      descuentoCtrl.text = (data['discount'] ?? '').toString();
      fechaInicio = (data['startDate'] as Timestamp?)?.toDate();
      fechaFin = (data['endDate'] as Timestamp?)?.toDate();

      if (selectedProductId != null) {
        final pdoc = await FirebaseFirestore.instance.collection('products').doc(selectedProductId).get();
        if (pdoc.exists) price = ((pdoc.data()?['price'] ?? 0) as num).toDouble();
      }
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setLocal) {
          return AlertDialog(
            title: Text(editingPromotion == null ? 'Agregar promoción' : 'Editar promoción'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (productos.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Text('No hay productos disponibles.'),
                    ),
                  if (productos.isNotEmpty)
                    DropdownButtonFormField<String>(
                      value: selectedProductId,
                      decoration: const InputDecoration(labelText: 'Producto'),
                      items: productos.map((doc) {
                        return DropdownMenuItem(
                          value: doc.id,
                          child: Text(doc['name'] ?? 'Sin nombre'),
                        );
                      }).toList(),
                      onChanged: (value) async {
                        selectedProductId = value;
                        if (value != null) {
                          final prod = await FirebaseFirestore.instance.collection('products').doc(value).get();
                          setLocal(() => price = ((prod.data()?['price'] ?? 0) as num).toDouble());
                        } else {
                          setLocal(() => price = null);
                        }
                      },
                    ),
                  if (price != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text('Precio actual: \$${price!.toStringAsFixed(2)}'),
                    ),
                  TextFormField(
                    controller: descuentoCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Porcentaje de descuento (%)'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(fechaInicio == null ? 'Inicio: —' : 'Inicio: ${_fmtDate(fechaInicio!)}'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.calendar_today),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: fechaInicio ?? DateTime.now(),
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) setLocal(() => fechaInicio = picked);
                        },
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(fechaFin == null ? 'Fin: —' : 'Fin: ${_fmtDate(fechaFin!)}'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.calendar_month),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: fechaFin ?? DateTime.now(),
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) setLocal(() => fechaFin = picked);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: () async {
                  if (selectedProductId == null || descuentoCtrl.text.trim().isEmpty || fechaInicio == null || fechaFin == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Complete todos los campos')));
                    return;
                  }
                  final payload = {
                    'productId': selectedProductId,
                    'discount': double.tryParse(descuentoCtrl.text.trim()) ?? 0.0,
                    'startDate': fechaInicio,
                    'endDate': fechaFin,
                    'createdAt': DateTime.now(),
                  };
                  if (editingPromotion == null) {
                    await FirebaseFirestore.instance.collection('promotions').add(payload);
                  } else {
                    await FirebaseFirestore.instance.collection('promotions').doc(editingPromotion.id).update(payload);
                  }
                  if (mounted) Navigator.pop(context);
                },
                child: const Text('Guardar', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _confirmDeletePromotion(DocumentSnapshot promotionDoc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar promoción'),
        content: const Text('¿Seguro que quieres eliminar esta promoción?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FirebaseFirestore.instance.collection('promotions').doc(promotionDoc.id).delete();
    }
  }

  void _sendToEgreso(Map<String, dynamic> productData) {
    try {
      Navigator.pushNamed(context, '/egreso', arguments: {
        'productId': productData['id'],
        'name': productData['name'],
        'price': productData['price'],
      });
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el formulario de egreso. Verifica la ruta /egreso')),
      );
    }
  }

  static String _fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  // --- UI ----
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 700;

    return Stack(
      children: [
        SingleChildScrollView(
          child: Column(
            children: [
              // Carrusel responsivo
              SizedBox(
                height: isMobile ? 180 : 260,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PageView.builder(
                      controller: _pageController,
                      itemCount: _images.length,
                      onPageChanged: (index) => setState(() => _currentIndex = index),
                      itemBuilder: (context, index) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(_images[index], fit: BoxFit.cover, width: double.infinity),
                        );
                      },
                    ),
                    Positioned(left: 10, child: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white), onPressed: _goToPrevious)),
                    Positioned(right: 10, child: IconButton(icon: const Icon(Icons.arrow_forward_ios, color: Colors.white), onPressed: _goToNext)),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              const Text('Ofertas (Próximos a vencer)', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),

              // Grid: Productos próximos a vencer (<= 90 días)
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('products').orderBy('expiryDate').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Error al cargar productos.'),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final docs = snapshot.data!.docs;
                  final filtered = docs.where((doc) {
                    final expiry = (doc['expiryDate'] as Timestamp?)?.toDate();
                    if (expiry == null) return false;
                    final remainingDays = expiry.difference(now).inDays;
                    return remainingDays <= 90; // próximos a vencer (3 meses)
                  }).toList();

                  if (filtered.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('No hay productos próximos a vencer.'),
                    );
                  }

                  return _ResponsiveGrid.builder(
                    itemCount: filtered.length,
                    minTileWidth: 280, // <- define el ancho mínimo de cada card
                    itemBuilder: (context, index) {
                      final doc = filtered[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final expiry = (data['expiryDate'] as Timestamp).toDate();
                      final price = ((data['price'] ?? 0) as num).toDouble();
                      final stock = (data['stock'] is int)
                          ? (data['stock'] as int)
                          : int.tryParse((data['stock'] ?? '0').toString()) ?? 0;

                      // Regla de descuento fijo 45% para próximos a vencer
                      const double discount = 45;
                      final discountedPrice = (price * (1 - discount / 100)).toStringAsFixed(2);
                      final outOfStock = stock <= 0;

                      return _ProductCard(
                        leadingIcon: Icons.medication,
                        title: data['name'] ?? 'Producto',
                        subtitleTop: 'Vence: ${_fmtDate(expiry)}',
                        discountText: 'Descuento: ${discount.toStringAsFixed(0)}%',
                        priceText: '\$$discountedPrice',
                        stock: stock,
                        dimWhenNoStock: true,
                        actions: _buildActionsForRole(
                          productId: doc.id,
                          productName: data['name'],
                          price: price,
                          outOfStock: outOfStock,
                          allowPromoActions: _canManagePromotions,
                        ),
                      );
                    },
                  );
                },
              ),

              const SizedBox(height: 20),
              const Text('Promociones guardadas', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),

              // Grid: Promociones guardadas
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('promotions').orderBy('createdAt', descending: true).snapshots(),
                builder: (context, snapPromos) {
                  if (snapPromos.hasError) {
                    return const Padding(padding: EdgeInsets.all(12), child: Text('Error al cargar promociones.'));
                  }
                  if (!snapPromos.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final promos = snapPromos.data!.docs;
                  if (promos.isEmpty) {
                    return const Padding(padding: EdgeInsets.all(12), child: Text('No hay promociones guardadas.'));
                  }

                  return _ResponsiveGrid.builder(
                    itemCount: promos.length,
                    minTileWidth: 280,
                    itemBuilder: (context, index) {
                      final promoDoc = promos[index];
                      final promoData = promoDoc.data() as Map<String, dynamic>;
                      final productId = promoData['productId'] as String?;
                      final discount = ((promoData['discount'] ?? 0) as num).toDouble();
                      final startDate = (promoData['startDate'] as Timestamp?)?.toDate();
                      final endDate = (promoData['endDate'] as Timestamp?)?.toDate();

                      return FutureBuilder<DocumentSnapshot>(
                        future: productId == null
                            ? null
                            : FirebaseFirestore.instance.collection('products').doc(productId).get(),
                        builder: (context, prodSnap) {
                          if (prodSnap.connectionState == ConnectionState.waiting) {
                            return const Card(
                              elevation: 2,
                              child: Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
                            );
                          }
                          if (prodSnap.data == null || !(prodSnap.data!.exists)) {
                            return const Card(
                              elevation: 2,
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: Center(child: Text('Producto no encontrado')),
                              ),
                            );
                          }

                          final prodData = prodSnap.data!.data() as Map<String, dynamic>;
                          final prodPrice = ((prodData['price'] ?? 0) as num).toDouble();
                          final stock = (prodData['stock'] is int)
                              ? (prodData['stock'] as int)
                              : int.tryParse((prodData['stock'] ?? '0').toString()) ?? 0;
                          final outOfStock = stock <= 0;
                          final discountedPrice = (prodPrice * (1 - discount / 100)).toStringAsFixed(2);

                          return _ProductCard(
                            leadingIcon: Icons.local_offer,
                            title: prodData['name'] ?? 'Producto',
                            subtitleTop: (startDate != null && endDate != null)
                                ? 'Desde: ${_fmtDate(startDate)}\nHasta: ${_fmtDate(endDate)}'
                                : null,
                            discountText: 'Descuento: ${discount.toStringAsFixed(0)}%',
                            priceText: '\$$discountedPrice',
                            stock: stock,
                            dimWhenNoStock: true,
                            actions: _buildActionsForRole(
                              productId: prodSnap.data!.id,
                              productName: prodData['name'],
                              price: prodPrice,
                              outOfStock: outOfStock,
                              allowPromoActions: _canManagePromotions,
                              promoDoc: promoDoc,
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),

        // FAB solo para admin/farmacéutico
        if (_canManagePromotions)
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton(
              backgroundColor: Colors.green,
              onPressed: () => _showAddOrEditPromotionDialog(),
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildActionsForRole({
    required String productId,
    required String? productName,
    required double price,
    required bool outOfStock,
    required bool allowPromoActions,
    DocumentSnapshot? promoDoc,
  }) {
    final actions = <Widget>[];

    // Vendedor: solo egreso (si hay stock)
    // Admin/Farmaceutico: editar/eliminar + egreso (si hay stock)
    if (allowPromoActions) {
      actions.addAll([
        IconButton(
          tooltip: promoDoc == null ? 'Crear/Editar promoción' : 'Editar promoción',
          onPressed: () async {
            if (promoDoc != null) {
              await _showAddOrEditPromotionDialog(editingPromotion: promoDoc);
            } else {
              // buscar si ya existe promoción para este producto
              final promoSnap = await FirebaseFirestore.instance
                  .collection('promotions')
                  .where('productId', isEqualTo: productId)
                  .limit(1)
                  .get();
              if (promoSnap.docs.isNotEmpty) {
                await _showAddOrEditPromotionDialog(editingPromotion: promoSnap.docs.first);
              } else {
                await _showAddOrEditPromotionDialog(preselectedProductId: productId);
              }
            }
          },
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Eliminar promoción',
          onPressed: () async {
            if (promoDoc != null) {
              await _confirmDeletePromotion(promoDoc);
            } else {
              final promoSnap = await FirebaseFirestore.instance
                  .collection('promotions')
                  .where('productId', isEqualTo: productId)
                  .limit(1)
                  .get();
              if (promoSnap.docs.isNotEmpty) {
                await _confirmDeletePromotion(promoSnap.docs.first);
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No hay promoción para eliminar en este producto')),
                  );
                }
              }
            }
          },
          icon: const Icon(Icons.delete_outline),
        ),
      ]);
    }

    if (_canSendToEgreso) {
      actions.add(
        IconButton(
          tooltip: outOfStock ? 'Sin stock' : 'Mandar a egreso',
          onPressed: outOfStock
              ? null
              : () => _sendToEgreso({'id': productId, 'name': productName, 'price': price}),
          icon: const Icon(Icons.shopping_cart_outlined),
        ),
      );
    }

    return actions;
  }
}

/// Widget de card de producto/promo con indicador de stock y estado sin stock.
class _ProductCard extends StatelessWidget {
  final IconData leadingIcon;
  final String title;
  final String? subtitleTop;
  final String discountText;
  final String priceText;
  final int stock;
  final bool dimWhenNoStock;
  final List<Widget> actions;

  const _ProductCard({
    required this.leadingIcon,
    required this.title,
    required this.discountText,
    required this.priceText,
    required this.stock,
    required this.actions,
    this.subtitleTop,
    this.dimWhenNoStock = false,
  });

  @override
  Widget build(BuildContext context) {
    final out = stock <= 0;

    final card = Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 2),
            Icon(leadingIcon, size: 40, color: Colors.green),
            const SizedBox(height: 6),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            if (subtitleTop != null) ...[
              const SizedBox(height: 6),
              Text(subtitleTop!, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 6),
            Center(child: Text(discountText, style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
            const SizedBox(height: 4),
            Center(child: Text(priceText, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 15))),
            const SizedBox(height: 8),
            Center(
              child: Text(
                out ? 'Sin stock' : 'Stock: $stock',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: out ? Colors.red : Colors.black87,
                ),
              ),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: actions,
            ),
          ],
        ),
      ),
    );

    if (!dimWhenNoStock || !out) return card;

    // Atenuar cuando no hay stock
    return Stack(
      children: [
        Opacity(opacity: 0.6, child: card),
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.shade600,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('SIN STOCK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
          ),
        ),
      ],
    );
  }
}

/// Grid responsivo que elimina huecos usando un ancho mínimo de tile.
/// Ajusta columnas automáticamente según el ancho real disponible.
class _ResponsiveGrid extends StatelessWidget {
  final int itemCount;
  final double minTileWidth;
  final IndexedWidgetBuilder itemBuilder;

  const _ResponsiveGrid.builder({
    required this.itemCount,
    required this.itemBuilder,
    this.minTileWidth = 260,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final maxW = constraints.maxWidth;
      final crossAxisCount = (maxW / minTileWidth).floor().clamp(1, 6);
      final tileWidth = maxW / crossAxisCount;
      // Relación de aspecto para tarjetas verticales cómodas.
      final childAspectRatio = tileWidth / 360;

      return GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: itemCount,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: childAspectRatio,
        ),
        itemBuilder: itemBuilder,
      );
    });
  }
}
