import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:artlistener_1/services/wifi_service.dart';
import 'exhibit_page.dart';
import 'admin_login_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tapCount = 0;
  DateTime? _lastTapTime;

  final WifiService _wifiService = WifiService();
  bool _isLoading = false;

  void _handleTitleTap() {
    final now = DateTime.now();
    
    // Reset tap count if more than 1 second has passed since last tap
    if (_lastTapTime != null && now.difference(_lastTapTime!) > const Duration(seconds: 1)) {
      _tapCount = 0;
    }

    _tapCount++;
    _lastTapTime = now;

    // If tapped 10 times, navigate to admin login
    if (_tapCount >= 10) {
      _tapCount = 0; // Reset counter
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const AdminLoginPage()),
      );
    }
  }

  Future<void> _findAndNavigateToExhibit() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final exhibit = await _wifiService.findMatchingExhibit();
      
      if (!mounted) return;
      
      if (exhibit != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ExhibitPage(exhibit: exhibit),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No matching exhibit found nearby.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error finding exhibit: ${e.toString()}'),
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _handleTitleTap,
          child: const Text(
            'Artlistener',
            style: TextStyle(
              color: Colors.black,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // First Button
            SizedBox(
              width: 250,
              height: 60,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _findAndNavigateToExhibit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: Text(
                  _isLoading ? 'Searching...' : 'Get Exhibit Description',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20), // Space between buttons
            // Second Button
            SizedBox(
              width: 250,
              height: 60,
              child: ElevatedButton(
                onPressed: () {
                  // Add functionality for Auto Narration mode
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: const Text(
                  'Auto Narration mode',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }
}