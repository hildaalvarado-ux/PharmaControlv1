import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'user_manual.dart';

class PreguntasFrecuentesPage extends StatelessWidget {
  final String role; // admin, vendedor, farmaceutico

  const PreguntasFrecuentesPage({
    super.key,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {

    final String roleNorm = role.toLowerCase();
    String preguntaRol;
    String respuestaRol;
    IconData roleIcon;

    switch (roleNorm) {
      case 'admin':
        preguntaRol = '¿Qué hace el rol de Administrador en el sistema?';
        respuestaRol =
            'El rol Administrador tiene acceso completo al sistema PharmaControl. '
            'Puede gestionar usuarios, productos, inventario, proveedores, movimientos '
            '(ingresos y egresos) y las ofertas o promociones. Es responsable de la '
            'configuración general y del control de la información.';
        roleIcon = Icons.admin_panel_settings;
        break;

      case 'vendedor':
        preguntaRol = '¿Qué hace el rol de Vendedor en el sistema?';
        respuestaRol =
            'El rol Vendedor se encarga principalmente de atender al cliente y registrar las ventas. '
            'Puede consultar las ofertas vigentes, buscar productos disponibles y generar comprobantes '
            'de venta desde la pantalla “Registrar venta”. Pero debe asegurarse de que las ventas se registren correctamente.';
        roleIcon = Icons.point_of_sale;
        break;

      case 'farmaceutico':
      case 'farmacéutico':
        preguntaRol = '¿Qué hace el rol de Farmacéutico en el sistema?';
        respuestaRol =
            'El rol Farmacéutico tiene un enfoque técnico sobre los medicamentos y el inventario. '
            'Puede consultar y gestionar productos, revisar existencias y lotes, controlar fechas de vencimiento '
            'y registrar ventas (egresos) cuando dispensa medicamentos. Pero debe garantizar que la información de los productos y las ventas '
            'sea correcta.';
        roleIcon = Icons.science_outlined;
        break;

      default:
        preguntaRol = '¿Qué puedo hacer con mi rol dentro del sistema?';
        respuestaRol =
            'En esta sección encontrarás una breve descripción de tus responsabilidades '
            'dentro del sistema y acceso al manual de usuario correspondiente a tu rol.';
        roleIcon = Icons.help_outline;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Título
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

          
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preguntaRol,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    respuestaRol,
                    style: const TextStyle(fontSize: 14),
                    textAlign: TextAlign.justify,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          
          Center(
            child: Icon(
              roleIcon,
              color: kGreen1,
              size: 48,
            ),
          ),

          const SizedBox(height: 30),

          
          Center(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: kGreen1,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => UserManualPage(role: role),
                  ),
                );
              },
              icon: const Icon(Icons.menu_book, color: Colors.white),
              label: const Text(
                'Manual de usuario',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
