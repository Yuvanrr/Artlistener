import 'package:flutter/material.dart';
import 'package:wifi_scan/wifi_scan.dart' as wifi_scan;
import 'package:provider/provider.dart';
import '../providers/firebase_provider.dart';

class SetExhibitPage extends StatefulWidget {
  const SetExhibitPage({super.key});

  @override
  _SetExhibitPageState createState() => _SetExhibitPageState();
}

class _SetExhibitPageState extends State<SetExhibitPage> {
  final _formKey = GlobalKey<FormState>();
  final _exhibitNameController = TextEditingController();
  final _exhibitDescController = TextEditingController();
  List<wifi_scan.WiFiAccessPoint> _wifiNetworks = [];
  List<Map<String, dynamic>> _fingerprintZones = []; // Store multiple zones
  int _currentZoneNumber = 1;
  bool _isLoading = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _scanWifiNetworks();
  }

  Future<void> _scanWifiNetworks() async {
    setState(() {
      _isLoading = true;
    });

    // Request location permission
    final can = await wifi_scan.WiFiScan.instance.canStartScan();
    if (can != wifi_scan.CanStartScan.yes) {
      // Handle case when location permission is not granted
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission is required to scan for WiFi networks'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    // Start scan and get results
    try {
      final result = await wifi_scan.WiFiScan.instance.getScannedResults();
      
      if (mounted) {
        setState(() {
          _wifiNetworks = result.take(5).toList(); // Take top 5 networks
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to scan for WiFi networks'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _addReferencePoint() async {
    if (_wifiNetworks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please scan for WiFi networks first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Create fingerprint from current WiFi scan
    final fingerprint = {
      for (var ap in _wifiNetworks) ap.bssid: ap.level
    };

    setState(() {
      _fingerprintZones.add({
        'zoneNumber': _currentZoneNumber,
        'fingerprint': fingerprint,
        'timestamp': DateTime.now().toIso8601String(),
        'networkCount': _wifiNetworks.length,
      });
      _currentZoneNumber++;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reference point ${_fingerprintZones.length} added successfully!'),
          backgroundColor: Colors.green[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    // Automatically scan again for next point
    await _scanWifiNetworks();
  }

  void _removeReferencePoint(int index) {
    setState(() {
      _fingerprintZones.removeAt(index);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reference point removed'),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _exhibitNameController.dispose();
    _exhibitDescController.dispose();
    super.dispose();
  }

  Future<void> _onSetExhibit() async {
    if (!_formKey.currentState!.validate()) {
      print('Form validation failed');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final firebaseProvider = Provider.of<FirebaseProvider>(context, listen: false);
      
      // Prepare WiFi fingerprint data - use zones instead of single fingerprints
      print('Found ${_wifiNetworks.length} WiFi networks');
      final wifiFingerprints = _wifiNetworks.map((ap) => {
        'ssid': ap.ssid,
        'bssid': ap.bssid,
        'level': ap.level,
        'frequency': ap.frequency,
        'capabilities': ap.capabilities,
      }).toList();

      // Prepare exhibit data with fingerprint zones
      final exhibitData = {
        'name': _exhibitNameController.text.trim(),
        'description': _exhibitDescController.text.trim(),
        'wifiFingerprints': wifiFingerprints,
        'wifiSsid': _wifiNetworks.isNotEmpty ? _wifiNetworks[0].ssid : '',
        'fingerprintZones': _fingerprintZones, // Add fingerprint zones
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      };

      print('Prepared exhibit data:');
      print('Name: ${exhibitData['name']}');
      print('Description: ${exhibitData['description']}');
      print('WiFi SSID: ${exhibitData['wifiSsid']}');
      print('WiFi Fingerprints count: ${wifiFingerprints.length}');
      
      // Save to Firebase
      print('Sending data to Firebase...');
      final success = await firebaseProvider.addExhibit(exhibitData);
      print('Firebase response - Success: $success');

      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Exhibit saved successfully!'),
              backgroundColor: Colors.green[700],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
          
          // Clear form after successful submission
          _formKey.currentState!.reset();
          setState(() {
            _wifiNetworks.clear();
            _fingerprintZones.clear();
            _currentZoneNumber = 1;
          });
          _scanWifiNetworks();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to save exhibit: ${firebaseProvider.error}'),
              backgroundColor: Colors.red[700],
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Set Exhibit',
          style: TextStyle(
            color: Colors.black,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black54),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Exhibit Name Field
                Text(
                  'Exhibit Name',
                  style: TextStyle(
                    color: Colors.grey[800],
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _exhibitNameController,
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Enter exhibit name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.black, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter exhibit name';
                    }
                    return null;
                  },
                ),
                
                const SizedBox(height: 20),
                
                // Exhibit Description Field
                Text(
                  'Exhibit Description',
                  style: TextStyle(
                    color: Colors.grey[800],
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _exhibitDescController,
                  style: const TextStyle(fontSize: 16),
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'Enter exhibit description',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.black, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter exhibit description';
                    }
                    return null;
                  },
                ),
                
                const SizedBox(height: 28),
                
                // Reference Points Section
                if (_fingerprintZones.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Reference Points (${_fingerprintZones.length})',
                        style: TextStyle(
                          color: Colors.grey[800],
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _fingerprintZones.length,
                    separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey[200]),
                    itemBuilder: (context, index) {
                      final zone = _fingerprintZones[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${zone['zoneNumber']}',
                            style: TextStyle(
                              color: Colors.green[700],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          'Point ${zone['zoneNumber']}',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          '${zone['networkCount']} networks • ${zone['timestamp']?.toString().substring(11, 19) ?? ''}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                          onPressed: () => _removeReferencePoint(index),
                          tooltip: 'Remove Point',
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                
                // Add Reference Point Button
                if (_wifiNetworks.isNotEmpty) ...[
                  ElevatedButton.icon(
                    onPressed: _addReferencePoint,
                    icon: const Icon(Icons.add_location, size: 20),
                    label: Text(_fingerprintZones.isEmpty ? 'ADD REFERENCE POINT' : 'ADD ANOTHER POINT'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                
                // WiFi Networks Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Available WiFi Networks',
                      style: TextStyle(
                        color: Colors.grey[800],
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh, color: Colors.black54),
                      onPressed: _isLoading ? null : _scanWifiNetworks,
                      tooltip: 'Refresh WiFi List',
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // WiFi Networks List
                if (_isLoading && _wifiNetworks.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24.0),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_wifiNetworks.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.wifi_off, size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 12),
                        Text(
                          'No WiFi networks found',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _wifiNetworks.length,
                    separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey[200]),
                    itemBuilder: (context, index) {
                      final network = _wifiNetworks[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.wifi, color: Colors.blue),
                        ),
                        title: Text(
                          network.ssid.isNotEmpty ? network.ssid : 'Hidden Network',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          'Signal: ${network.level} dBm',
                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),
                        trailing: Radio<String>(
                          value: network.ssid,
                          groupValue: _exhibitNameController.text,
                          activeColor: Colors.black,
                          onChanged: (value) {
                            setState(() {
                              _exhibitNameController.text = value ?? '';
                            });
                          },
                        ),
                      );
                    },
                  ),
                
                const SizedBox(height: 32),
                
                // Set Exhibit Button
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _onSetExhibit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'SET EXHIBIT',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                ),
                
                const SizedBox(height: 16),
                
                // Cancel Button
                TextButton(
                  onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'CANCEL',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
