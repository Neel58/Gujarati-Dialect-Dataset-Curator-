import 'package:flutter/material.dart';
import '../models/contributor.dart';
import 'record_screen.dart';

class ThirdPartySpeakerForm extends StatefulWidget {
  final String prompt;
  
  const ThirdPartySpeakerForm({super.key, required this.prompt});

  @override
  State<ThirdPartySpeakerForm> createState() => _ThirdPartySpeakerFormState();
}

class _ThirdPartySpeakerFormState extends State<ThirdPartySpeakerForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _placeCtrl = TextEditingController();
  final _dialectCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _placeCtrl.dispose();
    _dialectCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    
    // Create a temporary contributor representing the third party speaker
    final speaker = Contributor(
      id: '', // Not tied to an auth account
      name: _nameCtrl.text.trim(),
      age: int.parse(_ageCtrl.text.trim()),
      place: _placeCtrl.text.trim(),
      dialect: _dialectCtrl.text.trim(),
    );
    
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => RecordScreen(
          prompt: widget.prompt,
          speaker: speaker,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Speaker Details')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Please enter the details of the person speaking.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: _ageCtrl,
                decoration: const InputDecoration(labelText: 'Age'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (int.tryParse(v.trim()) == null) return 'Enter a number';
                  return null;
                },
              ),
              TextFormField(
                controller: _placeCtrl,
                decoration: const InputDecoration(labelText: 'Place'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: _dialectCtrl,
                decoration: const InputDecoration(labelText: 'Dialect (e.g. Kathiyawadi, Surti)'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submit,
                child: const Text('Continue to Record'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
