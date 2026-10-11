#!/bin/bash
# PreToolUse(Edit|Write) для ролей без права менять код: писать можно только в каталог задачи,
# в change OpenSpec, во временный каталог сессии и в свой worktree эксперимента из EnterWorktree.

input=$(cat)
file=$(jq -r '.tool_input.file_path // empty' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")
[[ "$file" == */../* ]] && { echo "Путь с '..' запрещён: укажи нормализованный абсолютный путь." >&2; exit 2; }
[[ "$file" == */docs/tasks/* || "$file" == */openspec/changes/* || "$file" == /private/tmp/claude-* || "$file" == /tmp/claude-* ]] && exit 0
# После EnterWorktree cwd роли — её worktree; чужие worktree потоков лежат вне cwd.
[[ "$cwd" == */.claude/worktrees/* && "$file" == "$cwd"/* ]] && exit 0

echo "Эта роль пишет только в docs/tasks/<задача>/ и openspec/changes/<change>/ — отчёт клади туда, правку кода верни оркестратору." >&2
exit 2
