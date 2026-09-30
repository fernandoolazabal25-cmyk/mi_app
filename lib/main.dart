import 'package:flutter/material.dart';
import 'package:postgres/postgres.dart';

// ---------------------------------------------------------------------------
// Configuración de la base de datos
// ---------------------------------------------------------------------------
const dbHost = '165.1.121.84';
const dbPort = 5430; 
const dbName = 'iot';
const dbUser = 'iot';
const dbPass = 'iot-pass';

class Task {
  final int id;
  final String name;
  final String description;
  Task({required this.id, required this.name, required this.description});
}

// ---------------------------------------------------------------------------
// Acceso a datos (CRUD)
// ---------------------------------------------------------------------------
class TaskRepository {
  Future<Connection> _open() {
    return Connection.open(
      Endpoint(
        host: dbHost,
        port: dbPort,
        database: dbName,
        username: dbUser,
        password: dbPass,
      ),
      settings: const ConnectionSettings(
        // Si el servidor exige SSL, cambia a SslMode.require
        sslMode: SslMode.disable,
        connectTimeout: Duration(seconds: 10),
      ),
    );
  }

  // READ
  Future<List<Task>> getAll() async {
    final conn = await _open();
    try {
      final result = await conn.execute(
        Sql.named('SELECT id, name, description FROM tasks ORDER BY id'),
      );
      return result.map((row) {
        return Task(
          id: row[0] as int,
          name: (row[1] as String?) ?? '',
          description: (row[2] as String?) ?? '',
        );
      }).toList();
    } finally {
      await conn.close();
    }
  }

  // CREATE
  Future<void> create(String name, String description) async {
    final conn = await _open();
    try {
      await conn.execute(
        Sql.named(
          'INSERT INTO tasks (name, description) VALUES (@name, @description)',
        ),
        parameters: {'name': name, 'description': description},
      );
    } finally {
      await conn.close();
    }
  }

  // UPDATE
  Future<void> update(int id, String name, String description) async {
    final conn = await _open();
    try {
      await conn.execute(
        Sql.named(
          'UPDATE tasks SET name = @name, description = @description '
          'WHERE id = @id',
        ),
        parameters: {'id': id, 'name': name, 'description': description},
      );
    } finally {
      await conn.close();
    }
  }

  // DELETE
  Future<void> delete(int id) async {
    final conn = await _open();
    try {
      await conn.execute(
        Sql.named('DELETE FROM tasks WHERE id = @id'),
        parameters: {'id': id},
      );
    } finally {
      await conn.close();
    }
  }
}

// ---------------------------------------------------------------------------
// UI
// ---------------------------------------------------------------------------
void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tasks CRUD',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const TaskListPage(),
    );
  }
}

class TaskListPage extends StatefulWidget {
  const TaskListPage({super.key});

  @override
  State<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends State<TaskListPage> {
  final _repo = TaskRepository();
  List<Task> _tasks = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tasks = await _repo.getAll();
      if (!mounted) return;
      setState(() => _tasks = tasks);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _openForm({Task? task}) async {
    final nameCtrl = TextEditingController(text: task?.name ?? '');
    final descCtrl = TextEditingController(text: task?.description ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(task == null ? 'Nueva tarea' : 'Editar tarea'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(labelText: 'Descripción'),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (saved != true || nameCtrl.text.trim().isEmpty) return;

    final name = nameCtrl.text.trim();
    final desc = descCtrl.text.trim();
    await _run(() => task == null
        ? _repo.create(name, desc)
        : _repo.update(task.id, name, desc));
  }

  Future<void> _confirmDelete(Task task) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar tarea'),
        content: Text('¿Eliminar "${task.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok == true) await _run(() => _repo.delete(task.id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }
    if (_tasks.isEmpty) return const Center(child: Text('No hay tareas'));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _tasks.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final t = _tasks[i];
          return ListTile(
            leading: CircleAvatar(child: Text('${t.id}')),
            title: Text(t.name),
            subtitle: Text(t.description),
            onTap: () => _openForm(task: t),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(t),
            ),
          );
        },
      ),
    );
  }
}
