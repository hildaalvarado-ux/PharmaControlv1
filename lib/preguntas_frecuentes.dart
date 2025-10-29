import 'package:flutter/material.dart';
import 'app_theme.dart';

class PreguntasFrecuentesPage extends StatelessWidget {
  const PreguntasFrecuentesPage({super.key});

  @override
  Widget build(BuildContext context) {
    
    final List<Map<String, dynamic>> faqList = [
      {
        'pregunta': '¿Cómo crear un usuario?',
        'respuesta': 'Ve al panel de usuarios, presiona "Agregar" y completa el formulario.',
        'icono': Icons.person_add_alt_1,
      },
      {
        'pregunta': '¿Cómo registrar un egreso?',
        'respuesta': 'Ingresa a "Registrar Egreso", completa los datos del producto y confirma la operación.',
        'icono': Icons.receipt_long,
      },
      {
        'pregunta': '¿Cómo agregar un proveedor?',
        'respuesta': 'Dirígete a "Proveedores" y presiona "Agregar proveedor".',
        'icono': Icons.local_shipping,
      },
      {
        'pregunta': '¿Puedo modificar un producto?',
        'respuesta': 'Sí, en "Gestionar productos" selecciona el producto y presiona "Editar".',
        'icono': Icons.edit_note,
      },
      {
        'pregunta': '¿Cómo buscar un producto en el inventario?',
        'respuesta': 'Usa la barra de búsqueda en "Inventario" y escribe el nombre o código del producto.',
        'icono': Icons.search,
      },
      {
        'pregunta': '¿Cómo cambiar mi contraseña?',
        'respuesta': 'Ve a tu perfil de usuario, selecciona "Cambiar contraseña" y sigue los pasos.',
        'icono': Icons.lock_reset,
      },
      {
        'pregunta': '¿Puedo generar reportes de ventas?',
        'respuesta': 'Sí, en la sección "Movimientos" puedes filtrar por fechas y exportar los reportes.',
        'icono': Icons.bar_chart,
      },
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kGreen1.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Preguntas Frecuentes',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: kGreen1,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),

          
          ...faqList.map(
            (faq) => Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ExpansionTile(
                leading: Icon(faq['icono'], color: kGreen1), 
                title: Text(
                  faq['pregunta']!,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Text(
                      faq['respuesta']!,
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
