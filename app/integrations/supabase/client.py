"""Supabase client singletons.

Two clients per process:
  - `anon_client()` — uses the public anon key. Subject to RLS. Use for
    anything driven by an authenticated user's JWT (auth.get_user, app
    queries that need to respect the per-user policies from SUPA-2).
  - `service_client()` — uses the service-role key. Bypasses RLS.
    Use for background jobs, cross-tenant admin tasks, and tables with
    no per-user policy (comprehension cache, rate buckets).

NEVER expose the service client to request handlers without an explicit
reason — service-key bypassing RLS is the entire RLS escape hatch.

Sync client (not async) because the rest of the app is sync (SQLModel
+ FastAPI sync dependencies); mixing async here would force every call
site to be `async def`.
"""

from functools import lru_cache

from app.config import get_settings
from supabase import Client, create_client


@lru_cache(maxsize=1)
def anon_client() -> Client:
    """Singleton anon-key client. RLS applies."""
    settings = get_settings()
    return create_client(settings.supabase_url, settings.supabase_anon_key)


@lru_cache(maxsize=1)
def service_client() -> Client:
    """Singleton service-key client. RLS is bypassed. Server-side only."""
    settings = get_settings()
    return create_client(settings.supabase_url, settings.supabase_service_key)
