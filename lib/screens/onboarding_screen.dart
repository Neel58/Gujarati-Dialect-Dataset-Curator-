import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import 'home_screen.dart';

// Providers for caching dialects and districts
final dialectsProvider = FutureProvider<List<Dialect>>((ref) async {
  final data = await Supabase.instance.client.from('dialects').select().eq('is_active', true).order('sort_order');
  return data.map((json) => Dialect.fromJson(json)).toList();
});

final districtsProvider = FutureProvider<List<District>>((ref) async {
  final data = await Supabase.instance.client.from('districts').select().order('name_en');
  return data.map((json) => District.fromJson(json)).toList();
});

class OnboardingScreen extends ConsumerStatefulWidget {
  final Profile? currentProfile;
  const OnboardingScreen({super.key, this.currentProfile});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _yearsCtrl = TextEditingController();
  
  String? _ageBand;
  String? _gender;
  Dialect? _selectedDialect;
  District? _selectedDistrict;
  bool _isLoading = false;

  final _ageBands = ['18-25', '26-35', '36-50', '51-65', '65+'];
  final _genders = ['female', 'male', 'other', 'prefer_not'];

  @override
  void initState() {
    super.initState();
    if (widget.currentProfile != null) {
      _nameCtrl.text = widget.currentProfile!.displayName;
      _yearsCtrl.text = widget.currentProfile!.yearsLivedThere.toString();
      _ageBand = widget.currentProfile!.ageBand;
      _gender = widget.currentProfile!.gender;
      // Note: dialect and district need to be set after they are loaded
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _yearsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_ageBand == null || _selectedDialect == null || _selectedDistrict == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all required fields.')));
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Not logged in');
      
      // Get consented_at from user metadata if available, otherwise now
      final consentedAtStr = user.userMetadata?['consented_at'] as String?;
      final consentedAt = consentedAtStr != null ? DateTime.parse(consentedAtStr) : DateTime.now();
      
      final profile = Profile(
        id: user.id,
        displayName: _nameCtrl.text.trim(),
        ageBand: _ageBand!,
        gender: _gender,
        nativeDialectId: _selectedDialect!.id,
        grewUpDistrictId: _selectedDistrict!.id,
        yearsLivedThere: int.parse(_yearsCtrl.text.trim()),
        isAdmin: false, // will be ignored by trigger if attempting update
        consentedAt: consentedAt,
      );

      await Supabase.instance.client.from('profiles').upsert(profile.toJson());
      
      if (!mounted) return;
      // Trigger a rebuild of AuthGate by doing pushReplacement to AuthGate or HomeScreen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dialectsAsync = ref.watch(dialectsProvider);
    final districtsAsync = ref.watch(districtsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Complete Profile')),
      body: dialectsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Error loading data: $err'),
              ElevatedButton(
                onPressed: () {
                  ref.invalidate(dialectsProvider);
                  ref.invalidate(districtsProvider);
                },
                child: const Text('Retry'),
              )
            ],
          ),
        ),
        data: (dialects) => districtsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Error: $err')),
          data: (districts) {
            if (_selectedDialect == null && widget.currentProfile != null && dialects.isNotEmpty) {
              _selectedDialect = dialects.firstWhere(
                (d) => d.id == widget.currentProfile!.nativeDialectId,
                orElse: () => dialects.first,
              );
            }
            if (_selectedDistrict == null && widget.currentProfile != null && districts.isNotEmpty) {
              _selectedDistrict = districts.firstWhere(
                (d) => d.id == widget.currentProfile!.grewUpDistrictId,
                orElse: () => districts.first,
              );
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(labelText: 'Display Name *'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Age Band *'),
                      initialValue: _ageBand,
                      items: _ageBands.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                      onChanged: (v) => setState(() => _ageBand = v),
                      validator: (v) => v == null ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Gender (Optional)'),
                      initialValue: _gender,
                      items: _genders.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                      onChanged: (v) => setState(() => _gender = v),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<Dialect>(
                      decoration: const InputDecoration(labelText: 'Native Dialect *'),
                      initialValue: _selectedDialect,
                      items: dialects.map((d) => DropdownMenuItem(
                        value: d, 
                        child: Text('${d.nameEn} - ${d.nameGu}'),
                      )).toList(),
                      onChanged: (v) => setState(() => _selectedDialect = v),
                      validator: (v) => v == null ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownMenu<District>(
                      width: MediaQuery.of(context).size.width - 32,
                      label: const Text('District you grew up in *'),
                      enableFilter: true,
                      initialSelection: _selectedDistrict,
                      onSelected: (v) => setState(() => _selectedDistrict = v),
                      dropdownMenuEntries: districts.map((d) => DropdownMenuEntry(
                        value: d,
                        label: d.nameGu != null ? '${d.nameEn} (${d.nameGu})' : d.nameEn,
                      )).toList(),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _yearsCtrl,
                      decoration: const InputDecoration(labelText: 'Years lived there *'),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (int.tryParse(v.trim()) == null) return 'Must be a number';
                        return null;
                      },
                    ),
                    const SizedBox(height: 32),
                    FilledButton(
                      onPressed: _isLoading ? null : _submit,
                      child: _isLoading 
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Save Profile'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
