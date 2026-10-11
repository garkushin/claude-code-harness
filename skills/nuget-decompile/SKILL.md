---
name: nuget-decompile
description: Read the source of any NuGet package via ilspycmd decompilation — when you need to see how a package type is implemented, what a method actually does, what an internal/undocumented contract looks like, or to debug behavior hidden inside a dependency. Use for any ".NET package internals" question instead of guessing from memory.
---

# Чтение исходников NuGet-пакетов

Декомпиляция через `~/.dotnet/tools/ilspycmd` (может отсутствовать в PATH — зови по полному пути). Всегда добавляй `--disable-updatecheck`.

## 1. Найди сборку

Кеш пакетов: `~/.nuget/packages/<package-id-в-нижнем-регистре>/<версия>/lib/<tfm>/*.dll`

- Точный путь к dll даёт `obj/project.assets.json` проекта: в секции `targets` у пакета ключ `runtime` называет ровно тот `lib/<tfm>/x.dll`, что выбрал NuGet (включая транзитивные пакеты). Не гадай TFM руками, если assets.json есть. По ключу `compile` не ходи — он часто указывает в `ref/`; `runtime` пуст или равен `_._` — сборки в пакете нет.
- Нет потребляющего проекта (смотришь пакет сам по себе) — бери самую новую версию из кеша и самый новый TFM.
- Бери `lib/`, не `ref/`: ref-сборки — только сигнатуры, все тела `throw null`. `runtimes/` — платформо-специфичные варианты.
- Версии из assets.json нет в кеше — `dotnet restore` проекта (assets.json бывает stale). Пакета нет вообще — `dotnet add package` во временный проект в scratchpad.
- Не знаешь, в каком пакете тип? Сначала grep по `project.assets.json`, потом цикл `ilspycmd -l cisde` по кандидатам. Типы shared framework (ASP.NET Core и т.п.) живут не в кеше, а в `/usr/local/share/dotnet/shared/`.

```bash
ls ~/.nuget/packages/<id>/            # какие версии есть локально
find ~/.nuget/packages/<id>/<ver> -name '*.dll'
```

## 2. Лестница навигации — от дешёвого к дорогому

**Обзор типов** (что вообще есть в сборке; grep по имени):
```bash
~/.dotnet/tools/ilspycmd -l cisde --disable-updatecheck <dll> | grep -i <name>
```
Буквы = class/interface/struct/delegate/enum, слитно одним значением: `-l c,i,s` и повторные `-l` молча дают пустой вывод с exit 0. Типы вида `<>c__DisplayClass`, `<Module>`, `<>f__AnonymousType`, `<PrivateImplementationDetails>` — компиляторный шум, игнорируй.

**Один тип** (основной инструмент — контракт и реализация, в stdout):
```bash
~/.dotnet/tools/ilspycmd -t Full.Namespace.TypeName --disable-updatecheck <dll>
```
Generic-типы: `-l` печатает имя без арности, но `-t` требует CLR-имя `` Namespace.Type`N `` (в кавычках для шелла), иначе падает со stack trace `Could not find type definition`. Тип есть в `-l`, но исходника нет — он может быть `TypeForwardedTo` в другую сборку: смотри `AssemblyInfo.cs` декомпилята и иди в тот пакет.
XML-документация пакета вшивается в вывод автоматически (из `.xml` рядом с dll) — контракт виден вместе с кодом.

**Вся сборка как проект** — когда нужен grep по всей реализации (цепочки вызовов, все использования) или это уже второй вопрос к тому же пакету. Выводи в постоянный кеш — пакетная папка иммутабельна, значит декомпилят под ключом `<id>/<ver>` не протухает никогда; сначала проверь, не декомпилировано ли уже:
```bash
CACHE=~/.cache/nuget-decompiled/<id>/<ver>
[ -d "$CACHE" ] || ~/.dotnet/tools/ilspycmd -p --nested-directories --disable-updatecheck -o "$CACHE" <dll>
```
Дальше — обычный grep/read по дереву `.cs`. В репозиторий декомпилят не выводить никогда.

## 3. Уточнения

- Предупреждения о неразрешённых зависимостях лечатся `-r <папка-с-dll-зависимостей>` (обычно `lib/` соседних пакетов) — но для чтения кода чаще всего можно игнорировать.
- IL нужен редко (`-il`) — только когда C#-декомпилят подозрителен (async/await, yield-машины).
- Декомпилят — это восстановленный код: имена локальных переменных синтетические, sugar может быть развёрнут. Для вопросов «как использовать API» сначала XML-доки/README пакета, декомпиляция — для «как оно работает на самом деле».

## Анти-паттерны

- Не декомпилируй всю сборку ради одного типа — `-t` дешевле на два порядка.
- Не отвечай про поведение пакета по памяти, если dll лежит в кеше — проверь.
- Не коммить декомпилят и не оставляй его в рабочем дереве проекта.
