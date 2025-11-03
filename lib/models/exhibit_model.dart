import 'package:cloud_firestore/cloud_firestore.dart';

class Exhibit {
  final String id;
  final String name;
  final String description;
  final String? wifiSsid;
  final String? audioUrl;
  final DateTime? createdAt;
  final String? version; // App version that created the exhibit
  final String? locationHint; // WiFi network hint for location context
  final List<String>? photos; // Exhibit photos
  final Map<String, dynamic>? wifiFingerprint; // WiFi fingerprint data (current format)

  Exhibit({
    required this.id,
    required this.name,
    required this.description,
    this.wifiSsid,
    this.audioUrl,
    this.createdAt,
    this.version,
    this.locationHint,
    this.photos,
    this.wifiFingerprint,
  });

  // Create a copyWith method for easy updates
  Exhibit copyWith({
    String? id,
    String? name,
    String? description,
    String? wifiSsid,
    String? audioUrl,
    DateTime? createdAt,
    String? version,
    String? locationHint,
    List<String>? photos,
    Map<String, dynamic>? wifiFingerprint,
  }) {
    return Exhibit(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      wifiSsid: wifiSsid ?? this.wifiSsid,
      audioUrl: audioUrl ?? this.audioUrl,
      createdAt: createdAt ?? this.createdAt,
      version: version ?? this.version,
      locationHint: locationHint ?? this.locationHint,
      photos: photos ?? this.photos,
      wifiFingerprint: wifiFingerprint ?? this.wifiFingerprint,
    );
  }

  // Convert to map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'wifiSsid': wifiSsid,
      'audioUrl': audioUrl,
      'createdAt': createdAt?.toIso8601String(),
      'version': version,
      'locationHint': locationHint,
      'photos': photos,
      'wifiFingerprint': wifiFingerprint,
    };
  }

  // Create from map (updated to handle new fields)
  factory Exhibit.fromMap(Map<String, dynamic> map) {
    DateTime? parseTimestamp(dynamic timestamp) {
      if (timestamp == null) return null;
      
      // Handle Firestore Timestamp
      if (timestamp is Timestamp) {
        return timestamp.toDate();
      }
      
      // Handle ISO 8601 string
      if (timestamp is String) {
        return DateTime.tryParse(timestamp);
      }
      
      // Handle other cases (like milliseconds since epoch)
      if (timestamp is int) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
      
      return null;
    }
    
    return Exhibit(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      description: map['description'] as String? ?? '',
      wifiSsid: map['wifiSsid'] as String?,
      audioUrl: map['audioUrl'] as String?,
      createdAt: parseTimestamp(map['createdAt'] ?? map['timestamp']),
      version: map['version'] as String?,
      locationHint: map['location_hint'] as String?,
      photos: map['photos'] != null
          ? List<String>.from(map['photos'] as List)
          : null,
      wifiFingerprint: map['wifi_fingerprint'] as Map<String, dynamic>?,
    );
  }

  // Validate if the exhibit ID follows the new format
  bool get hasValidUniqueId {
    // Check if it's the new format (EX_YYYYMMDDHHMMSS_XXXXXX_XXXX_XXX)
    final regex = RegExp(r'^EX_\d{14}_[A-Z0-9]{6}_[A-Z0-9]{4}_[A-Z0-9]{3}$');
    return regex.hasMatch(id) || id.isNotEmpty; // Allow legacy IDs to still work
  }

  // Get formatted creation date
  String get formattedCreatedDate {
    if (createdAt == null) return 'Unknown';
    return '${createdAt!.day}/${createdAt!.month}/${createdAt!.year} ${createdAt!.hour}:${createdAt!.minute.toString().padLeft(2, '0')}';
  }
}
