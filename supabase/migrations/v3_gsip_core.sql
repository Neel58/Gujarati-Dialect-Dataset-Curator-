-- =============================================================================
-- GSIP Migration v3: Core Platform Tables
-- File: supabase/migrations/v3_gsip_core.sql
-- Run in Supabase SQL Editor AFTER harden_profiles_is_admin.sql
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. CONSENT TYPES
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.consent_types (
    id TEXT PRIMARY KEY,  -- e.g. 'research_only', 'commercial_ai', 'open'
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    allows_research BOOLEAN NOT NULL DEFAULT true,
    allows_commercial BOOLEAN NOT NULL DEFAULT false,
    allows_open_distribution BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.consent_types (id, name, description, allows_research, allows_commercial, allows_open_distribution) VALUES
('research_only', 'Research Only', 'May be used for academic and non-commercial research only.', true, false, false),
('commercial_ai', 'Commercial AI', 'May be used for training commercial AI systems.', true, true, false),
('open', 'Open', 'May be freely used and distributed under open license.', true, true, true)
ON CONFLICT (id) DO NOTHING;


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. DOMAINS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.domains (
    id TEXT PRIMARY KEY,  -- e.g. 'general', 'healthcare', 'education'
    name TEXT NOT NULL,
    description TEXT
);

INSERT INTO public.domains (id, name, description) VALUES
('general',      'General',       'Everyday conversation and general speech'),
('healthcare',   'Healthcare',    'Medical terminology and health-related conversation'),
('education',    'Education',     'Educational content and academic speech'),
('agriculture',  'Agriculture',   'Farming, rural, and agricultural conversation'),
('commerce',     'Commerce',      'Business, trade, and commercial conversation'),
('government',   'Government',    'Civic and government-related speech'),
('religious',    'Religious',     'Religious and devotional speech'),
('news',         'News/Media',    'News reading and media content'),
('narrative',    'Narrative',     'Storytelling and narrative speech')
ON CONFLICT (id) DO NOTHING;


-- ─────────────────────────────────────────────────────────────────────────────
-- 3. ENVIRONMENTS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.environments (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT
);

INSERT INTO public.environments (id, name, description) VALUES
('quiet_indoor',  'Quiet Indoor',   'Quiet room, minimal background noise'),
('noisy_indoor',  'Noisy Indoor',   'Indoor environment with background noise'),
('outdoor',       'Outdoor',        'Outside recording'),
('telephone',     'Telephone',      'Telephone or mobile call quality'),
('vehicle',       'Vehicle',        'Recorded in a moving vehicle'),
('public_space',  'Public Space',   'Public area with crowd noise')
ON CONFLICT (id) DO NOTHING;


-- ─────────────────────────────────────────────────────────────────────────────
-- 4. DATA ASSETS (canonical data object — supersedes raw recordings row)
-- ─────────────────────────────────────────────────────────────────────────────
-- A data asset wraps a recording with quality, consent, provenance, and review.
-- The recordings table is kept; each recording will get a data_asset row.
-- New recordings should create a data_asset simultaneously.

CREATE TABLE IF NOT EXISTS public.data_assets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Source recording
    recording_id UUID REFERENCES public.recordings(id) ON DELETE CASCADE,
    -- Core content
    transcript TEXT,                          -- transcription of the audio
    normalized_text TEXT,                     -- normalized/cleaned transcript
    -- Classification
    dialect_id INT REFERENCES public.dialects(id),
    domain_id TEXT REFERENCES public.domains(id) DEFAULT 'general',
    environment_id TEXT REFERENCES public.environments(id),
    -- Speaker info (anonymized)
    contributor_id UUID REFERENCES auth.users(id),
    speaker_age_band TEXT CHECK (speaker_age_band IN ('18-25','26-35','36-50','51-65','65+')),
    speaker_gender TEXT CHECK (speaker_gender IN ('female','male','other','prefer_not')),
    -- Audio technical info
    duration_ms INT,
    sample_rate INT,
    channels INT,
    file_size_bytes INT,
    audio_format TEXT CHECK (audio_format IN ('wav', 'm4a', 'webm', 'ogg')),
    storage_path TEXT,
    -- Consent / license
    consent_type_id TEXT REFERENCES public.consent_types(id) DEFAULT 'research_only',
    consented_at TIMESTAMPTZ,
    -- Review
    review_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (review_status IN ('pending', 'approved', 'rejected', 'needs_revision')),
    reviewed_by UUID REFERENCES auth.users(id),
    reviewed_at TIMESTAMPTZ,
    review_notes TEXT,
    -- Quality (summary — detail in data_asset_quality_checks)
    quality_score INT CHECK (quality_score BETWEEN 0 AND 100),
    quality_computed_at TIMESTAMPTZ,
    -- State
    is_deleted BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_data_assets_recording_id ON public.data_assets(recording_id);
CREATE INDEX IF NOT EXISTS idx_data_assets_contributor ON public.data_assets(contributor_id);
CREATE INDEX IF NOT EXISTS idx_data_assets_dialect ON public.data_assets(dialect_id);
CREATE INDEX IF NOT EXISTS idx_data_assets_domain ON public.data_assets(domain_id);
CREATE INDEX IF NOT EXISTS idx_data_assets_review_status ON public.data_assets(review_status);
CREATE INDEX IF NOT EXISTS idx_data_assets_consent ON public.data_assets(consent_type_id);

-- Updated_at trigger
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_data_assets_updated_at ON public.data_assets;
CREATE TRIGGER trg_data_assets_updated_at
    BEFORE UPDATE ON public.data_assets
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Enforce data asset review governance at the database level:
-- 1. Non-admins cannot alter review_status, quality_score, reviewed_by, reviewed_at.
-- 2. Non-admin inserts are always forced to 'pending'.
-- 3. Admins CANNOT approve their own submissions (strict self-approval prevention).
CREATE OR REPLACE FUNCTION public.enforce_data_asset_governance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
    v_is_admin BOOLEAN;
BEGIN
    v_is_admin := public.is_admin();

    IF TG_OP = 'INSERT' THEN
        IF NOT v_is_admin THEN
            NEW.review_status := 'pending';
            NEW.reviewed_by := NULL;
            NEW.reviewed_at := NULL;
        ELSE
            IF NEW.review_status = 'approved' AND NEW.contributor_id = auth.uid() THEN
                RAISE EXCEPTION 'Authorization violation: Contributor cannot approve their own submission.';
            END IF;
            IF NEW.review_status = 'approved' THEN
                NEW.reviewed_by := auth.uid();
                NEW.reviewed_at := now();
            END IF;
        END IF;
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        IF NOT v_is_admin THEN
            IF NEW.review_status IS DISTINCT FROM OLD.review_status THEN
                RAISE EXCEPTION 'Non-admin contributors cannot modify review_status.';
            END IF;
            IF NEW.reviewed_by IS DISTINCT FROM OLD.reviewed_by THEN
                RAISE EXCEPTION 'Non-admin contributors cannot modify reviewed_by.';
            END IF;
            IF NEW.reviewed_at IS DISTINCT FROM OLD.reviewed_at THEN
                RAISE EXCEPTION 'Non-admin contributors cannot modify reviewed_at.';
            END IF;
            IF NEW.quality_score IS DISTINCT FROM OLD.quality_score THEN
                RAISE EXCEPTION 'Non-admin contributors cannot overwrite quality_score.';
            END IF;
        ELSE
            -- Enforce NO SELF-APPROVAL for admins
            IF NEW.review_status = 'approved' AND (OLD.review_status IS DISTINCT FROM 'approved') THEN
                IF NEW.contributor_id = auth.uid() THEN
                    RAISE EXCEPTION 'Authorization violation: Contributor cannot approve their own submission.';
                END IF;
                NEW.reviewed_by := auth.uid();
                NEW.reviewed_at := now();
            END IF;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_data_asset_governance ON public.data_assets;
CREATE TRIGGER trg_enforce_data_asset_governance
    BEFORE INSERT OR UPDATE ON public.data_assets
    FOR EACH ROW EXECUTE FUNCTION public.enforce_data_asset_governance();


-- ─────────────────────────────────────────────────────────────────────────────
-- 5. QUALITY CHECKS (individual quality signals, not one opaque score)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.data_asset_quality_checks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    data_asset_id UUID NOT NULL REFERENCES public.data_assets(id) ON DELETE CASCADE,
    -- Format checks
    format_valid BOOLEAN,
    sample_rate_hz INT,
    channels INT,
    bit_depth INT,
    duration_ms INT,
    file_size_bytes INT,
    -- Content checks
    speech_presence BOOLEAN,         -- was speech detected?
    silence_ratio FLOAT              -- fraction of silence
        CHECK (silence_ratio IS NULL OR (silence_ratio >= 0 AND silence_ratio <= 1)),
    clipping_detected BOOLEAN,
    -- Volume
    peak_amplitude_db FLOAT,
    rms_db FLOAT,
    -- Hash for duplicate detection
    audio_sha256 TEXT,
    -- Computed scores
    audio_quality_score INT CHECK (audio_quality_score BETWEEN 0 AND 100),
    metadata_quality_score INT CHECK (metadata_quality_score BETWEEN 0 AND 100),
    consent_quality_score INT CHECK (consent_quality_score BETWEEN 0 AND 100),
    overall_quality_score INT CHECK (overall_quality_score BETWEEN 0 AND 100),
    -- Provider status (for features requiring ML)
    advanced_analysis_status TEXT DEFAULT 'unavailable'
        CHECK (advanced_analysis_status IN ('unavailable', 'pending', 'complete', 'failed')),
    -- Notes/explanations
    quality_explanation JSONB DEFAULT '[]'::JSONB,
    computed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_quality_checks_asset ON public.data_asset_quality_checks(data_asset_id);
CREATE INDEX IF NOT EXISTS idx_quality_checks_sha256 ON public.data_asset_quality_checks(audio_sha256)
    WHERE audio_sha256 IS NOT NULL;


-- ─────────────────────────────────────────────────────────────────────────────
-- 6. PROVENANCE EVENTS (immutable audit trail)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.provenance_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    data_asset_id UUID NOT NULL REFERENCES public.data_assets(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL
        CHECK (event_type IN (
            'recorded', 'uploaded', 'quality_computed', 'reviewed',
            'approved', 'rejected', 'correction_requested',
            'added_to_dataset', 'removed_from_dataset',
            'exported', 'deleted', 'consent_updated'
        )),
    actor_id UUID REFERENCES auth.users(id),  -- who performed action (null = system)
    event_data JSONB DEFAULT '{}'::JSONB,     -- arbitrary structured context
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_provenance_asset ON public.provenance_events(data_asset_id);
CREATE INDEX IF NOT EXISTS idx_provenance_type ON public.provenance_events(event_type);
CREATE INDEX IF NOT EXISTS idx_provenance_time ON public.provenance_events(occurred_at);

-- Provenance is append-only: no UPDATE or DELETE for ordinary users
-- (Deletes only allowed by service role for GDPR/legal compliance)


-- ─────────────────────────────────────────────────────────────────────────────
-- 7. MISSIONS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.missions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    task_type TEXT NOT NULL
        CHECK (task_type IN ('recording', 'transcription_review', 'metadata_validation', 'dialect_validation')),
    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('draft', 'active', 'paused', 'completed', 'cancelled')),
    created_by UUID REFERENCES auth.users(id),
    -- Requirements (all nullable = "any value acceptable")
    required_dialect_id INT REFERENCES public.dialects(id),
    required_domain_id TEXT REFERENCES public.domains(id),
    required_environment_id TEXT REFERENCES public.environments(id),
    required_age_band TEXT CHECK (required_age_band IN ('18-25','26-35','36-50','51-65','65+')),
    -- Targets
    target_quantity INT NOT NULL DEFAULT 10 CHECK (target_quantity > 0),
    completed_quantity INT NOT NULL DEFAULT 0 CHECK (completed_quantity >= 0),
    quality_threshold INT CHECK (quality_threshold BETWEEN 0 AND 100),
    min_duration_ms INT CHECK (min_duration_ms >= 0),
    max_duration_ms INT CHECK (max_duration_ms >= 0),
    -- Metadata
    priority INT NOT NULL DEFAULT 5 CHECK (priority BETWEEN 1 AND 10),  -- 10 = highest
    is_featured BOOLEAN NOT NULL DEFAULT false,
    tags TEXT[] DEFAULT '{}',
    instructions_markdown TEXT,
    -- Lifecycle
    starts_at TIMESTAMPTZ,
    ends_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_missions_status ON public.missions(status);
CREATE INDEX IF NOT EXISTS idx_missions_dialect ON public.missions(required_dialect_id);
CREATE INDEX IF NOT EXISTS idx_missions_domain ON public.missions(required_domain_id);
CREATE INDEX IF NOT EXISTS idx_missions_priority ON public.missions(priority DESC);

DROP TRIGGER IF EXISTS trg_missions_updated_at ON public.missions;
CREATE TRIGGER trg_missions_updated_at
    BEFORE UPDATE ON public.missions
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- ─────────────────────────────────────────────────────────────────────────────
-- 8. MISSION SUBMISSIONS (links data_asset to mission)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.mission_submissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mission_id UUID NOT NULL REFERENCES public.missions(id) ON DELETE CASCADE,
    data_asset_id UUID REFERENCES public.data_assets(id) ON DELETE SET NULL,
    contributor_id UUID NOT NULL REFERENCES auth.users(id),
    submission_status TEXT NOT NULL DEFAULT 'submitted'
        CHECK (submission_status IN ('submitted', 'accepted', 'rejected', 'needs_revision')),
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    reviewed_at TIMESTAMPTZ,
    UNIQUE(mission_id, data_asset_id)  -- one asset can only be submitted to a mission once
);

