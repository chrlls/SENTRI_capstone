-- ============================================================================
-- SENTRI Row-Level Security Policies
-- Architecture: Laravel-only backend, using the Supabase SERVICE ROLE key.
-- Flutter and FastAPI never connect to Supabase directly — all reads/writes
-- go through Laravel, which owns authorization logic (role checks, barangay
-- jurisdiction, on-duty status, dispatcher decisions, etc.).
--
-- CONSEQUENCE FOR THESE POLICIES: the service_role connection BYPASSES RLS
-- entirely (this is standard Postgres/Supabase behavior — RLS never applies
-- to service_role). So these policies are NOT the primary access control.
-- They are the defense-in-depth backstop: if the anon/authenticated key is
-- ever used against this project (leaked service key substituted with the
-- wrong key, a misconfigured client, a future feature that forgets this
-- design decision), these policies ensure that connection sees and touches
-- NOTHING. Deny-by-default, intentionally, for every application table.
--
-- Run this after schema.sql. Idempotent-ish: re-running will error on
-- duplicate policy names — drop first if re-applying during development.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Helper: apply "enable RLS + deny all to anon/authenticated" to a table.
-- Postgres has no loop-over-tables DDL helper without PL/pgSQL, so this is
-- a DO block that iterates the known application tables. Kept explicit
-- (not SELECT * FROM information_schema...) so nothing is silently swept
-- in/out as the schema evolves without a deliberate update here.
-- ----------------------------------------------------------------------------

DO $$
DECLARE
    tbl TEXT;
    app_tables TEXT[] := ARRAY[
        'users',
        'barangay_boundaries',
        'responder_profiles',
        'emergency_contacts',
        'incidents',
        'incident_status_history',
        'voice_analysis_events',
        'keyword_match_events',
        'movement_anomaly_events',
        'checkin_dismissal_verifications',
        'incident_notifications',
        'sms_fallback_log',
        'crime_incident_records',
        'crime_risk_zones',
        'false_alarm_reports',
        'user_trust_scores'
    ];
BEGIN
    FOREACH tbl IN ARRAY app_tables LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', tbl);

        -- Deny-by-default: no policy = no access for anon/authenticated.
        -- We still add an explicit "deny_all" policy (USING (false)) rather
        -- than relying purely on "no policy exists" behavior, so the intent
        -- is self-documenting to anyone reading pg_policies later and to
        -- the Supabase dashboard's policy list (an empty policy list looks
        -- identical to "forgot to write policies" — an explicit false
        -- policy makes the deny-by-default a visible, intentional decision).
        EXECUTE format(
            'CREATE POLICY deny_all_anon_authenticated ON public.%I
                FOR ALL
                TO anon, authenticated
                USING (false)
                WITH CHECK (false);',
            tbl
        );
    END LOOP;
END $$;

-- ============================================================================
-- spatial_ref_sys note (see DESIGN_DECISIONS.md):
-- Owned by supabase_admin, not alterable from this project's role
-- (ERROR 42501 on ALTER TABLE ... ENABLE ROW LEVEL SECURITY). Contains only
-- static EPSG reference data, no application data. Documented as an
-- accepted, non-remediable linter finding — intentionally NOT included
-- in app_tables above since any attempt will fail the whole DO block.
-- ============================================================================

-- ============================================================================
-- VERIFICATION QUERIES — run after applying, confirm the intended state
-- ============================================================================

-- 1. Confirm RLS is enabled on every app table:
-- SELECT tablename, rowsecurity
-- FROM pg_tables
-- WHERE schemaname = 'public'
-- ORDER BY tablename;
-- -> rowsecurity should be 't' for all 16 tables above.

-- 2. Confirm each table has exactly the deny_all policy (i.e. nothing else
--    accidentally grants anon/authenticated access):
-- SELECT tablename, policyname, roles, cmd, qual, with_check
-- FROM pg_policies
-- WHERE schemaname = 'public'
-- ORDER BY tablename;

-- 3. Functional check — this should return ZERO rows / permission denied
--    when run as anon or authenticated (e.g. via Supabase client with the
--    anon key), even though rows exist in the table:
-- SELECT * FROM public.incidents LIMIT 1;
