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
import 'sobre_nosotros.dart';
import 'preguntas_frecuentes.dart';

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
  int _selectedIndex = 0; // 0 = Ofertas (HomeCarousel) por defecto

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
        _selectedIndex = 0; // aseguramos Ofertas como primera vista
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

  void _selectPage(int index) {
    if (!mounted) return;
    setState(() => _selectedIndex = index);
  }

  // ---- Navegación rápida
  void _openOfertas() => _selectPage(0);
  void _openUsuarios() => _selectPage(1);
  void _openProductos() => _selectPage(2);
  void _openMovimientos() => _selectPage(3);
  void _openInventario() => _selectPage(4);
  void _openEgresos() => _selectPage(5);
  void _openProveedores() => _selectPage(6);
  void _openSobreNosotros() => _selectPage(7);
  void _openPreguntasFrecuentes() => _selectPage(8);

  // ---- Menú Drawer
  Widget _buildMenuTile({required IconData icon, required String title, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: kGreen1),
      title: Text(title),
      onTap: () {
        Navigator.of(context).pop();
        if (onTap != null) onTap();
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      dense: true,
      visualDensity: const VisualDensity(vertical: -1),
    );
  }

  Widget _adminMenu() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Panel de Administrador', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _buildMenuTile(icon: Icons.local_offer, title: 'Ofertas', onTap: _openOfertas),
        _buildMenuTile(icon: Icons.manage_accounts, title: 'Gestionar usuarios', onTap: _openUsuarios),
        _buildMenuTile(icon: Icons.production_quantity_limits, title: 'Gestionar productos', onTap: _openProductos),
        _buildMenuTile(icon: Icons.swap_vert, title: 'Movimientos', onTap: _openMovimientos),
        _buildMenuTile(icon: Icons.inventory_2, title: 'Inventario', onTap: _openInventario),
        _buildMenuTile(icon: Icons.local_shipping, title: 'Proveedores', onTap: _openProveedores),
      ],
    );
  }

  Widget _farmaceuticoMenu() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Panel Farmacéutico', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _buildMenuTile(icon: Icons.local_offer, title: 'Ofertas', onTap: _openOfertas),
        _buildMenuTile(icon: Icons.production_quantity_limits, title: 'Gestionar productos', onTap: _openProductos),
        // Inventario también visible para farmacéutico
        _buildMenuTile(icon: Icons.inventory_2, title: 'Inventario', onTap: _openInventario),
        _buildMenuTile(icon: Icons.remove_shopping_cart, title: 'Registrar venta (Factura)', onTap: _openEgresos),
      ],
    );
  }

  Widget _vendedorMenu() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Panel Vendedor', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _buildMenuTile(icon: Icons.local_offer, title: 'Ofertas', onTap: _openOfertas),
        _buildMenuTile(icon: Icons.remove_shopping_cart, title: 'Registrar venta (Factura)', onTap: _openEgresos),
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

  // ---- Acciones AppBar (escritorio)
  List<Widget> _actionsForRole() {
    final role = _roleNorm();
    final List<Widget> actions = [];

    actions.add(
      TextButton(
        onPressed: _openOfertas,
        child: const Text("Ofertas", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );

    if (role == 'admin') {
      actions.addAll([
        TextButton(onPressed: _openUsuarios, child: const Text("Usuarios", style: TextStyle(color: Colors.white))),
        TextButton(onPressed: _openProductos, child: const Text("Productos", style: TextStyle(color: Colors.white))),
        TextButton(onPressed: _openMovimientos, child: const Text("Movimientos", style: TextStyle(color: Colors.white))),
        TextButton(onPressed: _openInventario, child: const Text("Inventario", style: TextStyle(color: Colors.white))),
        TextButton(onPressed: _openProveedores, child: const Text("Proveedores", style: TextStyle(color: Colors.white))),
      ]);
    } else if (role == 'farmaceutico' || role == 'farmacéutico') {
      // Farmacéutico también ve Inventario y Registrar venta en la AppBar
      actions.addAll([
        TextButton(onPressed: _openProductos, child: const Text("Productos", style: TextStyle(color: Colors.white))),
        TextButton(onPressed: _openInventario, child: const Text("Inventario", style: TextStyle(color: Colors.white))),
        TextButton(onPressed: _openEgresos, child: const Text("Registrar venta", style: TextStyle(color: Colors.white))),
      ]);
    } else if (role == 'vendedor') {
      actions.add(TextButton(onPressed: _openEgresos, child: const Text("Registrar venta", style: TextStyle(color: Colors.white))));
    }

    actions.add(TextButton(onPressed: _openSobreNosotros, child: const Text("Sobre nosotros", style: TextStyle(color: Colors.white))));
    actions.add(TextButton(onPressed: _openPreguntasFrecuentes, child: const Text("Preguntas frecuentes", style: TextStyle(color: Colors.white))));
    actions.add(IconButton(onPressed: _onSignOutPressed, icon: const Icon(Icons.logout, color: Colors.white)));
    
    return actions;
  }

  // ---- Páginas
  Widget _pageOfertas() => const HomeCarousel();
  Widget _pageUsuarios() => const AdminUserManager();
  Widget _pageProductos() => const AdminProductManager();
  Widget _pageMovimientos() => const MovementsManager();
  // Reutiliza el gestor de productos para Inventario
  Widget _pageInventario() => const AdminProductManager();
  Widget _pageEgresos() => EgresoFormWidget();

  Widget _cardContentByIndex() {
    switch (_selectedIndex) {
      case 0:
        return _pageOfertas();
      case 1:
        return _pageUsuarios();
      case 2:
        return _pageProductos();
      case 3:
        return _pageMovimientos();
      case 4:
        return _pageInventario();
      case 5:
        return _pageEgresos();
      case 6:
        return ProvidersManager();
      case 7:
        return const SobreNosotrosPage();
      case 8:
        return const PreguntasFrecuentesPage();
      default:
        return _pageOfertas();
    }
  }

  // ---- AppBar title: SOLO texto
  Widget _buildAppBarTitle(bool isMobile) {
    return const Text("PharmaControl", style: TextStyle(color: Colors.white));
  }

  // ---- Encabezado responsive
  Widget _headerResponsive(bool isMobile) {
    final logo = Container(
      height: isMobile ? 48 : 72,
      width: isMobile ? 48 : 72,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Image.asset(
        'assets/logo.png',
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.inventory_2, color: Colors.green),
      ),
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: kGreen1.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('Bienvenido, $_name',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: kGreen1)),
                const SizedBox(height: 4),
                Text('Rol: ${_role.isNotEmpty ? _role : '—'}',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 10),
                logo,
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bienvenido, $_name',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kGreen1)),
                      const SizedBox(height: 6),
                      Text('Rol: ${_role.isNotEmpty ? _role : '—'}', style: const TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
                logo,
              ],
            ),
    );
  }

  // ---- Drawer
  Widget _buildDrawerContents(bool isMobile) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
          decoration: BoxDecoration(color: kGreen1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('PharmaControl',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Container(
                height: 56,
                width: 56,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Image.asset('assets/logo.png', fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.inventory_2, color: Colors.green)),
              ),
              const SizedBox(height: 10),
              Text('Bienvenido, $_name', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 4),
              Text('Rol: ${_role.isNotEmpty ? _role : '—'}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: _menuForRole()),
        const SizedBox(height: 8),
        const Divider(),
        _buildMenuTile(icon: Icons.info_outline, title: 'Sobre nosotros', onTap: _openSobreNosotros),
        _buildMenuTile(icon: Icons.help_outline, title: 'Preguntas frecuentes', onTap: _openPreguntasFrecuentes),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: kGreen2,
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _onSignOutPressed,
            icon: const Icon(Icons.logout, color: Colors.white),
            label: const Text('Cerrar sesión', style: TextStyle(color: Colors.white)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 800;
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
                // ---- Aquí se muestra TODO dentro del mismo layout (header + card)
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _headerResponsive(isMobile),
                        const SizedBox(height: 18),
                        Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 3,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            // El contenido (incluye Egresos) se muestra aquí dentro
                            child: _cardContentByIndex(),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
        floatingActionButton: isMobile
            ? (_selectedIndex != 5
                ? FloatingActionButton.extended(
                    heroTag: 'fabOfertas',
                    backgroundColor: kGreen2,
                    onPressed: _openOfertas,
                    icon: const Icon(Icons.local_offer, color: Colors.white),
                    label: const Text('Ofertas', style: TextStyle(color: Colors.white)),
                  )
                : null)
            : null,
      ),
    );
  }
}
