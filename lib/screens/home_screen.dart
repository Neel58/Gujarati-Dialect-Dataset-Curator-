import 'package:flutter/material.dart';
import '../data/prompts.dart';
import '../services/supabase_service.dart';
import 'speaker_select_screen.dart';
import 'review_screen.dart';
import 'edit_profile_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _editProfile(BuildContext context) async {
    final profile = await SupabaseService.instance.getOperatorProfile();
    if (profile == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Operator profile not found.')),
      );
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditProfileScreen(currentProfile: profile)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gujarati Dialect Curator'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            tooltip: 'Edit Profile',
            onPressed: () => _editProfile(context),
          ),
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'Review uploads',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReviewScreen()),
            ),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: PromptBank.prompts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final prompt = PromptBank.prompts[index];
          return Card(
            child: ListTile(
              title: Text(prompt, style: const TextStyle(fontSize: 18)),
              trailing: const Icon(Icons.mic),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SpeakerSelectScreen(prompt: prompt),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}