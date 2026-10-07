-- =============================================================================
-- GSIP Security Hardening: profiles.is_admin
-- File: supabase/harden_profiles_is_admin.sql
-- Run this in the Supabase SQL Editor as the project owner.
-- =============================================================================
--
-- PROBLEM ANALYSIS (two distinct vulnerabilities):
--
-- 1. The existing trigger prevent_is_admin_update() is SECURITY DEFINER.
--    Inside a SECURITY DEFINER function, current_user is always the *function
--    owner* (typically 'postgres' or the project role), never 'authenticator'
--    or 'anon'. So the check `current_user IN ('authenticator', 'anon')` is
--    always FALSE and the guard never fires. Any UPDATE that touches is_admin
--    goes through unchecked.
--
-- 2. The trigger fires BEFORE UPDATE only. The INSERT RLS policy is:
--      WITH CHECK (auth.uid() = id)
--    A user can INSERT a row with is_admin = true. The trigger does not
--    intercept INSERT, so the row lands with is_admin = true.
--    Combined with ON CONFLICT DO UPDATE (upsert), this is exploitable.
--
-- FIX STRATEGY (defense in depth, three layers):
--
-- Layer 1 — Column-level REVOKE:
--   Revoke INSERT/UPDATE privilege on the is_admin column from the
--   `authenticated` role. PostgREST (Supabase's API layer) runs as
--   `authenticated`, so this blocks the attack at the lowest level.
--
-- Layer 2 — Correct BEFORE INSERT OR UPDATE trigger:
--   Replace the broken trigger with one that correctly resets is_admin
--   to false on INSERT (always), and to OLD.is_admin on UPDATE if the
--   caller is not the service-role / postgres superuser. This uses
--   auth.uid() presence and pg_has_role() — both work correctly
--   regardless of SECURITY DEFINER context.
--
-- Layer 3 — Fix is_admin() helper function search_path:
--   Set search_path = public on the public.is_admin() function to prevent
--   search-path manipulation attacks.
--
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- LAYER 1: Column-level privileges
-- ─────────────────────────────────────────────────────────────────────────────

-- Revoke INSERT and UPDATE on the is_admin column from the authenticated role.
-- This is enforced by PostgreSQL before any row-level policy or trigger fires.
-- Supabase's PostgREST API runs as the `authenticated` role; after this,
-- any INSERT or UPDATE payload that includes is_admin will have that column
-- silently ignored (if PostgREST strips unknown columns) or rejected outright.
REVOKE INSERT (is_admin) ON TABLE public.profiles FROM authenticated;
REVOKE UPDATE (is_admin) ON TABLE public.profiles FROM authenticated;

-- Also revoke from anon role for completeness.
REVOKE INSERT (is_admin) ON TABLE public.profiles FROM anon;
REVOKE UPDATE (is_admin) ON TABLE public.profiles FROM anon;


-- ─────────────────────────────────────────────────────────────────────────────
-- LAYER 2: Correct BEFORE INSERT OR UPDATE trigger
-- ─────────────────────────────────────────────────────────────────────────────

-- Drop the old broken trigger and function.
DROP TRIGGER IF EXISTS trg_prevent_is_admin_update ON public.profiles;
DROP FUNCTION IF EXISTS public.prevent_is_admin_update();

-- New function: does NOT use current_user (which is wrong in SECURITY DEFINER).
-- Uses pg_has_role() to detect whether the caller has superuser/service-role
-- privileges. Regular JWT-authenticated API users do NOT have these privileges.
--
-- On INSERT: always force is_admin = false unless caller is privileged.
-- On UPDATE: if caller is not privileged, reset is_admin to OLD.is_admin.
--
-- Note: this trigger is SECURITY INVOKER (default) so current_user = actual
-- caller role. But we intentionally do NOT rely on current_user matching a
-- specific string because role names can vary across Supabase plans.
-- pg_has_role(current_user, 'pg_read_all_data', 'USAGE') would catch service
-- role. A simpler and reliable approach: check whether the change came from
-- within a JWT context (auth.uid() IS NOT NULL means it is an API call).
-- Service-role calls either have auth.uid() = NULL or bypass RLS entirely.
--
CREATE OR REPLACE FUNCTION public.prevent_is_admin_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER  -- current_user IS the actual caller here
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- On any INSERT via API: force is_admin to false.
        -- Service-role / postgres superuser inserts bypass RLS entirely,
        -- so they do not reach this trigger through the API in the same way.
        -- But even if they do, they can correct it with a direct SQL UPDATE.
        --
        -- We detect "API call" by whether the authenticated role is in use.
        -- pg_has_role returns true if current_user has the given role.
        IF NOT pg_has_role(current_user, 'postgres', 'MEMBER') THEN
            NEW.is_admin := false;
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        -- Prevent authenticated users from changing is_admin.
        -- Service-role and postgres superuser are allowed (they bypass RLS
        -- and have the postgres member role).
        IF NEW.is_admin IS DISTINCT FROM OLD.is_admin THEN
            IF NOT pg_has_role(current_user, 'postgres', 'MEMBER') THEN
                NEW.is_admin := OLD.is_admin;
            END IF;
        END IF;
        RETURN NEW;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_is_admin_change ON public.profiles;
CREATE TRIGGER trg_prevent_is_admin_change
    BEFORE INSERT OR UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.prevent_is_admin_change();

-- ─────────────────────────────────────────────────────────────────────────────
-- LAYER 3: Fix is_admin() helper function — set search_path
-- ─────────────────────────────────────────────────────────────────────────────

-- The existing is_admin() helper is used in RLS policies.
-- Adding SET search_path = public prevents search-path injection attacks
-- where a malicious schema could shadow the profiles table.

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND is_admin = true
  );
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFICATION QUERIES (run these after applying to confirm)
-- ─────────────────────────────────────────────────────────────────────────────
--
-- 1. Check column privileges:
--    SELECT grantee, column_name, privilege_type
--    FROM information_schema.column_privileges
--    WHERE table_name = 'profiles' AND column_name = 'is_admin';
--    Expected: authenticated and anon should NOT appear for INSERT/UPDATE.
--
-- 2. Check trigger exists:
--    SELECT trigger_name, event_manipulation, action_timing
--    FROM information_schema.triggers
--    WHERE event_object_table = 'profiles';
--    Expected: trg_prevent_is_admin_change appears for INSERT and UPDATE.
--
-- 3. Check is_admin() function has search_path set:
--    SELECT prosrc, proconfig
--    FROM pg_proc
--    WHERE proname = 'is_admin' AND pronamespace = 'public'::regnamespace;
--    Expected: proconfig includes 'search_path=public'.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (if needed)
-- ─────────────────────────────────────────────────────────────────────────────
--
-- To revert:
--   GRANT INSERT (is_admin) ON TABLE public.profiles TO authenticated;
--   GRANT UPDATE (is_admin) ON TABLE public.profiles TO authenticated;
--   DROP TRIGGER IF EXISTS trg_prevent_is_admin_change ON public.profiles;
--   DROP FUNCTION IF EXISTS public.prevent_is_admin_change();
--   (Then re-apply the old trigger from supabase_setup.sql if desired.)
--
-- =============================================================================
