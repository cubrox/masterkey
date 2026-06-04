-- COMP-5 (#128): per-passage comprehension toggle.
--
-- Additive column, default true, so every existing passage keeps its
-- questions on. The reading view + POST /passages/{id}/comprehension flip
-- this; the questions route skips generation when it's false. Mirrors the
-- SQLModel field on app/models/passage.py.
--
-- IF NOT EXISTS keeps the migration idempotent across re-applies and
-- per-PR Supabase branches.
ALTER TABLE public.passage
    ADD COLUMN IF NOT EXISTS comprehension_enabled boolean NOT NULL DEFAULT true;
