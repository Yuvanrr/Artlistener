import 'package:flutter/material.dart';
import 'package:wifi_scan/wifi_scan.dart' as wifi_scan;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/exhibit_model.dart';

class UpdateExhibitPage extends StatefulWidget {
  final Exhibit exhibit;

  const UpdateExhibitPage({
    Key? key,
    required this.exhibit,
  }) : super(key: key);

  @override
  _UpdateExhibitPageState createState() => _UpdateExhibitPageState();
}

class _UpdateExhibitPageState extends State<UpdateExhibitPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  List<wifi_scan.WiFiAccessPoint> _wifiNetworks = [];
  bool _isLoading = false;
  bool _isScanning = false;
  String? _selectedWifiSsid;
  wifi_scan.WiFiAccessPoint? _selectedAp;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.exhibit.name);
    _descriptionController = TextEditingController(text: widget.exhibit.description);
    _selectedWifiSsid = widget.exhibit.wifiSsid;
    _scanWifiNetworks();
  }

  Future<void> _scanWifiNetworks() async {
    if (_isScanning) return;
    
    setState(() {
      _isScanning = true;
    });

    // Request location permission
    final can = await wifi_scan.WiFiScan.instance.canStartScan();
    if (can != wifi_scan.CanStartScan.yes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission is required to scan for WiFi networks'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isScanning = false;
        });
      }
      return;
    }

    try {
      final result = await wifi_scan.WiFiScan.instance.getScannedResults();
      
      if (mounted) {
        setState(() {
          _wifiNetworks = result.take(5).toList(); // Take top 5 networks
          _isScanning = false;
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
          _isScanning = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _updateExhibit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final Map<String, dynamic> updateData = {
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
      };

      if (_selectedAp != null) {
        updateData['wifi'] = {
          'ssid': _selectedAp!.ssid,
          'bssid': _selectedAp!.bssid,
          'rssi': _selectedAp!.level,
          'frequency': _selectedAp!.frequency,
          'channelWidth': _selectedAp!.channelWidth,
          'capabilities': _selectedAp!.capabilities,
          'standard': _selectedAp!.standard,
          'centerFrequency0': _selectedAp!.centerFrequency0,
          'centerFrequency1': _selectedAp!.centerFrequency1,
          'is80211mcResponder': _selectedAp!.is80211mcResponder,
        };
      }

      await FirebaseFirestore.instance.collection('c_guru').doc(widget.exhibit.id).update(updateData);

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Exhibit updated successfully'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
          ),
        );

        // Navigate back with the updated exhibit
        Navigator.pop(
          context,
          widget.exhibit.copyWith(
            name: _nameController.text.trim(),
            description: _descriptionController.text.trim(),
            wifiSsid: _selectedWifiSsid,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update exhibit: $e'),
            backgroundColor: Colors.red,
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
          'Update Exhibit',
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
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Current Exhibit Info
                _buildSectionHeader('Current Exhibit'),
                const SizedBox(height: 8),
                _buildInfoCard(widget.exhibit),
                const SizedBox(height: 24),
                
                // Update Form
                _buildSectionHeader('Update Details'),
                const SizedBox(height: 16),
                _buildNameField(),
                const SizedBox(height: 20),
                _buildDescriptionField(),
                const SizedBox(height: 28),
                _buildWifiList(),
                const SizedBox(height: 32),
                _buildUpdateButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildInfoCard(Exhibit exhibit) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              exhibit.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              exhibit.description,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      decoration: InputDecoration(
        labelText: 'Exhibit Name',
        hintText: 'Enter exhibit name',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.grey, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black, width: 2.0),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      style: const TextStyle(fontSize: 16),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Please enter an exhibit name';
        }
        return null;
      },
    );
  }

  Widget _buildDescriptionField() {
    return TextFormField(
      controller: _descriptionController,
      maxLines: 4,
      decoration: InputDecoration(
        labelText: 'Description',
        hintText: 'Enter exhibit description',
        alignLabelWithHint: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.grey, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black, width: 2.0),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
      style: const TextStyle(fontSize: 16),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Please enter a description';
        }
        return null;
      },
    );
  }

  Widget _buildWifiList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              icon: _isScanning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, color: Colors.black54),
              onPressed: _isScanning ? null : _scanWifiNetworks,
              tooltip: 'Refresh WiFi List',
            ),
          ],
        ),
        
        const SizedBox(height: 12),
        
        // WiFi Networks List
        if (_isScanning && _wifiNetworks.isEmpty)
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
                  groupValue: _selectedWifiSsid,
                  activeColor: Colors.black,
                  onChanged: (value) {
                    setState(() {
                      _selectedWifiSsid = value;
                      _selectedAp = network;
                    });
                  },
                ),
              );
            },
          ),
      ],
    );
  }



  Widget _buildUpdateButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _updateExhibit,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Text(
                'UPDATE EXHIBIT',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }
}