CREATE INDEX IF NOT EXISTS idx_mission_submissions_mission ON public.mission_submissions(mission_id);
CREATE INDEX IF NOT EXISTS idx_mission_submissions_contributor ON public.mission_submissions(contributor_id);

-- Automatically increment mission completed_quantity upon valid submission
CREATE OR REPLACE FUNCTION public.handle_mission_submission_count()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.missions
    SET completed_quantity = completed_quantity + 1,
        updated_at = now()
    WHERE id = NEW.mission_id;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_mission_submission_count ON public.mission_submissions;
CREATE TRIGGER trg_mission_submission_count
    AFTER INSERT ON public.mission_submissions
    FOR EACH ROW EXECUTE FUNCTION public.handle_mission_submission_count();

CREATE OR REPLACE FUNCTION public.increment_mission_count(mission_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.missions
    SET completed_quantity = completed_quantity + 1,
        updated_at = now()
    WHERE id = mission_id;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 9. DATASETS + VERSIONING
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.datasets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    created_by UUID REFERENCES auth.users(id),
    is_public BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.dataset_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dataset_id UUID NOT NULL REFERENCES public.datasets(id) ON DELETE CASCADE,
    version TEXT NOT NULL,   -- e.g. '1.0', '1.1'
    description TEXT,
    -- Filtering criteria used to build this version (stored for reproducibility)
    filter_criteria JSONB NOT NULL DEFAULT '{}'::JSONB,
    -- Statistics (computed at publish time)
    asset_count INT NOT NULL DEFAULT 0,
    total_duration_ms BIGINT NOT NULL DEFAULT 0,
    speaker_count INT NOT NULL DEFAULT 0,
    dialect_distribution JSONB DEFAULT '{}'::JSONB,
    domain_distribution JSONB DEFAULT '{}'::JSONB,
    average_quality_score FLOAT,
    consent_summary JSONB DEFAULT '{}'::JSONB,
    -- Immutability
    is_published BOOLEAN NOT NULL DEFAULT false,
    published_at TIMESTAMPTZ,
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(dataset_id, version)
);

