import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'admin_create_user.dart';
import 'productos.dart';
import 'movements_manager.dart';
import 'egreso_form.dart';
import 'carrusel.dart';
import 'proveedores.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String _role = '';
  String _name = '';
  bool _loading = true;
  DateTime? _loadedAt;
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

  Future<bool> _confirmSignOutDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar cierre de sesión'),
        content: const Text('¿Estás seguro que deseas cerrar sesión?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Cerrar sesión')),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _onSignOutPressed() async {
    final confirmed = await _confirmSignOutDialog();
    if (confirmed) await _signOut();
  }

  String _roleNorm() => _role.toLowerCase();

  Widget _buildMenuTile({required IconData icon, required String title, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: kGreen1),
      title: Text(title),
      onTap: () {
        Navigator.of(context).pop(); // cerrar menú móvil
        if (onTap != null) onTap();
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      dense: true,
      visualDensity: const VisualDensity(vertical: -1),
    );
  }

  void _selectPage(int index) {
    if (!mounted) return;
    setState(() {
      _selectedIndex = index;
    });
  }

  void _openUsuarios() => _selectPage(1);
  void _openProductos() => _selectPage(2);
  void _openMovimientos() => _selectPage(3);
  void _openEgresos() => _selectPage(5);
  void _openInventario() => _selectPage(4);
  void _openProveedores() => _selectPage(6);

  Widget _adminMenu() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Panel de Administrador', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _buildMenuTile(icon: Icons.manage_accounts, title: 'Gestionar usuarios', onTap: _openUsuarios),
        _buildMenuTile(icon: Icons.production_quantity_limits, title: 'Gestionar productos', onTap: _openProductos),
        _buildMenuTile(icon: Icons.swap_vert, title: 'Movimientos', onTap: _openMovimientos),
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
        _buildMenuTile(icon: Icons.production_quantity_limits, title: 'Gestionar productos', onTap: _openProductos),
        _buildMenuTile(icon: Icons.remove_shopping_cart, title: 'Registrar Egreso (Factura)', onTap: _openEgresos),
      ],
    );
  }

  Widget _vendedorMenu() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Panel Vendedor', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _buildMenuTile(icon: Icons.remove_shopping_cart, title: 'Registrar Egreso (Factura)', onTap: _openEgresos),
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

  List<Widget> _actionsForRole() {
    final role = _roleNorm();
    final List<Widget> actions = [];

    if (role == 'admin') {
      actions.addAll([
        TextButton(onPressed: _openUsuarios, child: const Text("Usuarios", style: TextStyle(color: Colors.white))),
        TextButton(onPressed: _openProductos, child: const Text("Productos", style: TextStyle(color: Colors.white))),
        TextButton(onPressed: _openMovimientos, child: const Text("Movimientos", style: TextStyle(color: Colors.white))),
        TextButton(onPressed: _openInventario, child: const Text("Inventario", style: TextStyle(color: Colors.white))),
        TextButton(onPressed: _openProveedores, child: const Text("Proveedores", style: TextStyle(color: Colors.white))),
      ]);
    } else if (role == 'farmaceutico' || role == 'farmacéutico') {
      actions.addAll([
        TextButton(onPressed: _openProductos, child: const Text("Productos", style: TextStyle(color: Colors.white))),
        TextButton(onPressed: _openEgresos, child: const Text("Registrar Egreso", style: TextStyle(color: Colors.white))),
      ]);
    } else if (role == 'vendedor') {
      actions.add(TextButton(onPressed: _openEgresos, child: const Text("Registrar Egreso", style: TextStyle(color: Colors.white))));
    }

    actions.add(TextButton(onPressed: () => _selectPage(0), child: const Text("Sobre nosotros", style: TextStyle(color: Colors.white))));
    actions.add(IconButton(onPressed: _onSignOutPressed, icon: const Icon(Icons.logout, color: Colors.white)));
    return actions;
  }

  Widget _buildDrawerContents(bool isMobile) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        DrawerHeader(
          decoration: BoxDecoration(color: kGreen1),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('PharmaControl',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: Image.asset(
                  'assets/logo.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.inventory_2, color: Colors.white, size: 36),
                ),
              ),
              const SizedBox(height: 8),
              Text('Bienvenido, $_name', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 4),
              Text('Rol: ${_role.isNotEmpty ? _role : '—'}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: _menuForRole()),
        const SizedBox(height: 12),
        const Divider(),
        _buildMenuTile(icon: Icons.help_outline, title: 'Sobre nosotros', onTap: () => _selectPage(0)),
        if (_roleNorm() == 'admin')
          _buildMenuTile(icon: Icons.local_shipping, title: 'Proveedores', onTap: _openProveedores),
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

  Widget _pageHomeCardContent() => HomeCarousel();
  Widget _pageUsuariosCardContent() => const AdminUserManager();
  Widget _pageProductosCardContent() => const AdminProductManager();
  Widget _pageMovimientosCardContent() => const MovementsManager();
  Widget _pageInventarioCardContent() => Center(child: Text('Inventario (rol: ${_roleNorm()})'));

  Widget _pageEgresosCardContent() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: SingleChildScrollView(child: EgresoFormWidget(userRole: _roleNorm())),
    );
  }

  Widget _cardContentByIndex() {
    switch (_selectedIndex) {
      case 1:
        return _pageUsuariosCardContent();
      case 2:
        return _pageProductosCardContent();
      case 3:
        return _pageMovimientosCardContent();
      case 4:
        return _pageInventarioCardContent();
      case 5:
        return _pageEgresosCardContent();
      case 6:
        return ProvidersManager();
      default:
        return _pageHomeCardContent();
    }
  }

  Widget _buildAppBarTitle(bool isMobile) {
    if (isMobile) {
      return const Text("PharmaControl", style: TextStyle(color: Colors.white));
    } else {
      return Row(
        children: [
          SizedBox(
            height: 34,
            child: Image.asset(
              'assets/logo.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.inventory_2, color: Colors.white, size: 28),
            ),
          ),
          const SizedBox(width: 8),
          const Text("PharmaControl", style: TextStyle(color: Colors.white)),
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final double screenHeight = MediaQuery.of(context).size.height;

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: kGreen1,
          iconTheme: const IconThemeData(color: Colors.white),
          automaticallyImplyLeading: isMobile,
          title: _buildAppBarTitle(isMobile),
          actions: isMobile ? [] : _actionsForRole(),
        ),
        drawer: isMobile ? Drawer(child: _buildDrawerContents(isMobile)) : null,
        body: Container(
          constraints: BoxConstraints(minHeight: screenHeight),
          decoration: const BoxDecoration(gradient: kBackgroundGradient),
          padding: const EdgeInsets.all(16),
          child: SafeArea(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment:
                          isMobile ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                      children: [
                        if (!isMobile)
                          Row(
                            children: [
                              SizedBox(
                                height: 34,
                                child: Image.asset(
                                  'assets/logo.png',
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.inventory_2, color: Colors.green, size: 28),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Bienvenido, $_name',
                                      style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: kGreen1)),
                                  const SizedBox(height: 4),
                                  Text('Rol: ${_role.isNotEmpty ? _role : '—'}',
                                      style: const TextStyle(fontSize: 14)),
                                ],
                              ),
                            ],
                          )
                        else ...[
                          Text('Bienvenido, $_name',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.bold, color: kGreen1)),
                          const SizedBox(height: 4),
                          Text('Rol: ${_role.isNotEmpty ? _role : '—'}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 14)),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 40,
                            child: Image.asset(
                              'assets/logo.png',
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.inventory_2, color: Colors.green, size: 32),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Card(
                          shape:
                              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 3,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: _cardContentByIndex(),
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
}
