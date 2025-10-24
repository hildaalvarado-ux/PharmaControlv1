import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HomeCarousel extends StatefulWidget {
  HomeCarousel({super.key}); // 🔹 quitamos const para evitar conflictos con hot reload

  @override
  State<HomeCarousel> createState() => _HomeCarouselState();
}

class _HomeCarouselState extends State<HomeCarousel> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  Timer? _timer;

  final List<String> _images = [
    'assets/oferta1.png',
    'assets/oferta2.png',
    'assets/oferta3.png',
  ];

  @override
  void initState() {
    super.initState();
    _startAutoPlay();
  }

  void _startAutoPlay() {
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_images.isNotEmpty && mounted) {
        int nextPage = (_currentIndex + 1) % _images.length;
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _goToPrevious() {
    int prevPage = _currentIndex > 0 ? _currentIndex - 1 : _images.length - 1;
    _pageController.animateToPage(
      prevPage,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  void _goToNext() {
    int nextPage = (_currentIndex + 1) % _images.length;
    _pageController.animateToPage(
      nextPage,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final now = DateTime.now();

    return SingleChildScrollView(
      child: Column(
        children: [
          // 🔹 Carrusel de imágenes
          SizedBox(
            height: isMobile ? 220 : 400,
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
                      child: Image.asset(
                        _images[index],
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
                    );
                  },
                ),
                Positioned(
                  left: 10,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                    onPressed: _goToPrevious,
                  ),
                ),
                Positioned(
                  right: 10,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, color: Colors.white),
                    onPressed: _goToNext,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // 🔹 Indicadores del carrusel
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_images.length, (index) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _currentIndex == index ? 12 : 8,
                height: _currentIndex == index ? 12 : 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _currentIndex == index ? Colors.green : Colors.grey,
                ),
              );
            }),
          ),
          const SizedBox(height: 20),

          // 🔹 Título de la sección de productos
          const Text(
            'Ofertas (Próximos a vencer)',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          // 🔹 Productos próximos a vencer desde Firestore
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('products')
                .orderBy('expiryDate')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text('Error al cargar los productos.');
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final products = snapshot.data!.docs.where((doc) {
                final expiry = (doc['expiryDate'] as Timestamp?)?.toDate();
                if (expiry == null) return false;
                return expiry.isBefore(now.add(const Duration(days: 90)));
              }).toList();

              if (products.isEmpty) {
                return const Text('No hay productos próximos a vencer.');
              }

              int crossAxisCount = isMobile ? 2 : 4;

              return GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.75,
                ),
                itemCount: products.length.clamp(0, 8),
                itemBuilder: (context, index) {
                  final data = products[index].data() as Map<String, dynamic>;
                  final expiry = (data['expiryDate'] as Timestamp).toDate();
                  final price = (data['price'] ?? 0).toDouble();
                  final remaining = expiry.difference(now).inDays;

                  double discount = 0;
                  if (remaining <= 45) {
                    discount = 50;
                  } else if (remaining <= 60) {
                    discount = 25;
                  }

                  final discountedPrice =
                      (price * (1 - discount / 100)).toStringAsFixed(2);

                  return Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.medication,
                              size: 40, color: Colors.green),
                          const SizedBox(height: 6),
                          Text(
                            data['name'] ?? 'Producto',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Vence: ${expiry.day}/${expiry.month}/${expiry.year}',
                            style: const TextStyle(
                                color: Colors.red, fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          if (discount > 0)
                            Text(
                              'Descuento: $discount%',
                              style: const TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          const SizedBox(height: 4),
                          if (discount > 0)
                            Text(
                              '\$$discountedPrice',
                              style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          if (discount == 0)
                            Text(
                              '\$${price.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black54,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
