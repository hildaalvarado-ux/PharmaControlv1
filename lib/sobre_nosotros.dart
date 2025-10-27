import 'package:flutter/material.dart';

class SobreNosotrosPage extends StatelessWidget {
  const SobreNosotrosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Título principal
          const Text(
            'Sobre Nosotros',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'PharmaControl es una aplicación diseñada para optimizar la gestión '
            'farmacéutica, facilitando el control de inventarios, egresos, movimientos y proveedores. '
            'Nuestro objetivo es ofrecer herramientas digitales eficientes que ayuden a las farmacias '
            'a mejorar la organización, reducir errores y brindar un mejor servicio al cliente.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, height: 1.6),
          ),
          const SizedBox(height: 24),

          // Misión
          const Text(
            'Misión',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green),
          ),
          const SizedBox(height: 8),
          const Text(
            'Brindar soluciones tecnológicas innovadoras para la gestión farmacéutica, '
            'promoviendo el uso eficiente de los recursos y contribuyendo al desarrollo '
            'de un sistema de salud más moderno y confiable.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, height: 1.5),
          ),
          const SizedBox(height: 24),

          // Visión
          const Text(
            'Visión',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green),
          ),
          const SizedBox(height: 8),
          const Text(
            'Ser reconocidos como una plataforma líder en gestión farmacéutica digital, '
            'destacada por su calidad, innovación y compromiso con la mejora continua '
            'del sector salud a través de la tecnología.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, height: 1.5),
          ),
          const SizedBox(height: 32),

          // Nuestro equipo
          const Text(
            'Nuestro Equipo',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 30,
            runSpacing: 20,
            alignment: WrapAlignment.center,
            children: const [
              _MiembroEquipo(
                nombre: 'Hilda Jazmin Alvarado Hernandez',
                rol: 'Desarrolladora Principal',
                imagenUrl: 'https://cdn-icons-png.flaticon.com/512/2922/2922566.png',
              ),
              _MiembroEquipo(
                nombre: 'Keyri Sarai Saravia Calles',
                rol: 'Diseñadora UI/UX',
                imagenUrl: 'https://cdn-icons-png.flaticon.com/512/2922/2922566.png',
              ),
              _MiembroEquipo(
                nombre: 'Jenifer Eunice Benitez Santos',
                rol: 'Analista de Datos',
                imagenUrl: 'https://cdn-icons-png.flaticon.com/512/2922/2922566.png',
              ),
              _MiembroEquipo(
                nombre: 'Jimmy Jesus Ayala Nuñez',
                rol: 'Gestor de Proyectos',
                imagenUrl: 'https://cdn-icons-png.flaticon.com/512/3135/3135715.png',
              ),
            ],
          ),

          const SizedBox(height: 40),

          // Logo de la universidad y descripción del proyecto (Asset)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            color: Colors.green.shade50,
            child: const Column(
              children: [
                Text(
                  'Universidad Luterana Salvadoreña',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 8),
                // Logo de la universidad como asset
                Image(
                  image: AssetImage('assets/logo_uls.png'),
                  width: 60,
                  height: 60,
                  fit: BoxFit.contain,
                ),
                SizedBox(height: 8),
                Text(
                  'Centro Regional de Cabañas',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Redes Sociales
          const Text(
            'Contactos',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 20,
            children: const [
              _IconoRedSocial(
                url: 'https://cdn-icons-png.flaticon.com/512/733/733547.png',
                nombre: 'Facebook',
              ),
              _IconoRedSocial(
                url: 'https://cdn-icons-png.flaticon.com/512/1384/1384063.png',
                nombre: 'Instagram',
              ),
              _IconoRedSocial(
                url: 'https://cdn-icons-png.flaticon.com/512/145/145807.png',
                nombre: 'LinkedIn',
              ),
            ],
          ),

          const SizedBox(height: 30),

          // Derechos reservados
          const Divider(thickness: 1),
          const SizedBox(height: 8),
          const Text(
            '© 2025 PharmaControl - Todos los derechos reservados',
            style: TextStyle(color: Colors.grey, fontSize: 13),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// Widget para mostrar cada miembro del equipo
class _MiembroEquipo extends StatelessWidget {
  final String nombre;
  final String rol;
  final String imagenUrl;

  const _MiembroEquipo({
    required this.nombre,
    required this.rol,
    required this.imagenUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 45,
          backgroundImage: NetworkImage(imagenUrl),
          backgroundColor: Colors.green.shade50,
        ),
        const SizedBox(height: 8),
        Text(
          nombre,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          textAlign: TextAlign.center,
        ),
        Text(
          rol,
          style: const TextStyle(fontSize: 14, color: Colors.grey),
        ),
      ],
    );
  }
}

// Widget para mostrar los íconos de redes sociales
class _IconoRedSocial extends StatelessWidget {
  final String url;
  final String nombre;

  const _IconoRedSocial({
    required this.url,
    required this.nombre,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.network(
          url,
          width: 45,
          height: 45,
        ),
        const SizedBox(height: 4),
        Text(
          nombre,
          style: const TextStyle(fontSize: 13),
        ),
      ],
    );
  }
}
