import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:farm_go_app/firebase_services.dart';
import 'package:farm_go_app/permission_handler.dart';
import 'package:farm_go_app/user_model.dart'; // This now imports AppUser
import 'package:farm_go_app/map_search_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'firebase_options.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'ml/model_service.dart';   // For ML part
import 'package:image/image.dart' as img;




// =========================================================================
// Global State Management
// =========================================================================
class AppState extends ChangeNotifier {
  String _currentLanguage = 'English';
  String _currentFarmType = 'Poultry';

  String get currentLanguage => _currentLanguage;
  String get currentFarmType => _currentFarmType;

  void setLanguage(String newLanguage) {
    _currentLanguage = newLanguage;
    notifyListeners();
  }
  void setFarmType(String newFarmType) {
    _currentFarmType = newFarmType;
    notifyListeners();
  }
}

// =========================================================================
// Main & Notification Service
// =========================================================================
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _initializeNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
}

tz.TZDateTime _nextInstanceOfTenAM() {
  final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
  tz.TZDateTime scheduledDate =
      tz.TZDateTime(tz.local, now.year, now.month, now.day, 10);
  if (scheduledDate.isBefore(now)) {
    scheduledDate = scheduledDate.add(const Duration(days: 1));
  }
  return scheduledDate;
}

Future<void> _scheduleDailyReminder() async {
  try {
    await flutterLocalNotificationsPlugin.zonedSchedule(
      0,
      'FarmGo Daily Reminder',
      'Do not forget to log today\'s mortality, feed, and water intake!',
      _nextInstanceOfTenAM(),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_reminder_channel_id',
          'Daily Reminders',
          channelDescription: 'Channel for daily farm data logging reminders',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      // REMOVE these two lines:
      // uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
    developer.log('Successfully scheduled daily reminder.');
  } catch (e) {
    developer.log('Could not schedule notification due to permission error: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: ".env");
  print("--- API Key from .env: ${dotenv.env['GEMINI_API_KEY']} ---");

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Load ML models ONCE (singleton ModelService)
  print("Loading ML Models...");
  await ModelService().loadModels();
  print("ML Models Loaded!");

  // Initialize notifications
  await _initializeNotifications();
  tz.initializeTimeZones();
  _scheduleDailyReminder();

  // Lock orientation + start the app
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]).then((_) {
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (context) => AppState()),
          Provider(create: (context) => FirebaseServices()),
        ],
        child: const FarmGoApp(),
      ),
    );
  });
}


// =========================================================================
// App Definition & Auth Flow
// =========================================================================
class FarmGoApp extends StatelessWidget {
  const FarmGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF2E7D32);
    const secondaryColor = Color(0xFFC28B3B);
    const textColor = Color(0xFF333333);
    const backgroundColor = Color(0xFFFDFBF8);

    return MaterialApp(
      title: 'FarmGo',
      theme: ThemeData(
        fontFamily: 'Inter',
        scaffoldBackgroundColor: backgroundColor,
        colorScheme: const ColorScheme.light(
          primary: primaryColor,
          secondary: secondaryColor,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          surface: Colors.white,
          onSurface: textColor,
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(
              fontFamily: 'FreightTextMedium',
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: textColor),
          bodyLarge: TextStyle(fontFamily: 'Inter', color: textColor),
          bodyMedium: TextStyle(fontFamily: 'Inter', color: textColor),
        ),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          print("--- STREAM BUILDER: Connection state: ${snapshot.connectionState}, Has data: ${snapshot.hasData}, User: ${snapshot.data?.uid} ---");

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasData) {
            print("--- STREAM BUILDER: Showing FarmGoHomePage ---");
            return const FarmGoHomePage();
          }
          print("--- STREAM BUILDER: Showing OnboardingScreen ---");
          return const OnboardingScreen();
        },
      ),
    );
  }
}

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
          child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.grass, size: 80, color: Color(0xFF2E7D32)),
          const SizedBox(height: 20),
          const Text("Welcome to FarmGo!",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40, vertical: 10),
            child: Text(
                "Your all-in-one biosecurity and farm management solution.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (context) => const AuthScreen()),
              );
            },
            child: const Text("Get Started"),
          )
        ],
      )),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLogin = false;
  String _farmType = 'Poultry';
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  bool _isLoading = false;

  void _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final firebaseApi = Provider.of<FirebaseServices>(context, listen: false);
      final appState = Provider.of<AppState>(context, listen: false);

      AppUser? userDetails; // <-- RENAMED

      print("--- AUTH FORM: Starting ${_isLogin ? 'login' : 'signup'} process ---");

      if (_isLogin) {
        userDetails = await firebaseApi.logIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        userDetails = await firebaseApi.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          fullName: _nameController.text.trim(),
          farmLocation: _locationController.text.trim(),
          farmType: _farmType,
        );
      }

      print("--- AUTH FORM: Authentication completed, userDetails: ${userDetails != null ? 'SUCCESS' : 'NULL'} ---");

      // Update app state with farm type
      if (userDetails != null) {
        appState.setFarmType(userDetails.farmType);
        print("--- AUTH FORM: Authentication successful, navigating to home page ---");

        // Navigate to home page after successful authentication
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const FarmGoHomePage()),
          );
        }
      } else {
        print("--- AUTH FORM: userDetails is null, authentication failed ---");
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        String errorMessage = _getAuthErrorMessage(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e, s) { // <-- Added 's' for stack trace
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        // These print statements will give us the full story
        print("--- AUTH FORM ERROR ---");
        print("THE ERROR: $e");
        print("STACK TRACE: $s"); // This tells us the exact line of the crash

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An error occurred: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getAuthErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return 'The password provided is too weak.';
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'user-not-found':
        return 'No user found for that email.';
      case 'wrong-password':
        return 'Wrong password provided.';
      case 'invalid-email':
        return 'The email address is invalid.';
      case 'user-disabled':
        return 'This user account has been disabled.';
      case 'too-many-requests':
        return 'Too many requests. Please try again later.';
      case 'operation-not-allowed':
        return 'Email/password accounts are not enabled.';
      default:
        return 'Authentication failed: ${e.message}';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_isLogin ? 'Welcome Back!' : 'Create Account',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 20),
                if (!_isLogin) ...[
                  TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Full Name'),
                      validator: (v) => v!.isEmpty ? 'Required' : null),
                  const SizedBox(height: 16),
                  TextFormField(
                      controller: _locationController,
                      decoration:
                          const InputDecoration(labelText: 'Farm Location'),
                      validator: (v) => v!.isEmpty ? 'Required' : null),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _farmType,
                    decoration: const InputDecoration(labelText: 'Farm Type'),
                    items: ['Poultry', 'Pig', 'Both']
                        .map((String type) => DropdownMenuItem<String>(
                            value: type, child: Text(type)))
                        .toList(),
                    onChanged: (String? newValue) =>
                        setState(() => _farmType = newValue!),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => v!.isEmpty ? 'Required' : null),
                const SizedBox(height: 16),
                TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    validator: (v) => v!.isEmpty ? 'Required' : null),
                const SizedBox(height: 24),
                if (_isLoading)
                  const CircularProgressIndicator()
                else
                  ElevatedButton(
                      onPressed: _submitForm,
                      child: Text(_isLogin ? 'Log In' : 'Sign Up')),
                TextButton(
                    onPressed: () => setState(() => _isLogin = !_isLogin),
                    child: Text(_isLogin
                        ? 'Need an account? Sign Up'
                        : 'Already have an account? Log In')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =========================================================================
// App Guide Page
// =========================================================================
class AppGuidePage extends StatelessWidget {
  const AppGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('App Guide')),
      body: const Padding(
        padding: EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How to Use FarmGo',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              SizedBox(height: 16),
              Text(
                '1. Home Screen: Get an overview of farm challenges using the top tabs (Solution, Biosecurity, etc.).\n'
                '2. Bottom Navigation: Switch between the main sections of the app (Home, Dashboard, Camera, etc.).\n'
                '3. Profile & Settings: Access your profile, this guide, or log out from the top-right icons on the Home screen.\n'
                '4. Data Logging: Go to the Dashboard tab to view and add daily farm data.\n'
                '5. AI Chatbot: Ask any farming-related question for instant help.\n'
                '6. Fecal Analysis: Use the Camera tab to take a photo of a sample for a preliminary AI analysis.',
                style: TextStyle(fontSize: 16, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================================
// Main Navigation Structure
// =========================================================================
class HomePageContent extends StatelessWidget {
  const HomePageContent({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('FarmGo'),
          actions: [
            IconButton(
              tooltip: 'Profile',
              icon: const Icon(Icons.account_circle_outlined),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const ProfileScreen()),
                );
              },
            ),
            IconButton(
              tooltip: 'App Guide',
              icon: const Icon(Icons.help_outline),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const AppGuidePage()),
                );
              },
            ),
            IconButton(
              tooltip: 'Logout',
              icon: const Icon(Icons.logout),
              onPressed: () =>
                  Provider.of<FirebaseServices>(context, listen: false)
                      .signOut(),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.lightbulb_outline_rounded), text: 'Solution'),
              Tab(icon: Icon(Icons.shield_outlined), text: 'Biosecurity'),
              Tab(
                  icon: Icon(Icons.report_problem_outlined),
                  text: 'Problems'),
              Tab(icon: Icon(Icons.bar_chart_rounded), text: 'Challenge'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            SolutionSection(),
            BiosecuritySection(),
            ProblemsSection(),
            ChallengeSection(),
          ],
        ),
      ),
    );
  }
}

