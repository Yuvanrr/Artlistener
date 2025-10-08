import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/exhibit_model.dart';
import 'update_exhibit_page.dart';

class ExhibitListPage extends StatefulWidget {
  const ExhibitListPage({Key? key}) : super(key: key);

  @override
  _ExhibitListPageState createState() => _ExhibitListPageState();
}

class _ExhibitListPageState extends State<ExhibitListPage> {
  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('c_guru')
        .orderBy('timestamp', descending: true);

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
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: query.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(
                    'Failed to load exhibits: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingList();
            }

            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return const _EmptyState();
            }

            // Map Firestore docs -> Exhibit model
            final exhibits = docs.map((doc) {
              final data = doc.data();
              final name = (data['name'] ?? '').toString();
              final description = (data['description'] ?? '').toString();
              final wifiSsid = (data['wifiSsid'] as String?)?.trim();
              final audioUrl = (data['audioUrl'] as String?);
              // Firestore serverTimestamp can be null on first write; fall back to doc write time or now
              DateTime createdAt;
              final ts = data['timestamp'];
              if (ts is Timestamp) {
                createdAt = ts.toDate();
              } else {
                createdAt = doc.metadata.hasPendingWrites
                    ? DateTime.now()
                    : DateTime.now();
              }

              return Exhibit(
                id: doc.id,
                name: name,
                description: description,
                wifiSsid: (wifiSsid != null && wifiSsid.isNotEmpty) ? wifiSsid : null,
                audioUrl: (audioUrl != null && audioUrl.isNotEmpty) ? audioUrl : null,
                createdAt: createdAt,
              );
            }).toList();

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: exhibits.length,
              itemBuilder: (context, index) {
                final exhibit = exhibits[index];
                return _ExhibitCard(
                  exhibit: exhibit,
                  onUpdate: () => _onUpdateExhibit(exhibit),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _onUpdateExhibit(Exhibit exhibit) async {
    final updatedExhibit = await Navigator.push<Exhibit?>(
      context,
      MaterialPageRoute(
        builder: (context) => UpdateExhibitPage(exhibit: exhibit),
      ),
    );

    if (!mounted) return;

    if (updatedExhibit != null) {
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
      itemCount: 3,
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
            SizedBox(width: 200, height: 24, child: Placeholder()),
            SizedBox(height: 8),
            SizedBox(width: double.infinity, height: 16, child: Placeholder()),
            SizedBox(height: 8),
            SizedBox(width: 150, height: 16, child: Placeholder()),
            SizedBox(height: 8),
            SizedBox(width: 120, height: 16, child: Placeholder()),
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
          Icon(Icons.museum_outlined, size: 64, color: Colors.grey[400]),
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
            onPressed: () => Navigator.pop(context),
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
