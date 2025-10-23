import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:farm_go_app/firebase_services.dart';
import 'package:farm_go_app/permission_handler.dart';
import 'package:farm_go_app/user_model.dart'; // This now imports AppUser
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
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
    developer.log('Successfully scheduled daily reminder.');
  } catch (e) {
    developer.log('Could not schedule notification due to permission error: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  print("--- API Key from .env: ${dotenv.env['GEMINI_API_KEY']} ---");
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await _initializeNotifications();
  tz.initializeTimeZones();
  _scheduleDailyReminder();

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
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasData) {
            return const FarmGoHomePage();
          }
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

      // Update app state with farm type
      if (userDetails != null) {
        appState.setFarmType(userDetails.farmType);
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

class _ChallengeSectionState extends State<ChallengeSection> {
  late String _lossDataKey;
  final Map<String, List<Map<String, dynamic>>> _lossData = const {
    'poultry': [
      {'label': 'Avian Influenza', 'value': 120},
      {'label': 'Newcastle Disease', 'value': 85},
      {'label': 'Gumboro', 'value': 70},
      {'label': 'Coccidiosis', 'value': 55},
      {'label': 'Mycoplasmosis', 'value': 40}
    ],
    'pig': [
      {'label': 'African Swine Fever (ASF)', 'value': 250},
      {'label': 'PRRS', 'value': 180},
      {'label': 'Classical Swine Fever (CSF)', 'value': 110},
      {'label': 'Swine Dysentery', 'value': 75},
      {'label': 'PED', 'value': 60}
    ],
  };

  @override
  void initState() {
    super.initState();
    final farmType = Provider.of<AppState>(context, listen: false).currentFarmType;
    _lossDataKey = (farmType == 'Pig') ? 'pig' : 'poultry';
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final theme = Theme.of(context);
    final lossData = _lossData[_lossDataKey]!;

    return _buildSection(
      context: context,
      title: 'The High Cost of Disease',
      subtitle:
          'Disease outbreaks pose a significant economic threat. This section visualizes the estimated annual losses.',
      child: Column(
        children: [
          if (appState.currentFarmType == 'Both')
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLossToggleButton('poultry', 'Poultry', theme),
                const SizedBox(width: 16),
                _buildLossToggleButton('pig', 'Pigs', theme),
              ],
            ),
          const SizedBox(height: 24),
          Card(
            elevation: 4,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                      _lossDataKey == 'poultry'
                          ? 'Impact of Major Poultry Diseases'
                          : 'Impact of Major Pig Diseases',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ...lossData.map(
                    (data) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          Expanded(
                              flex: 2,
                              child: Text(data['label'] as String,
                                  style: const TextStyle(fontSize: 14))),
                          Expanded(
                              flex: 3,
                              child: LinearProgressIndicator(
                                  value: (data['value'] as int) / 250,
                                  backgroundColor: Colors.grey[300],
                                  color: theme.colorScheme.secondary,
                                  minHeight: 12,
                                  borderRadius: BorderRadius.circular(6))),
                          const SizedBox(width: 8),
                          Text('₹${data['value']}M',
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.bold)),
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

  Widget _buildLossToggleButton(String key, String label, ThemeData theme) {
    bool isSelected = _lossDataKey == key;
    return ElevatedButton(
      onPressed: () => setState(() => _lossDataKey = key),
      style: ElevatedButton.styleFrom(
        foregroundColor:
            isSelected ? theme.colorScheme.onPrimary : Colors.grey[800],
        backgroundColor:
            isSelected ? theme.colorScheme.primary : Colors.grey[200],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: isSelected ? 2 : 0,
        minimumSize: const Size(100, 40),
      ),
      child: Text(label),
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

  void _showSaveDialog(String analysisResult) {
    String? notes;
    String? selectedLocationId;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Analysis Complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(analysisResult),
            const SizedBox(height: 24),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Notes (Optional)',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => notes = value,
            ),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users/${_user.uid}/locations')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const SizedBox.shrink();
                }
                return DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                      labelText: 'Location (Optional)',
                      border: OutlineInputBorder()),
                  items: snapshot.data!.docs.map((doc) {
                    return DropdownMenuItem(
                        value: doc.id, child: Text(doc['name']));
                  }).toList(),
                  onChanged: (value) => selectedLocationId = value,
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Discard')),
          ElevatedButton(
            onPressed: () async {
              final String? currentNotes = notes;
              final String? currentLocationId = selectedLocationId;

              Navigator.pop(dialogContext);

              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Saving record...')),
              );

              final imageUrl = await _uploadImageToStorage(_image!);
              
              if (!mounted) return;
              
              await _firebaseServices.saveHealthRecord(_user.uid, {
                'imageUrl': imageUrl,
                'result': {
                  'parasiteType': analysisResult
                      .split(' ')
                      .firstWhere((s) => s.isNotEmpty, orElse: () => 'Unknown'),
                  'severity': 'moderate',
                  'fullText': analysisResult,
                },
                'locationId': currentLocationId,
                'notes': currentNotes,
                'timestamp': FieldValue.serverTimestamp(),
              });
              
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Analysis saved!')));
            },
            child: const Text('Save'),
          ),
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
    final analysisResult = await _firebaseServices.analyzeFecalImage(File(image.path));
    final result = analysisResult.toString();
    if (mounted) {
      setState(() {
        _isAnalyzing = false;
      });
      _showSaveDialog(result);
    }
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
  static const LatLng _center = LatLng(20.5937, 78.9629);

  @override
  void initState() {
    super.initState();
    _listenToMarkers();
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
        actions: [
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
      body: GoogleMap(
        onMapCreated: (GoogleMapController controller) {
          _controller.complete(controller);
        },
        initialCameraPosition:
            const CameraPosition(target: _center, zoom: 5.0),
        markers: _markers,
        onTap: _onMapTap,
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
                          axisSide: meta.axisSide,
                          space: 4,
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
                          axisSide: meta.axisSide,
                          space: 4,
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