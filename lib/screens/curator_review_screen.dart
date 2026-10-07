import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/gsip_models.dart';
import 'missions_screen.dart';

final reviewAssetsProvider = FutureProvider.family<List<DataAsset>, ReviewStatus?>((ref, status) async {
  final repo = ref.watch(gsipRepositoryProvider);
  return repo.fetchDataAssets(reviewStatus: status, limit: 100);
});

class CuratorReviewScreen extends ConsumerStatefulWidget {
  const CuratorReviewScreen({super.key});

  @override
  ConsumerState<CuratorReviewScreen> createState() => _CuratorReviewScreenState();
}

class _CuratorReviewScreenState extends ConsumerState<CuratorReviewScreen> {
  ReviewStatus _selectedStatus = ReviewStatus.pending;
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentlyPlayingId;
  PlayerState _playerState = PlayerState.stopped;

  @override
  void initState() {
    super.initState();
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _playerState = state);
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _toggleAudio(DataAsset asset) async {
    if (_currentlyPlayingId == asset.id && _playerState == PlayerState.playing) {
      await _audioPlayer.pause();
      return;
    }

    if (asset.storagePath == null || asset.storagePath!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No audio storage path available for this clip.')),
      );
      return;
    }

    try {
      final signedUrl = await Supabase.instance.client.storage
          .from('audio-clips')
          .createSignedUrl(asset.storagePath!, 60);

      setState(() => _currentlyPlayingId = asset.id);
      await _audioPlayer.play(UrlSource(signedUrl));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not stream audio: $e')),
        );
      }
    }
  }

  Future<void> _updateStatus(DataAsset asset, ReviewStatus newStatus) async {
    final repo = ref.read(gsipRepositoryProvider);
    final currentUserId = repo.currentUserId;

    // Security check: Contributor cannot approve their own data!
    if (newStatus == ReviewStatus.approved &&
        asset.contributorId != null &&
        asset.contributorId == currentUserId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('Authorization violation: You cannot approve your own submission.'),
        ),
      );
      return;
    }

    try {
      await repo.updateReviewStatus(
        assetId: asset.id,
        status: newStatus,
        notes: 'Review by curator $currentUserId',
      );

      ref.invalidate(reviewAssetsProvider(_selectedStatus));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Asset status updated to ${newStatus.value}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update status: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final assetsAsync = ref.watch(reviewAssetsProvider(_selectedStatus));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Curation & Quality Review'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(reviewAssetsProvider(_selectedStatus)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: ReviewStatus.values.map((status) {
                final isSelected = _selectedStatus == status;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(status.value.toUpperCase()),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) setState(() => _selectedStatus = status);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: assetsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Error: $err'),
                    ElevatedButton(
                      onPressed: () => ref.invalidate(reviewAssetsProvider(_selectedStatus)),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (assets) {
                if (assets.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.rule_folder_outlined, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(
                            'No ${_selectedStatus.value} assets in curation queue.',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Submissions from contributors will appear here for automated quality verification and human approval.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: assets.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
                  itemBuilder: (context, idx) {
                    final a = assets[idx];
                    final isPlaying = _currentlyPlayingId == a.id && _playerState == PlayerState.playing;

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header: Quality & Consent
                            Row(
                              children: [
                                if (a.qualityScore != null)
                                  Chip(
                                    label: Text(
                                      'Quality: ${a.qualityScore} / 100',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    backgroundColor: a.qualityScore! >= 80
                                        ? Colors.teal.shade50
                                        : Colors.amber.shade50,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                const SizedBox(width: 8),
                                Chip(
                                  label: Text(
                                    'Consent: ${a.consentTypeId.replaceAll('_', ' ').toUpperCase()}',
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                                const Spacer(),
                                Chip(
                                  label: Text(
                                    a.reviewStatus.value.toUpperCase(),
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                  backgroundColor: a.reviewStatus == ReviewStatus.approved
                                      ? Colors.teal.shade100
                                      : (a.reviewStatus == ReviewStatus.rejected
                                          ? Colors.red.shade100
                                          : Colors.grey.shade200),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Gujarati Transcript
                            if (a.transcript != null && a.transcript!.isNotEmpty) ...[
                              const Text('Transcript (Gujarati):', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              const SizedBox(height: 4),
                              Text(
                                a.transcript!,
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 12),
                            ],

                            // Audio & Technical Info
                            Row(
                              children: [
                                IconButton.filled(
                                  icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                                  onPressed: () => _toggleAudio(a),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Duration: ${((a.durationMs ?? 0) / 1000).toStringAsFixed(1)}s • ${a.sampleRate ?? 16000} Hz • ${a.channels == 1 ? "Mono" : "Stereo"}',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                      ),
                                      Text(
                                        'Domain: ${a.domainId} • Dialect ID: ${a.dialectId ?? "Not specified"}',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Explainable Quality Checks Report (Feature 3 & 4)
                            FutureBuilder<DataAssetQualityChecks?>(
                              future: ref.read(gsipRepositoryProvider).fetchQualityChecks(a.id),
                              builder: (context, qcSnap) {
                                if (qcSnap.connectionState == ConnectionState.waiting) {
                                  return const LinearProgressIndicator(minHeight: 2);
                                }
                                final qc = qcSnap.data;
                                if (qc == null || qc.qualityExplanation.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                return Container(
                                  padding: const EdgeInsets.all(8),
                                  margin: const EdgeInsets.only(top: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Automated Quality Checks:',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                                      ),
                                      const SizedBox(height: 4),
                                      ...qc.qualityExplanation.map((item) => Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 1.0),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  item.passed ? Icons.check_circle : Icons.warning_amber_rounded,
                                                  size: 13,
                                                  color: item.passed ? Colors.teal : Colors.deepOrange,
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    item.message,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: item.passed ? Colors.black87 : Colors.deepOrange.shade800,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )),
                                    ],
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 16),

                            // Curator Decision Action Buttons
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                                  onPressed: () => _updateStatus(a, ReviewStatus.rejected),
                                  child: const Text('Reject'),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: () => _updateStatus(a, ReviewStatus.needsRevision),
                                  child: const Text('Request Revision'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                                  onPressed: () => _updateStatus(a, ReviewStatus.approved),
                                  child: const Text('Approve'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
