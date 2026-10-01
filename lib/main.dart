import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/**
 * PORTABLECOOK - PRODUCTION APP
 * Features: Multi-modal Fridge, Tiered Video Analysis, RevenueCat IAP, 
 * Smart Reminders, Calendar Events, Video/Image Generation
 */

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize RevenueCat
  await Purchases.configure(
    PurchasesConfiguration('goog_fiSuHJMwkGQCQBaqoZIdirmPFkm'),
  );

  tz.initializeTimeZones();
  // Initialize Notifications
  await _initNotifications();

  runApp(const PortableCookApp());
}

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _initNotifications() async {
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings();
  await notificationsPlugin.initialize(
    const InitializationSettings(android: androidSettings, iOS: iosSettings),
  );
}

class PortableCookApp extends StatelessWidget {
  const PortableCookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PortableCook',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6B35),
          brightness: Brightness.light,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

// === MODELS ===

enum UserTier { free, pro, premium }

class UserSession {
  final String userId;
  final String email;
  int trialsRemaining;
  int imageGenRemaining;
  int videoGenRemaining;
  UserTier tier;
  bool healthyTipsEnabled;

  UserSession({
    required this.userId,
    required this.email,
    this.trialsRemaining = 5,
    this.imageGenRemaining = 0,
    this.videoGenRemaining = 0,
    this.tier = UserTier.free,
    this.healthyTipsEnabled = true,
  });

  factory UserSession.fromJson(Map<String, dynamic> json) => UserSession(
    userId: json['user_id'] ?? '',
    email: json['email'] ?? '',
    trialsRemaining: json['trials_remaining'] ?? 5,
    imageGenRemaining: json['image_gen_remaining'] ?? 0,
    videoGenRemaining: json['video_gen_remaining'] ?? 0,
    tier: UserTier.values.firstWhere(
      (t) => t.toString().split('.').last == (json['tier'] ?? 'free'),
      orElse: () => UserTier.free,
    ),
    healthyTipsEnabled: json['healthy_tips_enabled'] ?? true,
  );

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'email': email,
    'trials_remaining': trialsRemaining,
    'image_gen_remaining': imageGenRemaining,
    'video_gen_remaining': videoGenRemaining,
    'tier': tier.toString().split('.').last,
    'healthy_tips_enabled': healthyTipsEnabled,
  };
}

class CookingEvent {
  final String id;
  final String recipeName;
  final DateTime scheduledDate;
  final String notes;

  CookingEvent({
    required this.id,
    required this.recipeName,
    required this.scheduledDate,
    this.notes = '',
  });

  factory CookingEvent.fromJson(Map<String, dynamic> json) => CookingEvent(
    id: json['id'] ?? '',
    recipeName: json['recipe_name'] ?? '',
    scheduledDate: DateTime.parse(json['scheduled_date']),
    notes: json['notes'] ?? '',
  );
}

// === API SERVICE ===

class ApiService {
  static const String baseUrl =
      'https://portablebook-cmeudedafkdgdxfc.eastus-01.azurewebsites.net'; // Android emulator
  // For iOS simulator: 'http://localhost:5000'
  // For physical device: 'http://YOUR_LOCAL_IP:5000'

  static Future<Map<String, dynamic>> register(
    String email,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> loginWithGoogle(String idToken) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/google'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'id_token': idToken}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/forgot-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getUserProfile(String userId) async {
    final response = await http.get(Uri.parse('$baseUrl/user/$userId/profile'));
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> uploadMedia(
    File file,
    String userId,
    String type,
  ) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/upload'),
    );
    request.fields['user_id'] = userId;
    request.fields['type'] = type;
    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    var streamedResponse = await request.send();
    var response = await http.Response.fromStream(streamedResponse);
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> analyzeVideo(
    String userId,
    String videoUrl,
    File? videoFile,
  ) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/analyze/video'),
    );
    request.fields['user_id'] = userId;

    if (videoUrl.isNotEmpty) {
      request.fields['video_url'] = videoUrl;
    } else if (videoFile != null) {
      request.files.add(
        await http.MultipartFile.fromPath('video', videoFile.path),
      );
    }

    var streamedResponse = await request.send();
    var response = await http.Response.fromStream(streamedResponse);
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> generateImage(
    String userId,
    String prompt,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/generate/image'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId, 'prompt': prompt}),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> generateVideo(
    String userId,
    String prompt,
    File? imageFile,
  ) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/generate/video'),
    );
    request.fields['user_id'] = userId;
    request.fields['prompt'] = prompt;

    if (imageFile != null) {
      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path),
      );
    }

    var streamedResponse = await request.send();
    var response = await http.Response.fromStream(streamedResponse);
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> analyzeFridge(
    String userId,
    String prompt,
    File? mediaFile,
    String mediaType,
  ) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/fridge/analyze'),
    );
    request.fields['user_id'] = userId;
    request.fields['prompt'] = prompt;
    request.fields['media_type'] = mediaType;

    if (mediaFile != null) {
      request.files.add(
        await http.MultipartFile.fromPath('media', mediaFile.path),
      );
    }

    var streamedResponse = await request.send();
    var response = await http.Response.fromStream(streamedResponse);
    return jsonDecode(response.body);
  }

  static Future<List<CookingEvent>> getCookingEvents(String userId) async {
    final response = await http.get(Uri.parse('$baseUrl/user/$userId/events'));
    final List<dynamic> data = jsonDecode(response.body)['events'];
    return data.map((e) => CookingEvent.fromJson(e)).toList();
  }

  static Future<void> saveCookingEvent(
    String userId,
    CookingEvent event,
  ) async {
    await http.post(
      Uri.parse('$baseUrl/user/$userId/events'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'recipe_name': event.recipeName,
        'scheduled_date': event.scheduledDate.toIso8601String(),
        'notes': event.notes,
      }),
    );
  }
}