CREATE INDEX IF NOT EXISTS idx_dataset_versions_dataset ON public.dataset_versions(dataset_id);

-- Dataset version assets (immutable after publish)
CREATE TABLE IF NOT EXISTS public.dataset_version_assets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dataset_version_id UUID NOT NULL REFERENCES public.dataset_versions(id) ON DELETE CASCADE,
    data_asset_id UUID NOT NULL REFERENCES public.data_assets(id) ON DELETE RESTRICT,
    added_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(dataset_version_id, data_asset_id)
);

CREATE INDEX IF NOT EXISTS idx_dv_assets_version ON public.dataset_version_assets(dataset_version_id);
CREATE INDEX IF NOT EXISTS idx_dv_assets_asset ON public.dataset_version_assets(data_asset_id);

-- Prevent modifying a published dataset version's assets
CREATE OR REPLACE FUNCTION public.prevent_published_version_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
    v_published BOOLEAN;
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT is_published INTO v_published
        FROM public.dataset_versions WHERE id = NEW.dataset_version_id;
    ELSE
        SELECT is_published INTO v_published
        FROM public.dataset_versions WHERE id = OLD.dataset_version_id;
    END IF;

    IF v_published THEN
        RAISE EXCEPTION 'Cannot modify assets of a published dataset version.';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_published_mutation ON public.dataset_version_assets;
