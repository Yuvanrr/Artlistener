import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wifi_scan/wifi_scan.dart' as wifi_scan;
import 'package:flutter_tts/flutter_tts.dart';

// Audio player states for the audio player
enum AudioPlayerState { stopped, playing, paused, completed }

class ExhibitPage extends StatefulWidget {
  const ExhibitPage({super.key});

  @override
  State<ExhibitPage> createState() => _ExhibitPageState();
}

class _ExhibitPageState extends State<ExhibitPage> {
  // Data shown to user
  String? exhibitName;
  String? exhibitDescription;
  String? audioUrl;

  // Audio player
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  AudioPlayerState _playerState = AudioPlayerState.stopped;

  // TTS
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;

  // No longer need allowed SSIDs list - we'll use any SSID from database
  bool _isLoadingNetworks = false;

  @override
  void initState() {
    super.initState();

    // Optional defaults while nothing is loaded
    exhibitName = 'Exhibit';
    exhibitDescription = 'Tap the button to detect location and play the description.';

    // Configure audio player listeners
    _audioPlayer.onPlayerStateChanged.listen((PlayerState state) {
      setState(() {
        _isPlaying = state == PlayerState.playing;
        _playerState = _isPlaying
            ? AudioPlayerState.playing
            : (state == PlayerState.paused
                ? AudioPlayerState.paused
                : AudioPlayerState.stopped);
      });
    });

    _audioPlayer.onDurationChanged.listen((Duration d) {
      setState(() {
        _duration = d;
      });
    });

    _audioPlayer.onPositionChanged.listen((Duration p) {
      setState(() {
        _position = p;
      });
    });

    _audioPlayer.onPlayerComplete.listen((event) {
      setState(() {
        _isPlaying = false;
        _position = Duration.zero;
        _playerState = AudioPlayerState.completed;
      });
    });

    // Configure TTS defaults
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US'); // adjust as needed
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _tts.setStartHandler(() => setState(() => _isSpeaking = true));
    _tts.setCompletionHandler(() => setState(() => _isSpeaking = false));
    _tts.setCancelHandler(() => setState(() => _isSpeaking = false));
    _tts.setErrorHandler((msg) => setState(() => _isSpeaking = false));
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _playPauseAudio() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
        setState(() {
          _playerState = AudioPlayerState.paused;
          _isPlaying = false;
        });
      } else {
        if (audioUrl != null) {
          if (_playerState == AudioPlayerState.stopped || _playerState == AudioPlayerState.completed) {
            await _audioPlayer.play(UrlSource(audioUrl!));
            setState(() {
              _playerState = AudioPlayerState.playing;
              _isPlaying = true;
            });
          } else {
            await _audioPlayer.resume();
            setState(() {
              _playerState = AudioPlayerState.playing;
              _isPlaying = true;
            });
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error playing audio: $e')),
      );
    }
  }

