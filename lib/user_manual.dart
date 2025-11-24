import 'package:flutter/material.dart';
import 'app_theme.dart';

class UserManualPage extends StatelessWidget {
  final String role; // admin, vendedor, farmaceutico

  const UserManualPage({
    super.key,
    required this.role,
  });

  String getRoleTitle() {
    switch (role) {
      case 'admin':
        return 'Administrador';
      case 'vendedor':
        return 'Vendedor';
      case 'farmaceutico':
      case 'farmacéutico':
        return 'Farmacéutico';
      default:
        return role;
    }
  }

  @override
  Widget build(BuildContext context) {
    final manualData = _getManualDataByRole(role.toLowerCase());

    return Scaffold(
      appBar: AppBar(
        title: Text('Manual de usuario - ${getRoleTitle()}'),
        backgroundColor: kGreen1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...(manualData['secciones'] as List<Map<String, dynamic>>).map(
              (seccion) => Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ExpansionTile(
                  leading: const Icon(Icons.view_compact, color: kGreen1),
                  title: Text(
                    seccion['titulo'] as String,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      seccion['descripcion'] as String,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  children: [
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children:
                            (seccion['faqs'] as List<Map<String, String>>)
                                .map(
                                  (faq) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 6),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          faq['pregunta']!,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          faq['respuesta']!,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =================== CONTENIDO POR ROL ===================
  Map<String, dynamic> _getManualDataByRole(String role) {
    // ---------- ADMIN ----------
    if (role == 'admin') {
      return {
        'secciones': [
          {
            'titulo': 'Módulo Ofertas (Próximos a vencer)',
            'descripcion':
                'Permite administrar promociones de productos próximos a vencer.',
            'faqs': [
              {
                'pregunta': '¿Qué información veo en las ofertas?',
                'respuesta':
                    'Nombre del producto, vencimiento, porcentaje de descuento, precio reducido y stock disponible.'
              },
              {
                'pregunta': '¿Cómo crear una nueva oferta?',
                'respuesta':
                    'Usa el botón verde con el ícono "+", selecciona un producto, aplica el descuento y guarda.'
              },
              {
                'pregunta': '¿Cómo editar o eliminar una oferta?',
                'respuesta':
                    'En la tarjeta de la oferta, usa los íconos de lápiz o papelera.'
              },
            ],
          },
          {
            'titulo': 'Módulo Usuarios',
            'descripcion':
                'Gestión completa de las cuentas del sistema.',
            'faqs': [
              {
                'pregunta': '¿Qué puedo hacer en este módulo?',
                'respuesta':
                    'Crear, editar y eliminar usuarios; asignar roles y restablecer información.'
              },
              {
                'pregunta': '¿Cómo crear un usuario?',
                'respuesta':
                    'Presiona “Nuevo usuario”, completa los campos y selecciona el rol.'
              },
            ],
          },
          {
            'titulo': 'Módulo Productos',
            'descripcion':
                'Control total del catálogo de productos.',
            'faqs': [
              {
                'pregunta': '¿Qué se muestra en la tabla?',
                'respuesta':
                    'Precio, IVA, receta, stock, concentración, presentación, proveedor y lotes.'
              },
              {
                'pregunta': '¿Cómo agregar un producto?',
                'respuesta':
                    'Usa el botón “Nuevo producto” y completa los datos requeridos.'
              },
            ],
          },
          {
            'titulo': 'Movimientos (Ingresos y Egresos)',
            'descripcion':
                'Control del inventario entrante y saliente.',
            'faqs': [
              {
                'pregunta': '¿Cómo filtrar movimientos?',
                'respuesta':
                    'Por tipo (Ingreso/Egreso) o por rango de fechas.'
              },
              {
                'pregunta': '¿Cómo registrar ingresos o egresos?',
                'respuesta':
                    'Usa los botones “Nuevo ingreso” o “Nuevo egreso”.'
              },
            ],
          },
          {
            'titulo': 'Proveedores',
            'descripcion':
                'Gestión de proveedores de productos.',
            'faqs': [
              {
                'pregunta': '¿Qué puedo hacer aquí?',
                'respuesta':
                    'Crear, editar y eliminar proveedores.'
              },
            ],
          },
          {
            'titulo': 'Otras opciones',
            'descripcion':
                'Acceso a información general y utilidades.',
            'faqs': [
              {
                'pregunta': '¿Qué hay en “Sobre nosotros”?',
                'respuesta':
                    'Información general del sistema/misión/visión.'
              },
              {
                'pregunta': '¿Cómo cerrar sesión?',
                'respuesta':
                    'Usa el botón de la esquina superior derecha.'
              },
            ],
          },
        ],
      };
    }

    // ---------- VENDEDOR ----------
    if (role == 'vendedor') {
      return {
        'secciones': [
          {
            'titulo': 'Módulo Ofertas (Próximos a vencer)',
            'descripcion':
                'El vendedor puede consultar promociones vigentes.',
            'faqs': [
              {
                'pregunta': '¿Qué puede hacer el vendedor aquí?',
                'respuesta':
                    'Consultar productos en descuento, revisar precios rebajados y verificar disponibilidad.'
              },
              {
                'pregunta': '¿Puede crear o editar ofertas?',
                'respuesta':
                    'No. Solo el administrador puede modificarlas.'
              },
            ],
          },
          {
            'titulo': 'Registrar venta (Egreso)',
            'descripcion':
                'Pantalla principal del vendedor para realizar ventas.',
            'faqs': [
              {
                'pregunta': '¿Qué tipo de movimiento genera una venta?',
                'respuesta':
                    'Toda venta genera un Egreso, lo que reduce el inventario.'
              },
              {
                'pregunta': '¿Cómo agregar productos a la venta?',
                'respuesta':
                    'Buscando por nombre/SKU, seleccionando el producto y definiendo la cantidad.'
              },
              {
                'pregunta': '¿Qué información se muestra en la venta?',
                'respuesta':
                    'Subtotal sin IVA, IVA total, precio final, lista de productos y cantidades.'
              },
              {
                'pregunta': '¿Cómo finalizar una venta?',
                'respuesta':
                    'Presiona “Registrar venta” para guardar el egreso y actualizar el stock.'
              },
            ],
          },
          {
            'titulo': 'Otras opciones de menú',
            'descripcion':
                'Secciones informativas adicionales.',
            'faqs': [
              {
                'pregunta': '¿Qué hay en “Sobre nosotros”?',
                'respuesta':
                    'Información general de la farmacia o del sistema.'
              },
              {
                'pregunta': '¿Para qué sirve “Preguntas frecuentes”?',
                'respuesta':
                    'Para consultar dudas rápidas y acceder a este manual.'
              },
              {
                'pregunta': '¿Cómo cerrar sesión?',
                'respuesta':
                    'Usando el botón de salida en la barra superior.'
              },
            ],
          },
        ],
      };
    }

    // ---------- FARMACÉUTICO ----------
    if (role == 'farmaceutico' || role == 'farmacéutico') {
      return {
        'secciones': [
          {
            'titulo': 'Módulo Ofertas (Próximos a vencer)',
            'descripcion':
                'Similar al administrador, pero centrado en el control técnico de productos próximos a vencer.',
            'faqs': [
              {
                'pregunta':
                    '¿Qué revisa el farmacéutico en las ofertas?',
                'respuesta':
                    'Que los productos en promoción estén próximos a vencer, que el stock sea suficiente y que la venta sea segura para el paciente.'
              },
            ],
          },
          {
            'titulo': 'Módulo Productos',
            'descripcion':
                'Prácticamente el mismo módulo que ve el administrador, pero sin gestión de usuarios ni proveedores.',
            'faqs': [
              {
                'pregunta':
                    '¿Qué información de productos puede consultar o actualizar?',
                'respuesta':
                    'Nombre, forma/vía, concentración, presentación, receta, IVA, stock y lotes, según las políticas de la farmacia.'
              },
              {
                'pregunta': '¿Por qué es importante este módulo para el farmacéutico?',
                'respuesta':
                    'Porque garantiza que la información técnica del medicamento esté correcta antes de dispensarlo.'
              },
            ],
          },
          {
            'titulo': 'Inventario y control de existencias',
            'descripcion':
                'Vista muy similar a la del administrador para revisar stock y vencimientos.',
            'faqs': [
              {
                'pregunta':
                    '¿Qué tareas realiza el farmacéutico en inventario?',
                'respuesta':
                    'Revisar cantidades disponibles, identificar productos agotados o próximos a vencer y verificar que el stock físico coincida con el del sistema.'
              },
            ],
          },
          {
            'titulo': 'Registrar venta (Egreso)',
            'descripcion':
                'Al igual que el vendedor, el farmacéutico puede registrar ventas que generan egresos de inventario.',
            'faqs': [
              {
                'pregunta':
                    '¿Qué debe verificar antes de registrar una venta?',
                'respuesta':
                    'Que la indicación sea adecuada, que exista receta válida cuando aplique y que se respeten las cantidades permitidas.'
              },
              {
                'pregunta':
                    '¿Qué ocurre en el sistema al registrar una venta?',
                'respuesta':
                    'Se genera un Egreso que descuenta el stock del producto vendido y queda registrado en el historial de movimientos.'
              },
            ],
          },
          {
            'titulo': 'Otras opciones de menú',
            'descripcion':
                'Acceso a secciones informativas, igual que el administrador.',
            'faqs': [
              {
                'pregunta': '¿Qué puede ver en “Sobre nosotros”?',
                'respuesta':
                    'Información general del sistema, misión, visión y datos de contacto.'
              },
              {
                'pregunta':
                    '¿Cómo le ayuda “Preguntas frecuentes” y este manual?',
                'respuesta':
                    'Sirven como guía rápida para recordar procesos y límites de su rol dentro del sistema.'
              },
              {
                'pregunta': '¿Cómo cerrar sesión correctamente?',
                'respuesta':
                    'Desde el icono de salida en la barra superior cuando termine su turno, para proteger la información.'
              },
            ],
          },
        ],
      };
    }

    return {
      'secciones': [
        {
          'titulo': 'Manual no disponible',
          'descripcion':
              'Todavía no se ha configurado contenido específico para este rol.',
          'faqs': [
            {
              'pregunta': '¿Por qué no veo información completa?',
              'respuesta':
                  'El administrador aún no ha configurado el manual para este rol.'
            },
          ],
        },
      ],
    };
  }
}
