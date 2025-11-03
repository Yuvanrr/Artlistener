import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'location_service.dart'; // Assumed to contain ExhibitMatchResult and LocationService class
import 'dart:async';

class AutoNarrationPage extends StatefulWidget {
  const AutoNarrationPage({super.key});

  @override
  State<AutoNarrationPage> createState() => _AutoNarrationPageState();
}

class _AutoNarrationPageState extends State<AutoNarrationPage> {
  // --- Service State & Controls ---
  bool _isAutoNarrationActive = false;
  String _currentStatus = "System Ready";
  String _currentExhibitName = "---";
  double? _currentExhibitConfidence;

  final LocationService _locationService = LocationService();
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _detectionTimer;
  
  // Tracking History: Stores the ID of the last successfully played exhibit
  String _lastPlayedExhibitId = "";

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.5);
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    print('🔄 Initializing auto narration services...');
    final sensorSuccess = await _locationService.initialize();
    print('✅ Auto narration services initialized (Sensors: $sensorSuccess)');
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    _tts.stop();
    _audioPlayer.dispose();
    _locationService.dispose(); // Clean up sensor fusion resources
    super.dispose();
  }

  // --- CORE AUTO-NARRATION LOOP ---
  void _startContinuousDetection() {
    _detectionTimer?.cancel();
    _tts.stop();
    _audioPlayer.stop();
    _detectionTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!_isAutoNarrationActive) {
        timer.cancel();
        return;
      }
      setState(() {
        _currentStatus = "Scanning Wi-Fi and motion sensors...";
      });

      try {
      
        final result = await _locationService.findClosestExhibit();
        
        if (!mounted) return;
        if (result == null) {
          setState(() {
            _currentStatus = "No confident match found. Please stand still...";
            _currentExhibitName = "---";
            _currentExhibitConfidence = null;
          });
          return;
        }

        // Check if this is a new exhibit
        if (result.id != _lastPlayedExhibitId) {
          
          // 1. Play Audio (TTS or URL)
          if (result.audioUrl != null && result.audioUrl!.isNotEmpty) {
            await _audioPlayer.play(UrlSource(result.audioUrl!));
          } else if (result.description.isNotEmpty) {
            await _tts.speak(result.description);
          }
          
          // 2. Update UI and history
          setState(() {
            _currentStatus = "Playing description for new exhibit.";
            _currentExhibitName = result.name;
            _currentExhibitConfidence = result.confidenceDistance;
            _lastPlayedExhibitId = result.id;
          });

        } else {
          // Exhibit found, but already played
          setState(() {
            _currentStatus = "Exhibit known. Awaiting movement...";
            _currentExhibitConfidence = result.confidenceDistance;
          });
        }
        
      } catch (e) {
        if (mounted) {
          setState(() {
            _currentStatus = "Error during scan: ${e.toString()}";
          });
        }
      }
    });
  }

  void _toggleAutoNarration() {
    setState(() {
      _isAutoNarrationActive = !_isAutoNarrationActive;
      if (_isAutoNarrationActive) {
        _lastPlayedExhibitId = ""; // Clear history on start
        _currentExhibitName = "Searching...";
        _startContinuousDetection();
        
      } else {
        _currentStatus = "System Paused";
        _currentExhibitName = "---";
        _currentExhibitConfidence = null;
        _detectionTimer?.cancel();
        _tts.stop();
        _audioPlayer.stop();
      }
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_isAutoNarrationActive ? 'Auto Narration Started.' : 'Auto Narration Paused.'),
            backgroundColor: _isAutoNarrationActive ? Colors.green : Colors.red,
        ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // High contrast theme
      appBar: AppBar(
        title: const Text(
          'Auto Narration Control',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.black,
        elevation: 4,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Control Panel Card
            Card(
              color: Colors.grey[900],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: _isAutoNarrationActive ? Colors.amber : Colors.grey[700]!, width: 2),
              ),
              elevation: 10,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Automatic Tracking',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Switch(
                          value: _isAutoNarrationActive,
                          onChanged: (_) => _toggleAutoNarration(),
                          activeColor: Colors.amber,
                          inactiveThumbColor: Colors.grey[600],
                          inactiveTrackColor: Colors.grey[800],
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white24, height: 20),
                    Row(
                      children: [
                        Icon(
                            _isAutoNarrationActive ? Icons.wifi_find : Icons.pause_circle_outline,
                            color: _isAutoNarrationActive ? Colors.amber : Colors.redAccent,
                            size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isAutoNarrationActive ? "Status: ACTIVE" : "Status: PAUSED",
                          style: TextStyle(
                            color: _isAutoNarrationActive ? Colors.greenAccent : Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Service Message:",
                      style: TextStyle(color: Colors.white70),
                    ),
                    Text(
                      _currentStatus,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 30),

            // Current Exhibit Display
            Text(
              "Currently Guiding:",
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[850],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentExhibitName,
                    style: TextStyle(
                      color: _lastPlayedExhibitId == "" ? Colors.grey : Colors.amber,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_currentExhibitConfidence != null)
                      Padding(
                       padding: const EdgeInsets.only(top: 4.0),
                       child: Text(
                          'Confidence: ${_currentExhibitConfidence!.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 14,
                          ),
                       ),
                     ),
                ],
              ),
            ),
            
            const Spacer(),

            // Stop/Start Button (Toggle)
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _toggleAutoNarration,
                icon: Icon(_isAutoNarrationActive ? Icons.stop_circle_outlined : Icons.play_arrow_outlined),
                label: Text(
                  _isAutoNarrationActive ? 'STOP AUTO NARRATION' : 'START AUTO NARRATION',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isAutoNarrationActive ? Colors.redAccent : Colors.amber,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
