
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:wifi_scan/wifi_scan.dart' as wifi_scan;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class SetExhibitPage extends StatefulWidget {
  const SetExhibitPage({Key? key}) : super(key: key);

  @override
  _SetExhibitPageState createState() => _SetExhibitPageState();
}

class _SetExhibitPageState extends State<SetExhibitPage> {
  final _formKey = GlobalKey<FormState>();
  final _exhibitNameController = TextEditingController();
  final _exhibitDescController = TextEditingController();

  List<wifi_scan.WiFiAccessPoint> _wifiNetworks = [];
  List<wifi_scan.WiFiAccessPoint> _selectedWifiNetworks = [];

  bool _isLoading = false;
  bool _isSubmitting = false;

  // Photos
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _pickedImages = [];
  final Map<String, double> _uploadProgress = {}; // filePath -> 0..1

  @override
  void initState() {
    super.initState();
    _scanWifiNetworks();
  }

  @override
  void dispose() {
    _exhibitNameController.dispose();
    _exhibitDescController.dispose();
    super.dispose();
  }

  String _uniqueName(String original) {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final noSpaces = original.replaceAll(RegExp(r'\s+'), '_');
    return '${ts}_$noSpaces';
  }

  bool _fileExists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  int _frequencyToChannel(int frequency) {
    // 2.4GHz channels
    if (frequency >= 2400 && frequency <= 2500) {
      return ((frequency - 2401) ~/ 5) + 1;
    }
    // 5GHz channels
    else if (frequency >= 5000 && frequency <= 6000) {
      // Common 5GHz channels
      if (frequency >= 5150 && frequency <= 5250) return 36 + ((frequency - 5150) ~/ 10) * 2;
      if (frequency >= 5250 && frequency <= 5350) return 52 + ((frequency - 5250) ~/ 10) * 2;
      if (frequency >= 5470 && frequency <= 5725) return 100 + ((frequency - 5470) ~/ 10) * 2;
      if (frequency >= 5725 && frequency <= 5875) return 116 + ((frequency - 5725) ~/ 10) * 2;
    }
    return 0; // Unknown channel
  }

  // --- Wi-Fi Scan Logic ---
  Future<void> _scanWifiNetworks() async {
    setState(() => _isLoading = true);
    final can = await wifi_scan.WiFiScan.instance.canStartScan();
    if (can != wifi_scan.CanStartScan.yes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location permission is required to scan for Wi‑Fi networks'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _isLoading = false);
      return;
    }

    try {
      final result = await wifi_scan.WiFiScan.instance.getScannedResults();
      if (!mounted) return;
      result.sort((a, b) => b.level.compareTo(a.level));
      setState(() {
        _wifiNetworks = result.take(20).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to scan for Wi‑Fi networks'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _isLoading = false);
    }
  }

  // --- Image Handling Logic (Unchanged) ---
  Future<void> _pickImageFromGallery() async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1920,
    );
    if (file != null) {
      setState(() {
        _pickedImages.add(file);
      });
    }
  }

