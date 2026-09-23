import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/contributor.dart';
import '../../domain/repositories/contributor_repository.dart';

class SupabaseContributorRepository implements ContributorRepository {
  final SupabaseClient client;

  SupabaseContributorRepository(this.client);

  @override
  Future<Contributor> createContributor(Contributor contributor) async {
    final data = {
      'id': contributor.id,
      'name': contributor.name,
      'age_group': contributor.ageGroup,
      'native_region': contributor.nativeRegion,
      'current_region': contributor.currentRegion,
      'dialect': contributor.dialect,
      'consent_given': contributor.consentGiven,
    };
    
    final response = await client.from('contributors').insert(data).select().single();
    return _fromJson(response);
  }

  @override
  Future<Contributor?> getContributor(String id) async {
    try {
      final response = await client
          .from('contributors')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (response == null) return null;
      return _fromJson(response);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Contributor> updateContributor(Contributor contributor) async {
    final data = {
      'name': contributor.name,
      'age_group': contributor.ageGroup,
      'native_region': contributor.nativeRegion,
      'current_region': contributor.currentRegion,
      'dialect': contributor.dialect,
      'consent_given': contributor.consentGiven,
    };

    final response = await client
        .from('contributors')
        .update(data)
        .eq('id', contributor.id)
        .select()
        .single();
    return _fromJson(response);
  }

  Contributor _fromJson(Map<String, dynamic> json) {
    return Contributor(
      id: json['id'] as String,
      name: json['name'] as String?,
      ageGroup: json['age_group'] as String,
      nativeRegion: json['native_region'] as String,
      currentRegion: json['current_region'] as String,
      dialect: json['dialect'] as String,
      consentGiven: json['consent_given'] as bool,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    );
  }
}
