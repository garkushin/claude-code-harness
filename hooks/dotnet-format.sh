#!/bin/bash
# PostToolUse(Edit|Write): форматирует изменённый .cs-файл через dotnet format.
# Никогда не блокирует ход: сбой форматирования не повод останавливать агента.

file=$(jq -r '.tool_input.file_path // empty')
[[ "$file" == *.cs && -f "$file" ]] || exit 0

dir=$(dirname "$file")
proj=""
while [[ "$dir" != "/" ]]; do
  proj=$(find "$dir" -maxdepth 1 -name '*.csproj' -print -quit)
  [[ -n "$proj" ]] && break
  dir=$(dirname "$dir")
done

# --include резолвится от cwd, а не от проекта: абсолютный путь молча ничего не форматирует.
# Полный format (стиль + анализаторы) требует restored-проекта; в свежем worktree
# его нет — тогда хотя бы whitespace, которому проект не нужен.
if [[ -n "$proj" ]]; then
  root=$(dirname "$proj")
  cd "$root" && dotnet format "$proj" --include "${file#"$root"/}" --no-restore -v q >/dev/null 2>&1 && exit 0
fi
cd "$(dirname "$file")" && dotnet format whitespace . --folder --include "$(basename "$file")" -v q >/dev/null 2>&1
exit 0
