class Exhibit {
  final String id;
  final String name;
  final String description;
  final String? wifiSsid;
  final String? audioUrl;
  final DateTime createdAt;

  Exhibit({
    required this.id,
    required this.name,
    required this.description,
    this.wifiSsid,
    this.audioUrl,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  // Create a copyWith method for easy updates
  Exhibit copyWith({
    String? id,
    String? name,
    String? description,
    String? wifiSsid,
    String? audioUrl,
    DateTime? createdAt,
  }) {
    return Exhibit(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      wifiSsid: wifiSsid ?? this.wifiSsid,
      audioUrl: audioUrl ?? this.audioUrl,
      createdAt: createdAt ?? this.createdAt,
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
      'createdAt': createdAt.toIso8601String(),
    };
  }

  // Create from map
  factory Exhibit.fromMap(Map<String, dynamic> map) {
    return Exhibit(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String,
      wifiSsid: map['wifiSsid'] as String?,
      audioUrl: map['audioUrl'] as String?,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : null,
    );
  }
}
