import '../entities/prompt.dart';

abstract class PromptRepository {
  Future<List<Prompt>> getActivePrompts();
  Future<Prompt?> getPrompt(String id);
}