  // Button action: detect any Wi‑Fi network that has exhibits in the database
  Future<void> _getNewExhibitDescription() async {
    setState(() => _isLoadingNetworks = true);

    try {
      // 1) Scan Wi‑Fi and get all available networks
      final can = await wifi_scan.WiFiScan.instance.canStartScan();
      print('Can start Wi-Fi scan: $can');

      if (can != wifi_scan.CanStartScan.yes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location permission/services required for Wi‑Fi scan. Status: $can'),
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }

      // Start scan and get fresh results
      await wifi_scan.WiFiScan.instance.getScannedResults();
      final results = await wifi_scan.WiFiScan.instance.getScannedResults();

      // Debug: Print all detected networks
      print('All detected Wi-Fi networks:');
      for (var ap in results) {
        print('  SSID: "${ap.ssid}", BSSID: ${ap.bssid}, Level: ${ap.level}');
      }

      if (results.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No Wi‑Fi networks found nearby')),
        );
        return;
      }

      // 2) For each detected network, check if there are exhibits using that SSID
      wifi_scan.WiFiAccessPoint? bestAp;
      QueryDocumentSnapshot<Map<String, dynamic>>? bestDoc;

      for (final ap in results) {
        if (ap.ssid.isEmpty) continue; // Skip hidden networks

        print('Checking SSID: ${ap.ssid}');

        // Query database for exhibits with this SSID
        final querySnapshot = await FirebaseFirestore.instance
            .collection('c_guru')
            .where('wifi.ssid', isEqualTo: ap.ssid)
            .get();

        print('Found ${querySnapshot.docs.length} exhibits for SSID: ${ap.ssid}');

        if (querySnapshot.docs.isNotEmpty) {
          // Found exhibits for this SSID - use the strongest signal
          bestAp = ap;
          // Get the exhibit with closest RSSI match
          int bestDiff = 1 << 30;

          for (final doc in querySnapshot.docs) {
            final data = doc.data();
            final wifi = data['wifi'] as Map<String, dynamic>?;
            final storedRssi = (wifi?['rssi'] is num) ? (wifi?['rssi'] as num).toInt() : null;

            if (storedRssi != null) {
              final diff = (storedRssi - ap.level).abs();
              if (diff < bestDiff) {
                bestDiff = diff;
                bestDoc = doc;
              }
            }
          }

          if (bestDoc != null) {
            print('Best match found for SSID: ${ap.ssid}');
            break; // Found a match, no need to check other networks
          }
        }
      }

      if (bestAp == null || bestDoc == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No exhibits found for any detected networks. Found ${results.length} networks'),
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }

      // 3) Update UI with found exhibit
      final bestData = bestDoc!.data();
      final name = (bestData['name'] ?? '').toString();
      final description = (bestData['description'] ?? '').toString();
      final maybeAudio = (bestData['audioUrl'] as String?);

      if (!mounted) return;
      setState(() {
        exhibitName = name.isEmpty ? 'Exhibit' : name;
        exhibitDescription = description.isEmpty
            ? 'No description available.'
            : description;
        audioUrl = (maybeAudio != null && maybeAudio.isNotEmpty) ? maybeAudio : null;

        // Reset audio player state for any previous URL
        _audioPlayer.stop();
        _isPlaying = false;
        _position = Duration.zero;
        _playerState = AudioPlayerState.stopped;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exhibit loaded! Detected network: ${bestAp.ssid}. Tap the play button to hear the description.')),
      );

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load exhibit: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingNetworks = false);
      }
    }
  }

  Future<void> _playDescriptionTTS() async {
    if (exhibitDescription == null || exhibitDescription!.isEmpty) return;

    try {
      await _tts.stop();
      await _tts.speak(exhibitDescription!);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error playing description: $e')),
      );
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));

    return [
      if (duration.inHours > 0) hours,
      minutes,
      seconds,
    ].join(':');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Artlistener',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          if (_isLoadingNetworks)
            Container(
              margin: const EdgeInsets.only(right: 16),
              child: const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Exhibit Name
            Text(
              exhibitName ?? 'Exhibit not found',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 20),

            // Optional streaming audio (if audioUrl provided in DB)
            if (audioUrl != null) ...[
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Column(
                  children: [
                    Slider(
                      value: _position.inSeconds.clamp(0, _duration.inSeconds).toDouble(),
                      max: _duration.inSeconds == 0 ? 1 : _duration.inSeconds.toDouble(),
                      onChanged: (value) async {
                        await _audioPlayer.seek(Duration(seconds: value.toInt()));
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_formatDuration(_position)),
                          IconButton(
                            icon: Icon(
                              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                              size: 40,
                              color: Colors.black,
                            ),
                            onPressed: _playPauseAudio,
                          ),
                          Text(_formatDuration(_duration - _position)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Exhibit Description with play button
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Play button for description
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            _isSpeaking ? Icons.stop_circle : Icons.play_circle_filled,
                            size: 32,
                            color: Colors.black,
                          ),
                          onPressed: _isSpeaking
                              ? () async {
                                  await _tts.stop();
                                  setState(() => _isSpeaking = false);
                                }
                              : _playDescriptionTTS,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isSpeaking ? 'Stop Description' : 'Play Description',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    // Description text
                    Expanded(
                      child: SingleChildScrollView(
                        child: Text(
                          exhibitDescription ??
                              'Exhibit description has not been retrieved or is unable to retrieve due to server issues.',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Get Exhibit Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoadingNetworks ? null : _getNewExhibitDescription,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
                child: _isLoadingNetworks
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Get Exhibit (via Wi‑Fi)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
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