// === AUTH WRAPPER ===

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  UserSession? session;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user_session');

    if (userData != null) {
      setState(() {
        session = UserSession.fromJson(jsonDecode(userData));
        isLoading = false;
      });
    } else {
      setState(() => isLoading = false);
    }
  }

  void handleAuth(UserSession user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_session', jsonEncode(user.toJson()));
    setState(() => session = user);

    // === SYNC WITH REVENUECAT ===
    try {
      await Purchases.logIn(user.userId);
      await Purchases.setEmail(user.email);

      // UPDATE THIS STRING FOR EACH APP:
      await Purchases.setAttributes({
        'app_name':
            'PortableCook', // Change to 'MumWise', 'AICoach', 'PacksLight', etc.
        'signup_tier': user.tier.toString(),
      });
    } catch (e) {
      debugPrint('RevenueCat user sync error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return session == null
        ? LoginScreen(onSuccess: handleAuth)
        : MainNavigation(
          user: session!,
          onSessionUpdate: (u) => setState(() => session = u),
        );
  }
}

// === LOGIN SCREEN ===

class LoginScreen extends StatefulWidget {
  final Function(UserSession) onSuccess;
  const LoginScreen({super.key, required this.onSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool isLogin = true;
  bool isLoading = false;
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email']);

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    try {
      final response =
          isLogin
              ? await ApiService.login(
                _emailController.text,
                _passController.text,
              )
              : await ApiService.register(
                _emailController.text,
                _passController.text,
              );

      if (response['success'] == true) {
        widget.onSuccess(UserSession.fromJson(response['user']));
      } else {
        _showError(response['message'] ?? 'Authentication failed');
      }
    } catch (e) {
      _showError('Network error. Please check your connection.');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account != null) {
        final auth = await account.authentication;
        final response = await ApiService.loginWithGoogle(auth.idToken!);

        if (response['success'] == true) {
          widget.onSuccess(UserSession.fromJson(response['user']));
        }
      }
    } catch (e) {
      _showError('Google sign-in failed');
    }
  }

  Future<void> _forgotPassword() async {
    if (_emailController.text.isEmpty) {
      _showError('Please enter your email');
      return;
    }

    try {
      final response = await ApiService.forgotPassword(_emailController.text);
      _showError(
        response['message'] ?? 'Password reset link sent',
        isError: false,
      );
    } catch (e) {
      _showError('Failed to send reset link');
    }
  }

  void _showError(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.orange.shade700, Colors.deepOrange.shade400],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.restaurant_menu,
                      size: 80,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'PortableCook',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Text(
                      'Your AI Cooking Companion',
                      style: TextStyle(fontSize: 16, color: Colors.white70),
                    ),
                    const SizedBox(height: 48),

                    // Email Field
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.black87),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'Email',
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      validator:
                          (v) => v!.contains('@') ? null : 'Invalid email',
                    ),
                    const SizedBox(height: 16),

                    // Password Field
                    TextFormField(
                      controller: _passController,
                      obscureText: true,
                      style: const TextStyle(color: Colors.black87),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      validator:
                          (v) => v!.length >= 6 ? null : 'Min 6 characters',
                    ),

                    if (isLogin) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _forgotPassword,
                          child: const Text(
                            'Forgot Password?',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.orange.shade700,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child:
                            isLoading
                                ? const CircularProgressIndicator()
                                : Text(
                                  isLogin ? 'Login' : 'Register',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Toggle Login/Register
                    TextButton(
                      onPressed: () => setState(() => isLogin = !isLogin),
                      child: Text(
                        isLogin
                            ? 'New Chef? Create Account'
                            : 'Have an account? Login',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),

                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        children: [
                          Expanded(child: Divider(color: Colors.white54)),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'OR',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                          Expanded(child: Divider(color: Colors.white54)),
                        ],
                      ),
                    ),

                    // Google Sign In
                    OutlinedButton.icon(
                      onPressed: _loginWithGoogle,
                      icon: const Icon(Icons.g_mobiledata, size: 28),
                      label: const Text('Continue with Google'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white),
                        minimumSize: const Size(double.infinity, 56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
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

// === MAIN NAVIGATION ===

class MainNavigation extends StatefulWidget {
  final UserSession user;
  final Function(UserSession) onSessionUpdate;

  const MainNavigation({
    super.key,
    required this.user,
    required this.onSessionUpdate,
  });

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _updatePages();
  }

  @override
  void didUpdateWidget(MainNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user != widget.user) {
      _updatePages();
    }
  }

  void _updatePages() {
    _pages = [
      HomeScreen(user: widget.user),
      VirtualFridgeScreen(user: widget.user, onUpdate: widget.onSessionUpdate),
      GenerateScreen(user: widget.user, onUpdate: widget.onSessionUpdate),
      AnalyzeScreen(user: widget.user, onUpdate: widget.onSessionUpdate),
      UpgradeScreen(user: widget.user, onUpdate: widget.onSessionUpdate),
      ProfileScreen(user: widget.user, onUpdate: widget.onSessionUpdate),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.kitchen_outlined),
            selectedIcon: Icon(Icons.kitchen),
            label: 'Fridge',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Generate',
          ),
          NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            selectedIcon: Icon(Icons.video_library),
            label: 'Analyze',
          ),
          NavigationDestination(
            icon: Icon(Icons.workspace_premium_outlined),
            selectedIcon: Icon(Icons.workspace_premium),
            label: 'Upgrade',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// === HOME SCREEN ===

class HomeScreen extends StatefulWidget {
  final UserSession user;
  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String selectedCategory = 'All';

  final List<String> categories = [
    'All',
    'Appetizers',
    'Main Dishes',
    'Sides',
    'Desserts',
    'Beverages',
  ];
  final List<Map<String, dynamic>> recipes = [
    {
      'title': 'Fried Egg & Meatloaf',
      'category': 'Main Dishes',
      'image':
          'https://images.unsplash.com/photo-1525351484163-7529414344d8?q=80&w=1000&auto=format&fit=crop',
      'time': '25 min',
      'difficulty': 'Medium',
      'ingredients': [
        '2 eggs',
        '300g ground beef',
        '1 onion',
        'Breadcrumbs',
        'Mustard',
        'Salt & Pepper',
      ],
      'steps': [
        '🔥 Preheat oven to 180°C (350°F)',
        '🥩 Mix ground beef with finely chopped onion, breadcrumbs, and seasonings',
        '👐 Shape mixture into a loaf and place in baking dish',
        '🍳 Bake for 20 minutes until cooked through',
        '🥚 Fry eggs sunny-side up in a separate pan',
        '🍽️ Slice meatloaf and top with fried eggs. Serve with mustard!',
      ],
    },
    {
      'title': 'Queen Cake',
      'category': 'Desserts',
      'image':
          'https://images.unsplash.com/photo-1519915028121-7d3463d20b13?q=80&w=1000&auto=format&fit=crop',
      'time': '45 min',
      'difficulty': 'Easy',
      'ingredients': [
        '200g flour',
        '150g sugar',
        '3 eggs',
        '100g butter',
        'Vanilla extract',
        'Baking powder',
      ],
      'steps': [
        '🔥 Preheat oven to 170°C (340°F)',
        '🧈 Cream butter and sugar until fluffy',
        '🥚 Beat in eggs one at a time',
        '🍰 Fold in flour and baking powder gently',
        '🎂 Pour into greased cake tin',
        '⏰ Bake for 35-40 minutes until golden',
        '✨ Cool and dust with powdered sugar',
      ],
    },
    {
      'title': 'Veggie Skewer',
      'category': 'Sides',
      'image':
          'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?q=80&w=1000&auto=format&fit=crop',
      'time': '15 min',
      'difficulty': 'Easy',
      'ingredients': [
        'Bell peppers',
        'Zucchini',
        'Cherry tomatoes',
        'Mushrooms',
        'Olive oil',
        'Paprika',
      ],
      'steps': [
        '🔪 Cut vegetables into 2-inch chunks',
        '🌶️ Season with olive oil, paprika, salt',
        '🍢 Thread onto skewers alternating colors',
        '🔥 Grill for 10-12 minutes, turning occasionally',
        '🌿 Garnish with fresh herbs and serve hot!',
      ],
    },
    {
      'title': 'Hamburger Sandwich',
      'category': 'Main Dishes',
      'image':
          'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?q=80&w=1000&auto=format&fit=crop',
      'time': '20 min',
      'difficulty': 'Easy',
      'ingredients': [
        'Burger buns',
        '200g ground beef',
        'Lettuce',
        'Tomato',
        'Cheese',
        'Pickles',
        'Sauce',
      ],
      'steps': [
        '🥩 Form beef into patties and season well',
        '🔥 Heat grill or pan to medium-high',
        '🍔 Cook patties 4 minutes each side',
        '🧀 Add cheese in last minute',
        '🍞 Toast buns lightly',
        '🥬 Layer: sauce, patty, lettuce, tomato, pickles',
        '😋 Serve immediately with fries!',
      ],
    },
    {
      'title': 'Pancake Crepes',
      'category': 'Appetizers',
      'image':
          'https://images.unsplash.com/photo-1567620905732-2d1ec7bb7445?q=80&w=1000&auto=format&fit=crop',
      'time': '30 min',
      'difficulty': 'Medium',
      'ingredients': [
        '200g flour',
        '2 eggs',
        '400ml milk',
        'Butter',
        'Sugar',
        'Lemon juice',
      ],
      'steps': [
        '🥣 Whisk flour, eggs, and milk until smooth',
        '⏰ Let batter rest for 15 minutes',
        '🍳 Heat non-stick pan with butter',
        '🥞 Pour thin layer of batter and swirl',
        '⏱️ Cook 1 minute each side until golden',
        '🍋 Serve with sugar and lemon juice',
        '✨ Roll or fold as desired!',
      ],
    },
  ];

  List<Map<String, dynamic>> get filteredRecipes {
    if (selectedCategory == 'All') return recipes;
    return recipes.where((r) => r['category'] == selectedCategory).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'PortableCook',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Chip(
              avatar: const Icon(Icons.bolt, size: 18),
              label: Text(
                '${widget.user.trialsRemaining} Trials',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.orange.shade100,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Refresh user data from backend
          setState(() {});
        },
        child: ListView(
          children: [
            _buildHeroSection(),
            _buildCategoryFilter(),
            _buildRecipeGrid(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroSection() {
    return Container(
      height: 200,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        image: const DecorationImage(
          image: NetworkImage(
            'https://images.unsplash.com/photo-1556910103-1c02745aae4d?w=800',
          ),
          fit: BoxFit.cover,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome, Chef ${widget.user.email.split('@')[0]}!',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Let\'s create something delicious today',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSelected = category == selectedCategory;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(category),
              selected: isSelected,
              onSelected: (selected) {
                setState(() => selectedCategory = category);
              },
              backgroundColor: Colors.grey.shade200,
              selectedColor: Theme.of(context).colorScheme.primary,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecipeGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: filteredRecipes.length,
      itemBuilder: (context, index) {
        final recipe = filteredRecipes[index];
        return _RecipeCard(recipe: recipe);
      },
    );
  }
}

class _RecipeCard extends StatelessWidget {
  final Map<String, dynamic> recipe;

  const _RecipeCard({required this.recipe});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RecipeDetailScreen(recipe: recipe),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: recipe['image'],
                    fit: BoxFit.cover,
                    placeholder:
                        (_, __) => Container(color: Colors.grey.shade300),
                    errorWidget:
                        (_, __, ___) => Container(
                          color: Colors.grey.shade300,
                          child: const Icon(Icons.restaurant),
                        ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.timer,
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            recipe['time'],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipe['title'],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.restaurant_menu,
                        size: 14,
                        color: Colors.green.shade700,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          recipe['category'],
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green.shade700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// === RECIPE DETAIL SCREEN ===

class RecipeDetailScreen extends StatelessWidget {
  final Map<String, dynamic> recipe;

  const RecipeDetailScreen({super.key, required this.recipe});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                recipe['title'],
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: recipe['image'],
                    fit: BoxFit.cover,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.7),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _InfoChip(icon: Icons.timer, label: recipe['time']),
                      const SizedBox(width: 8),
                      _InfoChip(
                        icon: Icons.signal_cellular_alt,
                        label: recipe['difficulty'],
                      ),
                      const SizedBox(width: 8),
                      _InfoChip(
                        icon: Icons.restaurant_menu,
                        label: recipe['category'],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  const Text(
                    'Ingredients',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ...List.generate(
                    recipe['ingredients'].length,
                    (index) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            size: 20,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              recipe['ingredients'][index],
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Text(
                    'Instructions',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ...List.generate(
                    recipe['steps'].length,
                    (index) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              recipe['steps'][index],
                              style: const TextStyle(fontSize: 16, height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: Colors.orange.shade50,
    );
  }
}

// === VIRTUAL FRIDGE SCREEN ===

class VirtualFridgeScreen extends StatefulWidget {
  final UserSession user;
  final Function(UserSession) onUpdate;

  const VirtualFridgeScreen({
    super.key,
    required this.user,
    required this.onUpdate,
  });

  @override
  State<VirtualFridgeScreen> createState() => _VirtualFridgeScreenState();
}

class _VirtualFridgeScreenState extends State<VirtualFridgeScreen> {
  final _promptController = TextEditingController();
  File? _selectedMedia;
  String _mediaType = '';
  bool _isProcessing = false;
  bool _setReminder = false;

  Future<void> _pickMedia(String type) async {
    if (type == 'image') {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          _selectedMedia = File(pickedFile.path);
          _mediaType = 'image';
        });
      }
    } else if (type == 'video') {
      final picker = ImagePicker();
      final pickedFile = await picker.pickVideo(source: ImageSource.gallery);
      if (pickedFile != null) {
        final fileSize = await pickedFile.length();
        final maxSize =
            widget.user.tier == UserTier.free
                ? 5 * 1024 * 1024
                : widget.user.tier == UserTier.pro
                ? 15 * 1024 * 1024
                : 60 * 1024 * 1024;

        if (fileSize > maxSize) {
          _showError('Video exceeds size limit for your tier');
          return;
        }

        setState(() {
          _selectedMedia = File(pickedFile.path);
          _mediaType = 'video';
        });
      }
    }
  }

  Future<void> _analyzeContent(String action) async {
    if (_promptController.text.isEmpty && _selectedMedia == null) {
      _showError('Please provide text or media');
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final response = await ApiService.analyzeFridge(
        widget.user.userId,
        _promptController.text,
        _selectedMedia,
        _mediaType,
      );

      if (response['success'] == true) {
        _showResults(action, response['data']);
      } else {
        _showError(response['message'] ?? 'Analysis failed');
      }
    } catch (e) {
      _showError('Network error occurred');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _showResults(String action, Map<String, dynamic> data) {
    String title =
        action == 'meal'
            ? '🍳 Potential Meals'
            : action == 'grocery'
            ? '🛒 Grocery List'
            : '⏰ Reminder Set';

    String content =
        action == 'meal'
            ? (data['meals'] as List).map((m) => '• $m').join('\n')
            : action == 'grocery'
            ? (data['items'] as List).map((i) => '• $i').join('\n')
            : data['message'] ?? 'Reminder saved successfully';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            minChildSize: 0.4,
            expand: false,
            builder:
                (context, scrollController) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: scrollController,
                          child: Text(
                            content,
                            style: const TextStyle(fontSize: 16, height: 1.5),
                          ),
                        ),
                      ),
                      if (action == 'meal') ...[
                        const SizedBox(height: 16),
                        SwitchListTile(
                          title: const Text('Add to Cooking Calendar?'),
                          value: _setReminder,
                          onChanged: (v) => setState(() => _setReminder = v),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Done'),
                        ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Smart Virtual Fridge')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.kitchen, size: 80, color: Colors.orange),
            const SizedBox(height: 16),
            const Text(
              'Your AI Kitchen Assistant',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Upload a photo of your fridge or describe what you have',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),

            if (_selectedMedia != null) ...[
              Container(
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.grey.shade200,
                ),
                child:
                    _mediaType == 'image'
                        ? ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.file(_selectedMedia!, fit: BoxFit.cover),
                        )
                        : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.video_library, size: 48),
                              Text(
                                'Video selected: ${_selectedMedia!.path.split('/').last}',
                              ),
                            ],
                          ),
                        ),
              ),
              const SizedBox(height: 16),
            ],

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _MediaButton(
                  icon: Icons.camera_alt,
                  label: 'Photo',
                  onTap: () => _pickMedia('image'),
                ),
                _MediaButton(
                  icon: Icons.videocam,
                  label: 'Video',
                  onTap: () => _pickMedia('video'),
                ),
                _MediaButton(
                  icon: Icons.mic,
                  label: 'Audio',
                  onTap: () {
                    // Audio recording would go here
                    _showError('Audio recording coming soon!');
                  },
                ),
              ],
            ),

            const SizedBox(height: 24),
            TextField(
              controller: _promptController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText:
                    'What would you like to do?\n\nExamples:\n• Generate meal ideas\n• Create grocery list\n• Store items for 10 days',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),

            const SizedBox(height: 24),

            if (_isProcessing)
              const Center(child: CircularProgressIndicator())
            else ...[
              _ActionButton(
                label: 'Generate Potential Meals 🍳',
                color: Colors.green,
                onPressed: () => _analyzeContent('meal'),
              ),
              const SizedBox(height: 12),
              _ActionButton(
                label: 'Generate Grocery List 🛒',
                color: Colors.orange,
                onPressed: () => _analyzeContent('grocery'),
              ),
              const SizedBox(height: 12),
              _ActionButton(
                label: 'Set Perishable Alert ⏰',
                color: Colors.blue,
                onPressed: () => _analyzeContent('reminder'),
              ),
            ],

            const SizedBox(height: 32),
            Card(
              color: Colors.yellow.shade100,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.lightbulb, color: Colors.orange),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Pro Tip: Be specific in your prompts for better results!',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MediaButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: Colors.orange),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
}

// === GENERATE SCREEN (Video/Image) ===

class GenerateScreen extends StatefulWidget {
  final UserSession user;
  final Function(UserSession) onUpdate;

  const GenerateScreen({super.key, required this.user, required this.onUpdate});

  @override
  State<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends State<GenerateScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _promptController = TextEditingController();
  File? _inputImage;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _inputImage = File(pickedFile.path));
    }
  }

  Future<void> _generateImage() async {
    if (widget.user.imageGenRemaining <= 0 &&
        widget.user.trialsRemaining <= 0) {
      _showUpgradePrompt();
      return;
    }

    if (_promptController.text.isEmpty) {
      _showError('Please enter a prompt');
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final response = await ApiService.generateImage(
        widget.user.userId,
        _promptController.text,
      );

      if (response['success'] == true) {
        // Update credits
        if (widget.user.imageGenRemaining > 0) {
          widget.user.imageGenRemaining--;
        } else {
          widget.user.trialsRemaining--;
        }
        widget.onUpdate(widget.user);

        _showSuccess('Image generated! Check your gallery.');
      } else {
        _showError(response['message'] ?? 'Generation failed');
      }
    } catch (e) {
      _showError('Network error occurred');
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _generateVideo() async {
    if (widget.user.videoGenRemaining <= 0 &&
        widget.user.trialsRemaining <= 0) {
      _showUpgradePrompt();
      return;
    }

    if (_promptController.text.isEmpty) {
      _showError('Please enter a prompt');
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final response = await ApiService.generateVideo(
        widget.user.userId,
        _promptController.text,
        _inputImage,
      );

      if (response['success'] == true) {
        // Update credits
        if (widget.user.videoGenRemaining > 0) {
          widget.user.videoGenRemaining--;
        } else {
          widget.user.trialsRemaining--;
        }
        widget.onUpdate(widget.user);

        _showSuccess('Video generated! Check your gallery.');
      } else {
        _showError(response['message'] ?? 'Generation failed');
      }
    } catch (e) {
      _showError('Network error occurred');
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  void _showUpgradePrompt() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Out of Credits'),
            content: const Text(
              'You\'ve used all your credits. Upgrade to Pro or Premium to continue!',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  // Navigate to upgrade screen (handled by bottom nav)
                },
                child: const Text('Upgrade Now'),
              ),
            ],
          ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Generation'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Image Walkthrough', icon: Icon(Icons.image)),
            Tab(text: 'Video Tutorial', icon: Icon(Icons.video_library)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildImageTab(), _buildVideoTab()],
      ),
    );
  }

  Widget _buildImageTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.auto_awesome, size: 80, color: Colors.purple),
          const SizedBox(height: 16),
          const Text(
            'Generate Cooking Walkthrough',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Credits: ${widget.user.imageGenRemaining > 0 ? widget.user.imageGenRemaining : widget.user.trialsRemaining}',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 32),

          TextField(
            controller: _promptController,
            maxLines: 5,
            decoration: InputDecoration(
              hintText:
                  'Describe the cooking steps you want visualized...\n\nExample: "Step-by-step guide to making chocolate cake with mixing, baking, and decoration"',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),

          const SizedBox(height: 24),

          if (_isGenerating)
            const Center(child: CircularProgressIndicator())
          else
            ElevatedButton.icon(
              onPressed: _generateImage,
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Generate Image Walkthrough'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
            ),

          const SizedBox(height: 24),
          Card(
            color: Colors.purple.shade50,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tips_and_updates, color: Colors.purple),
                      SizedBox(width: 8),
                      Text(
                        'Tips for better results:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text('• Be specific about each cooking step'),
                  Text('• Mention ingredients and tools'),
                  Text('• Describe the final presentation'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.play_circle_outline, size: 80, color: Colors.red),
          const SizedBox(height: 16),
          const Text(
            'Generate Cooking Video',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Credits: ${widget.user.videoGenRemaining > 0 ? widget.user.videoGenRemaining : widget.user.trialsRemaining}',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 32),

          if (_inputImage != null) ...[
            Container(
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                image: DecorationImage(
                  image: FileImage(_inputImage!),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          OutlinedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.add_photo_alternate),
            label: const Text('Add Starting Image (Optional)'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),

          const SizedBox(height: 16),

          TextField(
            controller: _promptController,
            maxLines: 5,
            decoration: InputDecoration(
              hintText:
                  'Describe the cooking video you want...\n\nExample: "Chef preparing pasta carbonara, showing boiling pasta, frying bacon, mixing eggs, and plating"',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),

          const SizedBox(height: 24),

          if (_isGenerating)
            const Center(child: CircularProgressIndicator())
          else
            ElevatedButton.icon(
              onPressed: _generateVideo,
              icon: const Icon(Icons.videocam),
              label: const Text('Generate Video Tutorial'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _promptController.dispose();
    super.dispose();
  }
}

// === ANALYZE SCREEN ===

class AnalyzeScreen extends StatefulWidget {
  final UserSession user;
  final Function(UserSession) onUpdate;

  const AnalyzeScreen({super.key, required this.user, required this.onUpdate});

  @override
  State<AnalyzeScreen> createState() => _AnalyzeScreenState();
}

class _AnalyzeScreenState extends State<AnalyzeScreen> {
  final _urlController = TextEditingController();
  File? _videoFile;
  bool _isAnalyzing = false;

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final fileSize = await file.length();

      int maxSize;
      switch (widget.user.tier) {
        case UserTier.free:
          maxSize = 5 * 1024 * 1024; // 5MB
          break;
        case UserTier.pro:
          maxSize = 15 * 1024 * 1024; // 15MB
          break;
        case UserTier.premium:
          maxSize = 60 * 1024 * 1024; // 60MB
          break;
      }

      if (fileSize > maxSize) {
        _showError(
          'Video exceeds ${maxSize ~/ (1024 * 1024)}MB limit for ${widget.user.tier.toString().split('.').last} tier',
        );
        return;
      }

      setState(() => _videoFile = file);
    }
  }

  Future<void> _analyze() async {
    if (widget.user.trialsRemaining <= 0) {
      _showUpgradePrompt();
      return;
    }

    if (_urlController.text.isEmpty && _videoFile == null) {
      _showError('Please provide a video URL or upload a video');
      return;
    }

    setState(() => _isAnalyzing = true);

    try {
      final response = await ApiService.analyzeVideo(
        widget.user.userId,
        _urlController.text,
        _videoFile,
      );

      if (response['success'] == true) {
        widget.user.trialsRemaining--;
        widget.onUpdate(widget.user);

        _showResults(response['data']);
      } else {
        _showError(response['message'] ?? 'Analysis failed');
      }
    } catch (e) {
      _showError('Network error occurred');
    } finally {
      setState(() => _isAnalyzing = false);
    }
  }

  void _showResults(Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.7,
            maxChildSize: 0.95,
            minChildSize: 0.5,
            expand: false,
            builder:
                (context, scrollController) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Analysis Results',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          children: [
                            _ResultSection(
                              title: 'Recipe Title',
                              content: data['title'] ?? 'Untitled Recipe',
                            ),
                            _ResultSection(
                              title: 'Ingredients',
                              content:
                                  (data['ingredients'] as List?)?.join(
                                    '\n• ',
                                  ) ??
                                  'No ingredients detected',
                            ),
                            _ResultSection(
                              title: 'Instructions',
                              content:
                                  (data['steps'] as List?)
                                      ?.asMap()
                                      .entries
                                      .map((e) => '${e.key + 1}. ${e.value}')
                                      .join('\n\n') ??
                                  'No instructions detected',
                            ),
                            _ResultSection(
                              title: 'Cooking Time',
                              content: data['cooking_time'] ?? 'Not specified',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Save to My Recipes'),
                        ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  void _showUpgradePrompt() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Out of Credits'),
            content: const Text(
              'You\'ve used all your analysis credits. Upgrade to continue!',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Upgrade'),
              ),
            ],
          ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Video Analysis')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.analytics, size: 80, color: Colors.blue),
            const SizedBox(height: 16),
            const Text(
              'AI Recipe Extraction',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Trials Remaining: ${widget.user.trialsRemaining}',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 32),

            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: 'YouTube URL',
                hintText: 'https://youtube.com/watch?v=...',
                prefixIcon: const Icon(Icons.link),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('OR'),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
            ),

            if (_videoFile != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.video_file, size: 32, color: Colors.blue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Video selected',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            _videoFile!.path.split('/').last,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _videoFile = null),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            OutlinedButton.icon(
              onPressed: _pickVideo,
              icon: const Icon(Icons.upload_file),
              label: Text(
                'Upload Video (Max ${widget.user.tier == UserTier.free
                    ? '5'
                    : widget.user.tier == UserTier.pro
                    ? '15'
                    : '60'}MB)',
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),

            const SizedBox(height: 32),

            if (_isAnalyzing)
              const Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Analyzing video with Gemini 3 Flash...'),
                ],
              )
            else
              ElevatedButton.icon(
                onPressed: _analyze,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Analyze Recipe (1 Trial)'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),

            const SizedBox(height: 24),
            Card(
              color: Colors.blue.shade50,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue),
                        SizedBox(width: 8),
                        Text(
                          'How it works:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text('1. Upload a cooking video or paste YouTube link'),
                    Text('2. Our AI extracts ingredients & steps'),
                    Text('3. Save to your recipe collection'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }
}

class _ResultSection extends StatelessWidget {
  final String title;
  final String content;

  const _ResultSection({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(content, style: const TextStyle(fontSize: 16, height: 1.5)),
        ],
      ),
    );
  }
}

// === UPGRADE SCREEN ===

class UpgradeScreen extends StatefulWidget {
  final UserSession user;
  final Function(UserSession) onUpdate;

  const UpgradeScreen({super.key, required this.user, required this.onUpdate});

  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> {
  bool _isProcessing = false;

  Future<void> _purchaseSubscription(String productId) async {
    setState(() => _isProcessing = true);

    try {
      // RevenueCat purchase flow
      final offerings = await Purchases.getOfferings();
      if (offerings.current != null) {
        final package = offerings.current!.availablePackages.firstWhere(
          (p) => p.identifier == productId,
        );

        final purchaserInfo = await Purchases.purchasePackage(package);

        if (purchaserInfo.customerInfo.entitlements.all[productId]?.isActive ??
            false) {
          // Update user tier based on purchase
          if (productId.contains('pro')) {
            widget.user.tier = UserTier.pro;
            widget.user.imageGenRemaining = 11;
            widget.user.videoGenRemaining = 11;
          } else if (productId.contains('premium')) {
            widget.user.tier = UserTier.premium;
            widget.user.imageGenRemaining = 20;
            widget.user.videoGenRemaining = 20;
          }

          widget.onUpdate(widget.user);
          _showSuccess('Subscription activated!');
        }
      }
    } catch (e) {
      _showError('Purchase failed: ${e.toString()}');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _purchaseCredits(String productId, int credits) async {
    setState(() => _isProcessing = true);

    try {
      final offerings = await Purchases.getOfferings();
      if (offerings.current != null) {
        final package = offerings.current!.availablePackages.firstWhere(
          (p) => p.identifier == productId,
        );

        await Purchases.purchasePackage(package);

        // Add credits
        widget.user.trialsRemaining += credits;
        widget.onUpdate(widget.user);
        _showSuccess('$credits credits added!');
      }
    } catch (e) {
      _showError('Purchase failed: ${e.toString()}');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upgrade')),
      body:
          _isProcessing
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.workspace_premium,
                      size: 80,
                      color: Colors.amber,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Become a Master Chef',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Unlock unlimited AI-powered cooking',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 32),

                    // Current Tier Badge
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.stars, color: Colors.orange),
                          const SizedBox(width: 8),
                          Text(
                            'Current: ${widget.user.tier.toString().split('.').last.toUpperCase()}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),
                    const Text(
                      'Monthly Subscriptions',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    _SubscriptionCard(
                      title: 'Pro Plan',
                      price: '\$25/month',
                      features: const [
                        '11 Image Generations',
                        '11 Video Generations',
                        '15MB Video Uploads',
                        'Priority Support',
                      ],
                      color: Colors.blue,
                      onTap: () => _purchaseSubscription('pro'),
                    ),

                    const SizedBox(height: 16),

                    _SubscriptionCard(
                      title: 'Premium Plan',
                      price: '\$35/month',
                      features: const [
                        '20 Image Generations',
                        '20 Video Generations',
                        '60MB Video Uploads',
                        'Unlimited Analysis',
                        'Premium Support',
                        'Early Access to Features',
                      ],
                      color: Colors.purple,
                      onTap: () => _purchaseSubscription('premium'),
                      recommended: true,
                    ),

                    const SizedBox(height: 32),
                    const Text(
                      'One-Time Credit Packs',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    _CreditPackCard(
                      title: 'Sous Chef Pack',
                      credits: 25,
                      price: '\$40',
                      onTap: () => _purchaseCredits('credits_25', 25),
                    ),

                    const SizedBox(height: 12),

                    _CreditPackCard(
                      title: 'Prep Pack',
                      credits: 10,
                      price: '\$15',
                      onTap: () => _purchaseCredits('credits_10', 10),
                    ),

                    const SizedBox(height: 32),
                    Card(
                      color: Colors.green.shade50,
                      child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.security, color: Colors.green),
                                SizedBox(width: 8),
                                Text(
                                  'Secure Payments',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Text('• Cancel anytime, no questions asked'),
                            Text('• Powered by RevenueCat & App Store'),
                            Text('• 100% secure payment processing'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  final String title;
  final String price;
  final List<String> features;
  final Color color;
  final VoidCallback onTap;
  final bool recommended;

  const _SubscriptionCard({
    required this.title,
    required this.price,
    required this.features,
    required this.color,
    required this.onTap,
    this.recommended = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Card(
          elevation: recommended ? 8 : 2,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            price,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Icon(Icons.arrow_forward, color: color),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ...features.map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, size: 20, color: color),
                          const SizedBox(width: 8),
                          Expanded(child: Text(f)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (recommended)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'RECOMMENDED',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CreditPackCard extends StatelessWidget {
  final String title;
  final int credits;
  final String price;
  final VoidCallback onTap;

  const _CreditPackCard({
    required this.title,
    required this.credits,
    required this.price,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.orange,
          child: Icon(Icons.add_shopping_cart, color: Colors.white),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('$credits Analysis Credits'),
        trailing: Text(
          price,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.green,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

// === PROFILE SCREEN ===

class ProfileScreen extends StatefulWidget {
  final UserSession user;
  final Function(UserSession) onUpdate;

  const ProfileScreen({super.key, required this.user, required this.onUpdate});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<CookingEvent> _events = [];
  bool _isLoadingEvents = false;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoadingEvents = true);
    try {
      final events = await ApiService.getCookingEvents(widget.user.userId);
      setState(() => _events = events);
    } catch (e) {
      // Handle error
    } finally {
      setState(() => _isLoadingEvents = false);
    }
  }

  Future<void> _scheduleEvent() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _EventDialog(),
    );

    if (result != null) {
      final event = CookingEvent(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        recipeName: result['recipe'] as String,
        scheduledDate: result['date'] as DateTime,
        notes: result['notes'] as String? ?? '',
      );

      await ApiService.saveCookingEvent(widget.user.userId, event);
      _loadEvents();

      // Schedule local notification
      await _scheduleNotification(event);
    }
  }

  Future<void> _scheduleNotification(CookingEvent event) async {
    await notificationsPlugin.zonedSchedule(
      event.id.hashCode,
      'Time to Cook!',
      'Don\'t forget: ${event.recipeName}',
      // FIX 1: Convert DateTime to TZDateTime using tz.local
      tz.TZDateTime.from(event.scheduledDate, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'cooking_events',
          'Cooking Events',
          channelDescription: 'Notifications for scheduled cooking events',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      // FIX 2: Use androidScheduleMode (this replaces the old interpretation param)
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      // REMOVE: uiLocalNotificationDateInterpretation (it's no longer needed in v17+)
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_session');

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthWrapper()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const CircleAvatar(radius: 50, child: Icon(Icons.person, size: 50)),
          const SizedBox(height: 16),
          Text(
            widget.user.email,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Center(
            child: Chip(
              label: Text(
                '${widget.user.tier.toString().split('.').last.toUpperCase()} TIER',
              ),
              backgroundColor: Colors.orange.shade100,
            ),
          ),

          const SizedBox(height: 32),

          // Credits Overview
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Credits Overview',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _CreditRow(
                    label: 'Trial Credits',
                    value: widget.user.trialsRemaining.toString(),
                  ),
                  _CreditRow(
                    label: 'Image Gen',
                    value: widget.user.imageGenRemaining.toString(),
                  ),
                  _CreditRow(
                    label: 'Video Gen',
                    value: widget.user.videoGenRemaining.toString(),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
          const Text(
            'Settings',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          SwitchListTile(
            title: const Text('Healthy Eating Tips'),
            subtitle: const Text('Receive daily nutrition reminders'),
            value: widget.user.healthyTipsEnabled,
            onChanged: (value) {
              setState(() => widget.user.healthyTipsEnabled = value);
              widget.onUpdate(widget.user);
            },
          ),

          const Divider(),

          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: const Text('Cooking Calendar'),
            subtitle: Text('${_events.length} upcoming events'),
            trailing: IconButton(
              icon: const Icon(Icons.add),
              onPressed: _scheduleEvent,
            ),
            onTap: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (context) => _EventsListSheet(events: _events),
              );
            },
          ),

          const Divider(),

          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Analysis History'),
            onTap: () {
              // Navigate to history screen
            },
          ),

          ListTile(
            leading: const Icon(Icons.bookmark),
            title: const Text('Saved Recipes'),
            onTap: () {
              // Navigate to saved recipes
            },
          ),

          const SizedBox(height: 32),

          Card(
            color: Colors.blue.shade50,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.help_outline, color: Colors.blue),
                      SizedBox(width: 8),
                      Text(
                        'Need Help?',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text('Email us at support@portablecook.com'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreditRow extends StatelessWidget {
  final String label;
  final String value;

  const _CreditRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventDialog extends StatefulWidget {
  const _EventDialog();

  @override
  State<_EventDialog> createState() => _EventDialogState();
}

class _EventDialogState extends State<_EventDialog> {
  final _recipeController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Schedule Cooking Event'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _recipeController,
              decoration: const InputDecoration(
                labelText: 'Recipe Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: Text(DateFormat('MMM dd, yyyy').format(_selectedDate)),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (date != null) setState(() => _selectedDate = date);
              },
            ),
            ListTile(
              leading: const Icon(Icons.access_time),
              title: Text(_selectedTime.format(context)),
              onTap: () async {
                final time = await showTimePicker(
                  context: context,
                  initialTime: _selectedTime,
                );
                if (time != null) setState(() => _selectedTime = time);
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes (Optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final dateTime = DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day,
              _selectedTime.hour,
              _selectedTime.minute,
            );

            Navigator.pop(context, {
              'recipe': _recipeController.text,
              'date': dateTime,
              'notes': _notesController.text,
            });
          },
          child: const Text('Schedule'),
        ),
      ],
    );
  }
}

class _EventsListSheet extends StatelessWidget {
  final List<CookingEvent> events;

  const _EventsListSheet({required this.events});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder:
          (context, scrollController) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Upcoming Cooking Events',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child:
                      events.isEmpty
                          ? const Center(child: Text('No events scheduled'))
                          : ListView.builder(
                            controller: scrollController,
                            itemCount: events.length,
                            itemBuilder: (context, index) {
                              final event = events[index];
                              return Card(
                                child: ListTile(
                                  leading: const Icon(Icons.restaurant_menu),
                                  title: Text(event.recipeName),
                                  subtitle: Text(
                                    DateFormat(
                                      'MMM dd, yyyy - HH:mm',
                                    ).format(event.scheduledDate),
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                ),
                              );
                            },
                          ),
                ),
              ],
            ),
          ),
    );
  }
}
