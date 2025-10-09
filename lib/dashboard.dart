// lib/dashboard.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'admin_create_user.dart';
// Si tienes un AdminUserManager (el widget que gestione usuarios avanzado), mantenlo en esta ruta.


class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String _role = '';
  String _name = '';
  bool _loading = true;

  // marca si el usuario navegó a alguna ruta desde el menú
  bool _navigatedFromMenu = false;

  // momento en que se cargó el perfil (para evitar alerta justo después del login)
  DateTime? _loadedAt;

  // índice de la página interna (0 = resumen)
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) Navigator.pushReplacementNamed(context, '/');
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data();
      setState(() {
        _role = (data?['role'] ?? '').toString();
        _name = data?['name'] ?? user.email ?? 'Usuario';
        _loading = false;
        _loadedAt = DateTime.now();
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _loadedAt = DateTime.now();
      });
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  // muestra confirmación y devuelve true si confirma cerrar sesión
  Future<bool> _confirmSignOutDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar cierre de sesión'),
        content: const Text('¿Estás seguro que deseas cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    return result == true;
  }

  // handler que usan todos los botones de "Cerrar sesión"
  Future<void> _onSignOutPressed() async {
    final confirmed = await _confirmSignOutDialog();
    if (confirmed) {
      await _signOut();
    }
  }

  String _roleNorm() => _role.toLowerCase();

  Widget _buildMenuTile({required IconData icon, required String title, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: kGreen1),
      title: Text(title),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      dense: true,
      visualDensity: const VisualDensity(vertical: -1),
    );
  }

  // CAMBIO: seleccionar páginas internas en lugar de pushNamed
  void _selectPage(int index) {
    setState(() {
      _selectedIndex = index;
      _navigatedFromMenu = true;
    });
  }

  void _openGestionUsuarios() => _selectPage(1);
  void _openGestionProductos() => _selectPage(2);
  void _openCompras() => _selectPage(3);
  void _openVentas() => _selectPage(4);
  void _openProveedores() => _selectPage(5);
  void _openInventario() => _selectPage(6);
  void _openGenerarFactura() => _selectPage(7);
  void _openRegistrarVenta() => _selectPage(8);

  // Menús por rol (Widgets)
  Widget _adminMenu() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Panel de Administrador', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _buildMenuTile(icon: Icons.manage_accounts, title: 'Gestionar usuarios', onTap: _openGestionUsuarios),
        _buildMenuTile(icon: Icons.production_quantity_limits, title: 'Gestionar productos', onTap: _openGestionProductos),
        _buildMenuTile(icon: Icons.shopping_cart_checkout, title: 'Compras', onTap: _openCompras),
        _buildMenuTile(icon: Icons.point_of_sale, title: 'Ventas', onTap: _openVentas),
        _buildMenuTile(icon: Icons.local_shipping, title: 'Proveedores', onTap: _openProveedores),
        _buildMenuTile(icon: Icons.inventory_2, title: 'Inventario', onTap: _openInventario),
      ],
    );
  }

  Widget _farmaceuticoMenu() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Panel Farmacéutico', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _buildMenuTile(icon: Icons.production_quantity_limits, title: 'Gestionar productos', onTap: _openGestionProductos),
        _buildMenuTile(icon: Icons.point_of_sale, title: 'Ventas / Facturación', onTap: _openGenerarFactura),
      ],
    );
  }

  Widget _vendedorMenu() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Panel Vendedor', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _buildMenuTile(icon: Icons.add_shopping_cart, title: 'Registrar venta', onTap: _openRegistrarVenta),
        _buildMenuTile(icon: Icons.receipt_long, title: 'Generar factura', onTap: _openGenerarFactura),
      ],
    );
  }

  Widget _menuForRole() {
    final role = _roleNorm();
    if (role == 'admin') return _adminMenu();
    if (role == 'farmaceutico' || role == 'farmacéutico') return _farmaceuticoMenu();
    if (role == 'vendedor') return _vendedorMenu();
    return const Text('Rol no definido o sin permisos.', style: TextStyle(color: Colors.red));
  }

  // Acciones del AppBar para pantallas grandes
  List<Widget> _actionsForRole() {
    final role = _roleNorm();
    final List<Widget> actions = [];

    if (role == 'admin') {
      actions.addAll([
        TextButton(onPressed: _openGestionUsuarios, child: const Text("Usuarios", style: TextStyle(color: Colors.white))),
        TextButton(onPressed: _openGestionProductos, child: const Text("Productos", style: TextStyle(color: Colors.white))),
        TextButton(onPressed: _openCompras, child: const Text("Compras", style: TextStyle(color: Colors.white))),
        TextButton(onPressed: _openVentas, child: const Text("Ventas", style: TextStyle(color: Colors.white))),
      ]);
    } else if (role == 'farmaceutico' || role == 'farmacéutico') {
      actions.addAll([
        TextButton(onPressed: _openGestionProductos, child: const Text("Productos", style: TextStyle(color: Colors.white))),
        TextButton(onPressed: _openGenerarFactura, child: const Text("Facturación", style: TextStyle(color: Colors.white))),
      ]);
    } else if (role == 'vendedor') {
      actions.add(TextButton(onPressed: _openRegistrarVenta, child: const Text("Registrar venta", style: TextStyle(color: Colors.white))));
    }

    // Botón cerrar sesión al final — usa el handler que muestra confirmación
    actions.add(IconButton(onPressed: _onSignOutPressed, icon: const Icon(Icons.logout, color: Colors.white)));

    return actions;
  }

  // Drawer (ítems) según rol
  Widget _buildDrawerContents() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        DrawerHeader(
          decoration: BoxDecoration(color: kGreen1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PharmaControl', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Bienvenido, $_name', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 4),
              Text('Rol: ${_role.isNotEmpty ? _role : '—'}', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: _menuForRole()),
        const SizedBox(height: 12),
        const Divider(),
        _buildMenuTile(icon: Icons.settings, title: 'Ajustes', onTap: () => _selectPage(0)),
        _buildMenuTile(icon: Icons.help_outline, title: 'Ayuda', onTap: () => _selectPage(0)),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: kGreen2,
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _onSignOutPressed,
            icon: const Icon(Icons.logout),
            label: const Text('Cerrar sesión', style: TextStyle(color: Colors.white)),
          ),
        ),
      ],
    );
  }

  // ---------- PÁGINAS INTERNAS (ahora se muestran dentro del mismo Card) ----------
  Widget _pageHomeCardContent() {
    // cuando estamos en resumen (selectedIndex==0) mostramos el menuForRole dentro del card
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Acciones disponibles para tu rol:'),
        const SizedBox(height: 8),
        _menuForRole(),
      ],
    );
  }

  Widget _pageUsuariosCardContent() {
    // Usa AdminUserManager si lo tienes; si no, fallback a placeholder list con iconos
    try {
      return const AdminUserManager();
    } catch (_) {
      // fallback: placeholder que lista usuarios con iconos
      return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return const Text('Error al cargar usuarios');
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty) return const Text('No hay usuarios registrados aún.');
          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, i) {
              final d = docs[i];
              final data = d.data() as Map<String, dynamic>;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: kGreen3,
                  child: const Icon(Icons.person, color: Colors.white),
                ),
                title: Text(data['name'] ?? '—'),
                subtitle: Text('${data['email'] ?? ''}\nRol: ${data['role'] ?? '—'}'),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'edit') {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Editar (implementa)')));
                    } else if (action == 'delete') {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Eliminar (implementa)')));
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit), title: Text('Editar'))),
                    PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete), title: Text('Eliminar'))),
                  ],
                ),
              );
            },
          );
        },
      );
    }
  }

  Widget _pageProductosCardContent() => Center(child: Text('Productos (rol: ${_roleNorm()})'));
  Widget _pageComprasCardContent() => Center(child: Text('Compras (rol: ${_roleNorm()})'));
  Widget _pageVentasCardContent() => Center(child: Text('Ventas (rol: ${_roleNorm()})'));
  Widget _pageProveedoresCardContent() => Center(child: Text('Proveedores (rol: ${_roleNorm()})'));
  Widget _pageInventarioCardContent() => Center(child: Text('Inventario (rol: ${_roleNorm()})'));
  Widget _pageFacturacionCardContent() => Center(child: Text('Facturación (rol: ${_roleNorm()})'));
  Widget _pageRegistrarVentaCardContent() => Center(child: Text('Registrar venta (rol: ${_roleNorm()})'));

  Widget _cardContentByIndex() {
    switch (_selectedIndex) {
      case 1:
        return _pageUsuariosCardContent();
      case 2:
        return _pageProductosCardContent();
      case 3:
        return _pageComprasCardContent();
      case 4:
        return _pageVentasCardContent();
      case 5:
        return _pageProveedoresCardContent();
      case 6:
        return _pageInventarioCardContent();
      case 7:
        return _pageFacturacionCardContent();
      case 8:
        return _pageRegistrarVentaCardContent();
      default:
        return _pageHomeCardContent();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final double screenHeight = MediaQuery.of(context).size.height;

    return WillPopScope(
      // bloqueamos siempre el "pop" para que la flecha atrás no haga nada en el dashboard
      onWillPop: () async {
        return false;
      },
      child: Scaffold(
        // Restauré automáticamente la hamburguesa: aparece solo en móvil.
        appBar: AppBar(
          backgroundColor: kGreen1,
          iconTheme: const IconThemeData(color: Colors.white),
          automaticallyImplyLeading: isMobile,
          title: isMobile
              ? const Text("PharmaControl", style: TextStyle(color: Colors.white))
              : const Text("PharmaControl", style: TextStyle(color: Colors.white, fontSize: 18)),
          actions: isMobile ? null : _actionsForRole(),
        ),
        drawer: isMobile ? Drawer(child: _buildDrawerContents()) : null,
        body: Container(
          constraints: BoxConstraints(minHeight: screenHeight),
          decoration: const BoxDecoration(gradient: kBackgroundGradient),
          padding: const EdgeInsets.all(16),
          child: SafeArea(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Título superior
                        Text('Bienvenido, $_name', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: kGreen1)),
                        const SizedBox(height: 8),
                        Text('Rol: ${_role.isNotEmpty ? _role : '—'}', style: const TextStyle(fontSize: 14)),
                        const SizedBox(height: 18),

                        // Aquí: Card principal que ahora muestra el contenido según _selectedIndex
                        Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 3,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header del Card con título (sin iconos innecesarios)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Resumen rápido', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kGreen1)),
                                    // simple Chip indicando la sección activa
                                    Chip(label: Text(_selectedIndex == 0 ? 'Resumen' : 'Ver: ${_selectedIndexLabel()}')),
                                  ],
                                ),

                                const SizedBox(height: 12),

                                // Aquí va el contenido real del Card: resumen o pantalla seleccionada
                                _cardContentByIndex(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  String _selectedIndexLabel() {
    switch (_selectedIndex) {
      case 1:
        return 'Usuarios';
      case 2:
        return 'Productos';
      case 3:
        return 'Compras';
      case 4:
        return 'Ventas';
      case 5:
        return 'Proveedores';
      case 6:
        return 'Inventario';
      case 7:
        return 'Facturación';
      case 8:
        return 'Registrar venta';
      default:
        return 'Resumen';
    }
  }
}