CREATE TRIGGER trg_prevent_published_mutation
    BEFORE INSERT OR UPDATE OR DELETE ON public.dataset_version_assets
    FOR EACH ROW EXECUTE FUNCTION public.prevent_published_version_mutation();

-- Prevent mutation or deletion of published dataset_versions themselves
CREATE OR REPLACE FUNCTION public.prevent_published_dataset_version_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.is_published THEN
            RAISE EXCEPTION 'Cannot delete a published dataset version.';
        END IF;
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.is_published THEN
            IF NEW.is_published IS FALSE THEN
                RAISE EXCEPTION 'Cannot unpublish a published dataset version.';
            END IF;
            IF NEW.filter_criteria IS DISTINCT FROM OLD.filter_criteria
               OR NEW.dataset_id IS DISTINCT FROM OLD.dataset_id
               OR NEW.version IS DISTINCT FROM OLD.version
               OR NEW.asset_count IS DISTINCT FROM OLD.asset_count
               OR NEW.total_duration_ms IS DISTINCT FROM OLD.total_duration_ms THEN
                RAISE EXCEPTION 'Cannot modify metadata or criteria of a published dataset version.';
            END IF;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_published_dataset_version_mutation ON public.dataset_versions;
CREATE TRIGGER trg_prevent_published_dataset_version_mutation
    BEFORE UPDATE OR DELETE ON public.dataset_versions
    FOR EACH ROW EXECUTE FUNCTION public.prevent_published_dataset_version_mutation();

-- Enforce dataset asset integrity and consent boundaries at the database level:
-- 1. Assets MUST be approved (review_status = 'approved').
-- 2. Assets MUST NOT be benchmark test assets (prevents benchmark contamination).
-- 3. Assets MUST meet the dataset version's consent requirements (commercial vs open vs research).
CREATE OR REPLACE FUNCTION public.validate_dataset_version_asset()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
    v_asset_status TEXT;
    v_asset_consent TEXT;
    v_req_consent TEXT;
    v_is_benchmark BOOLEAN;
BEGIN
    -- 1. Asset must be approved and not deleted
    SELECT review_status, consent_type_id INTO v_asset_status, v_asset_consent
    FROM public.data_assets
    WHERE id = NEW.data_asset_id AND NOT is_deleted;

    IF v_asset_status IS NULL OR v_asset_status != 'approved' THEN
        RAISE EXCEPTION 'Only approved data assets may be included in datasets (asset status: %).', COALESCE(v_asset_status, 'not found');
    END IF;

    -- 2. Asset must NOT be a benchmark test asset
    SELECT EXISTS (
        SELECT 1 FROM public.benchmark_items WHERE data_asset_id = NEW.data_asset_id
    ) INTO v_is_benchmark;

    IF v_is_benchmark THEN
        RAISE EXCEPTION 'Benchmark test assets are protected and cannot be exported into training datasets.';
    END IF;

    -- 3. Consent scope enforcement
    SELECT filter_criteria->>'required_consent_type' INTO v_req_consent
    FROM public.dataset_versions
    WHERE id = NEW.dataset_version_id;

    IF v_req_consent = 'commercial_ai' AND v_asset_consent NOT IN ('commercial_ai', 'open') THEN
        RAISE EXCEPTION 'Consent violation: Asset % has consent "%", which does not allow commercial AI usage.', NEW.data_asset_id, v_asset_consent;
    ELSIF v_req_consent = 'open' AND v_asset_consent != 'open' THEN
        RAISE EXCEPTION 'Consent violation: Asset % has consent "%", which does not allow open distribution.', NEW.data_asset_id, v_asset_consent;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_dataset_version_asset ON public.dataset_version_assets;
