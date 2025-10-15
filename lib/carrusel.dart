import 'package:flutter/material.dart';

class CarouselWidget extends StatefulWidget {
  final List<String> images;
  const CarouselWidget({super.key, required this.images});

  @override
  State<CarouselWidget> createState() => _CarouselWidgetState();
}

class _CarouselWidgetState extends State<CarouselWidget> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 390, // ajusta la altura según tu diseño
          child: PageView.builder(
            itemCount: widget.images.length,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  widget.images[index],
                  fit: BoxFit.cover,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.images.length, (index) {
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
      ],
    );
  }
}
