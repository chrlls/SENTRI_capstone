-- ============================================================================
-- SENTRI Database Schema
-- AI-Assisted Mobile Emergency SOS and Community-Based Crime Response System
-- Target: PostgreSQL 15+ with PostGIS 3.x
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================================
-- SECTION 1: USERS & AUTH
-- ============================================================================

CREATE TYPE user_role AS ENUM ('civilian', 'responder', 'pnp', 'admin');
CREATE TYPE account_status AS ENUM ('pending_verification', 'active', 'suspended', 'deactivated');

CREATE TABLE users (
    user_id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email               VARCHAR(255) NOT NULL UNIQUE,
    phone_number        VARCHAR(20) NOT NULL UNIQUE,
    password_hash       TEXT NOT NULL,
    full_name           VARCHAR(150) NOT NULL,
    role                user_role NOT NULL DEFAULT 'civilian',
    status              account_status NOT NULL DEFAULT 'pending_verification',

    -- Mandatory User Agreement acknowledgment (Objective: false-alert legal consequences)
    agreement_accepted_at TIMESTAMPTZ,
    agreement_version      VARCHAR(20),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_status ON users(status);

-- Barangay boundary polygons. Primary unit for responder jurisdiction and
-- accountability — matches the thesis's own framing ("for Urban Barangays
-- of Tagum City"). Also usable later for reporting/analytics (e.g. incident
-- counts per barangay) independent of responder matching.
CREATE TABLE barangay_boundaries (
    barangay_id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    barangay_name           VARCHAR(150) NOT NULL UNIQUE,
    boundary_geometry          GEOGRAPHY(Polygon, 4326) NOT NULL,
    created_at                    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_barangay_boundaries_geometry ON barangay_boundaries USING GIST(boundary_geometry);

-- Responder-specific verification details (PNP-verified tanod/responder accounts)
CREATE TYPE responder_type AS ENUM ('barangay_tanod', 'pnp_officer', 'other_verified');
CREATE TYPE verification_status AS ENUM ('pending', 'verified', 'rejected', 'revoked');

CREATE TABLE responder_profiles (
    responder_id        UUID PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
    responder_type       responder_type NOT NULL,
    badge_or_id_number   VARCHAR(50),
    verification_status  verification_status NOT NULL DEFAULT 'pending',
    verified_by          UUID REFERENCES users(user_id),  -- admin/PNP who verified
    verified_at           TIMESTAMPTZ,

    -- Primary jurisdiction: which barangay this responder (typically a tanod)
    -- is assigned to. NULL allowed for responder types that aren't
    -- barangay-scoped (e.g. pnp_officer covering a wider area).
    assigned_barangay_id    UUID REFERENCES barangay_boundaries(barangay_id),

    -- Last known location — still used as the FALLBACK signal (radius query)
    -- when the assigned barangay has no eligible on-duty responder.
    last_location         GEOGRAPHY(Point, 4326),
    last_location_at       TIMESTAMPTZ,
    is_on_duty            BOOLEAN NOT NULL DEFAULT false,

    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_responder_location ON responder_profiles USING GIST(last_location);
CREATE INDEX idx_responder_on_duty ON responder_profiles(is_on_duty) WHERE is_on_duty = true;
CREATE INDEX idx_responder_barangay ON responder_profiles(assigned_barangay_id);

-- Emergency contacts (civilian's personal contacts, distinct from verified responders)
CREATE TABLE emergency_contacts (
    contact_id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    contact_name        VARCHAR(150) NOT NULL,
    contact_phone       VARCHAR(20) NOT NULL,
    relationship        VARCHAR(50),
    priority_order      SMALLINT NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_emergency_contacts_user ON emergency_contacts(user_id);

-- Laravel Sanctum's required token table (Decision 18). Hand-written here,
-- consistent with how the rest of this schema is managed directly rather
-- than through Laravel's migration system — NOT Sanctum's stock published
-- migration, which assumes a bigint tokenable_id. This project's users.user_id
-- is UUID, so tokenable_id must be UUID too, or every token lookup would
-- fail to match. Column set/nullability otherwise mirrors Sanctum's own
-- migration exactly (see vendor/laravel/sanctum's create_personal_access_tokens_table
-- stub) so a future Sanctum upgrade's expectations still line up.
CREATE TABLE personal_access_tokens (
    id              BIGSERIAL PRIMARY KEY,
    tokenable_type  VARCHAR(255) NOT NULL,
    tokenable_id    UUID NOT NULL,
    name            TEXT NOT NULL,
    token           VARCHAR(64) NOT NULL UNIQUE,
    abilities       TEXT,
    last_used_at    TIMESTAMPTZ,
    expires_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ,
    updated_at      TIMESTAMPTZ
);

CREATE INDEX idx_personal_access_tokens_tokenable ON personal_access_tokens(tokenable_type, tokenable_id);
CREATE INDEX idx_personal_access_tokens_expires_at ON personal_access_tokens(expires_at);

-- ============================================================================
-- SECTION 2: INCIDENTS (core table — trigger-source-agnostic by design)
-- ============================================================================

-- CRITICAL DESIGN NOTE: trigger_source distinguishes manual SOS from AI-assisted
-- detection. Manual SOS rows must be insertable and immediately actionable
-- WITHOUT any dependency on AI pipeline tables below. The AI tables attach
-- supplementary data to an incident; they never gate its creation.
CREATE TYPE trigger_source AS ENUM (
    'manual_sos',           -- one-tap button, always instant, offline-capable
    'voice_distress',       -- AI voice/emotion classifier
    'keyword_detected',     -- rule-based keyword/phrase match
    'movement_anomaly'      -- Tier 1 (post check-in) or Tier 2 (direct) escalation
);

-- Human-verification-before-dispatch state machine. Dispatch is ALWAYS a
-- human PNP dispatcher decision; no state transitions to 'dispatched'
-- automatically from an AI confidence threshold.
CREATE TYPE incident_status AS ENUM (
    'detected',              -- created, not yet seen by dashboard
    'dashboard_alerted',     -- PNP dashboard notified (immediate, no delay)
    'dispatcher_reviewing',  -- a dispatcher has opened/is evaluating it
    'dispatched',            -- human dispatcher decision made
    'resolved',
    'false_alarm',
    'cancelled'               -- e.g. cancelled by user pre-dispatch, never auto-cancelled by silence
);

CREATE TABLE incidents (
    incident_id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reporter_id           UUID NOT NULL REFERENCES users(user_id),
    trigger_source         trigger_source NOT NULL,
    status                 incident_status NOT NULL DEFAULT 'detected',

    -- Location at time of trigger
    location               GEOGRAPHY(Point, 4326) NOT NULL,
    location_captured_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Resolved once at creation (via ST_Contains against barangay_boundaries)
    -- so responder matching and reporting don't repeat a point-in-polygon
    -- lookup on every query. NULL if the point falls outside all known
    -- boundaries (edge case: bad GPS fix, or boundary data incomplete) —
    -- in that case the app layer falls back to pure radius matching.
    incident_barangay_id      UUID REFERENCES barangay_boundaries(barangay_id),

    -- AI confidence score, if applicable (NULL for manual_sos — never required)
    ai_confidence_score      NUMERIC(4,3) CHECK (ai_confidence_score IS NULL OR (ai_confidence_score BETWEEN 0 AND 1)),

    -- Human dispatcher decision fields — explicitly separate from detection
    dispatched_by            UUID REFERENCES users(user_id),  -- PNP dispatcher, NULL until human acts
    dispatched_at             TIMESTAMPTZ,
    dispatcher_notes          TEXT,

    incident_notes            TEXT,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at                TIMESTAMPTZ,

    CONSTRAINT chk_dispatch_is_human
        CHECK (dispatched_at IS NULL OR dispatched_by IS NOT NULL)
);

CREATE INDEX idx_incidents_status ON incidents(status);
CREATE INDEX idx_incidents_reporter ON incidents(reporter_id);
CREATE INDEX idx_incidents_location ON incidents USING GIST(location);
CREATE INDEX idx_incidents_created_at ON incidents(created_at DESC);
CREATE INDEX idx_incidents_trigger_source ON incidents(trigger_source);
CREATE INDEX idx_incidents_barangay ON incidents(incident_barangay_id);

-- Append-only audit trail of every status transition, for the manuscript's
-- "audit trails for monitoring, investigation, and reporting" objective and
-- to prove human-in-the-loop dispatch during defense if ever questioned.
CREATE TABLE incident_status_history (
    history_id       BIGSERIAL PRIMARY KEY,
    incident_id       UUID NOT NULL REFERENCES incidents(incident_id) ON DELETE CASCADE,
    old_status         incident_status,
    new_status          incident_status NOT NULL,
    changed_by           UUID REFERENCES users(user_id),  -- NULL if system-generated
    changed_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    reason                TEXT
);

CREATE INDEX idx_incident_history_incident ON incident_status_history(incident_id);

-- ============================================================================
-- SECTION 3: AI VOICE DISTRESS DETECTION
-- ============================================================================

-- One row per audio clip analyzed. An incident may or may not exist yet at
-- analysis time (e.g. clip triggers creation of the incident), so
-- incident_id is nullable and backfilled.
CREATE TABLE voice_analysis_events (
    analysis_id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    incident_id            UUID REFERENCES incidents(incident_id) ON DELETE SET NULL,
    user_id                 UUID NOT NULL REFERENCES users(user_id),

    audio_storage_ref        TEXT NOT NULL,   -- path/URL to stored audio (not raw bytes in DB)
    audio_duration_seconds     NUMERIC(6,2),

    -- Binary distress classifier output (final_model_v2 / checkpoint-1083)
    distress_label            BOOLEAN NOT NULL,
    distress_confidence        NUMERIC(4,3) NOT NULL CHECK (distress_confidence BETWEEN 0 AND 1),
    model_version                VARCHAR(50) NOT NULL DEFAULT 'final_model_v2',

    analyzed_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_voice_analysis_incident ON voice_analysis_events(incident_id);
CREATE INDEX idx_voice_analysis_user ON voice_analysis_events(user_id);

-- Rule-based keyword/phrase matches (English now; Bisaya extension planned,
-- contingent on STT Bisaya accuracy verification — language column supports
-- that extension without a schema change).
CREATE TABLE keyword_match_events (
    match_id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    incident_id            UUID REFERENCES incidents(incident_id) ON DELETE SET NULL,
    user_id                  UUID NOT NULL REFERENCES users(user_id),

    matched_phrase             TEXT NOT NULL,
    transcript_snippet           TEXT,
    language                       VARCHAR(10) NOT NULL DEFAULT 'en',  -- 'en' | 'bcl'/'ceb' when added
    matched_at                     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_keyword_match_incident ON keyword_match_events(incident_id);

-- ============================================================================
-- SECTION 4: MOVEMENT ANOMALY & CHECK-IN (Tier 0 / 1 / 2)
-- ============================================================================

CREATE TYPE movement_tier AS ENUM ('tier_0', 'tier_1', 'tier_2');
CREATE TYPE checkin_status AS ENUM (
    'not_required',     -- Tier 0: ignored entirely, row kept for completeness/analytics only
    'pending',           -- Tier 1: check-in prompt sent, awaiting response
    'confirmed_safe',    -- user dismissed AND both verification layers agreed
    'escalated',         -- Tier 2 direct, OR Tier 1 mismatch/timeout/no-response
    'timed_out'          -- no response at all — resolves to escalated, kept distinct for analytics
);

CREATE TABLE movement_anomaly_events (
    movement_event_id      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    incident_id              UUID REFERENCES incidents(incident_id) ON DELETE SET NULL,
    user_id                    UUID NOT NULL REFERENCES users(user_id),

    tier                          movement_tier NOT NULL,
    -- raw signal snapshot for later tuning/analysis
    signal_summary                 JSONB,  -- e.g. {"spike_magnitude":..., "stillness_duration_s":...}

    checkin_status                 checkin_status NOT NULL DEFAULT 'not_required',
    checkin_sent_at                  TIMESTAMPTZ,
    checkin_responded_at              TIMESTAMPTZ,

    detected_at                        TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_tier0_not_required
        CHECK (tier <> 'tier_0' OR checkin_status = 'not_required'),
    CONSTRAINT chk_tier2_skips_checkin
        CHECK (tier <> 'tier_2' OR checkin_status IN ('escalated', 'not_required'))
);

CREATE INDEX idx_movement_events_incident ON movement_anomaly_events(incident_id);
CREATE INDEX idx_movement_events_user ON movement_anomaly_events(user_id);

-- Two-layer verification on check-in DISMISSAL: reuses keyword matching +
-- binary distress classifier, run specifically on the dismiss audio.
-- A mismatch (correct phrase, distressed tone) must escalate, not cancel —
-- this table exists precisely to make that mismatch queryable/auditable.
CREATE TABLE checkin_dismissal_verifications (
    verification_id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    movement_event_id           UUID NOT NULL REFERENCES movement_anomaly_events(movement_event_id) ON DELETE CASCADE,

    dismiss_audio_storage_ref     TEXT NOT NULL,

    -- Layer 1: rule-based keyword/phrase match against expected safe-phrase(s)
    keyword_layer_passed             BOOLEAN NOT NULL,
    matched_phrase                     TEXT,

    -- Layer 2: same binary distress classifier used elsewhere, run on dismiss audio
    distress_layer_label               BOOLEAN NOT NULL,   -- true = distress detected in dismiss audio
    distress_layer_confidence           NUMERIC(4,3) NOT NULL CHECK (distress_layer_confidence BETWEEN 0 AND 1),

    -- Derived outcome: mismatch (keyword ok, but distress detected) => escalate
    verification_outcome                  checkin_status NOT NULL,

    verified_at                              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_dismissal_verif_event ON checkin_dismissal_verifications(movement_event_id);

-- ============================================================================
-- SECTION 5: RESPONDER NOTIFICATION (parallel, not sequential/gating)
-- ============================================================================

-- Every notification fired for an incident — PNP dashboard alert and tanod
-- pings are BOTH rows here, created at effectively the same time, so the
-- schema itself cannot express "tanod waits on PNP" or vice versa.
CREATE TYPE notified_party_type AS ENUM ('pnp_dashboard', 'barangay_tanod', 'emergency_contact');
CREATE TYPE notification_delivery_status AS ENUM ('queued', 'sent', 'delivered', 'failed', 'acknowledged');

CREATE TABLE incident_notifications (
    notification_id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    incident_id                UUID NOT NULL REFERENCES incidents(incident_id) ON DELETE CASCADE,

    notified_party_type          notified_party_type NOT NULL,
    notified_user_id                UUID REFERENCES users(user_id),  -- NULL for broadcast-style dashboard alerts
    notified_contact_id              UUID REFERENCES emergency_contacts(contact_id),

    -- Distance at time of notification, for radius-based responder selection audit trail
    distance_meters                    NUMERIC(10,2),

    delivery_status                      notification_delivery_status NOT NULL DEFAULT 'queued',
    delivery_channel                       VARCHAR(20),  -- 'push' | 'sms' | 'dashboard_socket'
    sent_at                                  TIMESTAMPTZ,
    acknowledged_at                            TIMESTAMPTZ,

    created_at                                  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_notifications_incident ON incident_notifications(incident_id);
CREATE INDEX idx_notifications_party_type ON incident_notifications(notified_party_type);

-- ============================================================================
-- SECTION 6: SMS FALLBACK (mentioned in Scope — separate delivery channel log)
-- ============================================================================

CREATE TABLE sms_fallback_log (
    sms_id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    incident_id             UUID NOT NULL REFERENCES incidents(incident_id) ON DELETE CASCADE,
    recipient_phone           VARCHAR(20) NOT NULL,
    message_body                TEXT NOT NULL,
    delivery_status               notification_delivery_status NOT NULL DEFAULT 'queued',
    provider_message_id             VARCHAR(100),
    sent_at                           TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_sms_fallback_incident ON sms_fallback_log(incident_id);

-- ============================================================================
-- SECTION 7: CRIME RISK-AWARENESS (flexible: raw records OR pre-aggregated zones)
-- ============================================================================

-- Raw geocoded crime records, IF PNP hands over incident-level data.
-- Nullable/optional fields since PNP data completeness is unknown pending access.
CREATE TABLE crime_incident_records (
    crime_record_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    source                     VARCHAR(50) NOT NULL DEFAULT 'pnp',  -- provenance, in case of multiple sources later
    crime_type                   VARCHAR(100),
    occurred_at                    TIMESTAMPTZ,
    location                         GEOGRAPHY(Point, 4326),
    raw_source_reference               TEXT,  -- original PNP record ID/reference, for traceability
    imported_at                          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_crime_records_location ON crime_incident_records USING GIST(location);
CREATE INDEX idx_crime_records_occurred_at ON crime_incident_records(occurred_at);

-- Pre-aggregated risk zones, IF PNP hands over hotspot data directly, OR
-- populated by our own aggregation job over crime_incident_records above.
-- Either path lands here — this is what the mobile app actually queries
-- for the risk-awareness map layer.
CREATE TABLE crime_risk_zones (
    zone_id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    zone_name                 VARCHAR(150),
    zone_geometry                GEOGRAPHY(Polygon, 4326) NOT NULL,
    risk_level                     SMALLINT NOT NULL CHECK (risk_level BETWEEN 1 AND 5),
    computed_from                    VARCHAR(20) NOT NULL DEFAULT 'pnp_provided',  -- 'pnp_provided' | 'self_aggregated'
    valid_from                         TIMESTAMPTZ NOT NULL DEFAULT now(),
    valid_until                          TIMESTAMPTZ,  -- NULL = current/active
    created_at                              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_risk_zones_geometry ON crime_risk_zones USING GIST(zone_geometry);
CREATE INDEX idx_risk_zones_active ON crime_risk_zones(valid_until) WHERE valid_until IS NULL;

-- ============================================================================
-- SECTION 8: FALSE ALARM / TRUST MONITORING
-- ============================================================================

CREATE TABLE false_alarm_reports (
    false_alarm_id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    incident_id                UUID NOT NULL REFERENCES incidents(incident_id) ON DELETE CASCADE,
    reported_by                  UUID NOT NULL REFERENCES users(user_id),  -- dispatcher/admin who marked it
    reason                          TEXT,
    reported_at                       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_false_alarm_incident ON false_alarm_reports(incident_id);

-- Running trust score per user, adjusted based on false-alarm history.
-- Kept separate from users table so it can be recomputed/audited independently.
CREATE TABLE user_trust_scores (
    user_id                UUID PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
    trust_score               NUMERIC(4,3) NOT NULL DEFAULT 1.000 CHECK (trust_score BETWEEN 0 AND 1),
    total_incidents_reported     INTEGER NOT NULL DEFAULT 0,
    total_false_alarms             INTEGER NOT NULL DEFAULT 0,
    last_recalculated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- SECTION 9: TRIGGERS — updated_at maintenance
-- ============================================================================

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_responder_profiles_updated_at
    BEFORE UPDATE ON responder_profiles
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_incidents_updated_at
    BEFORE UPDATE ON incidents
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Auto-log every incident status change into incident_status_history
CREATE OR REPLACE FUNCTION log_incident_status_change()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status) THEN
        INSERT INTO incident_status_history (incident_id, old_status, new_status, changed_at)
        VALUES (NEW.incident_id, OLD.status, NEW.status, now());
    ELSIF (TG_OP = 'INSERT') THEN
        INSERT INTO incident_status_history (incident_id, old_status, new_status, changed_at)
        VALUES (NEW.incident_id, NULL, NEW.status, now());
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_incident_status_history
    AFTER INSERT OR UPDATE ON incidents
    FOR EACH ROW EXECUTE FUNCTION log_incident_status_change();

-- Auto-resolve incident_barangay_id on insert via point-in-polygon lookup,
-- so the app layer never has to remember to do this itself. Leaves it NULL
-- if the point falls outside every known boundary (missing/incomplete
-- boundary data, bad GPS fix) — app layer treats NULL as "fall back to
-- radius-only matching immediately."
CREATE OR REPLACE FUNCTION resolve_incident_barangay()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.incident_barangay_id IS NULL THEN
        SELECT barangay_id INTO NEW.incident_barangay_id
        FROM barangay_boundaries
        WHERE ST_Contains(boundary_geometry::geometry, NEW.location::geometry)
        LIMIT 1;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_resolve_incident_barangay
    BEFORE INSERT ON incidents
    FOR EACH ROW EXECUTE FUNCTION resolve_incident_barangay();

-- ============================================================================
-- SECTION 10: EXAMPLE QUERIES — responder matching (barangay primary, radius fallback)
-- (reference only; actual call will live in Laravel/FastAPI service layer)
-- ============================================================================

-- STEP 1 (PRIMARY): on-duty tanods assigned to the incident's own barangay.
--
-- SELECT rp.responder_id, u.full_name,
--        ST_Distance(rp.last_location, i.location) AS distance_meters
-- FROM responder_profiles rp
-- JOIN users u ON u.user_id = rp.responder_id
-- CROSS JOIN incidents i
-- WHERE i.incident_id = :incident_id
--   AND rp.is_on_duty = true
--   AND rp.responder_type = 'barangay_tanod'
--   AND rp.assigned_barangay_id = i.incident_barangay_id
-- ORDER BY distance_meters ASC;
--
-- STEP 2 (FALLBACK): only run if Step 1 returns zero rows, OR if
-- i.incident_barangay_id IS NULL (point fell outside all known boundaries).
-- Widens to pure radius/proximity, same as the original pure-radius design —
-- this is what keeps the system from going silent when the primary
-- barangay has no on-duty responder.
--
-- SELECT rp.responder_id, u.full_name,
--        ST_Distance(rp.last_location, i.location) AS distance_meters
-- FROM responder_profiles rp
-- JOIN users u ON u.user_id = rp.responder_id
-- CROSS JOIN incidents i
-- WHERE i.incident_id = :incident_id
--   AND rp.is_on_duty = true
--   AND rp.responder_type = 'barangay_tanod'
--   AND ST_DWithin(rp.last_location, i.location, 1500)
-- ORDER BY distance_meters ASC;
--
-- App-layer logic: run Step 1; if empty, run Step 2; log which path was
-- used on the resulting incident_notifications rows (delivery_channel or
-- a future 'matched_via' column can carry this if you want it queryable).
