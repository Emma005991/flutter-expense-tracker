import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const ExpenseApp());
}

class ExpenseApp extends StatefulWidget {
  const ExpenseApp({super.key});

  @override
  State<ExpenseApp> createState() => _ExpenseAppState();
}

class _ExpenseAppState extends State<ExpenseApp> {
  bool _dark = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final p = await SharedPreferences.getInstance();
    _dark = p.getBool('dark') ?? false;
    setState(() => _loaded = true);
  }

  Future<void> _toggleTheme() async {
    final p = await SharedPreferences.getInstance();
    setState(() => _dark = !_dark);
    await p.setBool('dark', _dark);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Expense Tracker',
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: HomePage(onToggleTheme: _toggleTheme, isDark: _dark),
    );
  }
}

class Expense {
  final String id;
  String title;
  double amount;
  String category;
  DateTime date;

  Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
  });

  Map<String, dynamic> toMap() => {
        "id": id,
        "title": title,
        "amount": amount,
        "category": category,
        "date": date.toIso8601String(),
      };

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map["id"],
      title: map["title"],
      amount: (map["amount"] as num).toDouble(),
      category: map["category"],
      date: DateTime.parse(map["date"]),
    );
  }
}

class HomePage extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final bool isDark;

  const HomePage({
    super.key,
    required this.onToggleTheme,
    required this.isDark,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Expense> expenses = [];
  Map<String, double> budgets = {};

  @override
  void initState() {
    super.initState();
    _loadExpenses();
    _loadBudgets();
  }

  Future<void> _loadExpenses() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString("expenses");
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      setState(() {
        expenses = list.map((e) => Expense.fromMap(e)).toList();
      });
    }
  }

  Future<void> _saveExpenses() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(
      "expenses",
      jsonEncode(expenses.map((e) => e.toMap()).toList()),
    );
  }

  Future<void> _loadBudgets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString("budgets");
    if (raw != null) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      budgets = map.map((k, v) => MapEntry(k, (v as num).toDouble()));
      setState(() {});
    }
  }

  Future<void> _saveBudgets() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString("budgets", jsonEncode(budgets));
  }

  void _addExpense(Expense e) {
    setState(() => expenses.insert(0, e));
    _saveExpenses();
  }

  void _updateExpense(Expense e) {
    final i = expenses.indexWhere((x) => x.id == e.id);
    setState(() => expenses[i] = e);
    _saveExpenses();
  }

  void _deleteExpense(String id) {
    setState(() => expenses.removeWhere((e) => e.id == id));
    _saveExpenses();
  }

  void _openAdd([Expense? e]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddExpenseSheet(
        onAdd: e == null ? _addExpense : _updateExpense,
        existing: e,
      ),
    );
  }

  List<Expense> _thisMonth() {
    final n = DateTime.now();
    return expenses
        .where((e) => e.date.year == n.year && e.date.month == n.month)
        .toList();
  }

  double _monthTotal() => _thisMonth().fold(0.0, (s, e) => s + e.amount);

  Map<String, double> _byCategory() {
    final map = <String, double>{};
    for (final e in _thisMonth()) {
      map[e.category] = (map[e.category] ?? 0) + e.amount;
    }
    return map;
  }

  double _lastMonthTotal() {
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1);
    return expenses
        .where((e) =>
            e.date.year == lastMonth.year && e.date.month == lastMonth.month)
        .fold(0.0, (s, e) => s + e.amount);
  }

  String _topCategoryName() {
    final map = _byCategory();
    if (map.isEmpty) return "—";
    return map.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  String _weeklyMessage() {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final count = expenses.where((e) => e.date.isAfter(weekAgo)).length;

    if (count == 0) return "You haven’t added any expenses this week.";
    if (count < 3) return "You’ve added only $count expenses this week.";
    return "Good job tracking your expenses this week!";
  }

  List<String> _insights() {
    final messages = <String>[];
    final thisMonth = _monthTotal();
    final lastMonth = _lastMonthTotal();

    if (thisMonth > 0) {
      messages.add("You spent the most on ${_topCategoryName()} this month.");
    }

    if (lastMonth > 0) {
      if (thisMonth < lastMonth) {
        messages.add("Great job! You spent less than last month.");
      } else if (thisMonth > lastMonth) {
        messages.add("You spent more than last month. Watch your budget.");
      }
    }

    messages.add(_weeklyMessage());
    return messages;
  }

  String? _overBudgetMessage(String category, double spent) {
    final limit = budgets[category];
    if (limit == null) return null;
    if (spent > limit) {
      final diff = spent - limit;
      return "Over budget by ₦${diff.toStringAsFixed(0)}";
    }
    return null;
  }

  void _setBudget(String category) {
    final ctrl = TextEditingController(
      text: budgets[category]?.toString() ?? "",
    );

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Set budget for $category"),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: "Amount"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text);
              if (v != null) {
                setState(() {
                  budgets[category] = v;
                });
                _saveBudgets();
              }
              Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _exportCSV() {
    if (expenses.isEmpty) return;

    final buffer = StringBuffer();
    buffer.writeln("Title,Amount,Category,Date");

    for (final e in expenses) {
      buffer.writeln(
        '"${e.title.replaceAll('"', '""')}",${e.amount},${e.category},${e.date.toIso8601String()}',
      );
    }

    Share.share(
      buffer.toString(),
      subject: "My Expenses",
    );
  }

  Widget _summary(String l, String v) {
    return Column(
      children: [
        Text(l, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
        Text(v,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cat = _byCategory();
    final max =
        cat.values.isEmpty ? 1.0 : cat.values.reduce((a, b) => a > b ? a : b);
    final insights = _insights();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Expense Tracker"),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: "Export CSV",
            onPressed: _exportCSV,
          ),
          IconButton(
            icon: Icon(widget.isDark ? Icons.dark_mode : Icons.light_mode),
            onPressed: widget.onToggleTheme,
          ),
        ],
      ),
      body: Column(
        children: [
          if (expenses.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _summary(
                          "This Month", "₦${_monthTotal().toStringAsFixed(2)}"),
                      _summary("Entries", _thisMonth().length.toString()),
                      _summary("Categories", cat.length.toString()),
                    ],
                  ),
                ),
              ),
            ),
          if (insights.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Insights",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      ...insights.map(
                        (m) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              const Icon(Icons.lightbulb, size: 16),
                              const SizedBox(width: 6),
                              Expanded(child: Text(m)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (cat.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: cat.entries.map((e) {
                  final limit = budgets[e.key];
                  final pct = (e.value / max).clamp(0.0, 1.0);
                  final warning = _overBudgetMessage(e.key, e.value);

                  return GestureDetector(
                    onLongPress: () => _setBudget(e.key),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              SizedBox(width: 80, child: Text(e.key)),
                              Expanded(
                                child: LinearProgressIndicator(
                                  value: pct,
                                  color: warning != null ? Colors.red : null,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text("₦${e.value.toStringAsFixed(0)}"),
                            ],
                          ),
                          if (limit != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 80, top: 2),
                              child: Text(
                                "Budget: ₦${limit.toStringAsFixed(0)}",
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          if (warning != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 80, top: 2),
                              child: Text(
                                warning,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.red,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          Expanded(
            child: expenses.isEmpty
                ? const Center(child: Text("No expenses yet"))
                : ListView.builder(
                    itemCount: expenses.length,
                    itemBuilder: (_, i) {
                      final e = expenses[i];
                      return Card(
                        margin: const EdgeInsets.all(8),
                        child: ListTile(
                          onTap: () => _openAdd(e),
                          title: Text(e.title),
                          subtitle: Text(
                              "${e.category} • ${DateFormat.yMMMd().format(e.date)}"),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text("₦${e.amount.toStringAsFixed(2)}"),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () => _deleteExpense(e.id),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAdd(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class AddExpenseSheet extends StatefulWidget {
  final void Function(Expense) onAdd;
  final Expense? existing;

  const AddExpenseSheet({
    super.key,
    required this.onAdd,
    this.existing,
  });

  @override
  State<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<AddExpenseSheet> {
  late TextEditingController title;
  late TextEditingController amount;
  late String category;
  late DateTime date;

  final cats = ["Food", "Transport", "Bills", "Fun", "Other"];

  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: widget.existing?.title ?? "");
    amount =
        TextEditingController(text: widget.existing?.amount.toString() ?? "");
    category = widget.existing?.category ?? "Food";
    date = widget.existing?.date ?? DateTime.now();
  }

  void _submit() {
    final t = title.text.trim();
    final a = double.tryParse(amount.text);

    if (t.isEmpty || a == null) return;

    final e = Expense(
      id: widget.existing?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      title: t,
      amount: a,
      category: category,
      date: date,
    );

    widget.onAdd(e);
    Navigator.pop(context);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() => date = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: "Title"),
            ),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Amount"),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField(
              value: category,
              items: cats
                  .map(
                    (c) => DropdownMenuItem(
                      value: c,
                      child: Text(c),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => category = v!),
              decoration: const InputDecoration(labelText: "Category"),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text("Date: ${DateFormat.yMMMd().format(date)}"),
                const Spacer(),
                TextButton(
                  onPressed: _pickDate,
                  child: const Text("Change"),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submit,
                child: Text(widget.existing == null ? "Add" : "Update"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
