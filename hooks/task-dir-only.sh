#!/bin/bash
# PreToolUse(Edit|Write) для ролей без права менять код: писать можно только в каталог задачи
# и во временный каталог сессии.

file=$(jq -r '.tool_input.file_path // empty')
[[ "$file" == */../* ]] && { echo "Путь с '..' запрещён: укажи нормализованный абсолютный путь." >&2; exit 2; }
[[ "$file" == */docs/tasks/* || "$file" == /private/tmp/claude-* || "$file" == /tmp/claude-* ]] && exit 0

echo "Эта роль пишет только в docs/tasks/<задача>/ — отчёт клади туда, правку кода верни оркестратору." >&2
exit 2
