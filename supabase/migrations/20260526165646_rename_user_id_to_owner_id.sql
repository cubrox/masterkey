-- Idempotent rename of `user_id` → `owner_id` on tenant-scoped tables (BUG-4 / #105).
--
-- Background: the production Supabase Postgres was data-migrated from
-- the old alembic-era Neon database, which used the column name
-- `user_id`. The SUPA-2c rename (`user_id` → `owner_id`) was applied to
-- the SQLModel definitions + the supabase/migrations/*.sql files
-- (which use `owner_id` from their initial state), but the production
-- database itself was never realigned. Surface symptom: paste fails
-- with `psycopg.errors.UndefinedColumn: column "owner_id" of relation
-- "passage" does not exist` after the #104 type-coercion fix moved
-- past the previous crash. See #105.
--
-- This migration is IDEMPOTENT:
--   - On production (still has `user_id`): does the rename.
--   - On local Supabase / per-PR branches (already `owner_id`): no-op.
--   - Re-running is safe.
--
-- Why IF EXISTS in every branch: the initial_schema migration already
-- creates the column as `owner_id` for fresh databases, so the IF
-- EXISTS guards make this migration land cleanly regardless of whether
-- a given database was bootstrapped from the alembic-era schema or
-- from a fresh `supabase db push`.

DO $$
BEGIN
    -- passage.user_id → owner_id
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name   = 'passage'
          AND column_name  = 'user_id'
    ) THEN
        ALTER TABLE public.passage RENAME COLUMN user_id TO owner_id;
    END IF;

    -- preference.user_id → owner_id  (also the primary key — the rename
    -- automatically renames the implicit PK constraint).
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name   = 'preference'
          AND column_name  = 'user_id'
    ) THEN
        ALTER TABLE public.preference RENAME COLUMN user_id TO owner_id;
    END IF;

    -- reading_event.user_id → owner_id
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name   = 'reading_event'
          AND column_name  = 'user_id'
    ) THEN
        ALTER TABLE public.reading_event RENAME COLUMN user_id TO owner_id;
    END IF;
END $$;

-- Rename indexes that reference the old column name.
-- (Postgres preserves the index logically when a column is renamed,
-- but the INDEX NAME stays as it was, so we rename for grep-ability.
-- The composite indexes were defined in the alembic-era migrations as
-- `ix_<table>_user_id_created_at`; rename to match the supabase-era
-- `ix_<table>_owner_id_created_at` shape.)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public'
          AND indexname  = 'ix_passage_user_id_created_at'
    ) THEN
        ALTER INDEX public.ix_passage_user_id_created_at
            RENAME TO ix_passage_owner_id_created_at;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public'
          AND indexname  = 'ix_reading_event_user_id_created_at'
    ) THEN
        ALTER INDEX public.ix_reading_event_user_id_created_at
            RENAME TO ix_reading_event_owner_id_created_at;
    END IF;
END $$;

-- Drop any leftover alembic-era FK constraints that pointed at the
-- deleted `public.user` table. Recreate the FK against `auth.users`
-- to match what the supabase-era initial_schema.sql declares.
--
-- Why this matters: if the data-migration preserved the column but the
-- old `public.user` table was dropped on the way to Supabase, the FK
-- constraint is dangling. On a database where the FK already points at
-- auth.users (fresh supabase bootstrap), the DROP IF EXISTS is a no-op
-- and the ADD CONSTRAINT either succeeds (if missing) or duplicates —
-- so we DROP IF EXISTS first to make ADD idempotent.
DO $$
DECLARE
    fk_record RECORD;
BEGIN
    -- Drop ANY foreign-key constraint on passage.owner_id /
    -- preference.owner_id / reading_event.owner_id, regardless of
    -- target. We re-add the auth.users FK below.
    FOR fk_record IN
        SELECT conname, conrelid::regclass AS table_name
        FROM pg_constraint
        WHERE contype = 'f'
          AND conrelid IN (
              'public.passage'::regclass,
              'public.preference'::regclass,
              'public.reading_event'::regclass
          )
    LOOP
        EXECUTE format(
            'ALTER TABLE %s DROP CONSTRAINT IF EXISTS %I',
            fk_record.table_name, fk_record.conname
        );
    END LOOP;
END $$;

ALTER TABLE public.passage
    ADD CONSTRAINT passage_owner_id_fkey
        FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE public.preference
    ADD CONSTRAINT preference_owner_id_fkey
        FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE public.reading_event
    ADD CONSTRAINT reading_event_owner_id_fkey
        FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE CASCADE;
