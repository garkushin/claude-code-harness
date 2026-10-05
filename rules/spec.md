# Спека

Спека пишется по `superpowers:brainstorming`: путь (spike, bounded, architectural), диалог, подходы и одобрения — по скиллу. Это правило задаёт, куда и в каком формате ложится письменная спека, если в проекте есть OpenSpec. Без OpenSpec — формат и место по скиллу.

Проект с OpenSpec — в репозитории есть `openspec/` (проверка: `openspec list --json`, поле `root` не `null`). Тогда спека — change OpenSpec, а не `docs/superpowers/specs/`:
- Диалог ведётся по brainstorming; проектные скиллы `openspec-propose` и `openspec-explore` его не заменяют.
- Одобренный дизайн записывается в change: `openspec new change <имя>`, каждый артефакт — по `openspec instructions <артефакт> --change <имя> --json`. Шаблон и инструкция схемы обязательны, `context` и `rules` из `openspec/config.yaml` — ограничения, их не копируют в файл. Намерение и критерии успеха идут в `proposal.md`, наблюдаемое поведение со сценариями — в дельты `specs/`, подходы с компромиссами, риски и обработка ошибок — в `design.md`.
- Самопроверка спеки включает `openspec validate <имя> --strict`.
- План — два файла. `tasks.md` в change — чек-лист: группа задач = поток, у каждой задачи способ проверки. Подробный план по `superpowers:writing-plans` — `plan.md` вне change, его задачи ссылаются на номера из `tasks.md`. Задача выполнена — её чекбокс в `tasks.md` отмечается.
- `openspec-apply-change` не используется: реализация идёт по плану.
- Change не коммитится отдельно, вопреки умолчанию brainstorming. Перед финальным коммитом — `openspec archive <имя> --yes`: дельты вливаются в `openspec/specs/`, и всё уходит одним коммитом с кодом.