class FarmGoHomePage extends StatefulWidget {
  const FarmGoHomePage({super.key});
  @override
  State<FarmGoHomePage> createState() => _FarmGoHomePageState();
}

class _FarmGoHomePageState extends State<FarmGoHomePage> {
  int _selectedIndex = 0;
  AppUser? currentUserDetails; // <-- RENAMED
  bool _isLoadingUserDetails = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final details = await FirebaseServices().getUserDetails(user.uid);
        if (mounted) {
          setState(() {
            currentUserDetails = details; // Store the object directly
            _isLoadingUserDetails = false;
          });

          // Update AppState with farm type
          if (details != null) {
            Provider.of<AppState>(context, listen: false).setFarmType(details.farmType);
          }
        }
      } catch (e) {
        developer.log('Error loading user data: $e');
        if (mounted) {
          setState(() {
            currentUserDetails = null;
            _isLoadingUserDetails = false;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoadingUserDetails = false;
        });
      }
    }
  }

  static const List<Widget> _mainPages = <Widget>[
    HomePageContent(),
    DashboardPage(),
    CameraAnalysisPage(),
    MapPage(),
    ChatbotPage(),
  ];

  void _onItemTapped(int index) {
    if (index == 2 || index == 3) {
      _checkPermissionsAndNavigate(index);
    } else {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  Future<void> _checkPermissionsAndNavigate(int index) async {
    final hasPermission = await requestPermissions();
    if (!mounted) return;

    if (hasPermission) {
      setState(() {
        _selectedIndex = index;
      });
    } else {
      handlePermissionsAndNavigate(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingUserDetails) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      body: _mainPages.elementAt(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.camera_alt_outlined),
            label: 'Camera',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'AI Chatbot',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
      ),
    );
  }
}

// =========================================================================
// Home Screen Content Sections
// =========================================================================
class SolutionSection extends StatefulWidget {
  const SolutionSection({super.key});
  @override
  State<SolutionSection> createState() => _SolutionSectionState();
}

class _SolutionSectionState extends State<SolutionSection> {
  Map<String, bool> checklistItems = {
    'Check & Refill Foot Dips': false,
    'Inspect Pest Control Stations': false,
    'Disinfect Shared Equipment After Use': false,
    'Verify Visitor PPE Compliance': false,
  };

