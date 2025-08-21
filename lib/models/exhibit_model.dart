import 'package:cloud_firestore/cloud_firestore.dart';

class Exhibit {
  final String id;
  final String name;
  final String description;
  final String? wifiSsid;
  final String? audioUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Map<String, dynamic>>? wifiFingerprints;

  Exhibit({
    required this.id,
    required this.name,
    required this.description,
    this.wifiSsid,
    this.audioUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.wifiFingerprints,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  // Create a copyWith method for easy updates
  Exhibit copyWith({
    String? id,
    String? name,
    String? description,
    String? wifiSsid,
    String? audioUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Map<String, dynamic>>? wifiFingerprints,
  }) {
    return Exhibit(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      wifiSsid: wifiSsid ?? this.wifiSsid,
      audioUrl: audioUrl ?? this.audioUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      wifiFingerprints: wifiFingerprints ?? this.wifiFingerprints,
    );
  }

  // Convert to map for storage
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'wifiSsid': wifiSsid,
      'audioUrl': audioUrl,
      'wifiFingerprints': wifiFingerprints,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  // Create from map (Firestore document)
  factory Exhibit.fromMap(Map<String, dynamic> map, {String? id}) {
    return Exhibit(
      id: id ?? map['id'] ?? '',
      name: map['name'] as String? ?? 'Unnamed Exhibit',
      description: map['description'] as String? ?? '',
      wifiSsid: map['wifiSsid'] as String?,
      audioUrl: map['audioUrl'] as String?,
      wifiFingerprints: (map['wifiFingerprints'] as List?)?.cast<Map<String, dynamic>>(),
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  // Create from Firestore document
  factory Exhibit.fromFirestore(DocumentSnapshot doc) {
    return Exhibit.fromMap(doc.data() as Map<String, dynamic>, id: doc.id);
  }
}
