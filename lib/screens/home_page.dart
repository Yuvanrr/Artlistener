import 'package:flutter/material.dart';
import 'exhibit_page.dart';
import 'admin_login_page.dart';
import 'dart:math'; // For random quote selection

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tapCount = 0;
  DateTime? _lastTapTime;

  // List of inspiring museum/art quotes
  final List<String> _quotes = [
    "Art enables us to find ourselves and lose ourselves at the same time.",
    "A museum is a place where you can lose your sense of time.",
    "The object of art is not to reproduce reality, but to create a reality of the same intensity.",
    "Every artist dips his brush in his own soul, and paints his own nature into his pictures.",
    "Museums are not just repositories of objects, but vibrant spaces for dialogue and discovery.",
    "Art is not what you see, but what you make others see.",
    "The journey through a museum is a journey through humanity's greatest achievements.",
  ];
  String _currentQuote = "";

  @override
  void initState() {
    super.initState();
    _currentQuote = _getRandomQuote(); // Set initial quote
  }

  String _getRandomQuote() {
    final random = Random();
    return _quotes[random.nextInt(_quotes.length)];
  }

  void _handleTitleTap() {
    final now = DateTime.now();
    
    // Reset tap count if more than 1 second has passed since last tap
    if (_lastTapTime != null && now.difference(_lastTapTime!) > const Duration(seconds: 1)) {
      _tapCount = 0;
    }

    _tapCount++;
    _lastTapTime = now;

    // Secret tap gesture: If tapped 3 times quickly, navigate to admin login
    if (_tapCount >= 3) {
      _tapCount = 0; // Reset counter
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const AdminLoginPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Dark background for high contrast
      appBar: AppBar(
        // Use GestureDetector on the title to maintain the hidden admin login feature
        title: GestureDetector(
          onTap: _handleTitleTap,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.museum, color: Colors.amber, size: 30), // Highlighted icon
              SizedBox(width: 10),
              Text(
                'Artlistener',
                style: TextStyle(
                  color: Colors.white, // White text for contrast
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent, // Transparent to show body background
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Inspirational Quote
              Text(
                _currentQuote,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontStyle: FontStyle.italic,
                  color: Colors.white70, // Slightly subdued for elegance
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 60), // Increased space

              // Button 1: Manual Exhibit Search
              _buildFeatureCard(
                context,
                icon: Icons.search,
                title: 'Manual Exhibit Search',
                subtitle: 'Detect the exhibit you are standing next to and play its description.',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ExhibitPage()),
                  );
                },
                color: Colors.amber, // Contrasting vibrant color
                iconColor: Colors.black, // Dark icon for contrast
                textColor: Colors.black, // Dark text for contrast
                borderColor: Colors.amber,
              ),

              const SizedBox(height: 24), // Space between cards

              // Button 2: Auto Narration Mode
              _buildFeatureCard(
                context,
                icon: Icons.headphones_outlined,
                title: 'Auto Narration Mode',
                subtitle: 'Automatically play audio guides as you approach each exhibit (Coming Soon).',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Auto Narration Mode is not yet implemented.'),
                      backgroundColor: Colors.amber,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                color: Colors.grey[850]!, // Darker grey for secondary action
                borderColor: Colors.grey[700], // Subtle border
                textColor: Colors.white70,
                iconColor: Colors.white70,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper widget to build visually appealing feature cards
  Widget _buildFeatureCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color color,
    required Color iconColor,
    Color textColor = Colors.white,
    Color? borderColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor ?? Colors.transparent, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4), // More pronounced shadow
              spreadRadius: 2,
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 36, color: iconColor),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 14,
                color: textColor.withOpacity(0.9), // Slightly more opaque
              ),
            ),
          ],
        ),
      ),
    );
  }
}