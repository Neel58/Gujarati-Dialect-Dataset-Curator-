import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  var supabaseUrl = const String.fromEnvironment('SUPABASE_URL');
  var supabaseAnonKey = const String.fromEnvironment('SUPABASE_ANON_KEY');
  
  // Fallback for IDEs that don't pass --dart-define
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    try {
      await dotenv.load(fileName: ".env");
      supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
      supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
    } catch (e) {
      debugPrint('Failed to load .env: $e');
    }
  }

  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    throw Exception('Please provide SUPABASE_URL and SUPABASE_ANON_KEY via --dart-define or .env');
  }

  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseAnonKey,
  );
  
  runApp(const ProviderScope(child: GujaratiDialectApp()));
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

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final session = snapshot.data?.session;
        if (session == null) {
          return const LoginScreen(); // We will rename/update LoginScreen to AuthScreen
        }

        return FutureBuilder<dynamic>(
          future: Supabase.instance.client
              .from('profiles')
              .select()
              .eq('id', session.user.id)
              .maybeSingle(),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            if (profileSnapshot.hasError) {
              return Scaffold(body: Center(child: Text('Error: ${profileSnapshot.error}')));
            }
            
            final data = profileSnapshot.data;
            if (data == null) {
              return const OnboardingScreen();
            } else {
              return const HomeScreen();
            }
          },
        );
      },
    );
  }
}