CREATE TRIGGER trg_validate_dataset_version_asset
    BEFORE INSERT OR UPDATE ON public.dataset_version_assets
    FOR EACH ROW EXECUTE FUNCTION public.validate_dataset_version_asset();


-- ─────────────────────────────────────────────────────────────────────────────
-- 10. BENCHMARKS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.benchmarks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    benchmark_type TEXT NOT NULL DEFAULT 'asr'
        CHECK (benchmark_type IN ('asr', 'lid', 'did', 'tts_eval')),
    created_by UUID REFERENCES auth.users(id),
    is_public BOOLEAN NOT NULL DEFAULT false,  -- test data is protected by default
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.benchmark_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    benchmark_id UUID NOT NULL REFERENCES public.benchmarks(id) ON DELETE CASCADE,
    version TEXT NOT NULL,
    description TEXT,
    item_count INT NOT NULL DEFAULT 0,
    total_duration_ms BIGINT NOT NULL DEFAULT 0,
    category_distribution JSONB DEFAULT '{}'::JSONB,
    is_published BOOLEAN NOT NULL DEFAULT false,
    published_at TIMESTAMPTZ,
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(benchmark_id, version)
);

-- Benchmark items are separate from data_assets to prevent leakage
-- through ordinary dataset APIs.
CREATE TABLE IF NOT EXISTS public.benchmark_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    benchmark_version_id UUID NOT NULL REFERENCES public.benchmark_versions(id) ON DELETE CASCADE,
    data_asset_id UUID REFERENCES public.data_assets(id) ON DELETE SET NULL,
    reference_transcript TEXT NOT NULL,  -- ground truth
    category TEXT NOT NULL,              -- e.g. 'standard', 'kathiyawadi', 'noisy', 'telephone'
    dialect_id INT REFERENCES public.dialects(id),
    domain_id TEXT REFERENCES public.domains(id),
    environment_id TEXT REFERENCES public.environments(id),
    item_metadata JSONB DEFAULT '{}'::JSONB,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_benchmark_items_version ON public.benchmark_items(benchmark_version_id);
CREATE INDEX IF NOT EXISTS idx_benchmark_items_category ON public.benchmark_items(category);

-- Anti-contamination trigger: Assets already included in dataset versions cannot be used as benchmark items
CREATE OR REPLACE FUNCTION public.prevent_benchmark_training_data_contamination()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
    v_in_dataset BOOLEAN;
BEGIN
    IF NEW.data_asset_id IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1 FROM public.dataset_version_assets
            WHERE data_asset_id = NEW.data_asset_id
        ) INTO v_in_dataset;

        IF v_in_dataset THEN
            RAISE EXCEPTION 'Contamination violation: Asset % is already part of a dataset version and cannot be used as an isolated benchmark test item.', NEW.data_asset_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_benchmark_training_contamination ON public.benchmark_items;
CREATE TRIGGER trg_prevent_benchmark_training_contamination
    BEFORE INSERT OR UPDATE ON public.benchmark_items
    FOR EACH ROW EXECUTE FUNCTION public.prevent_benchmark_training_data_contamination();


-- ─────────────────────────────────────────────────────────────────────────────
-- 11. MODEL EVALUATIONS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.model_evaluations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    benchmark_version_id UUID NOT NULL REFERENCES public.benchmark_versions(id),
    evaluator_id UUID REFERENCES auth.users(id),
    model_name TEXT NOT NULL,
    model_version TEXT,
    model_description TEXT,
    -- Overall metrics
    overall_wer FLOAT CHECK (overall_wer >= 0),
    overall_cer FLOAT CHECK (overall_cer >= 0),
    -- Breakdown by category (stored as JSONB: { "kathiyawadi": { "wer": 0.27, "cer": 0.12 }, ... })
    category_metrics JSONB DEFAULT '{}'::JSONB,
    -- Failure analysis (computed)
    failure_summary JSONB DEFAULT '{}'::JSONB,
    -- Status
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'processing', 'complete', 'failed')),
    error_message TEXT,
    -- Prediction upload
    predictions_storage_path TEXT,  -- path to uploaded predictions file
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_evals_benchmark ON public.model_evaluations(benchmark_version_id);
CREATE INDEX IF NOT EXISTS idx_evals_evaluator ON public.model_evaluations(evaluator_id);

