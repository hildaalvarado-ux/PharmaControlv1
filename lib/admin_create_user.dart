// lib/admin_user_manager.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'app_theme.dart';

class AdminUserManager extends StatefulWidget {
  const AdminUserManager({super.key});

  @override
  State<AdminUserManager> createState() => _AdminUserManagerState();
}

class _AdminUserManagerState extends State<AdminUserManager> {
  final CollectionReference usersRef = FirebaseFirestore.instance.collection('users');
  bool _loadingAction = false;

  // Roles disponibles
  final List<String> _roles = ['admin', 'farmaceutico', 'vendedor'];

  // --- Utilidades ---
  Future<bool> _reauthenticateCurrentUser(String password) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return false;
    try {
      final credential = EmailAuthProvider.credential(email: user.email!, password: password);
      await user.reauthenticateWithCredential(credential);
      return true;
    } on FirebaseAuthException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _showConfirmation(String title, String message) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Si')),
        ],
      ),
    );
    return res == true;
  }

  Future<String?> _askForPassword({required String hint}) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Ingresa tu contraseña'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(hint),
            const SizedBox(height: 8),
            TextField(controller: controller, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok != true) return null;
    return controller.text.trim().isEmpty ? null : controller.text.trim();
  }

  // CRUD Firestore (solo documentos, no Auth)
  Future<void> _createUserFirestore(Map<String, dynamic> data) async {
    await usersRef.add({
      'name': data['name'],
      'usuario': data['usuario'],
      'email': data['email'],
      'role': data['role'],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _updateUserFirestore(String uid, Map<String, dynamic> data) async {
    await usersRef.doc(uid).update({
      'name': data['name'],
      'usuario': data['usuario'],
      'role': data['role'],
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _deleteUserFirestore(String uid) async {
    await usersRef.doc(uid).delete();
  }

  // Diálogos crear / editar
  Future<void> _showCreateUserDialog() async {
    final _formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String role = _roles.first;

    final created = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Crear usuario'),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre completo'), validator: (v) => v == null || v.trim().isEmpty ? 'Ingrese nombre' : null),
              const SizedBox(height: 8),
              TextFormField(controller: userCtrl, decoration: const InputDecoration(labelText: 'Usuario (único)'), validator: (v) => v == null || v.trim().isEmpty ? 'Ingrese usuario' : null),
              const SizedBox(height: 8),
              TextFormField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Correo'), validator: (v) => v == null || !v.contains('@') ? 'Correo inválido' : null),
              const SizedBox(height: 8),
              TextFormField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña (solo Firestore)'), validator: (v) => v == null || v.length < 6 ? 'Mínimo 6' : null),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: role,
                items: _roles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                onChanged: (v) => role = v ?? role,
                decoration: const InputDecoration(labelText: 'Rol'),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(c, true);
          }, child: const Text('Crear')),
        ],
      ),
    );

    if (created != true) return;

    if (role == 'admin') {
      final pass = await _askForPassword(hint: 'Confirma tu contraseña para asignar rol admin');
      if (pass == null) {
        _showSnack('Acción cancelada');
        return;
      }
      final ok = await _reauthenticateCurrentUser(pass);
      if (!ok) {
        _showSnack('Contraseña incorrecta');
        return;
      }
    }

    setState(() => _loadingAction = true);
    try {
      await _createUserFirestore({
        'name': nameCtrl.text.trim(),
        'usuario': userCtrl.text.trim(),
        'email': emailCtrl.text.trim(),
        'role': role,
      });
      _showSnack('Usuario creado (Firestore). Para crear cuenta en Auth usa Cloud Functions con privilegios.');
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      setState(() => _loadingAction = false);
    }
  }

  Future<void> _showEditUserDialog(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final _formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: data['name'] ?? '');
    final userCtrl = TextEditingController(text: data['usuario'] ?? '');
    String role = (data['role'] ?? _roles.first) as String;

    final confirmed = await _showConfirmation('Editar usuario', '¿Seguro que deseas editar los datos de este usuario?');
    if (!confirmed) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Editar usuario'),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre completo'), validator: (v) => v == null || v.trim().isEmpty ? 'Ingrese nombre' : null),
              const SizedBox(height: 8),
              TextFormField(controller: userCtrl, decoration: const InputDecoration(labelText: 'Usuario (único)'), validator: (v) => v == null || v.trim().isEmpty ? 'Ingrese usuario' : null),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: role,
                items: _roles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                onChanged: (v) => role = v ?? role,
                decoration: const InputDecoration(labelText: 'Rol'),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(c, true);
          }, child: const Text('Guardar')),
        ],
      ),
    );

    if (saved != true) return;

    final oldRole = (data['role'] ?? '') as String;
    if (oldRole != role && (role == 'admin' || oldRole == 'admin')) {
      final pass = await _askForPassword(hint: 'Confirma tu contraseña para cambiar roles');
      if (pass == null) {
        _showSnack('Acción cancelada');
        return;
      }
      final ok = await _reauthenticateCurrentUser(pass);
      if (!ok) {
        _showSnack('Contraseña incorrecta');
        return;
      }
    }

    setState(() => _loadingAction = true);
    try {
      await _updateUserFirestore(doc.id, {
        'name': nameCtrl.text.trim(),
        'usuario': userCtrl.text.trim(),
        'role': role,
      });
      _showSnack('Usuario actualizado (Firestore). Para afectar Firebase Auth usa Cloud Functions.');
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      setState(() => _loadingAction = false);
    }
  }

  Future<void> _tryDeleteUser(QueryDocumentSnapshot doc, int adminCount) async {
    final data = doc.data() as Map<String, dynamic>;
    final role = (data['role'] ?? '') as String;

    if (role == 'admin' && adminCount <= 1) {
      _showSnack('No se puede eliminar: debe existir al menos un administrador.');
      return;
    }

    final confirm = await _showConfirmation('Eliminar usuario', '¿Seguro que deseas eliminar a ${data['name'] ?? 'este usuario'}?');
    if (!confirm) return;

    final pass = await _askForPassword(hint: 'Ingresa tu contraseña para confirmar eliminación');
    if (pass == null) {
      _showSnack('Acción cancelada');
      return;
    }
    final ok = await _reauthenticateCurrentUser(pass);
    if (!ok) {
      _showSnack('Contraseña incorrecta');
      return;
    }

    setState(() => _loadingAction = true);
    try {
      await _deleteUserFirestore(doc.id);
      _showSnack('Usuario eliminado (Firestore). Para eliminar la cuenta en Auth usa Cloud Functions.');
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      setState(() => _loadingAction = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ✅ Título centrado
        Center(
          child: Text(
            'Gestión de usuarios',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kGreen1),
          ),
        ),
        const SizedBox(height: 12),

        // Lista de usuarios
        StreamBuilder<QuerySnapshot>(
          stream: usersRef.orderBy('createdAt', descending: true).snapshots(),
          builder: (context, snap) {
            if (snap.hasError) return const Text('Error al cargar usuarios');
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snap.data!.docs;
            final adminCount = docs.where((d) {
              final r = (d.data() as Map<String, dynamic>)['role'] ?? '';
              return r == 'admin';
            }).length;

            return LayoutBuilder(builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 700;

              if (isMobile) {
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final d = docs[i];
                    final data = d.data() as Map<String, dynamic>;
                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: kGreen3,
                          child: Text((data['name'] ?? 'U').toString().trim().isEmpty ? 'U' : data['name'].toString().substring(0,1).toUpperCase()),
                        ),
                        title: Text(data['name'] ?? '—'),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(data['email'] ?? ''),
                          Text('Rol: ${data['role'] ?? '—'}'),
                        ]),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) async {
                            if (action == 'edit') await _showEditUserDialog(d);
                            if (action == 'delete') await _tryDeleteUser(d, adminCount);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit), title: Text('Editar'))),
                            PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete), title: Text('Eliminar'))),
                          ],
                        ),
                      ),
                    );
                  },
                );
              } else {
                // Desktop
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Nombre')),
                      DataColumn(label: Text('Email')),
                      DataColumn(label: Text('Usuario')),
                      DataColumn(label: Text('Rol')),
                      DataColumn(label: Text('Acciones')),
                    ],
                    rows: docs.map((d) {
                      final data = d.data() as Map<String, dynamic>;
                      return DataRow(cells: [
                        DataCell(Text(data['name'] ?? '—')),
                        DataCell(Text(data['email'] ?? '—')),
                        DataCell(Text(data['usuario'] ?? '—')),
                        DataCell(Text(data['role'] ?? '—')),
                        DataCell(Row(children: [
                          IconButton(onPressed: () => _showEditUserDialog(d), icon: const Icon(Icons.edit, color: Colors.black54)),
                          IconButton(onPressed: () => _tryDeleteUser(d, adminCount), icon: const Icon(Icons.delete, color: Colors.redAccent)),
                        ])),
                      ]);
                    }).toList(),
                  ),
                );
              }
            });
          },
        ),

        // ✅ Botón centrado al final
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton.icon(
            onPressed: _showCreateUserDialog,
            icon: const Icon(Icons.person_add),
            label: const Text('Nuevo usuario'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kGreen2,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),

        if (_loadingAction) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
      ],
    );
  }
}
