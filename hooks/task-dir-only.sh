#!/bin/bash
# PreToolUse(Edit|Write) для ролей без права менять код: писать можно только в каталог задачи.

file=$(jq -r '.tool_input.file_path // empty')
[[ "$file" == */docs/tasks/* ]] && exit 0

echo "Эта роль пишет только в docs/tasks/<задача>/ — отчёт клади туда, правку кода верни оркестратору." >&2
exit 2
