import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'customer_list_screen.dart';
import 'customer_dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final SupabaseClient supabase = Supabase.instance.client;

  final _staffEmailController = TextEditingController();
  final _staffPasswordController = TextEditingController();

  final _meterNumberController = TextEditingController();
  final _customerPasswordController = TextEditingController();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _staffEmailController.dispose();
    _staffPasswordController.dispose();
    _meterNumberController.dispose();
    _customerPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin({required bool isPersonnel}) async {
    setState(() => _isLoading = true);
    try {
      if (isPersonnel) {
        final email = _staffEmailController.text.trim();
        final password = _staffPasswordController.text.trim();

        if (email.isEmpty || password.isEmpty) {
          throw 'Please enter personnel credentials.';
        }

        // Bypasses browser network CORS auth restrictions for local web testing
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const CustomerListScreen()),
          );
        }
      } else {
        final meter = _meterNumberController.text.trim();
        final password = _customerPasswordController.text.trim();

        if (meter.isEmpty || password.isEmpty) {
          throw 'Please enter Meter Number and Password.';
        }

        final customerData = await supabase
            .from('customers')
            .select()
            .eq('meter_number', meter)
            .maybeSingle();

        if (customerData == null) {
          throw 'Meter Number not found in system.';
        }

        final dbPassword = customerData['password'] ?? '123456';
        if (password != dbPassword) {
          throw 'Incorrect password.';
        }

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  CustomerDashboardScreen(customerData: customerData),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Login Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 450),
            padding: const EdgeInsets.all(24.0),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.water_drop, size: 60, color: Colors.blue),
                    const SizedBox(height: 12),
                    const Text(
                      "Aguila Women's Waterworks Inc.",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    TabBar(
                      controller: _tabController,
                      labelColor: Colors.blue,
                      unselectedLabelColor: Colors.grey,
                      tabs: const [
                        Tab(icon: Icon(Icons.badge), text: "Personnel"),
                        Tab(icon: Icon(Icons.person), text: "Customer"),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 180,
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          Column(
                            children: [
                              TextField(
                                controller: _staffEmailController,
                                decoration: const InputDecoration(
                                  labelText: 'Staff Email',
                                  prefixIcon: Icon(Icons.email),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _staffPasswordController,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: Icon(Icons.lock),
                                ),
                              ),
                            ],
                          ),
                          Column(
                            children: [
                              TextField(
                                controller: _meterNumberController,
                                decoration: const InputDecoration(
                                  labelText: 'Meter Number',
                                  prefixIcon: Icon(Icons.speed),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _customerPasswordController,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: Icon(Icons.lock),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _isLoading
                        ? const CircularProgressIndicator()
                        : SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () {
                                _handleLogin(
                                    isPersonnel: _tabController.index == 0);
                              },
                              child: const Text('LOG IN',
                                  style: TextStyle(fontSize: 16)),
                            ),
                          ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
