# FastAPI Starter

This is the Python/FastAPI alternative to the default Next.js starter.

## How to swap

1. Remove the Next.js files from root:

   ```bash
   rm -rf app/ __tests__/ package.json package-lock.json \
     next.config.ts tsconfig.json vitest.config.ts vitest.setup.ts \
     eslint.config.mjs instrumentation.ts
   ```

2. Copy files from this directory to the project root:

   ```bash
   cp -r starters/fastapi/app/ app/
   cp -r starters/fastapi/tests/ tests/
   cp starters/fastapi/pyproject.toml pyproject.toml
   cp starters/fastapi/uv.lock uv.lock
   cp starters/fastapi/render.yaml render.yaml
   ```

3. Update `CLAUDE.md` build/test commands to:

   ```bash
   uv run uvicorn app.main:app --reload  # Dev server
   uv run ruff check .                    # Lint
   uv run pytest                          # Tests
   ```

4. Install and run:

   ```bash
   pip install -e .
   uvicorn app.main:app --reload
   ```

The CI `python` job activates automatically when `pyproject.toml` exists.