-- Per-item evaluation results (detailed)
CREATE TABLE IF NOT EXISTS public.evaluation_results (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    evaluation_id UUID NOT NULL REFERENCES public.model_evaluations(id) ON DELETE CASCADE,
    benchmark_item_id UUID NOT NULL REFERENCES public.benchmark_items(id) ON DELETE CASCADE,
    hypothesis TEXT,             -- model's prediction
    reference TEXT NOT NULL,     -- ground truth (copied from benchmark_item)
    wer FLOAT CHECK (wer >= 0),
    cer FLOAT CHECK (cer >= 0),
    -- Error breakdown
    substitutions INT DEFAULT 0,
    deletions INT DEFAULT 0,
    insertions INT DEFAULT 0,
    UNIQUE(evaluation_id, benchmark_item_id)
);

CREATE INDEX IF NOT EXISTS idx_eval_results_evaluation ON public.evaluation_results(evaluation_id);


-- ─────────────────────────────────────────────────────────────────────────────
-- 12. DATA PROJECTS / REQUIREMENTS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.data_projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    owner_id UUID NOT NULL REFERENCES auth.users(id),
    -- Requirements
    requirements JSONB NOT NULL DEFAULT '{}'::JSONB,
    -- Coverage analysis (computed, updated periodically)
    coverage_analysis JSONB DEFAULT '{}'::JSONB,
    coverage_computed_at TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'paused', 'completed', 'cancelled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_data_projects_updated_at ON public.data_projects;
CREATE TRIGGER trg_data_projects_updated_at
    BEFORE UPDATE ON public.data_projects
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- ─────────────────────────────────────────────────────────────────────────────
-- 13. RLS FOR ALL NEW TABLES
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.consent_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.domains ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.environments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.data_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.data_asset_quality_checks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.provenance_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.missions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mission_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.datasets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dataset_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dataset_version_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.benchmarks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.benchmark_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.benchmark_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.model_evaluations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.evaluation_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.data_projects ENABLE ROW LEVEL SECURITY;

-- Lookup tables: authenticated users can read
CREATE POLICY "consent_types_read" ON public.consent_types FOR SELECT TO authenticated USING (true);
CREATE POLICY "domains_read" ON public.domains FOR SELECT TO authenticated USING (true);
CREATE POLICY "environments_read" ON public.environments FOR SELECT TO authenticated USING (true);

-- Data assets: contributor can read/write own; admin reads all; reviewer reads pending
CREATE POLICY "data_assets_own_read" ON public.data_assets
    FOR SELECT TO authenticated
    USING (contributor_id = auth.uid() OR public.is_admin());

CREATE POLICY "data_assets_own_insert" ON public.data_assets
    FOR INSERT TO authenticated
    WITH CHECK (contributor_id = auth.uid());

CREATE POLICY "data_assets_own_update" ON public.data_assets
    FOR UPDATE TO authenticated
    USING (contributor_id = auth.uid() AND review_status = 'pending')
    WITH CHECK (contributor_id = auth.uid());

-- Admins can update review status (approve/reject)
CREATE POLICY "data_assets_admin_update" ON public.data_assets
    FOR UPDATE TO authenticated
    USING (public.is_admin());

-- Approved assets are visible to all authenticated users (for dataset building)
CREATE POLICY "data_assets_approved_read" ON public.data_assets
    FOR SELECT TO authenticated
    USING (review_status = 'approved' AND NOT is_deleted);

-- Quality checks: readable if you can read the asset
CREATE POLICY "quality_checks_read" ON public.data_asset_quality_checks
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.data_assets da
            WHERE da.id = data_asset_id
              AND (da.contributor_id = auth.uid() OR public.is_admin()
                   OR da.review_status = 'approved')
        )
    );

CREATE POLICY "quality_checks_insert" ON public.data_asset_quality_checks
    FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.data_assets da
            WHERE da.id = data_asset_id AND da.contributor_id = auth.uid()
        ) OR public.is_admin()
    );

-- Provenance events: read by contributor or admin; insert by contributor or admin
CREATE POLICY "provenance_read" ON public.provenance_events
    FOR SELECT TO authenticated
    USING (
        actor_id = auth.uid() OR public.is_admin()
        OR EXISTS (
            SELECT 1 FROM public.data_assets da
            WHERE da.id = data_asset_id AND da.contributor_id = auth.uid()
        )
    );

CREATE POLICY "provenance_insert" ON public.provenance_events
    FOR INSERT TO authenticated
    WITH CHECK (actor_id = auth.uid() OR actor_id IS NULL);

-- No UPDATE or DELETE on provenance (append-only)

-- Missions: active missions visible to all authenticated; admin manages
CREATE POLICY "missions_read_active" ON public.missions
    FOR SELECT TO authenticated
    USING (status = 'active' OR public.is_admin());

CREATE POLICY "missions_admin_write" ON public.missions
    FOR ALL TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

-- Mission submissions: own submissions
CREATE POLICY "mission_submissions_own" ON public.mission_submissions
    FOR SELECT TO authenticated
    USING (contributor_id = auth.uid() OR public.is_admin());

CREATE POLICY "mission_submissions_insert" ON public.mission_submissions
    FOR INSERT TO authenticated
    WITH CHECK (contributor_id = auth.uid());

-- Datasets: creator or admin
CREATE POLICY "datasets_read" ON public.datasets
    FOR SELECT TO authenticated
    USING (is_public OR created_by = auth.uid() OR public.is_admin());

