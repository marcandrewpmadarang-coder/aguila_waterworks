import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:csv/csv.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseClient supabase = Supabase.instance.client;

  late TabController _tabController;

  // Filters & Controls
  String _selectedMonth = 'October';
  String _selectedYear = '2026';
  Map<String, dynamic>? _selectedCustomer;
  String _searchQuery = '';
  bool _showAnomaliesOnly = false;

  // Sorting
  int _sortColumnIndex = 0;
  bool _isAscending = true;

  // Data
  List<dynamic> _customers = [];
  List<Map<String, dynamic>> _reportData = [];
  List<Map<String, dynamic>> _filteredReportData = [];
  bool _isLoading = false;

  final List<String> _months = [
    'All',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];

  final List<String> _years = ['2024', '2025', '2026', '2027'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchCustomers();
    _generateReport();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchCustomers() async {
    try {
      final data =
          await supabase.from('customers').select('*').order('full_name');
      if (mounted) {
        setState(() => _customers = data);
      }
    } catch (e) {
      debugPrint('Error fetching customers: $e');
    }
  }

  // Rule-Based Anomaly Detection Engine
  List<String> _detectAnomalies(double consumption, double avgConsumption) {
    List<String> anomalies = [];
    if (avgConsumption > 0 && consumption > (avgConsumption * 1.5)) {
      anomalies.add(
          "Usage Spike (+${((consumption - avgConsumption) / avgConsumption * 100).toStringAsFixed(0)}% vs avg)");
    }
    if (consumption >= 30) {
      anomalies.add("High Consumption Volume (≥30 m³)");
    }
    if (consumption == 0 && avgConsumption >= 10) {
      anomalies.add("Zero Usage Detected (Possible Meter Fault)");
    }
    if (avgConsumption > 10 &&
        consumption < (avgConsumption * 0.5) &&
        consumption > 0) {
      anomalies.add("Sudden Consumption Drop");
    }
    return anomalies;
  }

  int _getMonthIndex(String month) => _months.indexOf(month);

  Future<void> _generateReport() async {
    setState(() => _isLoading = true);

    try {
      var query = supabase.from('bills').select('''
        id,
        amount_due,
        due_date,
        status,
        created_at,
        reading_id,
        customer_id,
        customers (id, full_name, meter_number)
      ''');

      if (_selectedCustomer != null) {
        query = query.eq('customer_id', _selectedCustomer!['id']);
      }

      final billsData = await query.order('created_at', ascending: false);

      List<Map<String, dynamic>> processedData = [];
      Map<String, List<double>> customerHistories = {};

      for (var bill in billsData) {
        final custId = bill['customer_id']?.toString() ?? 'unknown';
        final readingId = bill['reading_id'];
        if (readingId != null) {
          final readingRes = await supabase
              .from('meter_readings')
              .select('previous_reading, current_reading, consumption')
              .eq('id', readingId)
              .maybeSingle();

          if (readingRes != null) {
            final double curr = double.tryParse(
                    readingRes['current_reading']?.toString() ?? '0') ??
                0.0;
            final double prev = double.tryParse(
                    readingRes['previous_reading']?.toString() ?? '0') ??
                0.0;
            final double consumption = double.tryParse(
                    readingRes['consumption']?.toString() ??
                        (curr - prev).toString()) ??
                0.0;
            customerHistories.putIfAbsent(custId, () => []).add(consumption);
          }
        }
      }

      for (var bill in billsData) {
        final String createdAtStr = bill['created_at'] ?? '';
        final DateTime? recordDate = DateTime.tryParse(createdAtStr);

        if (recordDate != null) {
          if (_selectedYear != 'All' &&
              recordDate.year.toString() != _selectedYear) {
            continue;
          }
          if (_selectedMonth != 'All') {
            final int monthIdx = _getMonthIndex(_selectedMonth);
            if (monthIdx > 0 && recordDate.month != monthIdx) {
              continue;
            }
          }
        }

        final custId = bill['customer_id']?.toString() ?? 'unknown';
        final customer = bill['customers'] ?? {};

        double prevReading = 0.0;
        double currReading = 0.0;
        double consumption = 0.0;

        final readingId = bill['reading_id'];
        if (readingId != null) {
          final readingRes = await supabase
              .from('meter_readings')
              .select('previous_reading, current_reading, consumption')
              .eq('id', readingId)
              .maybeSingle();

          if (readingRes != null) {
            prevReading = double.tryParse(
                    readingRes['previous_reading']?.toString() ?? '0') ??
                0.0;
            currReading = double.tryParse(
                    readingRes['current_reading']?.toString() ?? '0') ??
                0.0;
            consumption = double.tryParse(
                    readingRes['consumption']?.toString() ??
                        (currReading - prevReading).toString()) ??
                0.0;
          }
        }

        final double amountDue =
            double.tryParse(bill['amount_due']?.toString() ?? '0') ?? 0.0;
        final histories = customerHistories[custId] ?? [consumption];
        final double avgConsumption = histories.isEmpty
            ? 0.0
            : histories.reduce((a, b) => a + b) / histories.length;

        final anomalies = _detectAnomalies(consumption, avgConsumption);

        processedData.add({
          'id': bill['id'],
          'full_name': customer['full_name'] ?? 'Unknown',
          'meter_number': customer['meter_number'] ?? 'N/A',
          'prev_reading': prevReading,
          'curr_reading': currReading,
          'consumption': consumption,
          'amount_due': amountDue,
          'due_date': bill['due_date'] ?? 'N/A',
          'status': bill['status'] ?? 'Unpaid',
          'anomalies': anomalies,
          'is_resolved': false,
        });
      }

      if (mounted) {
        setState(() {
          _reportData = processedData;
          _isLoading = false;
        });
        _applyLocalFilters();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error generating report: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  void _applyLocalFilters() {
    List<Map<String, dynamic>> temp = List.from(_reportData);

    if (_searchQuery.isNotEmpty) {
      temp = temp.where((item) {
        final name = item['full_name'].toString().toLowerCase();
        final meter = item['meter_number'].toString().toLowerCase();
        final query = _searchQuery.toLowerCase();
        return name.contains(query) || meter.contains(query);
      }).toList();
    }

    if (_showAnomaliesOnly) {
      temp =
          temp.where((item) => (item['anomalies'] as List).isNotEmpty).toList();
    }

    _sortData(temp);

    setState(() {
      _filteredReportData = temp;
    });
  }

  void _sortData(List<Map<String, dynamic>> dataList) {
    dataList.sort((a, b) {
      int comparison = 0;
      switch (_sortColumnIndex) {
        case 0:
          comparison = a['full_name'].compareTo(b['full_name']);
          break;
        case 1:
          comparison = a['meter_number'].compareTo(b['meter_number']);
          break;
        case 4:
          comparison = (a['consumption'] as double)
              .compareTo(b['consumption'] as double);
          break;
        case 5:
          comparison = a['due_date'].compareTo(b['due_date']);
          break;
        case 6:
          comparison =
              (a['amount_due'] as double).compareTo(b['amount_due'] as double);
          break;
      }
      return _isAscending ? comparison : -comparison;
    });
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _isAscending = ascending;
    });
    _applyLocalFilters();
  }

  void _resolveAnomaly(int index) {
    setState(() {
      _filteredReportData[index]['is_resolved'] = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Anomaly marked as Inspected & Resolved.'),
          backgroundColor: Colors.green),
    );
  }

  Future<void> _exportPdf() async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                  'Aguila Women\'s Waterworks Inc. - Billing & Anomaly Report',
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text(
                  'Period: $_selectedMonth $_selectedYear | Records Count: ${_filteredReportData.length}',
                  style: const pw.TextStyle(fontSize: 12)),
              pw.Divider(),
              pw.SizedBox(height: 10),
              pw.Table.fromTextArray(
                headers: [
                  'Customer Name',
                  'Meter #',
                  'Prev (m³)',
                  'Curr (m³)',
                  'Consumption',
                  'Due Date',
                  'Amount Due',
                  'Anomalies'
                ],
                data: _filteredReportData
                    .map((item) => [
                          item['full_name'],
                          item['meter_number'],
                          item['prev_reading'].toString(),
                          item['curr_reading'].toString(),
                          '${item['consumption']} m³',
                          item['due_date'],
                          '₱${(item['amount_due'] as double).toStringAsFixed(2)}',
                          (item['anomalies'] as List).join(', '),
                        ])
                    .toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey300),
                rowDecoration: const pw.BoxDecoration(
                    border: pw.Border(
                        bottom: pw.BorderSide(color: PdfColors.grey200))),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save());
  }

  void _exportCsv() {
    List<List<dynamic>> rows = [
      [
        'Customer Name',
        'Meter Number',
        'Prev Reading',
        'Curr Reading',
        'Consumption',
        'Due Date',
        'Amount Due',
        'Anomalies'
      ]
    ];

    for (var item in _filteredReportData) {
      rows.add([
        item['full_name'],
        item['meter_number'],
        item['prev_reading'],
        item['curr_reading'],
        item['consumption'],
        item['due_date'],
        item['amount_due'],
        (item['anomalies'] as List).join('; '),
      ]);
    }

    String csvData = const ListToCsvConverter().convert(rows);
    debugPrint('Exported CSV Data:\n$csvData');

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('CSV Data generated and logged to console output!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Aguila Waterworks - Reports Dashboard"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.table_chart), text: "Data Table View"),
            Tab(icon: Icon(Icons.bar_chart), text: "Analytics & Trends"),
            Tab(icon: Icon(Icons.build_circle), text: "Anomaly Audit Workflow"),
          ],
        ),
      ),
      body: Column(
        children: [
          // Filter Section
          Card(
            margin: const EdgeInsets.all(10),
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    SizedBox(
                      width: 130,
                      child: DropdownButtonFormField<String>(
                        value: _selectedMonth,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Month',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        ),
                        items: _months
                            .map((m) => DropdownMenuItem(
                                value: m,
                                child: Text(m,
                                    style: const TextStyle(fontSize: 12))))
                            .toList(),
                        onChanged: (val) =>
                            setState(() => _selectedMonth = val!),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 90,
                      child: DropdownButtonFormField<String>(
                        value: _selectedYear,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Year',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        ),
                        items: _years
                            .map((y) => DropdownMenuItem(
                                value: y,
                                child: Text(y,
                                    style: const TextStyle(fontSize: 12))))
                            .toList(),
                        onChanged: (val) =>
                            setState(() => _selectedYear = val!),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<Map<String, dynamic>?>(
                        value: _selectedCustomer,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Customer Scope',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        ),
                        hint: const Text('All Customers',
                            style: TextStyle(fontSize: 12)),
                        items: [
                          const DropdownMenuItem<Map<String, dynamic>?>(
                              value: null,
                              child: Text('All Customers',
                                  style: TextStyle(fontSize: 12))),
                          ..._customers.map((c) => DropdownMenuItem(
                                value: c,
                                child: Text(
                                    '${c['full_name']} (${c['meter_number']})',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12)),
                              )),
                        ],
                        onChanged: (val) =>
                            setState(() => _selectedCustomer = val),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                      icon: const Icon(Icons.analytics, size: 16),
                      label: const Text('Generate',
                          style: TextStyle(fontSize: 12)),
                      onPressed: _generateReport,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Search Toolbar & Quick Filter Switches
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 2.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search customer or meter #...',
                      prefixIcon: Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                    onChanged: (val) {
                      _searchQuery = val;
                      _applyLocalFilters();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Row(
                  children: [
                    const Text('Anomalies Only',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                    Switch(
                      value: _showAnomaliesOnly,
                      activeColor: Colors.red,
                      onChanged: (val) {
                        setState(() => _showAnomaliesOnly = val);
                        _applyLocalFilters();
                      },
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white),
                  icon: const Icon(Icons.print, size: 16),
                  label: const Text('PDF', style: TextStyle(fontSize: 12)),
                  onPressed: _filteredReportData.isEmpty ? null : _exportPdf,
                ),
                const SizedBox(width: 6),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white),
                  icon: const Icon(Icons.table_rows, size: 16),
                  label: const Text('CSV', style: TextStyle(fontSize: 12)),
                  onPressed: _filteredReportData.isEmpty ? null : _exportCsv,
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // Main TabBar Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      // TAB 1: Sorted DataTable View
                      _filteredReportData.isEmpty
                          ? const Center(
                              child: Text('No matching records found.'))
                          : Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Card(
                                elevation: 2,
                                child: SingleChildScrollView(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: DataTable(
                                      sortColumnIndex: _sortColumnIndex,
                                      sortAscending: _isAscending,
                                      headingRowColor: WidgetStateProperty.all(
                                          Colors.blue.shade50),
                                      columns: [
                                        DataColumn(
                                            label: const Text('Customer Name'),
                                            onSort: _onSort),
                                        DataColumn(
                                            label: const Text('Meter #'),
                                            onSort: _onSort),
                                        const DataColumn(
                                            label: Text('Prev (m³)')),
                                        const DataColumn(
                                            label: Text('Curr (m³)')),
                                        DataColumn(
                                            label: const Text('Consumption'),
                                            onSort: _onSort),
                                        DataColumn(
                                            label: const Text('Due Date'),
                                            onSort: _onSort),
                                        DataColumn(
                                            label: const Text('Amount Due'),
                                            onSort: _onSort),
                                        const DataColumn(label: Text('Status')),
                                      ],
                                      rows: List<DataRow>.generate(
                                          _filteredReportData.length, (index) {
                                        final item = _filteredReportData[index];
                                        final List<String> anomalies =
                                            List<String>.from(
                                                item['anomalies'] ?? []);
                                        final bool hasAnomaly =
                                            anomalies.isNotEmpty;

                                        return DataRow(
                                          color: WidgetStateProperty.all(
                                              hasAnomaly
                                                  ? Colors.red.shade50
                                                  : Colors.white),
                                          cells: [
                                            DataCell(Text(item['full_name'],
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600))),
                                            DataCell(
                                                Text(item['meter_number'])),
                                            DataCell(Text(item['prev_reading']
                                                .toString())),
                                            DataCell(Text(item['curr_reading']
                                                .toString())),
                                            DataCell(Text(
                                                '${item['consumption']} m³',
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.blue))),
                                            DataCell(Text(item['due_date'],
                                                style: const TextStyle(
                                                    color: Colors.redAccent))),
                                            DataCell(Text(
                                                '₱${(item['amount_due'] as double).toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold))),
                                            DataCell(
                                              hasAnomaly
                                                  ? Tooltip(
                                                      message:
                                                          anomalies.join('\n'),
                                                      child: const Row(
                                                        children: [
                                                          Icon(Icons.warning,
                                                              color: Colors.red,
                                                              size: 16),
                                                          SizedBox(width: 4),
                                                          Text('Flagged',
                                                              style: TextStyle(
                                                                  color: Colors
                                                                      .red,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold)),
                                                        ],
                                                      ),
                                                    )
                                                  : const Text('Normal',
                                                      style: TextStyle(
                                                          color: Colors.green)),
                                            ),
                                          ],
                                        );
                                      }),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                      // TAB 2: Visual Analytics & Progress Metrics
                      _filteredReportData.isEmpty
                          ? const Center(
                              child: Text('No analytical data available.'))
                          : Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: ListView(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Card(
                                          color: Colors.blue.shade50,
                                          child: Padding(
                                            padding: const EdgeInsets.all(14.0),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text('Total Consumption',
                                                    style: TextStyle(
                                                        color: Colors.blue,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                                const SizedBox(height: 6),
                                                Text(
                                                  '${_filteredReportData.fold<double>(0, (sum, item) => sum + (item['consumption'] as double))} m³',
                                                  style: const TextStyle(
                                                      fontSize: 20,
                                                      fontWeight:
                                                          FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Card(
                                          color: Colors.green.shade50,
                                          child: Padding(
                                            padding: const EdgeInsets.all(14.0),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text('Total Revenue Due',
                                                    style: TextStyle(
                                                        color: Colors.green,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                                const SizedBox(height: 6),
                                                Text(
                                                  '₱${_filteredReportData.fold<double>(0, (sum, item) => sum + (item['amount_due'] as double)).toStringAsFixed(2)}',
                                                  style: const TextStyle(
                                                      fontSize: 20,
                                                      fontWeight:
                                                          FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Card(
                                          color: Colors.red.shade50,
                                          child: Padding(
                                            padding: const EdgeInsets.all(14.0),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text('Anomalies Flagged',
                                                    style: TextStyle(
                                                        color: Colors.red,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                                const SizedBox(height: 6),
                                                Text(
                                                  '${_filteredReportData.where((item) => (item['anomalies'] as List).isNotEmpty).length}',
                                                  style: const TextStyle(
                                                      fontSize: 20,
                                                      fontWeight:
                                                          FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  const Text(
                                      'Consumption Volume Breakdown per Household',
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 10),
                                  ..._filteredReportData.map((item) {
                                    final double consumption =
                                        item['consumption'];
                                    final double maxVal = 50.0;
                                    final double percentage =
                                        (consumption / maxVal).clamp(0.0, 1.0);
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 6.0),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(item['full_name'],
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w500)),
                                              Text('$consumption m³',
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.blue)),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          LinearProgressIndicator(
                                            value: percentage,
                                            backgroundColor:
                                                Colors.grey.shade200,
                                            color: (item['anomalies'] as List)
                                                    .isNotEmpty
                                                ? Colors.red
                                                : Colors.blue,
                                            minHeight: 8,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),

                      // TAB 3: Anomaly Action & Inspection Workflow
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: ListView.builder(
                          itemCount: _filteredReportData
                              .where((item) =>
                                  (item['anomalies'] as List).isNotEmpty)
                              .length,
                          itemBuilder: (context, index) {
                            final flaggedItems = _filteredReportData
                                .where((item) =>
                                    (item['anomalies'] as List).isNotEmpty)
                                .toList();
                            final item = flaggedItems[index];
                            final bool isResolved =
                                item['is_resolved'] ?? false;

                            return Card(
                              elevation: 2,
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                leading: Icon(
                                  isResolved
                                      ? Icons.check_circle
                                      : Icons.warning_amber_rounded,
                                  color: isResolved ? Colors.green : Colors.red,
                                  size: 32,
                                ),
                                title: Text(item['full_name'],
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                    'Meter: ${item['meter_number']} | Flag: ${(item['anomalies'] as List).join(", ")}'),
                                trailing: isResolved
                                    ? const Chip(
                                        label: Text('Resolved'),
                                        backgroundColor: Colors.greenAccent)
                                    : ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.orange,
                                            foregroundColor: Colors.white),
                                        child: const Text('Resolve'),
                                        onPressed: () => _resolveAnomaly(index),
                                      ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
