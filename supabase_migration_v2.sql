-- MIGRATION V2: Upgrade path for existing DB

-- 1. ENUMS & EXTENSIONS
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 2. DIALECTS (New)
CREATE TABLE IF NOT EXISTS dialects (
    id SERIAL PRIMARY KEY,
    slug TEXT UNIQUE NOT NULL,
    name_en TEXT NOT NULL,
    name_gu TEXT NOT NULL,
    sort_order INT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true
);

INSERT INTO dialects (slug, name_en, name_gu, sort_order) VALUES
('standard', 'Standard', 'પ્રમાણભૂત', 1),
('kathiyawadi', 'Kathiyawadi', 'કાઠિયાવાડી', 2),
('surati', 'Surati', 'સુરતી', 3),
('charotari', 'Charotari', 'ચરોતરી', 4),
('kutchi', 'Kutchi', 'કચ્છી', 5),
('north_gujarati', 'North Gujarati', 'ઉત્તર ગુજરાતી', 6),
('other', 'Other', 'અન્ય', 98),
('unsure', 'Unsure', 'અચોક્કસ', 99)
ON CONFLICT (slug) DO NOTHING;

-- 3. DISTRICTS (New)
CREATE TABLE IF NOT EXISTS districts (
    id SERIAL PRIMARY KEY,
    name_en TEXT NOT NULL,
    name_gu TEXT,
    state TEXT NOT NULL DEFAULT 'Gujarat'
);

INSERT INTO districts (name_en, name_gu, state) VALUES
('Ahmedabad', 'અમદાવાદ', 'Gujarat'), ('Amreli', 'અમરેલી', 'Gujarat'), ('Anand', 'આણંદ', 'Gujarat'),
('Aravalli', 'અરવલ્લી', 'Gujarat'), ('Banaskantha', 'બનાસકાંઠા', 'Gujarat'), ('Bharuch', 'ભરૂચ', 'Gujarat'),
('Bhavnagar', 'ભાવનગર', 'Gujarat'), ('Botad', 'બોટાદ', 'Gujarat'), ('Chhota Udaipur', 'છોટા ઉદેપુર', 'Gujarat'),
('Dahod', 'દાહોદ', 'Gujarat'), ('Dang', 'ડાંગ', 'Gujarat'), ('Devbhoomi Dwarka', 'દેવભૂમિ દ્વારકા', 'Gujarat'),
('Gandhinagar', 'ગાંધીનગર', 'Gujarat'), ('Gir Somnath', 'ગીર સોમનાથ', 'Gujarat'), ('Jamnagar', 'જામનગર', 'Gujarat'),
('Junagadh', 'જૂનાગઢ', 'Gujarat'), ('Kheda', 'ખેડા', 'Gujarat'), ('Kutch', 'કચ્છ', 'Gujarat'),
('Mahisagar', 'મહીસાગર', 'Gujarat'), ('Mehsana', 'મહેસાણા', 'Gujarat'), ('Morbi', 'મોરબી', 'Gujarat'),
('Narmada', 'નર્મદા', 'Gujarat'), ('Navsari', 'નવસારી', 'Gujarat'), ('Panchmahal', 'પંચમહાલ', 'Gujarat'),
('Patan', 'પાટણ', 'Gujarat'), ('Porbandar', 'પોરબંદર', 'Gujarat'), ('Rajkot', 'રાજકોટ', 'Gujarat'),
('Sabarkantha', 'સાબરકાંઠા', 'Gujarat'), ('Surat', 'સુરત', 'Gujarat'), ('Surendranagar', 'સુરેન્દ્રનગર', 'Gujarat'),
('Tapi', 'તાપી', 'Gujarat'), ('Vadodara', 'વડોદરા', 'Gujarat'), ('Valsad', 'વલસાડ', 'Gujarat'),
('Outside Gujarat', 'ગુજરાત બહાર', 'Other')
ON CONFLICT DO NOTHING;

-- 4. PROFILES (New)
CREATE TABLE IF NOT EXISTS profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL,
    age_band TEXT CHECK (age_band IN ('18-25','26-35','36-50','51-65','65+')),
    gender TEXT CHECK (gender IN ('female','male','other','prefer_not')),
    native_dialect_id INT REFERENCES dialects(id),
    grew_up_district_id INT REFERENCES districts(id),
    years_lived_there INT,
    is_admin BOOLEAN NOT NULL DEFAULT false,
    consented_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION prevent_is_admin_update() RETURNS trigger AS $$
BEGIN
    IF NEW.is_admin IS DISTINCT FROM OLD.is_admin AND current_user IN ('authenticator', 'anon') THEN
        NEW.is_admin = OLD.is_admin;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_prevent_is_admin_update ON profiles;
