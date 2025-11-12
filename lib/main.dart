// lib/main.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_empleado.dart';
import 'dashboard.dart';
import 'app_theme.dart';
import 'register_vendedor.dart';
import 'ingreso_form.dart';
import 'egreso_form.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyACt_Zn3UwnDaGsvPofHDvLOxvILiV7ZBs",
        authDomain: "basepharma-e22c9.firebaseapp.com",
        projectId: "basepharma-e22c9",
        storageBucket: "basepharma-e22c9.firebasestorage.app",
        messagingSenderId: "719498473037",
        appId: "1:719498473037:web:17f1e172ae1f46cd703604",
      ),
    );
  } else {
    await Firebase.initializeApp();
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: kGreen2,
      primary: kGreen2,
      secondary: kGreen3,
      background: kGreen5,
      brightness: Brightness.light,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PharmaControl',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        appBarTheme: AppBarTheme(
          backgroundColor: kGreen1,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kGreen2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          ),
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const MyHomePage(),
        '/login_empleado': (context) => const LoginEmpleadoPage(),
        '/register_vendedor': (context) => const RegisterVendedorPage(),
        '/dashboard': (context) => const DashboardPage(),
        '/ingresos': (context) => const IngresoFormWidget(),
        '/egresos': (context) => const EgresoFormWidget(),
      },
    );
  }
}

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: kBackgroundGradient),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final logoH = w < 420 ? 140.0 : (w < 900 ? 200.0 : 250.0);
              final titleSize = w < 420 ? 18.0 : 22.0;

              return SingleChildScrollView(
                // Permite scroll en pantallas bajas para evitar overflow
                child: ConstrainedBox(
                  // Garantiza altura mínima = alto de pantalla (footer queda “pegado” abajo)
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      // Hero
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            Image.asset('assets/logo.png',
                                height: logoH, fit: BoxFit.contain),
                            const SizedBox(height: 20),
                            Text(
                              "Sistema de Gestión de Farmacia",
                              style: TextStyle(
                                fontSize: titleSize,
                                fontWeight: FontWeight.bold,
                                color: kGreen2,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            TextButton.icon(
                              onPressed: () =>
                                  Navigator.pushNamed(context, '/login_empleado'),
                              icon: const Icon(Icons.person, color: Colors.white),
                              label: const Text(
                                "Ingresar",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: kGreen2,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      // Footer nuevo (responsivo)
                      const PharmaFooter(),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Footer elegante, responsivo y con mejor contraste de logo.
class PharmaFooter extends StatelessWidget {
  const PharmaFooter({super.key});

  static const _about =
      "PharmaControl es una aplicación diseñada para optimizar la gestión "
      "farmacéutica, facilitando el control de inventarios, egresos, movimientos "
      "y proveedores.";

  static const _mision =
      "Brindar soluciones tecnológicas innovadoras para la gestión farmacéutica, "
      "promoviendo el uso eficiente de los recursos y contribuyendo al desarrollo "
      "de un sistema de salud más moderno y confiable.";

  static const _vision =
      "Ser reconocidos como una plataforma líder en gestión farmacéutica digital, "
      "destacada por su calidad, innovación y compromiso con la mejora continua del "
      "sector salud a través de la tecnología.";

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isWide = w > 900;

    // Paddings y tamaños adaptativos
    final hPad = w < 480 ? 14.0 : 20.0;
    final cardMax = w < 480 ? 500.0 : 420.0;
    final titleSize = w < 480 ? 15.0 : 16.0;
    final bodySize = w < 480 ? 13.0 : 13.5;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: kGreen1,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.15),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Cinta con logo — lo hago resaltar en una “insignia” blanca
          Container(
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [kGreen1, kGreen2],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
          ),

          // Tarjetas: Sobre, Misión, Visión
          Padding(
            padding: EdgeInsets.fromLTRB(hPad, 20, hPad, 8),
            child: Wrap(
              spacing: 24,
              runSpacing: 18,
              alignment: WrapAlignment.spaceBetween,
              children: [
                _InfoCard(
                  title: "Sobre Nosotros",
                  body: _about,
                  maxWidth: cardMax,
                  titleSize: titleSize,
                  bodySize: bodySize,
                ),
                _InfoCard(
                  title: "Misión",
                  body: _mision,
                  maxWidth: cardMax,
                  titleSize: titleSize,
                  bodySize: bodySize,
                ),
                _InfoCard(
                  title: "Visión",
                  body: _vision,
                  maxWidth: cardMax,
                  titleSize: titleSize,
                  bodySize: bodySize,
                ),
              ],
            ),
          ),

          Divider(
            color: Colors.white.withOpacity(.20),
            thickness: 1,
            height: 12,
            indent: hPad,
            endIndent: hPad,
          ),

          // Contacto (3 items) – centrado y colapsable
          Padding(
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 14),
            child: Wrap(
              spacing: 14,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.center,
              children: const [
                _ContactPill(icon: Icons.facebook, label: "Facebook / PharmaControl"),
                _ContactPill(icon: Icons.phone, label: "+503 2210-0000"),
                _ContactPill(icon: Icons.email, label: "soporte@uls.edu.sv"),
              ],
            ),
          ),

          // Derechos
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: kGreen1.withOpacity(.95),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                Text(
                  "© ${DateTime.now().year} PharmaControl — Todos los derechos reservados",
                  style: TextStyle(color: Colors.white.withOpacity(.85), fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  "Gestión farmacéutica segura, moderna y eficiente.",
                  style: TextStyle(color: Colors.white.withOpacity(.70), fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String body;
  final double maxWidth;
  final double titleSize;
  final double bodySize;

  const _InfoCard({
    required this.title,
    required this.body,
    required this.maxWidth,
    required this.titleSize,
    required this.bodySize,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: 260, maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: titleSize,
                )),
            const SizedBox(height: 8),
            Text(
              body,
              style: TextStyle(
                color: Colors.white.withOpacity(.88),
                fontSize: bodySize,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ContactPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}
