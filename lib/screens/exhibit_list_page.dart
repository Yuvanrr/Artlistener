import 'package:flutter/material.dart';
import '../models/exhibit_model.dart';
import 'update_exhibit_page.dart';

class ExhibitListPage extends StatefulWidget {
  const ExhibitListPage({Key? key}) : super(key: key);

  @override
  _ExhibitListPageState createState() => _ExhibitListPageState();
}

class _ExhibitListPageState extends State<ExhibitListPage> {
  bool _isLoading = true;
  final List<Exhibit> _exhibits = [];

  @override
  void initState() {
    super.initState();
    _loadExhibits();
  }

  Future<void> _loadExhibits() async {
    // Simulate network/database delay
    await Future.delayed(const Duration(seconds: 1));
    
    // TODO: Replace with actual data fetching logic
    final mockExhibits = [
      Exhibit(
        id: '1',
        name: 'Ancient Artifacts',
        description: 'A collection of ancient artifacts from various civilizations',
        wifiSsid: 'Museum_Ancient',
        audioUrl: 'https://example.com/audio1.mp3',
      ),
      // Add more mock data or keep empty to test empty state
    ];

    if (mounted) {
      setState(() {
        _exhibits.addAll(mockExhibits);
        _isLoading = false;
      });
    }
  }

  Future<void> _onUpdateExhibit(Exhibit exhibit) async {
    final updatedExhibit = await Navigator.push<Exhibit?>(
      context,
      MaterialPageRoute(
        builder: (context) => UpdateExhibitPage(exhibit: exhibit),
      ),
    );

    if (updatedExhibit != null && mounted) {
      // Update the exhibit in the list
      final index = _exhibits.indexWhere((e) => e.id == updatedExhibit.id);
      if (index != -1) {
        setState(() {
          _exhibits[index] = updatedExhibit;
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
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Exhibit List',
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
        child: _isLoading
            ? const _LoadingList()
            : _exhibits.isEmpty
                ? const _EmptyState()
                : _buildExhibitList(),
      ),
    );
  }

  Widget _buildExhibitList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _exhibits.length,
      itemBuilder: (context, index) {
        final exhibit = _exhibits[index];
        return _ExhibitCard(
          exhibit: exhibit,
          onUpdate: () => _onUpdateExhibit(exhibit),
        );
      },
    );
  }
}

class _ExhibitCard extends StatelessWidget {
  final Exhibit exhibit;
  final VoidCallback onUpdate;

  const _ExhibitCard({
    Key? key,
    required this.exhibit,
    required this.onUpdate,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    exhibit.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.black),
                  onPressed: onUpdate,
                  tooltip: 'Update Exhibit',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              exhibit.description,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            if (exhibit.wifiSsid != null) ...[
              _InfoRow(
                icon: Icons.wifi,
                label: 'WiFi Network',
                value: exhibit.wifiSsid!,
              ),
              const SizedBox(height: 8),
            ],
            if (exhibit.audioUrl != null) ...[
              _InfoRow(
                icon: Icons.audio_file,
                label: 'Audio Guide',
                value: 'Available',
                valueColor: Colors.green,
              ),
              const SizedBox(height: 8),
            ],
            _InfoRow(
              icon: Icons.calendar_today,
              label: 'Created',
              value: _formatDate(exhibit.createdAt),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    Key? key,
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 13,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? Colors.black87,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 3, // Number of shimmer placeholders
      itemBuilder: (context, index) => _buildShimmerCard(),
    );
  }

  Widget _buildShimmerCard() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      elevation: 0,
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title placeholder
            SizedBox(
              width: 200,
              height: 24,
              child: Placeholder(),
            ),
            SizedBox(height: 8),
            // Description placeholder
            SizedBox(
              width: double.infinity,
              height: 16,
              child: Placeholder(),
            ),
            SizedBox(height: 8),
            // Info row placeholders
            SizedBox(
              width: 150,
              height: 16,
              child: Placeholder(),
            ),
            SizedBox(height: 8),
            SizedBox(
              width: 120,
              height: 16,
              child: Placeholder(),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.museum_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No Exhibits Found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48.0),
            child: Text(
              'Add a new exhibit to get started',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              // TODO: Navigate to add exhibit page
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Add Exhibit'),
          ),
        ],
      ),
    );
  }
}
