# Claude Code env

Ручная конфигурация Claude Code: правила, скиллы, настройки. Всё остальное в
`~/.claude` — состояние харнеса, оно вне git (whitelist в `.gitignore`).

## Состав

- `rules/` — always-on правила: комментарии, документация, инструменты,
  стиль кода, тесты, модель сабагента, ревью. Claude Code грузит
  `~/.claude/rules/` сам, импорты из `CLAUDE.md` не нужны
- `skills/` — скиллы по требованию: `writing-docs`, `nuget-decompile`.
  `skills/synced/` — скиллы аккаунта claude.ai, их пишет синхронизация, вне git
- `agents/` — сабагенты `opus-medium`, `opus-high`, `opus-xhigh`
- `hooks/` — скрипты хуков; подключаются в `settings.json`
- `settings.json` — плагины, env, sandbox, хуки
- `mcp/` — версионированные копии MCP-конфигов; харнес их отсюда НЕ читает,
  восстанавливай командой из раздела ниже

## Пререквизиты

- .NET SDK 10 — минимум для roslyn-nav и `ilspycmd`, оба таргетят `net10.0`
- `ilspycmd` (`dotnet tool install -g ilspycmd`) — декомпиляция для скилла
  `nuget-decompile`; живёт в `~/.dotnet/tools`, PATH не обязателен
- Docker Desktop с MCP Toolkit — гейтвей `MCP_DOCKER`
- [RoslynCSMCP](https://github.com/bbfox0703/RoslynCSMCP), склонированный локально
  (например `~/projects/RoslynCSMCP`) — путь к клону зашит в `mcp/roslyn-nav.json`
  и правится под свою машину
- Плагины `superpowers` и `ponytail` — маркетплейсы уже прописаны в
  `settings.json`, при первом запуске Claude Code доустановит сам

## Доступные MCP

- **`roslyn-nav`** — символьная навигация по C#: ссылки, реализации, структура
  проекта, аутлайн файла. Локальный stdio-сервер, поднимается через `dotnet run`
- **`MCP_DOCKER`** — гейтвей Docker MCP Toolkit, профиль `default`:
  - `context7` — документация библиотек по версии пакета
  - `fetch` — загрузка веб-страниц
  - `sequentialthinking` — пошаговое рассуждение

Состав гейтвея меняется через Docker Desktop; текущий список — `docker mcp
profile server ls`.

## Восстановление на новой машине

1. Склонируй репозиторий в `~/.claude` до первого запуска Claude Code.
2. Поставь пререквизиты из списка выше.
3. Поправь путь к клону RoslynCSMCP в `mcp/roslyn-nav.json`.
4. Зарегистрируй MCP-серверы (они хранятся в `~/.claude.json`, вне git):

```bash
claude mcp add-json roslyn-nav --scope user "$(python3 -c "import json;print(json.dumps(json.load(open('$HOME/.claude/mcp/roslyn-nav.json'))['mcpServers']['roslyn-nav']))")"
```

```bash
claude mcp add MCP_DOCKER --scope user -- docker mcp gateway run --profile default
```

5. Проверь: `claude mcp list` должен показать оба сервера.

## Почему MCP не в репозитории

`mcpServers` читаются только из `~/.claude.json` (user/local scope) или
`.mcp.json` в корне конкретного проекта — `~/.claude/settings.json` этот ключ
не поддерживает. Поэтому в `mcp/` лежат эталонные копии, а не рабочий конфиг.
