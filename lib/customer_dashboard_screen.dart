import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'login_screen.dart';

class CustomerDashboardScreen extends StatefulWidget {
  final Map<String, dynamic> customerData;

  const CustomerDashboardScreen({super.key, required this.customerData});

  @override
  State<CustomerDashboardScreen> createState() =>
      _CustomerDashboardScreenState();
}

class _CustomerDashboardScreenState extends State<CustomerDashboardScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  List<dynamic> _bills = [];
  List<dynamic> _readings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchCustomerData();
  }

  Future<void> _fetchCustomerData() async {
    try {
      final customerId = widget.customerData['id'];

      final billsResponse = await supabase
          .from('bills')
          .select()
          .eq('customer_id', customerId)
          .order('created_at', ascending: false);

      final readingsResponse = await supabase
          .from('meter_readings')
          .select()
          .eq('customer_id', customerId)
          .order('reading_date', ascending: true);

      if (!mounted) return;
      setState(() {
        _bills = billsResponse;
        _readings = readingsResponse;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.customerData;
    bool hasAnomaly = _readings.any((r) => (r['consumption'] ?? 0) > 20.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Aguila Waterworks - Customer Portal"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    elevation: 3,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            customer['full_name'] ?? 'Customer',
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text('Meter Number: ${customer['meter_number']}'),
                          Text('Address: ${customer['address']}'),
                          Text(
                              'Contact: ${customer['contact_number'] ?? 'N/A'}'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (hasAnomaly)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        border: Border.all(color: Colors.red.shade200),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.red),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "Anomaly Alert: High water consumption (>20 m³) detected in recent readings. Please check for leaks.",
                              style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Text(
                    "Water Consumption Trend (cu.m)",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: SizedBox(
                        height: 220,
                        child: _readings.isEmpty
                            ? const Center(
                                child: Text(
                                    "No usage data available for graphing."))
                            : LineChart(
                                LineChartData(
                                  gridData: const FlGridData(show: true),
                                  titlesData: FlTitlesData(
                                    rightTitles: const AxisTitles(
                                        sideTitles:
                                            SideTitles(showTitles: false)),
                                    topTitles: const AxisTitles(
                                        sideTitles:
                                            SideTitles(showTitles: false)),
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        getTitlesWidget: (value, meta) {
                                          int index = value.toInt();
                                          if (index >= 0 &&
                                              index < _readings.length) {
                                            String dateStr = _readings[index]
                                                    ['reading_date'] ??
                                                '';
                                            return Text(
                                              dateStr.length >= 10
                                                  ? dateStr.substring(5)
                                                  : dateStr,
                                              style:
                                                  const TextStyle(fontSize: 10),
                                            );
                                          }
                                          return const Text('');
                                        },
                                      ),
                                    ),
                                  ),
                                  borderData: FlBorderData(show: true),
                                  lineBarsData: [
                                    LineChartBarData(
                                      spots: _readings
                                          .asMap()
                                          .entries
                                          .map((entry) {
                                        int index = entry.key;
                                        double consumption = double.tryParse(
                                                entry.value['consumption']
                                                    .toString()) ??
                                            0.0;
                                        return FlSpot(
                                            index.toDouble(), consumption);
                                      }).toList(),
                                      isCurved: true,
                                      color: Colors.blue,
                                      barWidth: 3,
                                      dotData: const FlDotData(show: true),
                                      belowBarData: BarAreaData(
                                        show: true,
                                        color: Colors.blue.withOpacity(0.15),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Your Water Bills History",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _bills.length,
                    itemBuilder: (context, index) {
                      final bill = _bills[index];
                      final isPaid = bill['status'] == 'Paid';
                      return Card(
                        child: ListTile(
                          leading: Icon(
                            isPaid ? Icons.check_circle : Icons.pending_actions,
                            color: isPaid ? Colors.green : Colors.orange,
                          ),
                          title: Text('Amount Due: ₱${bill['amount_due']}'),
                          subtitle: Text('Due Date: ${bill['due_date']}'),
                          trailing: Chip(
                            label: Text(
                              bill['status'] ?? 'Unpaid',
                              style: const TextStyle(color: Colors.white),
                            ),
                            backgroundColor:
                                isPaid ? Colors.green : Colors.orange,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }
}