CREATE TRIGGER trg_prevent_is_admin_update
    BEFORE UPDATE ON profiles
    FOR EACH ROW EXECUTE FUNCTION prevent_is_admin_update();

-- 5. PROMPTS
-- The old prompts table wasn't actively used since prompts were in prompts.dart. 
-- We drop and recreate it for the new schema.
DROP TABLE IF EXISTS prompts CASCADE;

CREATE TABLE prompts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    text_gu TEXT NOT NULL CHECK (length(text_gu) >= 5 AND length(text_gu) <= 200),
    standard_equivalent_gu TEXT,
    dialect_id INT NOT NULL REFERENCES dialects(id),
    submitted_by UUID REFERENCES auth.users(id),
    status TEXT NOT NULL DEFAULT 'approved' CHECK (status IN ('approved', 'flagged', 'removed')),
    text_norm TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (text_norm, dialect_id)
);

CREATE OR REPLACE FUNCTION validate_and_normalize_prompt() RETURNS trigger AS $$
DECLARE
    guj_chars INT;
    total_chars INT;
    recent_count INT;
BEGIN
    NEW.text_norm = lower(regexp_replace(trim(normalize(NEW.text_gu, NFC)), '\s+', ' ', 'g'));
    
    total_chars := length(regexp_replace(NEW.text_norm, '\s', '', 'g'));
    IF total_chars > 0 THEN
        guj_chars := length(regexp_replace(NEW.text_norm, '[^઀-૿]', '', 'g'));
        IF (guj_chars::float / total_chars::float) < 0.5 THEN
            RAISE EXCEPTION 'Text must contain at least 50%% Gujarati characters.';
        END IF;
    END IF;

    IF NEW.submitted_by IS NOT NULL THEN
        SELECT count(*) INTO recent_count FROM prompts 
        WHERE submitted_by = NEW.submitted_by AND created_at > (now() - interval '24 hours');
        IF recent_count >= 20 THEN
            RAISE EXCEPTION 'Rate limit exceeded: maximum 20 prompts per 24 hours.';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_validate_prompt
    BEFORE INSERT OR UPDATE ON prompts
    FOR EACH ROW EXECUTE FUNCTION validate_and_normalize_prompt();

-- 6. PROMPT REPORTS (New)
CREATE TABLE IF NOT EXISTS prompt_reports (
    prompt_id UUID REFERENCES prompts(id) ON DELETE CASCADE,
    reporter_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    reason TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (prompt_id, reporter_id)
);

CREATE OR REPLACE FUNCTION check_prompt_flags() RETURNS trigger AS $$
DECLARE
    report_count INT;
BEGIN
    SELECT count(DISTINCT reporter_id) INTO report_count FROM prompt_reports WHERE prompt_id = NEW.prompt_id;
    IF report_count >= 3 THEN
        UPDATE prompts SET status = 'flagged' WHERE id = NEW.prompt_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_check_prompt_flags
    AFTER INSERT ON prompt_reports
    FOR EACH ROW EXECUTE FUNCTION check_prompt_flags();

-- Seed standard prompts
DO $$
DECLARE
    std_id INT;
BEGIN
    SELECT id INTO std_id FROM dialects WHERE slug = 'standard';
    IF NOT EXISTS (SELECT 1 FROM prompts WHERE submitted_by IS NULL) THEN
        INSERT INTO prompts (text_gu, dialect_id, submitted_by) VALUES
        ('તમે કેમ છો?', std_id, null),
        ('આજે હવામાન કેવું છે?', std_id, null),
        ('મારું નામ છે.', std_id, null),
        ('હું શાળાએ જાઉં છું.', std_id, null),
        ('આ ગામનું નામ શું છે?', std_id, null),
        ('તમારો પરિવાર કેટલો મોટો છે?', std_id, null),
        ('આજે બજારમાં શું મળે છે?', std_id, null),
        ('વરસાદ ક્યારે આવશે?', std_id, null),
        ('મને ભૂખ લાગી છે.', std_id, null),
        ('ચાલો, આપણે ફરવા જઈએ.', std_id, null);
    END IF;
END $$;


