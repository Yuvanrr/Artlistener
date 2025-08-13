import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

// Audio player states for the audio player
enum AudioPlayerState {
  stopped,
  playing,
  paused,
  completed
}

class ExhibitPage extends StatefulWidget {
  const ExhibitPage({super.key});

  @override
  State<ExhibitPage> createState() => _ExhibitPageState();
}

class _ExhibitPageState extends State<ExhibitPage> {
  // These would typically come from an API or data source
  String? exhibitName; // Set to null to simulate no data
  String? exhibitDescription; // Set to null to simulate no data
  String? audioUrl; // URL to the audio description
  
  // Audio player
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  AudioPlayerState _playerState = AudioPlayerState.stopped;
  
  @override
  void initState() {
    super.initState();
    // Initialize with sample data - replace with actual data from your database
    exhibitName = 'Sample Exhibit';
    exhibitDescription = 'This is a sample exhibit description. It would be replaced with the actual description from your database.';
    audioUrl = 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3'; // Sample audio URL for testing
    
    // Set up audio player listeners
    _audioPlayer.onPlayerStateChanged.listen((PlayerState state) {
      setState(() {
        _isPlaying = state == PlayerState.playing;
        _playerState = _isPlaying ? AudioPlayerState.playing : 
            (state == PlayerState.paused ? AudioPlayerState.paused : AudioPlayerState.stopped);
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
  }
  
  @override
  void dispose() {
    _audioPlayer.dispose();
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
      print('Error playing audio: $e');
      // Show error message to the user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error playing audio: ${e.toString()}')),
        );
      }
    }
  }

  // Function to handle getting a new exhibit description
  void _getNewExhibitDescription() {
    // TODO: Implement the logic to fetch a new exhibit description
    // This is a placeholder - you'll need to connect this to your data source
    setState(() {
      exhibitName = 'New Exhibit';
      exhibitDescription = 'This is a new exhibit description. In a real app, this would be fetched from your database or API.';
      audioUrl = 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3';
      // Reset audio player state
      _audioPlayer.stop();
      _isPlaying = false;
      _position = Duration.zero;
      _playerState = AudioPlayerState.stopped;
    });
    
    // Show a snackbar to indicate the action
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Loading new exhibit...')),
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
            // Audio Player
            if (audioUrl != null) ...[
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Column(
                  children: [
                    // Progress bar
                    Slider(
                      value: _position.inSeconds.toDouble(),
                      max: _duration.inSeconds.toDouble(),
                      onChanged: (value) async {
                        await _audioPlayer.seek(Duration(seconds: value.toInt()));
                      },
                    ),
                    // Time and controls
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
                              color: Colors.blue,
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
            // Exhibit Description Container
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8.0),
                ),
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
            ),
            const SizedBox(height: 20),
            // Get New Exhibit Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _getNewExhibitDescription,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
                child: const Text(
                  'Get New Exhibit Description',
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