  Future<void> _captureFromCamera() async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1920,
    );
    if (file != null) {
      setState(() {
        _pickedImages.add(file);
      });
    }
  }

  Future<void> _removePicked(int index) async {
    setState(() {
      final path = _pickedImages[index].path;
      _uploadProgress.remove(path);
      _pickedImages.removeAt(index);
    });
  }

  void _selectAllWifiNetworks() {
    setState(() {
      _selectedWifiNetworks.clear();
      _selectedWifiNetworks.addAll(_wifiNetworks);
    });
  }

  void _clearWifiSelection() {
    setState(() {
      _selectedWifiNetworks.clear();
    });
  }

  void _toggleWifiSelection(wifi_scan.WiFiAccessPoint ap) {
    setState(() {
      if (_selectedWifiNetworks.contains(ap)) {
        _selectedWifiNetworks.remove(ap);
      } else {
        _selectedWifiNetworks.add(ap);
      }
    });
  }

  Future<List<String>> _uploadAllPicked(String docId) async {
    final storage = FirebaseStorage.instance;
    final List<String> urls = [];

    for (final x in _pickedImages) {
      final path = x.path;
      if (!_fileExists(path)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Image not found on disk: ${x.name}'),
              backgroundColor: Colors.red,
            ),
          );
        }
        continue;
      }

      final file = File(path);
      final safeName = _uniqueName(x.name);
      final ref = storage.ref().child('exhibits/$docId/$safeName');

      try {
        _uploadProgress[path] = 0.0;
        setState(() {});

        final uploadTask = ref.putFile(file);

        uploadTask.snapshotEvents.listen((TaskSnapshot snap) {
          if (snap.totalBytes > 0) {
            final progress = snap.bytesTransferred / snap.totalBytes;
            _uploadProgress[path] = progress;
            if (mounted) setState(() {});
          }
        });

        TaskSnapshot snapshot = await uploadTask;

        if (snapshot.state != TaskState.success) {
          final retryTask = ref.putFile(file);
          snapshot = await retryTask;
        }

        if (snapshot.state == TaskState.success) {
          final url = await ref.getDownloadURL();
          urls.add(url);
          _uploadProgress[path] = 1.0;
          if (mounted) setState(() {});
        } else {
          _uploadProgress.remove(path);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('One image failed to upload and was skipped.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } on FirebaseException catch (e) {
        _uploadProgress.remove(path);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Upload failed (${e.code}): ${e.message ?? 'Unknown error'}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        _uploadProgress.remove(path);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Upload failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }

    return urls;
  }

  // --- Submission Logic (Updated for manual WiFi selection) ---
  Future<void> _onSetExhibit() async {
    if (!_formKey.currentState!.validate()) return;

    // Check if at least one WiFi network is selected
    if (_selectedWifiNetworks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one Wi-Fi network for exhibit detection.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 1. Create Wi-Fi Fingerprint Vector from selected networks
    final List<Map<String, dynamic>> wifiFingerprint = [];

    for (var ap in _selectedWifiNetworks) {
      if (ap.bssid.isNotEmpty) {
        wifiFingerprint.add({
          'bssid': ap.bssid,
          'ssid': ap.ssid,
          'rssi': ap.level,
          'frequency': ap.frequency,
          'channel': _frequencyToChannel(ap.frequency),
        });
        print('💾 Storing selected AP: ${ap.ssid} (${ap.bssid}) | RSSI: ${ap.level} dBm | Freq: ${ap.frequency} MHz');
      }
    }

    print('✅ WiFi fingerprint created with ${wifiFingerprint.length} selected APs');

    setState(() => _isSubmitting = true);

    try {
      final col = FirebaseFirestore.instance.collection('c_guru');
      final docRef = col.doc(); 
      
      // Upload images
      List<String> photoUrls = [];
      if (_pickedImages.isNotEmpty) {
        for (final x in _pickedImages) {
          if (!_fileExists(x.path)) {
            throw Exception('Selected image missing on disk: ${x.name}');
          }
        }
        photoUrls = await _uploadAllPicked(docRef.id);
        if (_pickedImages.isNotEmpty && photoUrls.isEmpty) {
          throw Exception('No images uploaded. Check Storage rules or network and try again.');
        }
      }

      // Final Exhibit Data Payload
      final newExhibit = {
        'name': _exhibitNameController.text.trim(),
        'description': _exhibitDescController.text.trim(),
        'wifi_fingerprint': wifiFingerprint, // THE SELECTED NETWORKS VECTOR
        'photos': photoUrls,
        'timestamp': FieldValue.serverTimestamp(),
      };

      await docRef.set(newExhibit);

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Exhibit set successfully!'),
          backgroundColor: Colors.green[700],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

      // Clear the form and reset state
      _formKey.currentState!.reset();
      setState(() {
        _wifiNetworks.clear();
        _selectedWifiNetworks.clear();
        _pickedImages.clear();
        _uploadProgress.clear();
      });
      _scanWifiNetworks();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to set exhibit: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // --- UI Helpers (Updated for consistent style) ---
  Widget _sectionHeader(IconData icon, String title, {Widget? trailing}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.black87),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing,
        ],
      ],
    );
  }

  int _signalBars(int rssi) {
    if (rssi >= -55) return 4;
    if (rssi >= -65) return 3;
    if (rssi >= -75) return 2;
    return 1;
  }

  Color _signalColor(int rssi) {
    if (rssi >= -60) return Colors.amber[700]!;
    if (rssi >= -70) return Colors.orange;
    return Colors.red;
  }

  Widget _signalIndicator(int rssi) {
    final bars = _signalBars(rssi);
    final color = _signalColor(rssi);
    return Row(
      children: List.generate(4, (i) {
        final active = i < bars;
        final h = 6 + i * 4.0;
        return Container(
          width: 4,
          height: h,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(
            color: active ? color : Colors.grey[300],
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Widget _wifiCard(wifi_scan.WiFiAccessPoint ap) {
    final isSelected = _selectedWifiNetworks.contains(ap);
    return GestureDetector(
      onTap: () => _toggleWifiSelection(ap),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.amber[50] : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.amber[300]! : Colors.grey[200]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.amber[100] : Colors.amber[100],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSelected ? Icons.check_circle : Icons.wifi,
                  color: isSelected ? Colors.amber[900] : Colors.amber[900],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      ap.ssid.isNotEmpty ? ap.ssid : 'Hidden Network',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        _chip('BSSID', ap.bssid.isNotEmpty ? ap.bssid : '—'),
                        _chip('RSSI', '${ap.level} dBm'),
                        _chip('Freq', '${ap.frequency} MHz'),
                        _chip('Channel', '${_frequencyToChannel(ap.frequency)}'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                alignment: Alignment.topCenter,
                child: _signalIndicator(ap.level),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, String value) {
    // Handle long values by truncating them intelligently
    String displayValue = value;
    if (value.length > 12) {
      if (label == 'BSSID') {
        displayValue = '${value.substring(0, 8)}...';
      } else if (value.contains(' ')) {
        // For values with spaces, truncate to first word or significant part
        final parts = value.split(' ');
        if (parts.length > 1 && parts[0].length < 8) {
          displayValue = '${parts[0]}...';
        } else {
          displayValue = '${value.substring(0, 9)}...';
        }
      } else {
        displayValue = '${value.substring(0, 9)}...';
      }
    }

    return Container(
      constraints: BoxConstraints(maxWidth: 100), // Reduced from 120 for better fit
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(color: Colors.grey[700], fontSize: 11, fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: Text(
              displayValue,
              style: const TextStyle(fontSize: 11),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _photosSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          Icons.photo_library_outlined,
          'Exhibit photos',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Pick from gallery',
                onPressed: _pickImageFromGallery,
                icon: const Icon(Icons.photo_outlined, color: Colors.black54),
              ),
              IconButton(
                tooltip: 'Capture from camera',
                onPressed: _captureFromCamera,
                icon: const Icon(Icons.photo_camera_outlined, color: Colors.black54),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_pickedImages.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.image_outlined, color: Colors.grey[500]),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No photos selected. Add from gallery or camera.',
                    style: TextStyle(color: Colors.grey[700]),
                    softWrap: true,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          )
        else
          GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: _pickedImages.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemBuilder: (context, index) {
              final x = _pickedImages[index];
              final path = x.path;
              final progress = _uploadProgress[path] ?? 0.0;

              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      File(path),
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  if (progress > 0 && progress < 1.0)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withOpacity(0.3),
                        child: Center(
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              value: progress,
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned( 
                    top: 6,
                    right: 6,
                    child: InkWell(
                      onTap: () => _removePicked(index),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.close, size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomBar = SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey[200]!, width: 1)),
        ),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _onSetExhibit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle),
                label: Text(
                  _isSubmitting ? 'Saving...' : 'Set Exhibit',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Set Exhibit',
        style: TextStyle(color: Colors.black, fontSize: 24, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black54),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      bottomNavigationBar: bottomBar,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Scan status
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _isLoading ? Colors.blue[50] : Colors.green[50],
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _isLoading ? Colors.blue : Colors.green,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _isLoading ? Icons.wifi_find : Icons.check_circle,
                                  size: 16,
                                  color: _isLoading ? Colors.blue : Colors.green,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    _isLoading
                                        ? 'Scanning Wi‑Fi...'
                                        : 'Found ${_wifiNetworks.length} networks',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: _isLoading ? Colors.blue[900] : Colors.green[900],
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: TextButton.icon(
                            onPressed: _isLoading ? null : _scanWifiNetworks,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.black87,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text(
                              'Rescan',
                              style: TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Step 1: Details
                    _sectionHeader(Icons.info_outline, 'Exhibit details'),
                    const SizedBox(height: 8),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _exhibitNameController,
                            decoration: InputDecoration(
                              labelText: 'Exhibit name',
                              hintText: 'e.g., Ancient Artifacts',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Please enter exhibit name'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _exhibitDescController,
                            maxLines: 3,
                            decoration: InputDecoration(
                              labelText: 'Exhibit description',
                              hintText: 'Describe the exhibit for visitors',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Please enter exhibit description'
                                : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Step 1.5: Photos
                    _photosSection(),
                    const SizedBox(height: 20),

                    // Step 2: Wi‑Fi selection
                    _sectionHeader(
                      Icons.wifi,
                      'Select Wi‑Fi Networks',
                      trailing: _selectedWifiNetworks.isEmpty
                          ? null
                          : Text(
                              '${_selectedWifiNetworks.length} selected',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.amber,
                              ),
                            ),
                    ),
                    const SizedBox(height: 8),
                    // Selection controls
                    if (_wifiNetworks.isNotEmpty) ...[
                      Row(
                        children: [
                          Flexible(
                            child: TextButton.icon(
                              onPressed: _selectAllWifiNetworks,
                              icon: const Icon(Icons.select_all, size: 16),
                              label: const Text('Select All'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.black87,
                                textStyle: const TextStyle(fontSize: 12),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: TextButton.icon(
                              onPressed: _clearWifiSelection,
                              icon: const Icon(Icons.clear, size: 16),
                              label: const Text('Clear All'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.black87,
                                textStyle: const TextStyle(fontSize: 12),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    // Updated hint: allow manual selection
                    Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                            'Select the Wi-Fi networks that should trigger this exhibit detection. You can select multiple networks.',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            softWrap: true,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                        ),
                    ),
                  ],
                ),
              ),
            ),

            if (_isLoading && _wifiNetworks.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_wifiNetworks.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.wifi_off, size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 8),
                        Text(
                          'No Wi‑Fi networks found',
                          style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Make sure Location is On and try rescanning.',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12.5),
                          softWrap: true,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverList.separated(
                  itemCount: _wifiNetworks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _wifiCard(_wifiNetworks[index]),
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
    );
  }
}