import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_screen.dart';
import 'reports_screen.dart';
import 'add_bill_screen.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  List<dynamic> _customers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchCustomers();
  }

  // Explicitly call select('*') to ensure clean query serialization
  Future<void> _fetchCustomers() async {
    setState(() => _isLoading = true);
    try {
      final data = await supabase.from('customers').select('*');

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
            content: Text('Error loading customers: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Dialog for Add or Edit Customer
  void _showCustomerDialog({Map<String, dynamic>? customer}) {
    final isEditing = customer != null;

    final meterController = TextEditingController(
      text: customer?['meter_number'] ?? '',
    );

    String defaultFirstName = '';
    String defaultLastName = '';
    if (isEditing && customer['full_name'] != null) {
      final nameParts = (customer['full_name'] as String).split(' ');
      if (nameParts.length > 1) {
        defaultLastName = nameParts.last;
        defaultFirstName = nameParts.sublist(0, nameParts.length - 1).join(' ');
      } else {
        defaultFirstName = customer['full_name'];
      }
    }

    final firstNameController = TextEditingController(text: defaultFirstName);
    final lastNameController = TextEditingController(text: defaultLastName);

    final houseNumController = TextEditingController();
    final streetPurokController = TextEditingController();
    final barangayController = TextEditingController();
    final cityController = TextEditingController(text: 'San Jose');
    final provinceController = TextEditingController(text: 'Batangas');

    if (isEditing && customer['address'] != null) {
      final addrParts = (customer['address'] as String).split(', ');
      if (addrParts.isNotEmpty) houseNumController.text = addrParts[0];
      if (addrParts.length > 1) streetPurokController.text = addrParts[1];
      if (addrParts.length > 2) barangayController.text = addrParts[2];
      if (addrParts.length > 3) cityController.text = addrParts[3];
      if (addrParts.length > 4) provinceController.text = addrParts[4];
    }

    final contactController = TextEditingController(
      text: customer?['contact_number'] ?? '',
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isEditing ? 'Edit Customer' : 'Add New Customer'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: meterController,
                    decoration: const InputDecoration(
                      labelText: 'Meter Number',
                      prefixIcon: Icon(Icons.speed),
                    ),
                    enabled: !isEditing,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: firstNameController,
                          decoration: const InputDecoration(
                            labelText: 'First Name',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: lastNameController,
                          decoration: const InputDecoration(
                            labelText: 'Last Name',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: houseNumController,
                    decoration: const InputDecoration(
                      labelText: 'Building / House Number',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: streetPurokController,
                    decoration: const InputDecoration(
                      labelText: 'Street / Purok',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: barangayController,
                    decoration: const InputDecoration(labelText: 'Barangay'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: cityController,
                          decoration: const InputDecoration(
                            labelText: 'Town / City',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: provinceController,
                          decoration: const InputDecoration(
                            labelText: 'Province',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: contactController,
                    decoration: const InputDecoration(
                      labelText: 'Contact Number',
                      prefixIcon: Icon(Icons.phone),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final meter = meterController.text.trim();
                final firstName = firstNameController.text.trim();
                final lastName = lastNameController.text.trim();
                final fullName = '$firstName $lastName'.trim();

                final fullAddress = [
                  houseNumController.text.trim(),
                  streetPurokController.text.trim(),
                  barangayController.text.trim(),
                  cityController.text.trim(),
                  provinceController.text.trim(),
                ].where((part) => part.isNotEmpty).join(', ');

                final contact = contactController.text.trim();

                if (meter.isEmpty || fullName.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please fill in required fields.'),
                    ),
                  );
                  return;
                }

                try {
                  if (isEditing) {
                    await supabase.from('customers').update({
                      'full_name': fullName,
                      'address': fullAddress,
                      'contact_number': contact,
                    }).eq('id', customer['id']);
                  } else {
                    await supabase.from('customers').insert({
                      'meter_number': meter,
                      'full_name': fullName,
                      'address': fullAddress,
                      'contact_number': contact,
                      'password': '123456',
                    });
                  }

                  if (mounted) {
                    Navigator.pop(context);
                    _fetchCustomers();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isEditing ? 'Customer updated!' : 'Customer added!',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: Text(isEditing ? 'Update' : 'Save'),
            ),
          ],
        );
      },
    );
  }

  // View Customer Details Dialog
  void _viewCustomerDetails(Map<String, dynamic> customer) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.person, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(customer['full_name'] ?? 'Customer Details'),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                leading: const Icon(Icons.speed),
                title: const Text('Meter Number'),
                subtitle: Text(customer['meter_number'] ?? 'N/A'),
              ),
              ListTile(
                leading: const Icon(Icons.home),
                title: const Text('Address'),
                subtitle: Text(customer['address'] ?? 'N/A'),
              ),
              ListTile(
                leading: const Icon(Icons.phone),
                title: const Text('Contact Number'),
                subtitle: Text(customer['contact_number'] ?? 'N/A'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Aguila Waterworks Inc. - Personnel Portal"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: 'Create New Bill',
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddBillScreen()),
              );
              if (result == true) {
                _fetchCustomers();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'View Reports',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReportsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchCustomers,
            tooltip: 'Refresh List',
          ),
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
          : _customers.isEmpty
              ? const Center(
                  child: Text("No customers found. Click + to add one."),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _customers.length,
                  itemBuilder: (context, index) {
                    final customer = _customers[index];
                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.shade100,
                          child: Text(
                            (customer['full_name'] ?? 'C')[0].toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(
                          customer['full_name'] ?? 'No Name',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Meter #: ${customer['meter_number']}'),
                            Text(
                              customer['address'] ?? 'No Address',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.visibility,
                                color: Colors.blue,
                              ),
                              tooltip: 'View Details',
                              onPressed: () => _viewCustomerDetails(customer),
                            ),
                            IconButton(
                              icon:
                                  const Icon(Icons.edit, color: Colors.orange),
                              tooltip: 'Edit Customer',
                              onPressed: () =>
                                  _showCustomerDialog(customer: customer),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCustomerDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add Customer'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
    );
  }
}
