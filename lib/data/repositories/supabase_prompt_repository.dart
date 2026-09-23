import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/prompt.dart';
import '../../domain/repositories/prompt_repository.dart';

class SupabasePromptRepository implements PromptRepository {
  final SupabaseClient client;

  SupabasePromptRepository(this.client);

  @override
  Future<List<Prompt>> getActivePrompts() async {
    final response = await client
        .from('prompts')
        .select()
        .eq('active_status', true)
        .order('created_at', ascending: false);
        
    return (response as List).map((json) => _fromJson(json)).toList();
  }

  @override
  Future<Prompt?> getPrompt(String id) async {
    final response = await client
        .from('prompts')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (response == null) return null;
    return _fromJson(response);
  }

  Prompt _fromJson(Map<String, dynamic> json) {
    return Prompt(
      id: json['id'] as String,
      gujaratiText: json['gujarati_text'] as String,
      transliteration: json['transliteration'] as String?,
      category: json['category'] as String?,
      difficulty: json['difficulty'] as String?,
      activeStatus: json['active_status'] as bool,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    );
  }
}
