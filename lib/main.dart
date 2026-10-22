import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://hqpseoajvagdfmqocglv.supabase.co',
    publishableKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhxcHNlb2FqdmFnZGZtcW9jZ2x2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIzODEyNzIsImV4cCI6MjEwNzk1NzI3Mn0.Vry60KnrnOO9tndK3RBVrNRSnXMfbherG2e-1pPNviA',
  );

  runApp(const WaterworksApp());
}

class WaterworksApp extends StatelessWidget {
  const WaterworksApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Aguila Women's Waterworks Inc.",
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}
