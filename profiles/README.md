# Профиль OmniRoute

`omniroute.json` задаёт модели для вкладки Code в Claude Desktop через облачный OmniRoute. Sonnet 5.5 стоит первым и используется по умолчанию. Профиль ограничивает effort до `xhigh` для Sonnet 5.5 и до `max` для Opus и Haiku 5.5. Конкретный уровень выбирается в приложении. Эти настройки работают в Claude Desktop.

## Примени настройки

1. Закрой Claude; на новой машине сначала создай в нём профиль с именем `OmniRoute`.
2. Выполни:

```bash
python3 ~/.claude/profiles/apply-omniroute.py
```

3. Открой Claude и заново примени профиль `OmniRoute`.

Скрипт находит профиль по имени, обновляет адрес шлюза и список моделей из эталона. API-ключ сохраняется из рабочей копии; если его ещё нет, укажи ключ из Endpoints облачного OmniRoute в настройках приложения.

## Храни ключ локально

Рабочая копия лежит в `~/Library/Application Support/Claude-3p/configLibrary/`, вне этого репозитория. Поле `inferenceGatewayApiKey` и резервные копии рабочего профиля не добавляй в Git; SSO dashboard и Vault не выдают этот клиентский ключ автоматически.
