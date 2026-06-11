-- THROWAWAY (#99 validation): a harmless table comment so this PR is opened
-- as a migration change, which makes Supabase provision a preview branch —
-- letting us confirm the deploy step injects the branch's isolated DB.
-- This PR is NOT meant to merge.
COMMENT ON TABLE public.passage IS 'Reader passages (one row per passage or document part).';
