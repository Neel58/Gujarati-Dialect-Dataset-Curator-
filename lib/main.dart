import 'package:flutter/material.dart';
import 'services/supabase_service.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'models/contributor.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.init();
  runApp(const GujaratiDialectApp());
}

class GujaratiDialectApp extends StatelessWidget {
  const GujaratiDialectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gujarati Dialect Curator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<Contributor?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = SupabaseService.instance.getOperatorProfile();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Contributor?>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        
        // If they have a profile, go to Home. Otherwise, Login.
        if (snapshot.hasData && snapshot.data != null) {
          return const HomeScreen();
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}