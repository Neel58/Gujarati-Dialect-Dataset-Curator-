import 'package:flutter/material.dart';
import '../models/contributor.dart';
import '../services/supabase_service.dart';
import 'record_screen.dart';
import 'third_party_speaker_form.dart';

class SpeakerSelectScreen extends StatefulWidget {
  final String prompt;

  const SpeakerSelectScreen({super.key, required this.prompt});

  @override
  State<SpeakerSelectScreen> createState() => _SpeakerSelectScreenState();
}

class _SpeakerSelectScreenState extends State<SpeakerSelectScreen> {
  bool _isLoading = false;

  Future<void> _selectMyself() async {
    setState(() => _isLoading = true);
    try {
      final profile = await SupabaseService.instance.getOperatorProfile();
      if (!mounted) return;
      if (profile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Operator profile not found. Please log in again.')),
        );
        return;
      }
      
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => RecordScreen(
            prompt: widget.prompt,
            speaker: profile,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load profile: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _selectSomeoneElse() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ThirdPartySpeakerForm(prompt: widget.prompt),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Who is speaking?')),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Are you recording yourself, or someone else?',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                FilledButton.icon(
                  icon: const Icon(Icons.person),
                  label: const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('Recording Myself', style: TextStyle(fontSize: 18)),
                  ),
                  onPressed: _selectMyself,
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  icon: const Icon(Icons.group),
                  label: const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('Recording Someone Else', style: TextStyle(fontSize: 18)),
                  ),
                  onPressed: _selectSomeoneElse,
                ),
              ],
            ),
          ),
    );
  }
}