CREATE POLICY "datasets_insert" ON public.datasets
    FOR INSERT TO authenticated
    WITH CHECK (created_by = auth.uid() OR public.is_admin());

CREATE POLICY "datasets_update" ON public.datasets
    FOR UPDATE TO authenticated
    USING (created_by = auth.uid() OR public.is_admin());

-- Dataset versions
CREATE POLICY "dataset_versions_read" ON public.dataset_versions
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.datasets d
            WHERE d.id = dataset_id AND (d.is_public OR d.created_by = auth.uid() OR public.is_admin())
        )
    );

CREATE POLICY "dataset_versions_write" ON public.dataset_versions
    FOR ALL TO authenticated
    USING (created_by = auth.uid() OR public.is_admin())
    WITH CHECK (created_by = auth.uid() OR public.is_admin());

-- Dataset version assets
CREATE POLICY "dv_assets_read" ON public.dataset_version_assets
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.dataset_versions dv
            JOIN public.datasets d ON d.id = dv.dataset_id
            WHERE dv.id = dataset_version_id
              AND (d.is_public OR d.created_by = auth.uid() OR public.is_admin())
        )
    );

CREATE POLICY "dv_assets_write" ON public.dataset_version_assets
    FOR ALL TO authenticated
    USING (public.is_admin() OR
        EXISTS (
            SELECT 1 FROM public.dataset_versions dv
            WHERE dv.id = dataset_version_id AND dv.created_by = auth.uid()
        ))
    WITH CHECK (public.is_admin() OR
        EXISTS (
            SELECT 1 FROM public.dataset_versions dv
            WHERE dv.id = dataset_version_id AND dv.created_by = auth.uid()
        ));

-- Benchmarks: public benchmarks readable; items protected (admin only unless public)
CREATE POLICY "benchmarks_read" ON public.benchmarks
    FOR SELECT TO authenticated
    USING (is_public OR public.is_admin());

CREATE POLICY "benchmarks_write" ON public.benchmarks
    FOR ALL TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

CREATE POLICY "benchmark_versions_read" ON public.benchmark_versions
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.benchmarks b
            WHERE b.id = benchmark_id AND (b.is_public OR public.is_admin())
        )
    );

-- Benchmark items: readable for published benchmarks by authenticated users for evaluation;
-- Training dataset leakage is strictly prevented via validate_dataset_version_asset trigger.
-- Benchmark raw audio remains protected in benchmark-audio bucket.
CREATE POLICY "benchmark_items_read" ON public.benchmark_items
    FOR SELECT TO authenticated
    USING (
        public.is_admin() OR
        EXISTS (
            SELECT 1 FROM public.benchmark_versions bv
            JOIN public.benchmarks b ON b.id = bv.benchmark_id
            WHERE bv.id = benchmark_version_id AND bv.is_published AND b.is_public
        )
    );

-- Model evaluations
CREATE POLICY "evals_own_read" ON public.model_evaluations
    FOR SELECT TO authenticated
    USING (evaluator_id = auth.uid() OR public.is_admin());

CREATE POLICY "evals_insert" ON public.model_evaluations
    FOR INSERT TO authenticated
    WITH CHECK (evaluator_id = auth.uid());

CREATE POLICY "eval_results_read" ON public.evaluation_results
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.model_evaluations me
            WHERE me.id = evaluation_id
              AND (me.evaluator_id = auth.uid() OR public.is_admin())
        )
    );

-- Data projects
CREATE POLICY "data_projects_own" ON public.data_projects
    FOR SELECT TO authenticated
    USING (owner_id = auth.uid() OR public.is_admin());

CREATE POLICY "data_projects_insert" ON public.data_projects
    FOR INSERT TO authenticated
    WITH CHECK (owner_id = auth.uid());

CREATE POLICY "data_projects_update" ON public.data_projects
    FOR UPDATE TO authenticated
    USING (owner_id = auth.uid() OR public.is_admin());


-- ─────────────────────────────────────────────────────────────────────────────
-- 14. STORAGE — Benchmark items bucket (protected)
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'benchmark-audio',
    'benchmark-audio',
    false,
    10485760,  -- 10MB
    ARRAY['audio/wav', 'audio/x-wav', 'audio/mp4', 'audio/webm']
)
ON CONFLICT (id) DO UPDATE SET
    public = false,
    file_size_limit = 10485760;

-- Benchmark audio: admin only
CREATE POLICY "benchmark_audio_admin_read" ON storage.objects
    FOR SELECT TO authenticated
    USING (bucket_id = 'benchmark-audio' AND public.is_admin());

CREATE POLICY "benchmark_audio_admin_write" ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'benchmark-audio' AND public.is_admin());

-- Evaluation predictions upload bucket
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'eval-predictions',
    'eval-predictions',
    false,
    52428800,  -- 50MB
    ARRAY['text/plain', 'application/json', 'text/csv']
)
ON CONFLICT (id) DO UPDATE SET
    public = false,
    file_size_limit = 52428800;

CREATE POLICY "eval_predictions_own" ON storage.objects
    FOR SELECT TO authenticated
    USING (
        bucket_id = 'eval-predictions'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

CREATE POLICY "eval_predictions_upload" ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'eval-predictions'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );


