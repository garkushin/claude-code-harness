#!/bin/bash
# Тест hooks/signals.sh: журнал пишется во временный каталог из CLAUDE_SIGNALS_DIR.

hook="$(cd "$(dirname "$0")" && pwd)/signals.sh"
log=$(mktemp -d)
export CLAUDE_SIGNALS_DIR=$log CLAUDE_PROJECT_DIR=/proj
trap 'rm -rf "$log" "$log/../evil.jsonl"' EXIT
checks=0
failed=0
written=0

fail() { echo "FAIL: $1"; failed=1; }

check() { checks=$((checks + 1)); "${@:2}" || fail "$1"; }

total() { cat "$log"/*.jsonl 2>/dev/null | wc -l | tr -d ' '; }

lines() {
  local f="$log/${1:-s1}.jsonl"
  if [[ -f $f ]]; then wc -l <"$f" | tr -d ' '; else echo 0; fi
}

ev() {
  jq -nc --arg e "$1" --arg s "${3:-s1}" \
    "{session_id: \$s, prompt_id: \"p1\", cwd: \"/proj/sub\", hook_event_name: \$e} + ($2)"
}

run() {
  local before out
  before=$(total)
  out=$("$hook" <<<"$1" 2>&1) && [[ -z $out ]] || fail "хук падает или пишет в контекст"
  written=$(($(total) - before))
}

prompt() {
  local e
  e=$(ev UserPromptSubmit "{prompt: ($1)}" "$2")
  run "$e"
}

expect() {
  checks=$((checks + 1))
  [[ $written == 1 ]] && tail -n 1 "$log/${3:-s1}.jsonl" | jq -e "$2" >/dev/null 2>&1 || fail "$1"
}

# C1
prompt '"нет, верни как было"'
expect "реплика пользователя записана без общих полей, с project не из \$CLAUDE_PROJECT_DIR или ts не в UTC" \
  '.event=="UserPromptSubmit" and .origin=="user" and .prompt=="нет, верни как было" and .session_id=="s1" and .prompt_id=="p1" and .cwd=="/proj/sub" and .project=="/proj" and .agent_id==null and (.ts|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))'

# C2
prompt '"<task-notification>\n<task-id>x</task-id>"'
expect "отчёт фонового сабагента принят за реплику пользователя" '.origin=="harness"'
prompt '"Another Claude session sent a message: привет"'
expect "сообщение другой сессии принято за реплику пользователя" '.origin=="harness"'
prompt '"смотри <task-notification> ниже"'
expect "реплика пользователя с упоминанием конверта принята за харнес" '.origin=="user"'

# C3
prompt '"/retro"' s2
check "реплика /retro попала в журнал" test "$(lines s2)" -eq 0
check "реплика /retro не пометила сессию маркером" test -e "$log/.skip-s2"
prompt '"/retro проект"' s2a
check "реплика /retro с аргументом попала в журнал" test "$(lines s2a)" -eq 0
check "реплика /retro с аргументом не пометила сессию" test -e "$log/.skip-s2a"
prompt '"/retrospective"' s3
check "реплика /retrospective принята за /retro" test "$(lines s3)" -eq 1

# C4
run "$(ev UserPromptExpansion '{expansion_type: "slash_command", command_name: "retro", command_args: "", command_source: "user", prompt: "/retro"}' s4)"
run "$(ev Stop '{last_assistant_message: "x", stop_hook_active: false}' s4)"
run "$(ev PostToolUse '{tool_name: "Agent", agent_id: "ag9", tool_input: {prompt: "бриф"}, tool_response: {agentId: "a1"}}' s4)"
check "сессия /retro порождает сигналы" test ! -e "$log/s4.jsonl"
check "запуск /retro не пометил сессию маркером" test -e "$log/.skip-s4"
run "$(ev Stop '{last_assistant_message: "x", stop_hook_active: false}' s5)"
check "маркер /retro глушит чужую сессию" test "$(lines s5)" -eq 1

# C5
prompt '"до\n<pasted_content id=\"1\">\nABCDE\n</pasted_content id=\"1\">\nпосле"'
expect "вставка не заменена пометкой или в N посчитаны переводы строк" '.prompt=="до\n[вставка: 5 символов]\nпосле"'
prompt '"<pasted_content id=\"1\">\nABCDE\n</pasted_content id=\"1\">\n<pasted_content id=\"2\">\nABCDE\n</pasted_content id=\"2\">"'
expect "заменена не каждая вставка" '.prompt=="[вставка: 5 символов]\n[вставка: 5 символов]"'
prompt '"<pasted_content id=\"3\">\n" + "x" * 150000 + "\n</pasted_content id=\"3\">"'
expect "реплика с вставкой больше 100000 символов потеряна" '.prompt|contains("[вставка: 150000 символов]")'

# C6
masks() {
  prompt "$2"
  expect "$1" ".prompt==$3"
}
masks "маска стёрла имя ключа или пропустила значение key=value" '"token=abc123SECRETvalue"' '"token=[секрет]"'
masks "пароль в кавычках попал в журнал" '"password: \"hunter2pass\""' '"password: \"[секрет]\""'
masks "ключ API попал в журнал" '"API_KEY=sk-live-0123456789abcdef"' '"API_KEY=[секрет]"'
masks "токен Bearer попал в журнал" '"Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.e30.c2ln"' '"Authorization: Bearer [секрет]"'
masks "токен Bearer после имени ключа попал в журнал" '"access_token: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2lnbmF0dXJl"' '"access_token: [секрет] [секрет]"'
masks "значение ключа в JSON замаскировано не до закрывающей кавычки" '"{\"token\":\"Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2lnbmF0dXJl\"}"' '"{\"token\":\"[секрет]\"}"'
masks "hex-хеш короче 40 символов попал в журнал" '"md5 d41d8cd98f00b204e9800998ecf8427e"' '"md5 [секрет]"'
masks "base64-секрет попал в журнал" '"dGhpcyBpcyBhIHNlY3JldCB0b2tlbiB2YWx1ZTEyMzQ1Njc4"' '"[секрет]"'
masks "токен GitHub ghp_ попал в журнал" '"вот токен gh''p_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8"' '"вот токен [секрет]"'
masks "токен GitHub github_pat_ попал в журнал" '"github''_pat_11ABCDEFG0123456789_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456"' '"[секрет]"'
masks "токен из заголовка Authorization: token попал в журнал" '"curl -H \"Authorization: token s3cr3tT0k3n\""' '"curl -H \"Authorization: token [секрет]\""'
masks "пароль из URL попал в журнал" '"psql postgres://admin:S3cr3tPass@db.local:5432/app"' '"psql postgres://admin:[секрет]@db.local:5432/app"'
masks "пароль или токен из флага командной строки попал в журнал" '"mysql -u root --password hunter2pass; gh --token abc123tok"' '"mysql -u root --password [секрет]; gh --token [секрет]"'
masks "ключ Stripe попал в журнал" '"STRIPE=sk''_live_51HxYzAbCdEf0123 и sk''_test_4eC39HqLyjWDarjtT1zdp7dc"' '"STRIPE=[секрет] и [секрет]"'
masks "токен Slack попал в журнал" '"xo''xb-1234567890-1234567890123-AbCdEfGhIjKlMnOpQrStUvWx и xo''xp-9876543210-AbCdEf"' '"[секрет] и [секрет]"'
masks "ключ Anthropic замаскирован не целиком" '"sk''-ant-api03-Xy9_Zz8-Ww7AbCdEfGhIjKlMn-0pQ"' '"[секрет]"'

# C7
kept() {
  prompt "$1"
  expect "маска испортила доказательство $1" ".prompt==$1"
}
kept '"/Users/vlad/Projects/uniRest/orderCheckoutService2/src/Handlers/x.cs:12"'
kept '"/Users/vlad/Projects/pet2024/orderService3/src/Handlers/x.cs:12"'
kept '"550e8400-e29b-41d4-a716-446655440000"'
kept '"OrderCheckoutServiceRegistrationExtensionsV2"'
kept '"PrimaryKey: OrderId"'
kept '"var token = _issuer.Issue(user);"'

# C8
run "$(ev Stop '{last_assistant_message: "готово, token=abc123SECRETvalue", stop_hook_active: false}')"
expect "секрет из ответа ассистента попал в журнал" 'tostring|contains("abc123SECRETvalue")|not'

# C9
prompt '"я" * 4500'
expect "длинная реплика не обрезана до 4000 символов с пометкой" '.prompt == "я" * 4000 + "[обрезано: 500]"'
prompt '"я" * 4000'
expect "реплика ровно в лимит получила пометку обрезки" '.prompt == "я" * 4000'

# C10
run "$(ev Stop '{last_assistant_message: ("A" * 500 + "B" * 2000), stop_hook_active: false}')"
expect "из ответа ассистента сохранено не окончание" '.last_assistant_message == "[обрезано: 500]" + "B" * 2000'

# C22
sec=dGhpcyBpcyBhIHNlY3JldCB0b2tlbiB2YWx1ZTEyMzQ1Njc4
nofrag="[range(0; $((${#sec} - 8))) as \$i | \"$sec\"[\$i:\$i + 9]] as \$f | tostring as \$l | all(\$f[]; . as \$x | \$l | contains(\$x) | not)"
prompt "\"я\" * 3990 + \"$sec\" + \"я\" * 100"
expect "фрагмент секрета на границе лимита реплики попал в журнал" "$nofrag"
run "$(ev Stop "{last_assistant_message: (\"я\" * 100 + \"$sec\" + \"я\" * 1990)}")"
expect "фрагмент секрета на границе лимита ответа ассистента попал в журнал" "$nofrag"

# C11
run "$(ev PostToolUse '{tool_name: "Agent", tool_input: {subagent_type: "analyst", description: "Факты", prompt: "бриф"}, tool_response: {status: "completed", agentId: "a4d2c8f1e0b3a297", content: [{type: "text", text: "ok"}]}, tool_use_id: "t1"}')"
expect "бриф не связать со строками сабагента" '.tool_name=="Agent" and .subagent_type=="analyst" and .description=="Факты" and .prompt=="бриф" and .spawned_agent_id=="a4d2c8f1e0b3a297"'

# C12
run "$(ev PostToolUse '{tool_name: "SendMessage", tool_input: {to: "dev-a", message: "поправь X"}, tool_response: {}}')"
expect "сообщение сабагенту не записано строкой" '(.tool_input|type)=="string" and (.tool_input|contains("поправь X"))'

# C13
q='[{question: "Как?", header: "Выбор", options: [{label: "А", description: ""}, {label: "Б", description: ""}], multiSelect: false}]'
e=$(ev PostToolUse '{tool_name: "AskUserQuestion", tool_input: {questions: '"$q"'}, tool_response: {answers: {"Как?": "Б"}}}')
run "$e"
expect "вопросы искажены или ответ пользователя записан не строкой" ".questions == $q and (.tool_response|type)==\"string\" and (.tool_response|contains(\"Б\"))"
e=$(ev PostToolUse '{tool_name: "AskUserQuestion", tool_input: {questions: '"$q"'}, tool_response: "Б"}')
run "$e"
expect "строковый ответ пользователя закодирован в JSON повторно" '.tool_response=="Б"'

# C14
run "$(ev PostToolUse '{tool_name: "SubagentHandback", tool_input: {message: "итог"}, agent_id: "ag1", agent_type: "analyst"}')"
expect "отчёт сабагента потерян или не привязан к сабагенту" '.message=="итог" and .agent_id=="ag1" and .agent_type=="analyst"'

# C15
run "$(ev SubagentStop '{agent_id: "ag1", agent_type: "analyst", stop_hook_active: false, last_assistant_message: ("A" * 2000 + "B" * 500)}')"
expect "из ответа сабагента сохранено не начало" '.last_assistant_message == "A" * 2000 + "[обрезано: 500]"'
n=$(lines)
run "$(ev SubagentStop '{agent_id: "int1", agent_type: "", last_assistant_message: "x"}')"
check "внутренний агент Claude Code попал в журнал" test "$(lines)" -eq "$n"

# C16
run "$(ev PermissionDenied '{tool_name: "Bash", tool_input: {command: "rm -rf /tmp/build", description: "Clean build directory"}, tool_use_id: "t2", reason: "[Irreversible Local Destruction]"}')"
expect "отказ классификатора записан без команды или причины" '.tool_name=="Bash" and (.tool_input|contains("rm -rf /tmp/build")) and .reason=="[Irreversible Local Destruction]"'
run "$(ev PermissionDenied '{tool_name: "Bash", tool_input: {command: ("x" * 1500)}, tool_use_id: "t3", reason: "r"}')"
expect "вход отклонённого инструмента не обрезан до 1000 символов" '(.tool_input|test("\\[обрезано: [0-9]+\\]$")) and (.tool_input|length) < 1100'

# C17
run 'не json'
run "$(ev Stop '{last_assistant_message: "x"}' '../evil')"
check "session_id вывел запись за каталог журнала" test ! -e "$log/../evil.jsonl"
CLAUDE_SIGNALS_DIR=/dev/null/x
run "$(ev Stop '{last_assistant_message: "x"}')"
CLAUDE_SIGNALS_DIR=$log

# C18
mkdir "$log/s6.jsonl.lock"
"$hook" <<<"$(ev Stop '{last_assistant_message: "x"}' s6)" &
pid=$!
sleep 0.5
check "запись прошла мимо занятой блокировки" test "$(lines s6)" -eq 0
rmdir "$log/s6.jsonl.lock"
wait $pid
check "запись потеряна после снятия блокировки" test "$(lines s6)" -eq 1

finished() {
  local i
  for ((i = 0; i < $2; i++)); do kill -0 "$1" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$1" 2>/dev/null; then
    kill "$1"
    wait "$1" 2>/dev/null
    return 1
  fi
  wait "$1" 2>/dev/null
}

# C19
mkdir "$log/s7.jsonl.lock"
"$hook" <<<"$(ev Stop '{last_assistant_message: "x"}' s7)" &
check "хук бесконечно ждёт брошенную блокировку" finished $! 50
check "запись потеряна на брошенной блокировке" test "$(lines s7)" -eq 1
check "блокировка не снята после записи" test ! -d "$log/s7.jsonl.lock"

# C20
mkdir "$log/s8.jsonl.lock"
echo $$ >"$log/s8.jsonl.lock/pid"
"$hook" <<<"$(ev Stop '{last_assistant_message: "x"}' s8)" &
pid=$!
sleep 1
check "снята блокировка живого владельца" test "$(cat "$log/s8.jsonl.lock/pid" 2>/dev/null)" == $$
check "запись прошла мимо блокировки живого владельца" test "$(lines s8)" -eq 0
rm -f "$log/s8.jsonl.lock/pid"
rmdir "$log/s8.jsonl.lock"
wait $pid

# C21
true &
dead=$!
wait $dead
mkdir "$log/s9.jsonl.lock"
echo $dead >"$log/s9.jsonl.lock/pid"
"$hook" <<<"$(ev Stop '{last_assistant_message: "x"}' s9)" &
check "блокировка мёртвого владельца не снята сразу" finished $! 10
check "запись потеряна на блокировке мёртвого владельца" test "$(lines s9)" -eq 1

[[ $failed == 0 ]] || exit 1
echo "OK: $checks"
