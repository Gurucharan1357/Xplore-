import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// --- MODULAR SCREENS ---
import 'package:xplore_mobile/screens/explore_screen.dart';
import 'package:xplore_mobile/screens/my_dashboard_screen.dart' hide PublicProfileScreen;
import 'package:xplore_mobile/screens/live_trek_hud_screen.dart';
import 'package:xplore_mobile/services/tracking_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeTrackingService();

  await Supabase.initialize(
    url: 'https://lvkgxsfsvsydfuywphiv.supabase.co',
    anonKey: 'sb_publishable_549oaEIaBH2n8TzYaeQbLw_8kMM9Wzb',
  );

  runApp(const XploreApp());
}

// Inside lib/main.dart
class XploreApp extends StatelessWidget {
  const XploreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Xplore',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F1115),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFD4FF00), // <--- Change this line from Blue to Neon Yellow!
          secondary: Color(0xFFFC4C02),
          surface: Color(0xFF161922),
        ),
        useMaterial3: true,
      ),
      home: const AuthGateway(),
    );
  }
}

// ---------------------------------------------------------------------------
// AUTH GATEWAY & SCREENS
// ---------------------------------------------------------------------------
class AuthGateway extends StatelessWidget {
  const AuthGateway({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) return const RootNavigationShell();
        return const AuthScreen();
      },
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
  bool _isLoading = false;

  Future<void> _handleAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.length < 6) return;
    setState(() => _isLoading = true);

    try {
      if (_isSignUp) {
        await Supabase.instance.client.auth.signUp(email: email, password: password);
      } else {
        await Supabase.instance.client.auth.signInWithPassword(email: email, password: password);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Auth failed: $e'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.terrain, size: 70, color: Color(0xFF007AFF)),
              const SizedBox(height: 12),
              const Text('XPLORE', textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 3, color: Colors.white)),
              const SizedBox(height: 40),
              TextField(controller: _emailController, keyboardType: TextInputType.emailAddress, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: 'Email', filled: true, fillColor: const Color(0xFF161922), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
              const SizedBox(height: 16),
              TextField(controller: _passwordController, obscureText: true, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: 'Password', filled: true, fillColor: const Color(0xFF161922), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
              const SizedBox(height: 24),
              SizedBox(height: 52, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007AFF), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), onPressed: _isLoading ? null : _handleAuth, child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : Text(_isSignUp ? 'Create Account' : 'Sign In', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)))),
              const SizedBox(height: 16),
              TextButton(onPressed: () => setState(() => _isSignUp = !_isSignUp), child: Text(_isSignUp ? 'Already have an account? Sign In' : "Don't have an account? Sign Up", style: const TextStyle(color: Colors.grey))),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ROOT NAVIGATION SHELL
// ---------------------------------------------------------------------------
class RootNavigationShell extends StatefulWidget {
  const RootNavigationShell({super.key});

  @override
  State<RootNavigationShell> createState() => _RootNavigationShellState();
}

class _RootNavigationShellState extends State<RootNavigationShell> {
  int _currentIndex = 1; 
  Map<String, dynamic>? _selectedTrekToFollow;

  void _onSelectTrekFromExplore(Map<String, dynamic> trek) {
    setState(() {
      _selectedTrekToFollow = trek;
      _currentIndex = 1; 
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          ExploreScreen(onSelectTrek: _onSelectTrekFromExplore),
          LiveTrekHudScreen(trekToFollow: _selectedTrekToFollow),
          MyDashboardScreen(onSelectTrek: _onSelectTrekFromExplore),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF12141C),
        indicatorColor: const Color(0xFF007AFF).withValues(alpha: 0.2),
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.explore_outlined, color: Colors.grey), selectedIcon: Icon(Icons.explore, color: Color(0xFF007AFF)), label: 'Explore'),
          NavigationDestination(icon: Icon(Icons.radio_button_checked, color: Colors.grey), selectedIcon: Icon(Icons.radio_button_checked, color: Color(0xFF007AFF)), label: 'Record'),
          NavigationDestination(icon: Icon(Icons.person_outline, color: Colors.grey), selectedIcon: Icon(Icons.person, color: Color(0xFF007AFF)), label: 'Profile'),
        ],
      ),
    );
  }
}