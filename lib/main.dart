// lib/main.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_empleado.dart';
import 'dashboard.dart';
import 'app_theme.dart';
import 'register_vendedor.dart'; 

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
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: kBackgroundGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
                child: Center(
                  child: Text(
                    'PharmaControl',
                    style: TextStyle(
                      color: kGreen1,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const Spacer(),

              
              Image.asset('assets/logo.png', height: 140, fit: BoxFit.contain),

              const SizedBox(height: 20),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.0),
                child: Text(
                  "Sistema de Gestión de Farmacia",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: kGreen2,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 36),

              
              TextButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/login_empleado'),
                icon: const Icon(Icons.person, color: Colors.white),
                label: const Text(
                  "Ingresar",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: kGreen2,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              const Spacer(flex: 2),

              
              Container(
                width: double.infinity,
                color: kGreen1,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "© 2025 — Todos los derechos reservados",
                      style: TextStyle(fontSize: 12, color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.phone, size: 16, color: Colors.white),
                        SizedBox(width: 6),
                        Text("Tel: +503 2210-0000", style: TextStyle(fontSize: 12, color: Colors.white)),
                        SizedBox(width: 16),
                        Icon(Icons.email, size: 16, color: Colors.white),
                        SizedBox(width: 6),
                        Text("soporte@uls.edu.sv", style: TextStyle(fontSize: 12, color: Colors.white)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
