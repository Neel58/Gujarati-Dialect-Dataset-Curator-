import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import 'onboarding_screen.dart';

class AddPromptScreen extends ConsumerStatefulWidget {
  final Profile profile;
  const AddPromptScreen({super.key, required this.profile});

  @override
  ConsumerState<AddPromptScreen> createState() => _AddPromptScreenState();
}

class _AddPromptScreenState extends ConsumerState<AddPromptScreen> {
  final _formKey = GlobalKey<FormState>();
  final _promptCtrl = TextEditingController();
  final _standardCtrl = TextEditingController();
  Dialect? _selectedDialect;
  bool _isLoading = false;

  @override
  void dispose() {
    _promptCtrl.dispose();
    _standardCtrl.dispose();
    super.dispose();
  }

  bool _isGujaratiValid(String text) {
    final norm = text.replaceAll(RegExp(r'\s'), '');
    if (norm.isEmpty) return false;
    final gujChars = norm.replaceAll(RegExp(r'[^઀-૿]'), '');
    return (gujChars.length / norm.length) >= 0.5;
  }

  String _mapError(dynamic e) {
    final msg = e.toString();
    if (msg.contains('23505')) return 'This prompt already exists for this dialect.';
    if (msg.contains('Rate limit exceeded')) return 'You can only submit 20 prompts per 24 hours.';
    if (msg.contains('at least 50%')) return 'Text must contain at least 50% Gujarati characters.';
    return msg;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_selectedDialect == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a dialect.')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      await Supabase.instance.client.from('prompts').insert({
        'text_gu': _promptCtrl.text.trim(),
        'standard_equivalent_gu': _standardCtrl.text.trim().isEmpty ? null : _standardCtrl.text.trim(),
        'dialect_id': _selectedDialect!.id,
        'submitted_by': widget.profile.id,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Prompt submitted for review.')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_mapError(e))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dialectsAsync = ref.watch(dialectsProvider);

    dialectsAsync.whenData((dialects) {
      if (_selectedDialect == null && dialects.isNotEmpty) {
        _selectedDialect = dialects.firstWhere(
          (d) => d.id == widget.profile.nativeDialectId,
          orElse: () => dialects.first,
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Submit a Prompt')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Text(
                  'Guidelines:\n- Write it the way you\'d actually say it.\n- No personal info, phone numbers, or offensive content.\n- Must be primarily in Gujarati script.',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _promptCtrl,
                decoration: const InputDecoration(
                  labelText: 'Prompt (Gujarati)',
                  alignLabelWithHint: true,
                ),
                maxLines: 4,
                maxLength: 200,
                validator: (v) {
                  if (v == null || v.trim().length < 5) return 'Minimum 5 characters';
                  if (!_isGujaratiValid(v)) return 'Must be at least 50% Gujarati script';
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              dialectsAsync.when(
                data: (dialects) => DropdownButtonFormField<Dialect>(
                  decoration: const InputDecoration(labelText: 'Dialect this sentence is written in'),
                  initialValue: _selectedDialect,
                  items: dialects.map((d) => DropdownMenuItem(
                    value: d,
                    child: Text('${d.nameEn} - ${d.nameGu}'),
                  )).toList(),
                  onChanged: (v) => setState(() => _selectedDialect = v),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('Error loading dialects'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _standardCtrl,
                decoration: const InputDecoration(
                  labelText: 'Standard Gujarati equivalent (optional)',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Submit Prompt'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
