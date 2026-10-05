# Claude Code env

Ручная конфигурация Claude Code: правила, скиллы, настройки. Всё остальное в
`~/.claude` — состояние харнеса, оно вне git (whitelist в `.gitignore`).

## Состав

- `rules/` — always-on правила: комментарии, документация, инструменты,
  стиль кода, тесты, модель сабагента, ревью, спека. Claude Code грузит
  `~/.claude/rules/` сам, импорты из `CLAUDE.md` не нужны
- `skills/` — скиллы по требованию: `writing-docs`, `nuget-decompile`.
  `skills/synced/` — скиллы аккаунта claude.ai, их пишет синхронизация, вне git
- `agents/` — роли сабагентов: `analyst`, `researcher`, `architect`, `tech-writer`
  и пары тиров `developer-`, `reviewer-`, `verifier-` × `middle`/`senior`
- `hooks/` — скрипты хуков; подключаются в `settings.json`
- `output-styles/` — роль основной сессии. `/output-style Orchestrator` включает
  `Orchestrator` в текущем проекте (пишет в его `.claude/settings.local.json`);
  глобально — `"outputStyle": "Orchestrator"` в `settings.json`. Правку файла
  стиля Claude Code подхватывает после перезапуска
- `settings.json` — разрешения (glab, push), плагины, sandbox, хуки, база worktree
- Правки `rules/`, `agents/`, `output-styles/` проверяй `/doctor prompt-audit ~/.claude`:
  ищет устаревшие и противоречащие друг другу инструкции
- `mcp/` — версионированные копии MCP-конфигов; харнес их отсюда НЕ читает,
  восстанавливай командой из раздела ниже

## Пререквизиты

- .NET SDK 10 — минимум для roslyn-nav и `ilspycmd`, оба таргетят `net10.0`
- `ilspycmd` (`dotnet tool install -g ilspycmd`) — декомпиляция для скилла
  `nuget-decompile`; живёт в `~/.dotnet/tools`, PATH не обязателен
- Docker Desktop с MCP Toolkit — гейтвей `MCP_DOCKER`
- [RoslynCSMCP](https://github.com/bbfox0703/RoslynCSMCP), склонированный локально
  (например `~/projects/RoslynCSMCP`) — путь к клону зашит в `mcp/roslyn-*.json`
  и правится под свою машину
- Плагины `superpowers` и `ponytail` — маркетплейсы уже прописаны в
  `settings.json`, при первом запуске Claude Code доустановит сам

## Доступные MCP

- **`roslyn-nav`** — символьная навигация по C#: поиск символов, ссылки,
  аутлайн файла. Модуль `Navigation` RoslynCSMCP
- **`roslyn-quality`** — качество кода: запахи, сложность, конкурентность,
  магические числа. Модуль `Quality` RoslynCSMCP

Оба — локальные stdio-серверы, поднимаются через `dotnet run`.

- **`MCP_DOCKER`** — гейтвей Docker MCP Toolkit, профиль `default`:
  - `context7` — документация библиотек по версии пакета
  - `fetch` — загрузка веб-страниц
  - `sequentialthinking` — пошаговое рассуждение

Состав гейтвея меняется через Docker Desktop; текущий список — `docker mcp
profile server ls`.

## Восстановление на новой машине

1. Склонируй репозиторий в `~/.claude` до первого запуска Claude Code.
2. Поставь пререквизиты из списка выше.
3. Поправь путь к клону RoslynCSMCP в `mcp/roslyn-navigation.json` и
   `mcp/roslyn-quality.json`.
4. Зарегистрируй MCP-серверы (они хранятся в `~/.claude.json`, вне git):

```bash
claude mcp add-json roslyn-nav --scope user "$(python3 -c "import json;print(json.dumps(json.load(open('$HOME/.claude/mcp/roslyn-navigation.json'))['mcpServers']['roslyn-nav']))")"
```

```bash
claude mcp add-json roslyn-quality --scope user "$(python3 -c "import json;print(json.dumps(json.load(open('$HOME/.claude/mcp/roslyn-quality.json'))['mcpServers']['roslyn-quality']))")"
```

```bash
claude mcp add MCP_DOCKER --scope user -- docker mcp gateway run --profile default
```

5. Проверь: `claude mcp list` должен показать все три сервера.

## Почему MCP не в репозитории

`mcpServers` читаются только из `~/.claude.json` (user/local scope) или
`.mcp.json` в корне конкретного проекта — `~/.claude/settings.json` этот ключ
не поддерживает. Поэтому в `mcp/` лежат эталонные копии, а не рабочий конфиг.