  Future<void> _saveChecklist() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseServices().saveChecklist(user.uid, checklistItems);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Checklist saved!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving checklist: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildSection(
      context: context,
      title: "Digital Biosecurity Checklists",
      subtitle:
          "Ensure compliance and never miss a critical task. Tap to complete.",
      child: Column(
        children: [
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: checklistItems.keys.map((String key) {
                  return CheckboxListTile(
                    title: Text(key),
                    value: checklistItems[key],
                    onChanged: (bool? value) =>
                        setState(() => checklistItems[key] = value!),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _saveChecklist,
            icon: const Icon(Icons.save_alt_rounded),
            label: const Text('Save Today\'s Checklist'),
            style: ElevatedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class BiosecuritySection extends StatelessWidget {
  const BiosecuritySection({super.key});
  @override
  Widget build(BuildContext context) {
    const pillars = [
      {
        'icon': Icons.public,
        'title': 'Isolation',
        'description':
            'Controlling the introduction of new animals and creating a barrier between the farm and the outside world.'
      },
      {
        'icon': Icons.traffic,
        'title': 'Traffic Control',
        'description':
            'Managing the movement of people, vehicles, and equipment onto and within the farm.'
      },
      {
        'icon': Icons.water_drop,
        'title': 'Sanitation',
        'description':
            'Implementing rigorous cleaning and disinfection protocols for housing, equipment, and vehicles.'
      },
    ];

    return _buildSection(
        context: context,
        title: 'The Three Pillars of Biosecurity',
        subtitle:
            'Effective biosecurity is a comprehensive strategy built on three core principles.',
        isLightBackground: true,
        child: Wrap(
          spacing: 16, runSpacing: 16, alignment: WrapAlignment.center,
          children: pillars
              .map(
                (pillar) => SizedBox(
                  width: 250,
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                          Icon(pillar['icon'] as IconData,
                              size: 48,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(height: 16),
                          Text(pillar['title'] as String,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(pillar['description'] as String,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.black54)),
                        ],
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ));
  }
}

class ProblemsSection extends StatefulWidget {
  const ProblemsSection({super.key});
  @override
  State<ProblemsSection> createState() => _ProblemsSectionState();
}

class _ProblemsSectionState extends State<ProblemsSection> {
  int _selectedProblemIndex = -1;
  final List<Map<String, String>> _problems = const [
    {
      'title': 'Poor Record Keeping',
      'description':
          'Manual, paper-based logs are often incomplete, illegible, or lost, making it impossible to trace outbreaks or identify trends.'
    },
    {
      'title': 'Inconsistent Protocols',
      'description':
          'Staff may forget or inconsistently apply critical biosecurity steps. A trackable system ensures compliance and identifies areas for retraining.'
    },
    {
      'title': 'Delayed Disease Detection',
      'description':
          'Subtle early signs of disease can be missed. This delay allows diseases to spread, leading to higher treatment costs and losses.'
    },
    {
      'title': 'Lack of Actionable Data',
      'description':
          'Without aggregated digital data, farmers cannot easily compare treatment effectiveness or provide accurate health histories to veterinarians.'
    },
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _buildSection(
      context: context,
      title: 'Common Gaps in Farm Biosecurity',
      subtitle:
          'Even with the best intentions, farmers face daily challenges that can compromise biosecurity.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(_problems.length, (index) {
          final problem = _problems[index];
          bool isSelected = _selectedProblemIndex == index;
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            elevation: isSelected ? 4 : 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  width: 2),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () =>
                  setState(() => _selectedProblemIndex = isSelected ? -1 : index),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(problem['title']!,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    if (isSelected)
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: Text(problem['description']!,
                            style: const TextStyle(
                                fontSize: 14, color: Colors.black54)),
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class ChallengeSection extends StatefulWidget {
  const ChallengeSection({super.key});
  @override
  State<ChallengeSection> createState() => _ChallengeSectionState();
}

class _ChallengeSectionState extends State<ChallengeSection>
    with TickerProviderStateMixin {
  late String _lossDataKey;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  final Map<String, List<Map<String, dynamic>>> _diseaseData = const {
    'poultry': [
      {
        'name': 'Avian Influenza',
        'riskLevel': 'HIGH',
        'riskValue': 90,
        'icon': '🦠',
        'symptoms': 'Sudden death, respiratory distress, drop in egg production',
        'prevention': 'Vaccination every 6 months, strict biosecurity',
        'season': 'October - March (Peak Winter)',
        'urgency': 'Contact vet immediately if suspected'
      },
      {
        'name': 'Newcastle Disease',
        'riskLevel': 'MEDIUM',
        'riskValue': 70,
        'icon': '🦠',
        'symptoms': 'Respiratory issues, nervous signs, diarrhea',
        'prevention': 'Regular vaccination, quarantine new birds',
        'season': 'Year-round with spring peaks',
        'urgency': 'Isolate affected birds immediately'
      },
      {
        'name': 'Infectious Bronchitis',
        'riskLevel': 'MEDIUM',
        'riskValue': 65,
        'icon': '🫁',
        'symptoms': 'Coughing, sneezing, reduced egg quality',
        'prevention': 'Vaccination, proper ventilation',
        'season': 'Cold weather months',
        'urgency': 'Monitor flock closely'
      },
      {
        'name': 'Coccidiosis',
        'riskLevel': 'LOW',
        'riskValue': 40,
        'icon': '🩸',
        'symptoms': 'Bloody diarrhea, weight loss, lethargy',
        'prevention': 'Clean water, dry litter, anticoccidial drugs',
        'season': 'Warm, humid conditions',
        'urgency': 'Treatable with medication'
      },
      {
        'name': 'Heat Stress',
        'riskLevel': 'SEASONAL',
        'riskValue': 50,
        'icon': '🌡️',
        'symptoms': 'Panting, reduced feed intake, drop in production',
        'prevention': 'Adequate ventilation, cool water, shade',
        'season': 'Summer months (April - June)',
        'urgency': 'Immediate cooling measures needed'
      }
    ],
    'pig': [
      {
        'name': 'African Swine Fever',
        'riskLevel': 'CRITICAL',
        'riskValue': 95,
        'icon': '🦠',
        'symptoms': 'High fever, skin lesions, sudden death',
        'prevention': 'Strict biosecurity, no swill feeding',
        'season': 'Year-round threat',
        'urgency': 'Report to authorities immediately'
      },
      {
        'name': 'PRRS (Blue Ear)',
        'riskLevel': 'HIGH',
        'riskValue': 80,
        'icon': '🦠',
        'symptoms': 'Respiratory issues, reproductive failure',
        'prevention': 'Vaccination, biosecurity protocols',
        'season': 'Year-round with seasonal peaks',
        'urgency': 'Veterinary consultation required'
      },
      {
        'name': 'Classical Swine Fever',
        'riskLevel': 'MEDIUM',
        'riskValue': 60,
        'icon': '🦠',
        'symptoms': 'Fever, loss of appetite, skin hemorrhages',
        'prevention': 'Vaccination where permitted, biosecurity',
        'season': 'Year-round',
        'urgency': 'Immediate isolation and testing'
      },
      {
        'name': 'Swine Dysentery',
        'riskLevel': 'MEDIUM',
        'riskValue': 55,
        'icon': '🩸',
        'symptoms': 'Bloody diarrhea, weight loss, dehydration',
        'prevention': 'Good hygiene, proper nutrition',
        'season': 'Stress periods, poor conditions',
        'urgency': 'Antibiotic treatment available'
      },
      {
        'name': 'Feed Quality Issues',
        'riskLevel': 'LOW',
        'riskValue': 35,
        'icon': '🌾',
        'symptoms': 'Poor growth, digestive issues, mycotoxicosis',
        'prevention': 'Quality feed sources, proper storage',
        'season': 'Monsoon storage issues',
        'urgency': 'Regular feed testing recommended'
      }
    ],
  };

  @override
  void initState() {
    super.initState();
    final farmType = Provider.of<AppState>(context, listen: false).currentFarmType;
    _lossDataKey = (farmType == 'Pig') ? 'pig' : 'poultry';

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final theme = Theme.of(context);
    final diseaseData = _diseaseData[_lossDataKey]!;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: _buildSection(
        context: context,
        title: '🦠 Major Farm Challenges & Disease Guide',
        subtitle:
            'Stay informed about key health threats and prevention strategies for your farm type.',
        child: Column(
          children: [
            if (appState.currentFarmType == 'Both')
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildLossToggleButton('poultry', 'Poultry', theme),
                    const SizedBox(width: 8),
                    _buildLossToggleButton('pig', 'Pigs', theme),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white,
                    Colors.grey[50]!,
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _lossDataKey == 'poultry' ? Icons.pets : Icons.agriculture,
                          color: theme.colorScheme.primary,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _lossDataKey == 'poultry'
                                ? 'Major Poultry Health Challenges'
                                : 'Major Pig Health Challenges',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    ...diseaseData.asMap().entries.map(
                      (entry) {
                        final index = entry.key;
                        final disease = entry.value;

                        return TweenAnimationBuilder<double>(
                          duration: Duration(milliseconds: 400 + (index * 100)),
                          tween: Tween(begin: 0.0, end: 1.0),
                          builder: (context, animatedValue, child) {
                            return Transform.translate(
                              offset: Offset(0, 20 * (1 - animatedValue)),
                              child: Opacity(
                                opacity: animatedValue,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 6.0),
                                  child: ExpansionTile(
                                    tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                    childrenPadding: const EdgeInsets.all(20),
                                    backgroundColor: Colors.white,
                                    collapsedBackgroundColor: Colors.grey[50],
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: _getRiskColor(disease['riskLevel'] as String).withOpacity(0.2),
                                        width: 1,
                                      ),
                                    ),
                                    collapsedShape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: Colors.grey[300]!,
                                        width: 1,
                                      ),
                                    ),
                                    leading: Text(
                                      disease['icon'] as String,
                                      style: const TextStyle(fontSize: 20),
                                    ),
                                    title: Text(
                                      disease['name'] as String,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    trailing: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _getRiskColor(disease['riskLevel'] as String).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        disease['riskLevel'] as String,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: _getRiskColor(disease['riskLevel'] as String),
                                        ),
                                      ),
                                    ),
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          _buildSimpleInfoRow('🩺 Symptoms', disease['symptoms'] as String),
                                          const SizedBox(height: 12),
                                          _buildSimpleInfoRow('🛡️ Prevention', disease['prevention'] as String),
                                          const SizedBox(height: 12),
                                          _buildSimpleInfoRow('📅 Peak Season', disease['season'] as String),
                                          const SizedBox(height: 12),
                                          _buildSimpleInfoRow('⚡ Urgent Action', disease['urgency'] as String),
                                          const SizedBox(height: 16),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: OutlinedButton(
                                                  onPressed: () => _showPreventionGuide(disease),
                                                  style: OutlinedButton.styleFrom(
                                                    foregroundColor: theme.colorScheme.primary,
                                                    side: BorderSide(color: theme.colorScheme.primary),
                                                  ),
                                                  child: const Text('Prevention Guide'),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
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

  Color _getRiskColor(String riskLevel) {
    switch (riskLevel) {
      case 'CRITICAL':
        return Colors.red[800]!;
      case 'HIGH':
        return Colors.red[600]!;
      case 'MEDIUM':
        return Colors.orange[600]!;
      case 'LOW':
        return Colors.green[600]!;
      case 'SEASONAL':
        return Colors.blue[600]!;
      default:
        return Colors.grey[600]!;
    }
  }

  Widget _buildSimpleInfoRow(String label, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          content,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[700],
            height: 1.4,
          ),
        ),
      ],
    );
  }

  void _showPreventionGuide(Map<String, dynamic> disease) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle indicator
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Text(
                    disease['icon'] as String,
                    style: const TextStyle(fontSize: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Prevention Guide: ${disease['name']}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    _buildPreventionCard('🛡️ Primary Prevention', disease['prevention'] as String),
                    const SizedBox(height: 16),
                    _buildPreventionCard('📅 Seasonal Awareness', disease['season'] as String),
                    const SizedBox(height: 16),
                    _buildPreventionCard('⚡ Urgent Actions', disease['urgency'] as String),
                    const SizedBox(height: 16),
                    _buildPreventionCard('🩺 Watch for Symptoms', disease['symptoms'] as String),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildPreventionCard(String title, String content) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(content),
          ],
        ),
      ),
    );
  }

  Widget _buildLossToggleButton(String key, String label, ThemeData theme) {
    bool isSelected = _lossDataKey == key;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: ElevatedButton(
        onPressed: () => setState(() => _lossDataKey = key),
        style: ElevatedButton.styleFrom(
          foregroundColor:
              isSelected ? Colors.white : theme.colorScheme.primary,
          backgroundColor:
              isSelected ? theme.colorScheme.primary : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: theme.colorScheme.primary,
              width: 2,
            ),
          ),
          elevation: isSelected ? 4 : 0,
          minimumSize: const Size(100, 45),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              key == 'poultry' ? Icons.pets : Icons.agriculture,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// Shared section builder to reduce code duplication
Widget _buildSection(
    {required BuildContext context,
    required String title,
    required String subtitle,
    required Widget child,
    bool isLightBackground = false}) {
  return Container(
    color: isLightBackground
        ? Theme.of(context).colorScheme.surface.withAlpha(128)
        : Colors.transparent,
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        children: [
          Text(title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.black54)),
          const SizedBox(height: 32),
          child,
        ],
      ),
    ),
  );
}

// =========================================================================
// Main Feature Pages
// =========================================================================
class ChatbotPage extends StatefulWidget {
  const ChatbotPage({super.key});
  @override
  State<ChatbotPage> createState() => _ChatbotPageState();
}

class _ChatbotPageState extends State<ChatbotPage> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  bool _isLoading = false;

  Future<void> _sendMessage() async {
    if (_controller.text.isEmpty) return;
    final userMessage = _controller.text;

    setState(() {
      _messages.add({'role': 'user', 'text': userMessage});
      _isLoading = true;
    });
    _controller.clear();

    final firebaseApi = Provider.of<FirebaseServices>(context, listen: false);
    final response = await firebaseApi.getChatbotResponse(userMessage);

    if (mounted) {
      setState(() {
        _messages.add({'role': 'model', 'text': response});
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Assistant')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isUser = message['role'] == 'user';
                return Align(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isUser
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      message['text']!,
                      style: TextStyle(
                          color: isUser ? Colors.white : Colors.black87),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isLoading)
            const Padding(
                padding: EdgeInsets.all(8.0),
                child: CircularProgressIndicator()),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                        hintText: 'Ask a farming question...'),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}



class CameraAnalysisPage extends StatefulWidget {
  const CameraAnalysisPage({super.key});

  @override
  State<CameraAnalysisPage> createState() => _CameraAnalysisPageState();
}

class _CameraAnalysisPageState extends State<CameraAnalysisPage> {
  final ImagePicker _picker = ImagePicker();
  final _firebaseServices = FirebaseServices();
  final _user = FirebaseAuth.instance.currentUser!;

  XFile? _image;
  bool _isAnalyzing = false;

  Future<String> _uploadImageToStorage(XFile image) async {
    return await _firebaseServices.uploadHealthRecordImage(File(image.path), _user.uid);
  }

  void _showSaveDialog(
      String general,
      String disease,
      double confidence,
      ) {
    String riskLevel;

    if (confidence >= 80) {
      riskLevel = "High Risk";
    } else if (confidence >= 50) {
      riskLevel = "Moderate Risk";
    } else {
      riskLevel = "Low Risk";
    }

    // Expanded explanations (Option A)
    Map<String, String> explanations = {
      "Salmonella":
      "contaminated feed, dirty water, or unhygienic farm conditions",
      "Coccidiosis":
      "irritation inside the gut caused by internal parasites or wet litter",
      "Worm Infection":
      "internal worms affecting digestion and nutrient absorption",
      "Wet Droppings":
      "heat stress, diet changes, or mild digestive irritation",
      "Blood Streaks":
      "minor irritation inside the intestine or gut lining shedding",
      "Healthy":
      "normal digestion with no major signs of irritation",
      "New Cattle Disease":
      "unusual dropping patterns that do not match familiar conditions",
      "Unknown":
      "unclear or inconsistent patterns that may need monitoring",
    };

    String explanation = explanations[disease] ??
        "a digestive imbalance or unfamiliar pattern";

    // --- AI Safe Summary Format (Option B) ---
    String summary;

    if (disease == "Healthy") {
      summary =
      "The fecal sample appears normal in color and texture, suggesting healthy digestion with no concerning patterns.";
    } else {
      summary =
      "The given fecal image suggests a possible risk of $disease, which is typically associated with $explanation.";

      if (confidence < 50) {
        summary +=
        "\n\nLow confidence prediction — further observation is recommended.";
      }
    }

    String? notes;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Prediction Summary',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),

        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(summary,
                style: const TextStyle(fontSize: 15, height: 1.45)),
            const SizedBox(height: 16),

            Text(
              "Confidence: ${confidence.toStringAsFixed(1)}%",
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
            ),

            Text(
              "Risk Level: $riskLevel",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: riskLevel == "High Risk"
                    ? Colors.red
                    : riskLevel == "Moderate Risk"
                    ? Colors.orange
                    : Colors.green,
              ),
            ),

            const SizedBox(height: 20),

            TextField(
              decoration: const InputDecoration(
                labelText: 'Notes (Optional)',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => notes = v,
            ),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _showFurtherSteps(disease);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green),
              child: const Text("Further Steps"),
            ),
          ],
        ),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Discard'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              // TODO: handle saving
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }


  void _showFurtherSteps(String disease) {
    Map<String, String> steps = {
      "Salmonella": """
        • Isolate affected birds
        • Clean and disinfect coop
        • Provide electrolytes  
        • Contact vet for antibiotics  
        """,
      "Coccidiosis": """
• Check for blood in droppings
• Give anti-coccidial medication
• Keep litter dry
• Provide clean water
""",
      "Worm Infection": """
• Deworm under vet guidance
• Improve feed quality
• Maintain hygiene
""",
      "Wet Droppings": """
• Reduce heat stress
• Check feed quality
• Observe for 24 hours
""",
      "Healthy": """
• No immediate action
• Continue regular monitoring
""",
    };

    String stepText = steps[disease] ?? "General monitoring recommended.";

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Next Steps for $disease"),
        content: Text(stepText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          )
        ],
      ),
    );
  }



  Future<void> _pickAndAnalyzeImage() async {
    final XFile? image =
    await _picker.pickImage(source: ImageSource.camera, imageQuality: 50);

    if (image == null || !mounted) return;

    setState(() {
      _image = image;
      _isAnalyzing = true;
    });

    // Decode photo
    img.Image decoded = img.decodeImage(File(image.path).readAsBytesSync())!;

    // Use model service for BOTH models
    final model = ModelService();
    final results = await model.predictBoth(decoded);

    final general = results['general']!;
    final disease = results['disease']!;

    final combinedResult = "General: $general\nDisease: $disease";

    if (!mounted) return;

    setState(() {
      _isAnalyzing = false;
    });

    // Show ONLY ONE dialog
    _showSaveDialog(
      general,          // general prediction label
      disease,          // disease prediction label
      results['confidence'],   // confidence value returned from model
    );

  }

  Future<void> _pickFromGalleryAndAnalyze() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
    );

    if (image == null || !mounted) return;

    setState(() {
      _image = image;
      _isAnalyzing = true;
    });

    // Decode selected image
    img.Image decoded =
    img.decodeImage(File(image.path).readAsBytesSync())!;

    // Use SINGLETON model instance
    final model = ModelService();

    final results = await model.predictBoth(decoded);

    final general = results['general']!;
    final disease = results['disease']!;

    final combinedResult = "General: $general\nDisease: $disease";

    if (!mounted) return;

    setState(() {
      _isAnalyzing = false;
    });

    _showSaveDialog(
      general,
      disease,
      results['confidence'],
    );

  }




  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Fecal Analysis')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_image == null)
                const Text(
                    'Take a photo of a sample for AI-powered preliminary analysis.',
                    textAlign: TextAlign.center),
              const SizedBox(height: 20),
              if (_image != null) Image.file(File(_image!.path), height: 250),
              const SizedBox(height: 20),
              if (_isAnalyzing)
                const Column(children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 10),
                  Text("Analyzing...")
                ]),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _isAnalyzing ? null : _pickAndAnalyzeImage,
                icon: const Icon(Icons.camera_alt),
                label:
                    Text(_image == null ? 'Take Photo' : 'Take Another Photo'),
              ),
              const SizedBox(height: 12),

              ElevatedButton.icon(
                onPressed: _isAnalyzing ? null : _pickFromGalleryAndAnalyze,
                icon: const Icon(Icons.photo_library),
                label: const Text("Select From Gallery"),
              ),
              const SizedBox(height: 20),
              const Text(
                "Disclaimer: This is an AI-generated observation and not a medical diagnosis. Please consult a qualified veterinarian.",
                style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontSize: 12,
                    color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Stream<QuerySnapshot> _farmDataStream;
  final _user = FirebaseAuth.instance.currentUser!;

  @override
  void initState() {
    super.initState();
    _farmDataStream = FirebaseServices().getFarmDataStream(_user.uid);
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Dashboard (${appState.currentFarmType})'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 1,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _farmDataStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.info_outline, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    "No farm data recorded yet.",
                    style: TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Tap the '+' button to add your first log.",
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 32),
                  _buildLastAnalysisCard(),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;
          final reversedDocs = docs.reversed.toList();
          final mortalityData = reversedDocs
              .map((doc) => (doc['mortalityCount'] as int).toDouble())
              .toList();
          final feedData = reversedDocs
              .map((doc) => (doc['feedConsumption']['value'] as num).toDouble())
              .toList();
          final tempData = reversedDocs
              .map((doc) => (doc['temperature'] as num).toDouble())
              .toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                _buildLastAnalysisCard(),
                const SizedBox(height: 16),
                _buildWeeklyAnalysis(mortalityData, feedData, theme),
                const SizedBox(height: 16),
                _buildTemperatureTrends(tempData, theme),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DataInputScreen()),
        ),
        tooltip: 'Add Farm Data',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildLastAnalysisCard() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users/${_user.uid}/health_records')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        final record = snapshot.data!.docs.first;
        final data = record.data() as Map<String, dynamic>;
        final result = data['result'] as Map<String, dynamic>;

        return Card(
          elevation: 2,
          child: ListTile(
            leading: const Icon(Icons.science_outlined, color: Colors.blueAccent),
            title: const Text('Last AI Analysis'),
            subtitle: Text('${result['parasiteType']} (${result['severity']})'),
            trailing: IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'View All Records',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HealthRecordsScreen()),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWeeklyAnalysis(
      List<double> mortalityData, List<double> feedData, ThemeData theme) {
    const List<String> weeklyLabels = [
      'Day 1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7'
    ];
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text('Last 7 Days Mortality',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
                height: 150,
                child: CustomBarChart(
                    data: mortalityData,
                    labels: weeklyLabels,
                    color: Colors.red.shade400)),
            const Divider(height: 32),
            const Text('Last 7 Days Feed (kg)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
                height: 150,
                child: CustomLineChart(
                    data: feedData,
                    labels: weeklyLabels,
                    color: theme.colorScheme.primary)),
          ],
        ),
      ),
    );
  }

  Widget _buildTemperatureTrends(List<double> data, ThemeData theme) {
    const List<String> dataLabels = ['Entry 1', '2', '3', '4', '5', '6', '7'];
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text('Last 7 Days Temperature (°C)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
                height: 150,
                child: CustomLineChart(
                    data: data,
                    labels: dataLabels,
                    color: theme.colorScheme.secondary)),
          ],
        ),
      ),
    );
  }
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final Completer<GoogleMapController> _controller = Completer();
  final Set<Marker> _markers = {};
  final user = FirebaseAuth.instance.currentUser!;
  final _firebaseServices = FirebaseServices();
  final _searchService = MapSearchService();
  final _searchController = TextEditingController();
  static const LatLng _center = LatLng(20.5937, 78.9629);

  // Search state
  List<SearchResult> _searchResults = [];
  bool _isSearching = false;
  bool _showSearchResults = false;
  MapType _currentMapType = MapType.normal;
  Timer? _searchDebounceTimer;

  @override
  void initState() {
    super.initState();
    _listenToMarkers();
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _listenToMarkers() {
    _firebaseServices.getLocationsStream(user.uid).listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _markers.clear();
        for (final doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final geoPoint = data['coordinates'] as GeoPoint;
          _markers.add(
            Marker(
              markerId: MarkerId(doc.id),
              position: LatLng(geoPoint.latitude, geoPoint.longitude),
              infoWindow: InfoWindow(
                title: data['name'],
                snippet: 'Type: ${data['type']}',
              ),
              onTap: () => _showLocationDetails(doc),
            ),
          );
        }
      });
    });
  }

  void _showLocationDetails(DocumentSnapshot location) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(location['name'],
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Type: ${location['type']}'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => LocationDataScreen(
                          locationId: location.id,
                          locationName: location['name'])),
                );
              },
              child: const Text('View Linked Data'),
            ),
          ],
        ),
      ),
    );
  }

  // Optimized search functionality with debouncing
  void _performSearch(String query) {
    // Cancel previous timer
    _searchDebounceTimer?.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _showSearchResults = false;
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    // Show loading immediately for better UX
    setState(() {
      _isSearching = true;
      _showSearchResults = true;
    });

    // Debounce the actual search
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final results = await _searchService.search(query);
        if (mounted) {
          setState(() {
            _searchResults = results;
            _isSearching = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isSearching = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Search error: $e')),
          );
        }
      }
    });
  }

  void _selectSearchResult(SearchResult result) async {
    _searchService.addToHistory(result);
    _searchController.text = result.name;

    setState(() {
      _showSearchResults = false;
    });

    // Animate camera to the selected location
    final controller = await _controller.future;
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: result.coordinates,
          zoom: 16.0,
        ),
      ),
    );

    // Add a temporary marker for the searched location
    if (result.type == 'google_places') {
      setState(() {
        _markers.add(
          Marker(
            markerId: MarkerId('search_result_${result.id}'),
            position: result.coordinates,
            infoWindow: InfoWindow(
              title: result.name,
              snippet: result.description,
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          ),
        );
      });
    }
  }

  void _getCurrentLocation() async {
    final location = await _searchService.getCurrentLocation();
    if (location != null) {

      final controller = await _controller.future;
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: location, zoom: 16.0),
        ),
      );

      // Add current location marker
      setState(() {
        _markers.add(
          Marker(
            markerId: const MarkerId('current_location'),
            position: location,
            infoWindow: const InfoWindow(title: 'Your Location'),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          ),
        );
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get current location')),
      );
    }
  }

  void _toggleMapType() {
    setState(() {
      _currentMapType = _currentMapType == MapType.normal
          ? MapType.satellite
          : MapType.normal;
    });
  }

  void _onMapTap(LatLng position) {
    String name = '';
    String type = 'Pen';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Location'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(
                  labelText: 'Location Name', border: OutlineInputBorder()),
              onChanged: (value) => name = value,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(
                  labelText: 'Location Type', border: OutlineInputBorder()),
              items: ['Pen', 'Barn', 'Quarantine', 'Field']
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (value) => type = value!,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (name.isNotEmpty) {
                await _firebaseServices.addLocation(user.uid, {
                  'name': name,
                  'coordinates': GeoPoint(position.latitude, position.longitude),
                  'type': type,
                });
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Farm Map'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Try to pop first, if that fails, navigate to home
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              // Navigate back to home tab
              final homeState = context.findAncestorStateOfType<_FarmGoHomePageState>();
              homeState?._onItemTapped(0); // Go to home tab (index 0)
            }
          },
        ),
        actions: [
          IconButton(
            icon: Icon(_currentMapType == MapType.normal
                ? Icons.satellite_alt
                : Icons.map),
            tooltip: 'Toggle Map Type',
            onPressed: _toggleMapType,
          ),
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'Current Location',
            onPressed: _getCurrentLocation,
          ),
          IconButton(
            icon: const Icon(Icons.add_location_alt_outlined),
            tooltip: 'Add Location',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text(
                      'Tap anywhere on the map to add a new location pin.')),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (GoogleMapController controller) {
              _controller.complete(controller);
            },
            initialCameraPosition:
                const CameraPosition(target: _center, zoom: 5.0),
            markers: _markers,
            onTap: _onMapTap,
            mapType: _currentMapType,
          ),

          // Search bar
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              elevation: 8,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search locations...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _showSearchResults = false;
                                  _searchResults = [];
                                });
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(16),
                    ),
                    onChanged: _performSearch,
                  ),

                  // Search results
                  if (_showSearchResults) ...[
                    const Divider(height: 1),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: _isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : _searchResults.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text('No results found'),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: _searchResults.length,
                                  itemBuilder: (context, index) {
                                    final result = _searchResults[index];
                                    return ListTile(
                                      leading: Icon(
                                        result.type == 'local'
                                            ? Icons.location_on
                                            : Icons.place,
                                        color: result.type == 'local'
                                            ? Colors.green
                                            : Colors.blue,
                                      ),
                                      title: Text(result.name),
                                      subtitle: Text(result.description),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.favorite_border),
                                        onPressed: () {
                                          _searchService.addToFavorites(result);
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Added to favorites'),
                                            ),
                                          );
                                        },
                                      ),
                                      onTap: () => _selectSearchResult(result),
                                    );
                                  },
                                ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// === NEW DETAIL SCREENS ===
