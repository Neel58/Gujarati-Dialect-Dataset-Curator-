class RecordingEntry {
  final String? id;
  final String prompt;
  final String storagePath;
  final String operatorId;
  final String speakerName;
  final int speakerAge;
  final String speakerPlace;
  final String speakerDialect;
  final DateTime? createdAt;

  RecordingEntry({
    this.id,
    required this.prompt,
    required this.storagePath,
    required this.operatorId,
    required this.speakerName,
    required this.speakerAge,
    required this.speakerPlace,
    required this.speakerDialect,
    this.createdAt,
  });

  factory RecordingEntry.fromJson(Map<String, dynamic> json) {
    return RecordingEntry(
      id: json['id'] as String?,
      prompt: json['prompt'] as String,
      storagePath: json['storage_path'] as String,
      operatorId: json['operator_id'] as String,
      speakerName: json['speaker_name'] as String,
      speakerAge: json['speaker_age'] as int,
      speakerPlace: json['speaker_place'] as String,
      speakerDialect: json['speaker_dialect'] as String,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'] as String) 
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'prompt': prompt,
    'storage_path': storagePath,
    'operator_id': operatorId,
    'speaker_name': speakerName,
    'speaker_age': speakerAge,
    'speaker_place': speakerPlace,
    'speaker_dialect': speakerDialect,
    if (createdAt != null) 'created_at': createdAt?.toIso8601String(),
  };
}