-- PRESET-1 (#279): foundation for the curated preset message library (#278).
--
-- Adds:
--   1. `preset_passage` — the curated library of messages (e.g. UHJ letters).
--      Shared reference data: readable by any authenticated user, writable
--      only by the service role (seeded via migration/script in PRESET-2).
--   2. Nullable attribution columns on `passage` — copy-on-select (PRESET-4)
--      copies a preset's attribution onto the user-owned Passage it creates,
--      so the reading surface can always render the required
--      `Copyright © Bahá'í International Community` + source/author. Nullable
--      because paste/pdf passages carry no attribution.
--   3. Widens the `source_type` CHECK to allow 'preset'.
--
-- Additive and idempotent (IF NOT EXISTS / DROP-then-ADD) so it is safe to
-- re-apply across Supabase preview branches. No backfill: existing passages
-- keep NULL attribution.

-- 1. Curated library table.
CREATE TABLE IF NOT EXISTS public.preset_passage (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    title            text NOT NULL,
    -- Nullable: not every message names an individual author.
    author           text,
    copyright_holder text NOT NULL DEFAULT 'Bahá''í International Community',
    source_url       text NOT NULL,
    source_date      date,
    text             text NOT NULL,
    -- Content-addressable key into comprehension_question_cache (ADR-001), so
    -- every reader who opens the same preset shares one set of generated
    -- questions. SHA-256 of the exact stored text, same rule as passage.
    text_hash        bytea NOT NULL,
    -- Soft on/off without deleting history; the picker lists only active rows.
    is_active        boolean NOT NULL DEFAULT true,
    sort_order       integer NOT NULL DEFAULT 0,
    created_at       timestamptz NOT NULL DEFAULT now()
);

-- 2. Attribution columns on passage (nullable — paste/pdf have none).
ALTER TABLE public.passage
    ADD COLUMN IF NOT EXISTS attribution_title      text,
    ADD COLUMN IF NOT EXISTS attribution_author     text,
    ADD COLUMN IF NOT EXISTS attribution_copyright  text,
    ADD COLUMN IF NOT EXISTS attribution_source_url text;

-- 3. Widen the source_type CHECK to include 'preset'. DROP-then-ADD (not left
--    at the old 2-value form) so the constraint actually reflects reality.
ALTER TABLE public.passage
    DROP CONSTRAINT IF EXISTS passage_source_type_check;
ALTER TABLE public.passage
    ADD CONSTRAINT passage_source_type_check
        CHECK (source_type IN ('paste', 'pdf', 'preset'));

-- RLS: preset_passage is shared reference data. Any authenticated session may
-- SELECT; there is NO insert/update/delete policy, so only the service role
-- (which bypasses RLS) can write it. `anon` has no policy and cannot read it.
ALTER TABLE public.preset_passage ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated can read preset passages" ON public.preset_passage;
CREATE POLICY "authenticated can read preset passages"
    ON public.preset_passage FOR SELECT
    TO authenticated
    USING (true);
