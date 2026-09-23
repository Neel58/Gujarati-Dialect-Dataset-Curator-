class Dialect {
  final int id;
  final String slug;
  final String nameEn;
  final String nameGu;

  Dialect({required this.id, required this.slug, required this.nameEn, required this.nameGu});

  factory Dialect.fromJson(Map<String, dynamic> json) => Dialect(
        id: json['id'] as int,
        slug: json['slug'] as String,
        nameEn: json['name_en'] as String,
        nameGu: json['name_gu'] as String,
      );
}

class District {
  final int id;
  final String nameEn;
  final String? nameGu;
  final String state;

  District({required this.id, required this.nameEn, this.nameGu, required this.state});

  factory District.fromJson(Map<String, dynamic> json) => District(
        id: json['id'] as int,
        nameEn: json['name_en'] as String,
        nameGu: json['name_gu'] as String?,
        state: json['state'] as String,
      );
}

class Profile {
  final String id;
  final String displayName;
  final String ageBand;
  final String? gender;
  final int nativeDialectId;
  final int grewUpDistrictId;
  final int yearsLivedThere;
  final bool isAdmin;
  final DateTime consentedAt;

  Profile({
    required this.id,
    required this.displayName,
    required this.ageBand,
    this.gender,
    required this.nativeDialectId,
    required this.grewUpDistrictId,
    required this.yearsLivedThere,
    required this.isAdmin,
    required this.consentedAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        displayName: json['display_name'] as String,
        ageBand: json['age_band'] as String,
        gender: json['gender'] as String?,
        nativeDialectId: json['native_dialect_id'] as int,
        grewUpDistrictId: json['grew_up_district_id'] as int,
        yearsLivedThere: json['years_lived_there'] as int,
        isAdmin: json['is_admin'] as bool? ?? false,
        consentedAt: DateTime.parse(json['consented_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'display_name': displayName,
        'age_band': ageBand,
        'gender': gender,
        'native_dialect_id': nativeDialectId,
        'grew_up_district_id': grewUpDistrictId,
        'years_lived_there': yearsLivedThere,
        'consented_at': consentedAt.toIso8601String(),
      };
}

class Prompt {
  final String id;
  final String textGu;
  final String? standardEquivalentGu;
  final int dialectId;
  final String? submittedBy;
  final String status;

  Prompt({
    required this.id,
    required this.textGu,
    this.standardEquivalentGu,
    required this.dialectId,
    this.submittedBy,
    required this.status,
  });

  factory Prompt.fromJson(Map<String, dynamic> json) => Prompt(
        id: json['id'] as String,
        textGu: json['text_gu'] as String,
        standardEquivalentGu: json['standard_equivalent_gu'] as String?,
        dialectId: json['dialect_id'] as int,
        submittedBy: json['submitted_by'] as String?,
        status: json['status'] as String,
      );
}

class Recording {
  final String id;
  final String userId;
  final String? promptId;
  final String? promptText;
  final int dialectId;
  final String? dialectOtherText;
  final int districtId;
  final int durationMs;
  final int sampleRate;
  final int channels;
  final String audioFormat;
  final String storagePath;
  final DateTime createdAt;

  Recording({
    required this.id,
    required this.userId,
    this.promptId,
    this.promptText,
    required this.dialectId,
    this.dialectOtherText,
    required this.districtId,
    required this.durationMs,
    required this.sampleRate,
    required this.channels,
    required this.audioFormat,
    required this.storagePath,
    required this.createdAt,
  });

  factory Recording.fromJson(Map<String, dynamic> json) => Recording(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        promptId: json['prompt_id'] as String?,
        promptText: json['prompt_text'] as String?,
        dialectId: json['dialect_id'] as int,
        dialectOtherText: json['dialect_other_text'] as String?,
        districtId: json['district_id'] as int,
        durationMs: json['duration_ms'] as int,
        sampleRate: json['sample_rate'] as int,
        channels: json['channels'] as int,
        audioFormat: json['audio_format'] as String,
        storagePath: json['storage_path'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'prompt_id': promptId,
        'prompt_text': promptText,
        'dialect_id': dialectId,
        'dialect_other_text': dialectOtherText,
        'district_id': districtId,
        'duration_ms': durationMs,
        'sample_rate': sampleRate,
        'channels': channels,
        'audio_format': audioFormat,
        'storage_path': storagePath,
        'created_at': createdAt.toIso8601String(),
      };
}