// =========================================================================
class DataInputScreen extends StatefulWidget {
  const DataInputScreen({super.key});
  @override
  State<DataInputScreen> createState() => _DataInputScreenState();
}

class _DataInputScreenState extends State<DataInputScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firebaseServices = FirebaseServices();
  final _user = FirebaseAuth.instance.currentUser!;
  bool _isLoading = false;

  int _mortalityCount = 0;
  double _feedConsumption = 0;
  double _waterIntake = 0;
  double _temperature = 0;
  double _humidity = 0;
  String? _selectedLocationId;

  Future<void> _submitData() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      setState(() => _isLoading = true);
      try {
        await _firebaseServices.logFarmData(_user.uid, {
          'mortalityCount': _mortalityCount,
          'feedConsumption': {'value': _feedConsumption, 'unit': 'kg'},
          'waterIntake': _waterIntake,
          'temperature': _temperature,
          'humidity': _humidity,
          'locationId': _selectedLocationId,
          'timestamp': FieldValue.serverTimestamp(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Data saved!')));
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Error: $e')));
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Log Daily Farm Data')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                decoration: const InputDecoration(
                    labelText: 'Mortality Count', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
                validator: (v) => v!.isEmpty ? 'Required' : null,
                onSaved: (v) => _mortalityCount = int.parse(v!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: const InputDecoration(
                    labelText: 'Feed Consumption (kg)',
                    border: OutlineInputBorder()),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => v!.isEmpty ? 'Required' : null,
                onSaved: (v) => _feedConsumption = double.parse(v!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: const InputDecoration(
                    labelText: 'Water Intake (L)', border: OutlineInputBorder()),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => v!.isEmpty ? 'Required' : null,
                onSaved: (v) => _waterIntake = double.parse(v!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: const InputDecoration(
                    labelText: 'Temperature (°C)', border: OutlineInputBorder()),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => v!.isEmpty ? 'Required' : null,
                onSaved: (v) => _temperature = double.parse(v!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: const InputDecoration(
                    labelText: 'Humidity (%)', border: OutlineInputBorder()),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => v!.isEmpty ? 'Required' : null,
                onSaved: (v) => _humidity = double.parse(v!),
              ),
              const SizedBox(height: 16),
              StreamBuilder<QuerySnapshot>(
                stream: _firebaseServices.getLocationsStream(_user.uid),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.data!.docs.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                        labelText: 'Location (Optional)',
                        border: OutlineInputBorder()),
                    items: snapshot.data!.docs
                        .map((doc) => DropdownMenuItem(
                            value: doc.id, child: Text(doc['name'])))
                        .toList(),
                    onChanged: (value) => _selectedLocationId = value,
                  );
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _submitData,
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Save Data'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HealthRecordsScreen extends StatelessWidget {
  const HealthRecordsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    return Scaffold(
      appBar: AppBar(title: const Text('Health Analysis History')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseServices().getHealthRecordsStream(user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No health records found."));
          }

          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final record = snapshot.data!.docs[index];
              final data = record.data() as Map<String, dynamic>;
              final result = data['result'] as Map<String, dynamic>;
              final timestamp = (data['timestamp'] as Timestamp).toDate();
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: Image.network(
                      data['imageUrl'],
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.broken_image),
                      loadingBuilder: (context, child, progress) =>
                          progress == null
                              ? child
                              : const Center(child: CircularProgressIndicator()),
                    ),
                  ),
                  title:
                      Text('${result['parasiteType']} (${result['severity']})'),
                  subtitle: Text(DateFormat.yMMMd().add_jm().format(timestamp)),
                  isThreeLine: false,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class LocationDataScreen extends StatelessWidget {
  final String locationId;
  final String locationName;
  const LocationDataScreen(
      {super.key, required this.locationId, required this.locationName});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    return Scaffold(
      appBar: AppBar(title: Text(locationName)),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users/${user.uid}/farmData')
            .where('locationId', isEqualTo: locationId)
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(child: Text("No data logged for '$locationName'."));
          }

          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final data =
                  snapshot.data!.docs[index].data() as Map<String, dynamic>;
              final timestamp = (data['timestamp'] as Timestamp).toDate();
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  title: Text(
                      'Mortality: ${data['mortalityCount']} | Feed: ${data['feedConsumption']['value']} kg'),
                  subtitle: Text(DateFormat.yMMMd().add_jm().format(timestamp)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _user = FirebaseAuth.instance.currentUser!;
  final _firebaseServices = FirebaseServices();
  bool _isLoading = false;

  late TextEditingController _farmNameController;
  late TextEditingController _locationController;
  String _farmType = 'Poultry';

  @override
  void initState() {
    super.initState();
    _farmNameController = TextEditingController();
    _locationController = TextEditingController();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(_user.uid).get();
    if (doc.exists && mounted) {
      setState(() {
        _farmNameController.text = doc['fullName'] ?? '';
        _locationController.text = doc['farmLocation'] ?? '';
        _farmType = doc['farmType'] ?? 'Poultry';
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await _firebaseServices.updateUserProfile(_user.uid, {
        'fullName': _farmNameController.text,
        'farmLocation': _locationController.text,
        'farmType': _farmType,
      });
      if (mounted) {
        Provider.of<AppState>(context, listen: false).setFarmType(_farmType);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Profile updated!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _farmNameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Farm Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _farmNameController,
                decoration: const InputDecoration(
                    labelText: 'Farm Name', border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(
                    labelText: 'Farm Location', border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _farmType,
                decoration: const InputDecoration(
                    labelText: 'Farm Type', border: OutlineInputBorder()),
                items: ['Poultry', 'Pig', 'Both']
                    .map((type) =>
                        DropdownMenuItem(value: type, child: Text(type)))
                    .toList(),
                onChanged: (value) => setState(() => _farmType = value!),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Save Changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================================
// Custom Chart Widgets
// =========================================================================
class CustomBarChart extends StatelessWidget {
  final List<double> data;
  final List<String> labels;
  final Color color;

  const CustomBarChart(
      {super.key,
      required this.data,
      required this.labels,
      required this.color});

  @override
  Widget build(BuildContext context) {
    double maxY = data.isEmpty ? 0 : data.reduce((a, b) => a > b ? a : b) * 1.2;
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        barGroups: data.asMap().entries.map((entry) {
          return BarChartGroupData(
            x: entry.key,
            barRods: [
              BarChartRodData(
                  toY: entry.value,
                  color: color,
                  width: 16,
                  borderRadius: BorderRadius.circular(4))
            ],
          );
        }).toList(),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    if (value.toInt() < labels.length) {
                      return SideTitleWidget(
                          meta: meta,  // CORRECTED: meta is required
                          child: Text(labels[value.toInt()],
                              style: const TextStyle(fontSize: 10)));
                    }
                    return const Text('');
                  })),
          leftTitles: AxisTitles(
              sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (value, meta) {
                    return Text(value.toInt().toString(),
                        style: const TextStyle(fontSize: 10));
                  })),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
      ),
    );
  }
}
class CustomLineChart extends StatelessWidget {
  final List<double> data;
  final List<String> labels;
  final Color color;

  const CustomLineChart(
      {super.key,
      required this.data,
      required this.labels,
      required this.color});

  @override
  Widget build(BuildContext context) {
    double maxY = data.isEmpty ? 0 : data.reduce((a, b) => a > b ? a : b) * 1.2;
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: data
                .asMap()
                .entries
                .map((entry) => FlSpot(entry.key.toDouble(), entry.value))
                .toList(),
            isCurved: true,
            color: color,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                  colors: [color.withAlpha(80), color.withAlpha(0)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter),
            ),
          ),
        ],
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    if (value.toInt() < labels.length) {
                      return SideTitleWidget(
                          meta: meta,  // CORRECTED: meta is required
                          child: Text(labels[value.toInt()],
                              style: const TextStyle(fontSize: 10)));
                    }
                    return const Text('');
                  })),
          leftTitles: AxisTitles(
              sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (value, meta) {
                    return Text(value.toInt().toString(),
                        style: const TextStyle(fontSize: 10));
                  })),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
      ),
    );
  }
}
