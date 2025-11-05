import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';

class LoginEmpleadoPage extends StatefulWidget {
  const LoginEmpleadoPage({super.key});

  @override
  State<LoginEmpleadoPage> createState() => _LoginEmpleadoPageState();
}

class _LoginEmpleadoPageState extends State<LoginEmpleadoPage> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _remember = false;

  @override
  void initState() {
    super.initState();
    _loadRemember();
  }

  Future<void> _loadRemember() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('empleado_username');
    if (saved != null) {
      _userCtrl.text = saved;
      setState(() => _remember = true);
    }
  }

  Future<void> _saveRemember() async {
    final prefs = await SharedPreferences.getInstance();
    if (_remember) {
      await prefs.setString('empleado_username', _userCtrl.text.trim());
    } else {
      await prefs.remove('empleado_username');
    }
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  /// Busca el email real por el campo "usuario" en la colección "users".
  Future<String?> _emailFromUsuario(String usuario) async {
    final q = await FirebaseFirestore.instance
        .collection('users')
        .where('usuario', isEqualTo: usuario)
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    final data = q.docs.first.data();
    final email = (data['email'] as String?)?.trim();
    return (email != null && email.isNotEmpty) ? email : null;
  }

  Future<void> _signInEmpleado() async {
    final input = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    if (input.isEmpty || pass.length < 6) {
      _show('Introduce usuario o correo y contraseña (6+ caracteres).');
      return;
    }

    setState(() => _loading = true);

    try {
      String emailToUse;

      if (input.contains('@')) {
        // Ingresó correo
        emailToUse = input;
      } else {
        // Ingresó nombre de usuario — buscar su email real en Firestore
        final foundEmail = await _emailFromUsuario(input);
        if (foundEmail != null) {
          emailToUse = foundEmail;
        } else {
          // Comportamiento anterior (si usabas alias interno)
          emailToUse = '$input@pharma.local';
        }
      }

      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailToUse,
        password: pass,
      );

      final uid = cred.user!.uid;
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();

      if (!doc.exists) {
        await FirebaseAuth.instance.signOut();
        _show('Cuenta no configurada. Contacte al administrador.');
        return;
      }

      final role = doc.data()?['role'] ?? '';
      if (!(role == 'admin' || role == 'farmaceutico' || role == 'vendedor')) {
        await FirebaseAuth.instance.signOut();
        _show('Esta cuenta no tiene permisos de empleado.');
        return;
      }

      await _saveRemember();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/dashboard');
    } on FirebaseAuthException catch (e) {
      _show(_mapAuthError(e));
    } catch (e) {
      _show('Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'Usuario o correo no encontrado.';
      case 'wrong-password':
        return 'Contraseña incorrecta.';
      case 'invalid-email':
        return 'Formato de correo inválido.';
      case 'too-many-requests':
        return 'Demasiados intentos. Intenta más tarde.';
      case 'user-disabled':
        return 'Cuenta deshabilitada. Contacta al administrador.';
      default:
        return e.message ?? 'Error de autenticación (${e.code}).';
    }
  }

  void _show(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ========= NUEVO: diálogo "¿Olvidaste tu contraseña?" CORREGIDO =========

  Future<void> _openResetDialog() async {
    final textCtrl = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        bool sending = false;

        return StatefulBuilder(builder: (ctx, setS) {
          Future<void> handleSend() async {
            final input = textCtrl.text.trim();
            if (input.isEmpty) {
              _show('Escribe tu usuario o correo.');
              return;
            }

            setS(() => sending = true);
            try {
              await _sendResetEmail(input);

              // ÉXITO: cerramos el diálogo y NO volvemos a llamar setS aquí
              if (!mounted) return;
              Navigator.of(dialogCtx).pop();
              _show(
                'Si el correo existe, te enviamos un enlace para restablecerla. '
                'Revisa tu bandeja y SPAM.',
              );
            } on FirebaseAuthException catch (e) {
              // ERROR: el diálogo sigue abierto; podemos revertir el spinner
              setS(() => sending = false);
              _show(_mapAuthError(e));
            } catch (e) {
              setS(() => sending = false);
              _show('Error: $e');
            }
          }

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Recuperar contraseña'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Escribe tu usuario o correo. '
                  'Te enviaremos un enlace seguro para restablecer tu contraseña.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: textCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Usuario o correo',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                  autofocus: true,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: sending ? null : () => Navigator.of(dialogCtx).pop(),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: sending ? null : handleSend,
                child: sending
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enviar'),
              ),
            ],
          );
        });
      },
    );

    textCtrl.dispose();
  }

  /// Acepta usuario o correo; si es usuario, busca el email real en Firestore.
  Future<void> _sendResetEmail(String input) async {
    String email;
    if (input.contains('@')) {
      email = input;
    } else {
      final found = await _emailFromUsuario(input);
      if (found == null) {
        throw FirebaseAuthException(
            code: 'user-not-found', message: 'Usuario no encontrado.');
      }
      email = found;
    }
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
  }

  // =============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: kBackgroundGradient),
        alignment: Alignment.center,
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: kGreen3.withOpacity(0.15)),
                ),
                elevation: 10,
                margin: const EdgeInsets.all(20),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Iniciar Sesión',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: kGreen1)),
                      const SizedBox(height: 10),
                      Image.asset('assets/logo.png', height: 190),
                      const SizedBox(height: 20),

                      TextField(
                        controller: _userCtrl,
                        decoration: InputDecoration(
                          labelText: 'Usuario o correo',
                          hintText: 'Usuario o correo',
                          prefixIcon: const Icon(Icons.person_outline),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 14),

                      TextField(
                        controller: _passCtrl,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          prefixIcon: const Icon(Icons.lock_outline),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          suffixIcon: IconButton(
                            icon: Icon(
                                _obscure ? Icons.visibility_off : Icons.visibility),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      Row(
                        children: [
                          Checkbox(
                              value: _remember,
                              onChanged: (v) =>
                                  setState(() => _remember = v ?? false)),
                          const Text('Recordar usuario',
                              style: TextStyle(fontSize: 14)),
                        ],
                      ),
                      const SizedBox(height: 6),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kGreen2,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _loading ? null : _signInEmpleado,
                          child: _loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Acceder',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 16)),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // 👉 Link de "¿Olvidaste tu contraseña?"
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: _openResetDialog,
                            child: Text(
                              "¿Olvidaste tu contraseña?",
                              style: TextStyle(
                                color: kGreen2,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // 👉 Link de crear cuenta
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("¿No tienes cuenta? "),
                          GestureDetector(
                            onTap: () =>
                                Navigator.pushNamed(context, '/register_vendedor'),
                            child: Text(
                              "Crear una cuenta",
                              style: TextStyle(
                                color: kGreen2,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