-- ─────────────────────────────────────────────────────────────────────────────
-- 15. BACKFILL existing recordings into data_assets
-- ─────────────────────────────────────────────────────────────────────────────
-- Create a data_asset row for each existing recording that doesn't have one yet.
-- This is best-effort; null fields will be populated as data is reviewed.
INSERT INTO public.data_assets (
    id,
    recording_id,
    dialect_id,
    contributor_id,
    duration_ms,
    sample_rate,
    channels,
    audio_format,
    storage_path,
    consent_type_id,
    consented_at,
    review_status,
    created_at
)
SELECT
    gen_random_uuid(),
    r.id,
    r.dialect_id,
    r.user_id,
    r.duration_ms,
    r.sample_rate,
    r.channels,
    r.audio_format::TEXT,
    r.storage_path,
    'research_only',
    now(),
    'pending',
    r.created_at
FROM public.recordings r
WHERE r.user_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM public.data_assets da WHERE da.recording_id = r.id
  );


-- ─────────────────────────────────────────────────────────────────────────────
-- 16. SEED CANONICAL BENCHMARK (Gujarati ASR Robustness Benchmark v1.0)
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.benchmarks (id, name, description, benchmark_type, is_public)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'Gujarati ASR Robustness Benchmark',
    'Standardized robustness evaluation suite covering standard Gujarati, Kathiyawadi, Surati, medical terminology, and telephone channel degradations.',
    'asr',
    true
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.benchmark_versions (id, benchmark_id, version, description, is_published, published_at)
VALUES (
    '00000000-0000-0000-0000-000000000010',
    '00000000-0000-0000-0000-000000000001',
    '1.0',
    'Version 1.0 baseline robustness test set',
    true,
    now()
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.benchmark_items (id, benchmark_version_id, reference_transcript, category, dialect_id, domain_id, environment_id, sort_order)
VALUES
    ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000010', 'નમસ્તે ગુજરાત કેમ છો બધા', 'standard', 1, 'general', 'quiet_indoor', 1),
    ('00000000-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000010', 'આજે હવામાન ખૂબ સુંદર છે', 'standard', 1, 'general', 'quiet_indoor', 2),
    ('00000000-0000-0000-0000-000000000103', '00000000-0000-0000-0000-000000000010', 'હું કાલે સવારે સુરત જવાનો છું', 'surti', 3, 'general', 'quiet_indoor', 3),
    ('00000000-0000-0000-0000-000000000104', '00000000-0000-0000-0000-000000000010', 'તમે ક્યાં ગામના રહેવાસી છો ભાઈ', 'kathiyawadi', 2, 'general', 'quiet_indoor', 4),
    ('00000000-0000-0000-0000-000000000105', '00000000-0000-0000-0000-000000000010', 'આ દવા દિવસમાં બે વાર લેવાની છે', 'healthcare', 1, 'healthcare', 'quiet_indoor', 5),
    ('00000000-0000-0000-0000-000000000106', '00000000-0000-0000-0000-000000000010', 'હાલો આપડે ખેતરે જાઈએ', 'kathiyawadi', 2, 'agriculture', 'outdoor', 6),
    ('00000000-0000-0000-0000-000000000107', '00000000-0000-0000-0000-000000000010', 'હેલો અવાજ સંભળાય છે બરોબર', 'telephone', 1, 'general', 'telephone', 7)
ON CONFLICT (id) DO NOTHING;


-- ─────────────────────────────────────────────────────────────────────────────
-- 17. SEED INITIAL MISSIONS (Featured starter missions)
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.missions (id, title, description, task_type, status, required_dialect_id, required_domain_id, target_quantity, priority, is_featured, tags)
VALUES
    ('10000000-0000-0000-0000-000000000001', 'Kathiyawadi Healthcare Terminology', 'Record medical and symptom consultation sentences in authentic Kathiyawadi dialect to improve medical ASR.', 'recording', 'active', 2, 'healthcare', 30, 9, true, ARRAY['kathiyawadi', 'healthcare', 'high-priority']),
    ('10000000-0000-0000-0000-000000000002', 'Surati Everyday Conversation', 'Collect natural conversational speech from South Gujarat region with local intonations.', 'recording', 'active', 3, 'general', 25, 7, false, ARRAY['surati', 'conversation']),
    ('10000000-0000-0000-0000-000000000003', 'Charotari Agricultural Dialect Collection', 'Targeted collection for farming and crop vocabulary in Charotari dialect.', 'recording', 'active', 4, 'agriculture', 20, 8, false, ARRAY['charotari', 'agriculture'])
ON CONFLICT (id) DO NOTHING;


-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFICATION
-- ─────────────────────────────────────────────────────────────────────────────
-- After applying, run:
--   SELECT count(*) FROM public.data_assets;      -- should equal recordings with user_id
--   SELECT count(*) FROM public.missions;          -- should be 0 (none created yet)
--   SELECT count(*) FROM public.consent_types;     -- should be 3
--   SELECT count(*) FROM public.domains;           -- should be 9
--   SELECT count(*) FROM public.environments;      -- should be 6
