import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/exhibit_model.dart';
import '../providers/firebase_provider.dart';
import 'update_exhibit_page.dart';

class ExhibitListPage extends StatefulWidget {
  const ExhibitListPage({super.key});

  @override
  _ExhibitListPageState createState() => _ExhibitListPageState();
}

class _ExhibitListPageState extends State<ExhibitListPage> {
  @override
  void initState() {
    super.initState();
  }

  Future<void> _onUpdateExhibit(Exhibit exhibit) async {
    final updatedExhibit = await Navigator.push<Exhibit?>(
      context,
      MaterialPageRoute(
        builder: (context) => UpdateExhibitPage(exhibit: exhibit),
      ),
    );

    if (updatedExhibit != null && mounted) {
      // The stream will automatically update the UI
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Exhibits',
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
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Provider.of<FirebaseProvider>(context).getExhibits() as Stream<QuerySnapshot<Map<String, dynamic>>>,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${snapshot.error}'),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingList();
          }

          final exhibits = snapshot.data?.docs.map((doc) {
            return Exhibit.fromFirestore(doc);
          }).toList() ?? [];

          if (exhibits.isEmpty) {
            return const _EmptyState();
          }

          return _buildExhibitList(exhibits);
        },
      ),
    );
  }

  Widget _buildExhibitList(List<Exhibit> exhibits) {
    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: exhibits.length,
      itemBuilder: (context, index) {
        final exhibit = exhibits[index];
        return _ExhibitCard(
          exhibit: exhibit,
          onUpdate: () => _onUpdateExhibit(exhibit),
          onDelete: _onDeleteExhibit,
        );
      },
    );
  }
  
  Future<void> _onDeleteExhibit(String id) async {
    final firebaseProvider = Provider.of<FirebaseProvider>(context, listen: false);
    final success = await firebaseProvider.deleteExhibit(id);
    
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Exhibit deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete exhibit: ${firebaseProvider.error}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _ExhibitCard extends StatelessWidget {
  final Exhibit exhibit;
  final VoidCallback onUpdate;
  final Function(String) onDelete;

  const _ExhibitCard({
    required this.exhibit,
    required this.onUpdate,
    required this.onDelete,
  });

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
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.black),
                      onPressed: onUpdate,
                      tooltip: 'Update Exhibit',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _showDeleteConfirmation(context),
                      tooltip: 'Delete Exhibit',
                    ),
                  ],
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
            _InfoRow(
              icon: Icons.wifi,
              label: 'WiFi Network',
              value: exhibit.wifiSsid,
            ),
            const SizedBox(height: 8),
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

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Exhibit'),
        content: const Text('Are you sure you want to delete this exhibit? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onDelete(exhibit.id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

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
  const _LoadingList();

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
  const _EmptyState();

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
          const SizedBox(height: 24),uuu
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

