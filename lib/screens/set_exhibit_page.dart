import 'package:flutter/material.dart';
import 'package:wifi_scan/wifi_scan.dart' as wifi_scan;
import 'package:cloud_firestore/cloud_firestore.dart';

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
  String? _selectedSsid;
  wifi_scan.WiFiAccessPoint? _selectedAp;

  bool _isLoading = false;
  bool _isSubmitting = false;

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

  String? _enumToLabel(dynamic value) {
    if (value == null) return null;
    final s = value.toString();
    if (s.contains('.')) return s.split('.').last;
    return s;
  }

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

  Future<void> _onSetExhibit() async {
    if (!_formKey.currentState!.validate()) return;
    final ap = _selectedAp;
    if (ap == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a Wi‑Fi network'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final exhibits = FirebaseFirestore.instance.collection('c_guru');

      final wifiMap = {
        'ssid': ap.ssid ?? '',
        'bssid': ap.bssid ?? '',
        'rssi': ap.level,
        'frequency': ap.frequency,
        'channelWidth': _enumToLabel(ap.channelWidth),
        'capabilities': ap.capabilities ?? '',
        'standard': _enumToLabel(ap.standard),
        'centerFrequency0': ap.centerFrequency0,
        'centerFrequency1': ap.centerFrequency1,
        'is80211mcResponder': ap.is80211mcResponder == true,
      };

      final newExhibit = {
        'name': _exhibitNameController.text.trim(),
        'description': _exhibitDescController.text.trim(),
        'wifi': wifiMap,
        'timestamp': FieldValue.serverTimestamp(),
      };

      await exhibits.add(newExhibit);

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

      _formKey.currentState!.reset();
      setState(() {
        _selectedSsid = null;
        _selectedAp = null;
        _wifiNetworks.clear();
      });
      _scanWifiNetworks();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to set exhibit: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // UI helpers
  Widget _sectionHeader(IconData icon, String title, {Widget? trailing}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.black87),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const Spacer(),
        if (trailing != null) trailing,
      ],
    );
  }

  int _signalBars(int rssi) {
    // Simple RSSI to bars mapper
    if (rssi >= -55) return 4;
    if (rssi >= -65) return 3;
    if (rssi >= -75) return 2;
    return 1;
  }

  Color _signalColor(int rssi) {
    if (rssi >= -60) return Colors.green;
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
    return InkWell(
      onTap: () {
        setState(() {
          _selectedSsid = ap.ssid;
          _selectedAp = ap;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _selectedAp?.bssid == ap.bssid ? Colors.blue[50] : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _selectedAp?.bssid == ap.bssid ? Colors.blue : Colors.grey[200]!,
            width: _selectedAp?.bssid == ap.bssid ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.wifi, color: Colors.blue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                      _chip('BSSID', ap.bssid ?? '—'),
                      _chip('RSSI', '${ap.level} dBm'),
                      _chip('Freq', '${ap.frequency} MHz'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              children: [
                _signalIndicator(ap.level),
                const SizedBox(height: 8),
                Radio<String>(
                  value: ap.ssid,
                  groupValue: _selectedSsid,
                  activeColor: Colors.black,
                  onChanged: (_) {
                    setState(() {
                      _selectedSsid = ap.ssid;
                      _selectedAp = ap;
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ',
              style: TextStyle(color: Colors.grey[700], fontSize: 12, fontWeight: FontWeight.w600)),
          Text(value, style: const TextStyle(fontSize: 12)),
        ],
      ),
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
          style: TextStyle(color: Colors.black, fontSize: 22, fontWeight: FontWeight.w700),
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
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _isLoading ? Colors.blue[50] : Colors.green[50],
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _isLoading ? Colors.blue : Colors.green,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _isLoading ? Icons.wifi_find : Icons.check_circle,
                                size: 16,
                                color: _isLoading ? Colors.blue : Colors.green,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _isLoading
                                    ? 'Scanning Wi‑Fi...'
                                    : 'Found ${_wifiNetworks.length} networks',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: _isLoading ? Colors.blue[900] : Colors.green[900],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _isLoading ? null : _scanWifiNetworks,
                          style: TextButton.styleFrom(foregroundColor: Colors.black87),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Rescan'),
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

                    // Step 2: Wi‑Fi selection
                    _sectionHeader(Icons.wifi, 'Select Wi‑Fi'),
                    const SizedBox(height: 8),
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

            // Spacer before bottom button
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
    );
  }
}
