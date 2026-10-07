# Gujarati Speech Intelligence Platform (GSIP)

> Build, evaluate, and improve Gujarati speech AI with curated, dialect-aware data.

The **Gujarati Speech Intelligence Platform** transforms Gujarati speech data collection from a form/recording-oriented application into a complete data-generation, curation, benchmark evaluation, and intelligence platform.

---

## Complete Intelligence Loop

```text
DATA REQUIREMENT
       ↓
DATA GAP ANALYSIS
       ↓
TARGETED COLLECTION MISSION
       ↓
CONTRIBUTOR (RECORD / REVIEW)
       ↓
AUTOMATED QUALITY CHECKS
       ↓
HUMAN CURATION & APPROVAL
       ↓
CURATED DATASET & VERSIONING
       ↓
BENCHMARK & MODEL EVALUATION (WER/CER)
       ↓
FAILURE ANALYSIS & RECOMMENDATIONS
       ↓
NEW MISSION (REPEAT)
```

---

## Core Capabilities

### 1. Targeted Mission Engine (`missions`)
- Replaces generic recording lists with database-driven, targeted collection missions.
- Supports mission types: `recording`, `transcription_review`, `metadata_validation`, `dialect_validation`.
- Priority-weighted with real-time completion tracking (`completed_quantity` / `target_quantity`).

### 2. Canonical Data Asset Model (`data_assets`)
- Evolves beyond raw recording records into comprehensive `DataAsset` objects with quality scores, consent classification, domain/environment metadata, and provenance tracking.
- Preserves backward compatibility with existing `recordings` rows.

### 3. Automated Quality Layer (`QualityEngine`)
- Real deterministic audio analysis: sample rate (16 kHz), mono channels, 16-bit PCM, duration validation, file size check, peak volume, RMS dBFS, and clipping detection.
- Generates transparent, human-explainable quality breakdown items.
- Identifies identical uploads via SHA-256 binary hash.

### 4. Human Curation & Review (`CuratorReviewScreen`)
- Full curator workflow: listen to audio via secure signed URLs, inspect transcripts, evaluate automated quality scores, and transition assets between `pending`, `approved`, `needs_revision`, and `rejected`.
- **Authorization enforced**: Contributors are barred from approving their own submissions at both client and database levels.

### 5. Dataset Builder & Immutable Versioning (`DatasetBuilderService`)
- Filter approved assets by dialect, domain, environment, and quality score.
- **Strict consent enforcement**: Commercial AI datasets strictly exclude assets limited to research-only consent.
- Computes reproducible statistics: asset count, total hours, unique speakers, dialect distributions.
- Published versions (`v1.0`, `v1.1`) are immutable in the database via triggers.

### 6. Data Coverage & Gap Engine (`CoverageGapEngine`)
- Slices approved corpus by dialect, domain, environment, and demographic age groups.
- Detects under-represented data combinations against coverage targets.
- Generates **actionable recommendations with 1-click `[Create Mission]`** to immediately deploy collection tasks.

### 7. Gujarati Speech Benchmark (`benchmarks`)
- Features the **Gujarati ASR Robustness Benchmark (v1.0)** covering standard Gujarati, Kathiyawadi, Surti, Charotari, medical terminology, and telephone channels.
- Test assets and ground-truth references are protected from public dataset export.

### 8. Model Evaluation & Failure Analysis (`EvaluationEngine`)
- Upload model hypotheses and evaluate against benchmark references.
- Mathematically verified dynamic programming computation of **Word Error Rate (WER)** and **Character Error Rate (CER)**.
- Detailed error breakdown: substitutions, deletions, and insertions.
- Category-level error rates by dialect, domain, and acoustic environment.

### 9. Actionable Recommendations from Model Failures
- Automatically detects categories where error rates spike.
- Derives targeted data requirements and suggests targeted collection missions with 1-click deployment.

### 10. External AI Provider Boundary
- Clean abstraction interfaces (`TranscriptionProvider`, `DialectDetectionProvider`, `QualityAnalysisProvider`).
- ML features that lack local or configured weights return explicit `UNAVAILABLE` status rather than fabricated or randomized outputs.

---

## Setup & Supabase Migration

### 1. Database Provisioning
Run migrations in the Supabase SQL Editor in this order:
1. `supabase/harden_profiles_is_admin.sql` (Security hardening for `is_admin`)
2. `supabase/migrations/v3_gsip_core.sql` (GSIP Core platform tables, RLS, triggers, buckets, and backfill)

### 2. Environment Configuration
Provide credentials via `.env` or `--dart-define`:
```bash
flutter run --dart-define=SUPABASE_URL="https://YOUR_PROJECT.supabase.co" --dart-define=SUPABASE_ANON_KEY="YOUR_ANON_KEY"
```

---

## Verification & Testing

Run static analysis:
```bash
flutter analyze
```

Run comprehensive unit and integration test suite:
```bash
flutter test
```
- `test/evaluation_engine_test.dart` — Mathematical verification of WER, CER, substitutions, deletions, insertions, and batch category breakdown.
- `test/quality_engine_test.dart` — PCM volume analysis, format verification, and explainable quality scoring.
- `test/coverage_gap_engine_test.dart` — Corpus aggregation, deficit calculation, and gap-to-mission proposals.
- `test/dataset_builder_service_test.dart` — Consent boundary enforcement, pending asset exclusion, and versioning.
- `test/validators_test.dart` & `test/wav_info_test.dart` — Script and audio validation.
