// lib/providers_manager.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'app_theme.dart';

class ProvidersManager extends StatefulWidget {
  const ProvidersManager({super.key});

  @override
  State<ProvidersManager> createState() => _ProvidersManagerState();
}

class _ProvidersManagerState extends State<ProvidersManager> {
  final CollectionReference providersRef = FirebaseFirestore.instance.collection('providers');
  final CollectionReference purchasesRef = FirebaseFirestore.instance.collection('purchases'); // asume colección de compras

  bool _loadingAction = false;

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool?> _showConfirmation(String title, String message) {
    return showDialog<bool>(
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
  }

  Future<void> _createProviderFirestore(Map<String, dynamic> data) async {
    await providersRef.add({
      'name': data['name'],
      'contact': data['contact'],
      'phone': data['phone'],
      'email': data['email'],
      'address': data['address'],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _updateProviderFirestore(String id, Map<String, dynamic> data) async {
    await providersRef.doc(id).update({
      'name': data['name'],
      'contact': data['contact'],
      'phone': data['phone'],
      'email': data['email'],
      'address': data['address'],
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _deleteProviderFirestore(String id) async {
    await providersRef.doc(id).delete();
  }

  Future<void> _showCreateProviderDialog() async {
    final _formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final contactCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final addressCtrl = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nuevo proveedor'),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre'), validator: (v) => v == null || v.trim().isEmpty ? 'Ingrese nombre' : null),
              const SizedBox(height: 8),
              TextFormField(controller: contactCtrl, decoration: const InputDecoration(labelText: 'Contacto (persona)')),
              const SizedBox(height: 8),
              TextFormField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Teléfono')),
              const SizedBox(height: 8),
              TextFormField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email'), validator: (v) => v != null && v.isNotEmpty && !v.contains('@') ? 'Email inválido' : null),
              const SizedBox(height: 8),
              TextFormField(controller: addressCtrl, decoration: const InputDecoration(labelText: 'Dirección')),
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

    setState(() => _loadingAction = true);
    try {
      await _createProviderFirestore({
        'name': nameCtrl.text.trim(),
        'contact': contactCtrl.text.trim(),
        'phone': phoneCtrl.text.trim(),
        'email': emailCtrl.text.trim(),
        'address': addressCtrl.text.trim(),
      });
      _showSnack('Proveedor creado.');
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      setState(() => _loadingAction = false);
    }
  }

  Future<void> _showEditProviderDialog(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final _formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: data['name'] ?? '');
    final contactCtrl = TextEditingController(text: data['contact'] ?? '');
    final phoneCtrl = TextEditingController(text: data['phone'] ?? '');
    final emailCtrl = TextEditingController(text: data['email'] ?? '');
    final addressCtrl = TextEditingController(text: data['address'] ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Editar proveedor'),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre'), validator: (v) => v == null || v.trim().isEmpty ? 'Ingrese nombre' : null),
              const SizedBox(height: 8),
              TextFormField(controller: contactCtrl, decoration: const InputDecoration(labelText: 'Contacto (persona)')),
              const SizedBox(height: 8),
              TextFormField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Teléfono')),
              const SizedBox(height: 8),
              TextFormField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email'), validator: (v) => v != null && v.isNotEmpty && !v.contains('@') ? 'Email inválido' : null),
              const SizedBox(height: 8),
              TextFormField(controller: addressCtrl, decoration: const InputDecoration(labelText: 'Dirección')),
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

    setState(() => _loadingAction = true);
    try {
      await _updateProviderFirestore(doc.id, {
        'name': nameCtrl.text.trim(),
        'contact': contactCtrl.text.trim(),
        'phone': phoneCtrl.text.trim(),
        'email': emailCtrl.text.trim(),
        'address': addressCtrl.text.trim(),
      });
      _showSnack('Proveedor actualizado.');
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      setState(() => _loadingAction = false);
    }
  }

  Future<void> _tryDeleteProvider(QueryDocumentSnapshot doc) async {
    final confirm = await _showConfirmation('Eliminar proveedor', '¿Seguro que deseas eliminar ${ (doc.data() as Map<String,dynamic>)['name'] ?? 'este proveedor'}?');
    if (confirm != true) return;

    setState(() => _loadingAction = true);
    try {
      await _deleteProviderFirestore(doc.id);
      _showSnack('Proveedor eliminado.');
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      setState(() => _loadingAction = false);
    }
  }

  // --- Historial de compras por proveedor ---
  Future<List<QueryDocumentSnapshot>> _fetchPurchasesByProvider(String providerId) async {
    final snap = await purchasesRef.where('providerId', isEqualTo: providerId).orderBy('createdAt', descending: true).get();
    return snap.docs;
  }

  Future<void> _showPurchasesForProvider(QueryDocumentSnapshot providerDoc) async {
    final providerData = providerDoc.data() as Map<String, dynamic>;
    final purchases = await _fetchPurchasesByProvider(providerDoc.id);

    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Historial de compras - ${providerData['name'] ?? 'Proveedor'}'),
        content: SizedBox(
          width: double.maxFinite,
          child: purchases.isEmpty
              ? const Text('No hay compras registradas para este proveedor.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemBuilder: (ctx, i) {
                    final p = purchases[i].data() as Map<String, dynamic>;
                    final date = p['createdAt'] is Timestamp ? (p['createdAt'] as Timestamp).toDate() : null;
                    return ListTile(
                      title: Text('Compra: ${p['reference'] ?? purchases[i].id}'),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Total: ${p['total'] ?? '—'}'),
                        Text('Fecha: ${date?.toString() ?? '—'}'),
                      ]),
                    );
                  },
                  separatorBuilder: (_, __) => const Divider(),
                  itemCount: purchases.length,
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cerrar'))],
      ),
    );
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header y boton crear
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Proveedores', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kGreen1)),
            ElevatedButton.icon(
              onPressed: _showCreateProviderDialog,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Nuevo proveedor', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: kGreen2),
            ),
          ],
        ),
        const SizedBox(height: 12),

        StreamBuilder<QuerySnapshot>(
          stream: providersRef.orderBy('createdAt', descending: true).snapshots(),
          builder: (context, snap) {
            if (snap.hasError) return const Text('Error al cargar proveedores');
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snap.data!.docs;

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
                        leading: CircleAvatar(backgroundColor: kGreen3, child: Text((data['name'] ?? 'P').toString().substring(0, 1).toUpperCase())),
                        title: Text(data['name'] ?? '—'),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Contacto: ${data['contact'] ?? '—'}'),
                          Text('${data['phone'] ?? ''} • ${data['email'] ?? ''}'),
                        ]),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) async {
                            if (action == 'edit') await _showEditProviderDialog(d);
                            if (action == 'delete') await _tryDeleteProvider(d);
                            if (action == 'purchases') await _showPurchasesForProvider(d);
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'purchases', child: ListTile(leading: Icon(Icons.history), title: Text('Historial compras'))),
                            const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit), title: Text('Editar'))),
                            const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete), title: Text('Eliminar'))),
                          ],
                        ),
                      ),
                    );
                  },
                );
              } else {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Nombre')),
                      DataColumn(label: Text('Contacto')),
                      DataColumn(label: Text('Teléfono')),
                      DataColumn(label: Text('Email')),
                      DataColumn(label: Text('Dirección')),
                      DataColumn(label: Text('Acciones')),
                    ],
                    rows: docs.map((d) {
                      final data = d.data() as Map<String, dynamic>;
                      return DataRow(cells: [
                        DataCell(Text(data['name'] ?? '—')),
                        DataCell(Text(data['contact'] ?? '—')),
                        DataCell(Text(data['phone'] ?? '—')),
                        DataCell(Text(data['email'] ?? '—')),
                        DataCell(Text(data['address'] ?? '—')),
                        DataCell(Row(children: [
                          IconButton(onPressed: () => _showPurchasesForProvider(d), icon: const Icon(Icons.history, color: Colors.black54)),
                          IconButton(onPressed: () => _showEditProviderDialog(d), icon: const Icon(Icons.edit, color: Colors.black54)),
                          IconButton(onPressed: () => _tryDeleteProvider(d), icon: const Icon(Icons.delete, color: Colors.redAccent)),
                        ])),
                      ]);
                    }).toList(),
                  ),
                );
              }
            });
          },
        ),
        if (_loadingAction) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
      ],
    );
  }
}