-- 7. RECORDINGS MIGRATION
-- Add new columns, keeping legacy columns
ALTER TABLE recordings
    ALTER COLUMN operator_id DROP NOT NULL,
    ALTER COLUMN prompt DROP NOT NULL,
    ALTER COLUMN speaker_name DROP NOT NULL,
    ALTER COLUMN speaker_age DROP NOT NULL,
    ALTER COLUMN speaker_place DROP NOT NULL,
    ALTER COLUMN speaker_dialect DROP NOT NULL,
    ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id),
    ADD COLUMN IF NOT EXISTS prompt_id UUID REFERENCES prompts(id),
    ADD COLUMN IF NOT EXISTS prompt_text TEXT,
    ADD COLUMN IF NOT EXISTS dialect_id INT REFERENCES dialects(id),
    ADD COLUMN IF NOT EXISTS dialect_other_text TEXT,
    ADD COLUMN IF NOT EXISTS district_id INT REFERENCES districts(id),
    ADD COLUMN IF NOT EXISTS duration_ms INT,
    ADD COLUMN IF NOT EXISTS sample_rate INT,
    ADD COLUMN IF NOT EXISTS channels INT,
    ADD COLUMN IF NOT EXISTS audio_format TEXT CHECK (audio_format IN ('wav', 'm4a'));

-- Best-effort backfill dialect_id from legacy speaker_dialect
UPDATE recordings r
SET dialect_id = d.id
FROM dialects d
WHERE r.dialect_id IS NULL AND lower(r.speaker_dialect) = d.slug;


-- 8. RLS UPDATES
ALTER TABLE dialects ENABLE ROW LEVEL SECURITY;
ALTER TABLE districts ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE prompts ENABLE ROW LEVEL SECURITY;
ALTER TABLE prompt_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE recordings ENABLE ROW LEVEL SECURITY;

-- Drop old policies on recordings
DROP POLICY IF EXISTS "Allow insert own recordings" ON recordings;
DROP POLICY IF EXISTS "Allow read own recordings" ON recordings;

-- New Policies
CREATE POLICY "Allow select on dialects for authenticated" ON dialects FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow select on districts for authenticated" ON districts FOR SELECT TO authenticated USING (true);

CREATE POLICY "Allow users to read own profile" ON profiles FOR SELECT TO authenticated USING (auth.uid() = id);
CREATE POLICY "Allow admins to read all profiles" ON profiles FOR SELECT TO authenticated USING ((SELECT is_admin FROM profiles WHERE id = auth.uid()));
CREATE POLICY "Allow users to insert own profile" ON profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
CREATE POLICY "Allow users to update own profile" ON profiles FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

CREATE POLICY "Allow authenticated to read approved prompts" ON prompts FOR SELECT TO authenticated USING (status = 'approved');
CREATE POLICY "Allow authenticated to read own prompts" ON prompts FOR SELECT TO authenticated USING (auth.uid() = submitted_by);
CREATE POLICY "Allow authenticated to insert prompts" ON prompts FOR INSERT TO authenticated WITH CHECK (auth.uid() = submitted_by);
CREATE POLICY "Allow admins to read all prompts" ON prompts FOR SELECT TO authenticated USING ((SELECT is_admin FROM profiles WHERE id = auth.uid()));

CREATE POLICY "Allow users to insert own reports" ON prompt_reports FOR INSERT TO authenticated WITH CHECK (auth.uid() = reporter_id);

CREATE POLICY "Allow users to read own recordings" ON recordings FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Allow users to delete own recordings" ON recordings FOR DELETE TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Allow users to insert own recordings" ON recordings FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Allow admins to read all recordings" ON recordings FOR SELECT TO authenticated USING ((SELECT is_admin FROM profiles WHERE id = auth.uid()));
CREATE POLICY "Allow admins to read legacy recordings" ON recordings FOR SELECT TO authenticated USING (user_id IS NULL AND (SELECT is_admin FROM profiles WHERE id = auth.uid()));

-- 9. STORAGE UPDATES
UPDATE storage.buckets 
SET public = false, file_size_limit = 5242880, allowed_mime_types = ARRAY['audio/wav', 'audio/x-wav', 'audio/mp4']
WHERE id = 'audio-clips';

-- Replace storage policies
DROP POLICY IF EXISTS "Allow upload of audio clips" ON storage.objects;
DROP POLICY IF EXISTS "Allow public read of audio clips" ON storage.objects;

CREATE POLICY "Allow users to upload audio to their own folder" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'audio-clips' AND 
    (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "Allow users to read their own audio" ON storage.objects
FOR SELECT TO authenticated
USING (
    bucket_id = 'audio-clips' AND 
    (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "Allow users to delete their own audio" ON storage.objects
FOR DELETE TO authenticated
USING (
    bucket_id = 'audio-clips' AND 
    (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "Allow admins to read all audio" ON storage.objects
FOR SELECT TO authenticated
USING (
    bucket_id = 'audio-clips' AND 
    (SELECT is_admin FROM public.profiles WHERE id = auth.uid())
);
