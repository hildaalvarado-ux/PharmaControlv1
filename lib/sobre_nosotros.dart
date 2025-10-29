import 'package:flutter/material.dart';

class SobreNosotrosPage extends StatelessWidget {
  const SobreNosotrosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          
          _CardSeccion(
            titulo: 'Sobre Nosotros',
            contenido:
                'PharmaControl es una aplicación diseñada para optimizar la gestión farmacéutica, '
                'facilitando el control de inventarios, egresos, movimientos y proveedores. '
                'Nuestro objetivo es ofrecer herramientas digitales eficientes que ayuden a las farmacias '
                'a mejorar la organización, reducir errores y brindar un mejor servicio al cliente.',
          ),

          const SizedBox(height: 16),

          
          _CardSeccion(
            titulo: 'Misión',
            contenido:
                'Brindar soluciones tecnológicas innovadoras para la gestión farmacéutica, '
                'promoviendo el uso eficiente de los recursos y contribuyendo al desarrollo '
                'de un sistema de salud más moderno y confiable.',
          ),

          const SizedBox(height: 16),

          
          _CardSeccion(
            titulo: 'Visión',
            contenido:
                'Ser reconocidos como una plataforma líder en gestión farmacéutica digital, '
                'destacada por su calidad, innovación y compromiso con la mejora continua '
                'del sector salud a través de la tecnología.',
          ),

          const SizedBox(height: 16),

          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center, 
                children: [
                  const Text(
                    'Responsables',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  
                  const _MiembroEquipo(
                    nombre: 'Hilda Jazmin Alvarado Hernandez',
                    rol: 'Desarrolladora Principal',
                    imagenUrl: 'https://cdn-icons-png.flaticon.com/128/6833/6833591.png',
                  ),
                  const SizedBox(height: 20),
                  const _MiembroEquipo(
                    nombre: 'Keyri Sarai Saravia Calles',
                    rol: 'Diseñadora UI/UX',
                    imagenUrl: 'https://cdn-icons-png.flaticon.com/128/6833/6833591.png',
                  ),
                  const SizedBox(height: 20),
                  const _MiembroEquipo(
                    nombre: 'Jenifer Eunice Benitez Santos',
                    rol: 'Analista de Datos',
                    imagenUrl: 'https://cdn-icons-png.flaticon.com/128/6833/6833591.png',
                  ),
                  const SizedBox(height: 20),
                  const _MiembroEquipo(
                    nombre: 'Jimmy Jesus Ayala Nuñez',
                    rol: 'Gestor de Proyectos',
                    imagenUrl: 'https://cdn-icons-png.flaticon.com/512/3135/3135715.png',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text(
                    'Contactos',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 20,
                    children: const [
                      _IconoRedSocial(
                        url: 'https://cdn-icons-png.flaticon.com/128/5968/5968764.png',
                        nombre: 'Facebook',
                      ),
                      _IconoRedSocial(
                        url: 'https://cdn-icons-png.flaticon.com/128/888/888846.png',
                        nombre: 'Chrome',
                      ),
                      _IconoRedSocial(
                        url: 'https://cdn-icons-png.flaticon.com/128/3870/3870799.png',
                        nombre: 'Telefono',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 2,
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: const [
                  Text(
                    'Universidad Luterana Salvadoreña',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Centro Regional de Cabañas',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          
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


class _CardSeccion extends StatelessWidget {
  final String titulo;
  final String contenido;

  const _CardSeccion({required this.titulo, required this.contenido});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center, 
          children: [
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              contenido,
              style: const TextStyle(fontSize: 16, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

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
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

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
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
