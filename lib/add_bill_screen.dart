import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddBillScreen extends StatefulWidget {
  const AddBillScreen({super.key});

  @override
  State<AddBillScreen> createState() => _AddBillScreenState();
}

class _AddBillScreenState extends State<AddBillScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  List<dynamic> _customers = [];
  Map<String, dynamic>? _selectedCustomer;
  bool _isLoading = true;
  bool _isSaving = false;

  final TextEditingController _prevReadingController =
      TextEditingController(text: '0');
  final TextEditingController _currReadingController = TextEditingController();

  double _consumption = 0;
  double _totalAmount = 170; // Base fee minimum for first 10 m³

  @override
  void initState() {
    super.initState();
    _fetchCustomers();
  }

  Future<void> _fetchCustomers() async {
    try {
      final data =
          await supabase.from('customers').select('*').order('full_name');
      if (mounted) {
        setState(() {
          _customers = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error fetching customers: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _fetchLastReading(String customerId) async {
    try {
      final response = await supabase
          .from('meter_readings')
          .select('current_reading')
          .eq('customer_id', customerId)
          .order('reading_date', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null && response['current_reading'] != null) {
        _prevReadingController.text = response['current_reading'].toString();
      } else {
        _prevReadingController.text = '0';
      }
      _calculateBill();
    } catch (e) {
      _prevReadingController.text = '0';
      _calculateBill();
    }
  }

  void _calculateBill() {
    final double prev = double.tryParse(_prevReadingController.text) ?? 0;
    final double curr = double.tryParse(_currReadingController.text) ?? 0;

    if (curr >= prev) {
      final double consumed = curr - prev;
      double amount = 170.0; // Base fee for first 10 m³

      if (consumed > 10) {
        final double excess = consumed - 10;
        amount += excess * 70.0; // ₱70 increment per m³
      }

      setState(() {
        _consumption = consumed;
        _totalAmount = amount;
      });
    } else {
      setState(() {
        _consumption = 0;
        _totalAmount = 170.0;
      });
    }
  }

  Future<void> _saveBill() async {
    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a customer.')),
      );
      return;
    }

    final double prev = double.tryParse(_prevReadingController.text) ?? 0;
    final double curr = double.tryParse(_currReadingController.text) ?? 0;

    if (_currReadingController.text.isEmpty || curr < prev) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Current reading must be greater than or equal to previous reading.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final customerId = _selectedCustomer!['id'];
      final double consumedValue = curr - prev;

      // 1. Insert Meter Reading with guaranteed non-null consumption
      final readingResponse = await supabase
          .from('meter_readings')
          .insert({
            'customer_id': customerId,
            'previous_reading': prev,
            'current_reading': curr,
            'consumption': consumedValue,
            'reading_date': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      final readingId = readingResponse['id'];

      // 2. Set Due Date (15 days from today)
      final dueDate = DateTime.now()
          .add(const Duration(days: 15))
          .toIso8601String()
          .split('T')[0];

      // 3. Insert Bill Record
      await supabase.from('bills').insert({
        'customer_id': customerId,
        'reading_id': readingId,
        'amount_due': _totalAmount,
        'due_date': dueDate,
        'status': 'Unpaid',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Bill created successfully!'),
              backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error saving bill: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Meter Reading & Bill'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select Customer',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<Map<String, dynamic>>(
                    value: _selectedCustomer,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                    hint: const Text('Choose customer...'),
                    items: _customers.map((c) {
                      return DropdownMenuItem<Map<String, dynamic>>(
                        value: c,
                        child: Text(
                            '${c['full_name']} (Meter: ${c['meter_number']})'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedCustomer = val;
                      });
                      if (val != null) {
                        _fetchLastReading(val['id'].toString());
                      }
                    },
                  ),

                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _prevReadingController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Previous Reading (m³)',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => _calculateBill(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _currReadingController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Current Reading (m³)',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => _calculateBill(),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Billing Computation Breakdown Card
                  Card(
                    color: Colors.blue.shade50,
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Billing Computation Breakdown',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total Consumption:'),
                              Text('$_consumption m³',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Base Rate (First 10 m³):'),
                              const Text('₱170.00'),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                  'Excess Usage (${_consumption > 10 ? (_consumption - 10).toStringAsFixed(1) : 0} m³ @ ₱70/m³):'),
                              Text(
                                  '₱${_consumption > 10 ? ((_consumption - 10) * 70.0).toStringAsFixed(2) : "0.00"}'),
                            ],
                          ),
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total Amount Due:',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                              Text('₱${_totalAmount.toStringAsFixed(2)}',
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white),
                      onPressed: _isSaving ? null : _saveBill,
                      child: _isSaving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Save & Generate Bill',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
