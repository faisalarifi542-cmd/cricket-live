Upload/copy these files to your repo root:

1. AGENTS.md
2. AI_PROJECT_INDEX.md
3. AI_TASK_LOG.md
4. CLAUDE_START_PROMPT.txt

How to use:
- Every time you start Claude/Codex, paste the text from CLAUDE_START_PROMPT.txt.
- Put your task after "Now do this task:".
- Tell the agent not to scan the full repo.
- The agent must update AI_TASK_LOG.md after every task.

Why this reduces token usage:
- AI reads a short index instead of the whole project.
- AI uses targeted file paths instead of broad search.
- New sessions can continue from AI_TASK_LOG.md.
