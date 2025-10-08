// lib/app_theme.dart
import 'package:flutter/material.dart';

/// Paleta de verdes usada por la app
const Color kGreen1 = Color(0xFF1A7F11);
const Color kGreen2 = Color(0xFF4B9F3E);
const Color kGreen3 = Color(0xFF7DBF6B);
const Color kGreen4 = Color(0xFFAEDF98);
const Color kGreen5 = Color(0xFFE0FFC5);

/// Fondo degradado global
const LinearGradient kBackgroundGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [kGreen5, kGreen4, kGreen3],
);

/// Otros helpers de estilo si los necesitas
final BorderRadius kCardRadius = BorderRadius.circular(12);
