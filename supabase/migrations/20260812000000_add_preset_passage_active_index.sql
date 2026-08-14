-- Follow-up to PRESET-1/3 review (#279/#281): index the picker query.
--
-- GET /passages/new lists active presets ordered by sort_order then
-- created_at (app/api/passages.py new_passage_form). A partial index on
-- exactly that shape keeps the picker cheap as the curated library grows.
-- (The library is tiny today, so this is hygiene, not a hot path — but it's
-- free and matches the query.)
CREATE INDEX IF NOT EXISTS ix_preset_passage_active_order
    ON public.preset_passage (sort_order, created_at)
    WHERE is_active;
