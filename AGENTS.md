# AI Agent Instructions for CricPro

## Token-saving rule
Before searching the repo, read these files in this order:
1. `AGENTS.md`
2. `AI_PROJECT_INDEX.md`
3. `AI_TASK_LOG.md`

Do **not** scan the whole project unless the index does not answer where the relevant code lives.

## Required workflow
1. Read `AI_PROJECT_INDEX.md` first.
2. Identify the smallest set of files needed for the task.
3. Open only those files.
4. Make the change.
5. Run the smallest useful tests/checks.
6. Update `AI_TASK_LOG.md` with changed files, commands, result, and pending issues.
7. If you discover a new important file/route/table, update `AI_PROJECT_INDEX.md`.

## Hard rules
- Do not duplicate existing routes.
- Do not rewrite working features unless requested.
- Keep CricPro dark/cyan premium design consistent.
- Preserve score/team/status data logic unless explicitly asked.
- Admin-managed data should come from backend/admin panel first.
- No broken images: always fallback to safe initials/assets.

## When unsure
Use targeted search only. Search for exact symbols, route names, class names, or file names. Avoid broad project scans.
