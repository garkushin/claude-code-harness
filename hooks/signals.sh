#!/bin/bash
# UserPromptSubmit, UserPromptExpansion(retro), Stop, SubagentStop, PermissionDenied, PostToolUse(Agent|SendMessage|AskUserQuestion|SubagentHandback):
# пишет поправки и ответы в журнал сессии для /retro. Подключён async и на ход не влияет.

# stdout async-хука на UserPromptSubmit попадает в контекст следующего хода.
exec >/dev/null 2>&1
input=$(cat)

dir=${CLAUDE_SIGNALS_DIR:-$HOME/.claude/signals}
mkdir -p "$dir" || exit 0
sid=$(jq -r '.session_id // empty' <<<"$input")
[[ $sid =~ ^[A-Za-z0-9_-]+$ ]] || exit 0
[[ -e $dir/.skip-$sid ]] && exit 0

# Oniguruma отвергает {m,n} с границей больше 100000, и ошибка jq теряет строку журнала.
line=$(jq -c --arg project "$CLAUDE_PROJECT_DIR" '
  def unpaste:
    reduce (split("\n")[]) as $l ({out: [], n: null};
      if .n == null then
        if $l | startswith("<pasted_content") then .n = -1 else .out += [$l] end
      elif $l | startswith("</pasted_content") then
        .out += ["[вставка: \([.n, 0] | max) символов]"] | .n = null
      else .n += ($l | length) + 1 end)
    | if .n == null then .out else .out + ["[вставка: \([.n, 0] | max) символов]"] end
    | join("\n");
  def digits3: if ([explode[] | select(. >= 48 and . <= 57)] | length) >= 3 then "[секрет]" else . end;
  def mask:
    gsub("(gh[pousr]_[A-Za-z0-9]{20,255}|github_pat_[A-Za-z0-9_]{20,255}|sk-ant-[A-Za-z0-9_-]{8,512}|sk_(live|test)_[A-Za-z0-9]{8,255}|xox[bp]-[A-Za-z0-9-]{8,255})"; "[секрет]")
    | gsub("(?<p>[A-Za-z][A-Za-z0-9+.-]{0,31}://[^\\s:/@]{1,256}:)[^\\s/@]{1,256}@"; "\(.p)[секрет]@")
    | gsub("(?<p>(Bearer|Authorization:\\s{0,3}token)\\s{1,3})[A-Za-z0-9._~+/=-]{8,8192}"; "\(.p)[секрет]"; "i")
    | gsub("(?<p>--(password|passwd|token)(\\s{1,3}|=)(\\\\?[\"\\x27])?)[^\\s\"\\x27\\\\,;]{1,512}"; "\(.p)[секрет]")
    | gsub("(?<k>(?<![A-Za-z0-9])(([A-Za-z0-9]{1,32}[_-]){0,4}(?i:token|secret|password|passwd|key)|[A-Za-z][A-Za-z0-9]{0,32}(Token|Secret|Password|Passwd)|(?i:api|access|secret|private)(Key|key|KEY)))(?<s>\\\\?\"?\\s{0,3}[=:]\\s{0,3})((?<q>\\\\?[\"\\x27])[^\"\\x27\\\\\\n]{1,512}|(?<v>[^\\s\"\\x27\\\\,;]{1,512}))";
        if .v != null and (.v | test("^[A-Za-z_][A-Za-z0-9_]{0,63}(\\.[A-Za-z_][A-Za-z0-9_]{0,63}){0,8}\\(")) then .k + .s + .v
        else .k + .s + (.q // "") + "[секрет]" end)
    | gsub("(?<t>[A-Za-z0-9+=]{40,8192})"; .t | digits3)
    | gsub("(?<t>[0-9a-fA-F]{32,8192})"; .t | digits3);
  # match в jq 1.7.1 квадратичен по числу совпадений, поэтому маскируется только окно у лимита;
  # запас в 256 символов нужен, чтобы секрет на границе обрезки не ушёл в журнал фрагментом;
  # обрывок слова у края окна отрезается или дописывается, иначе правило не узнает секрет без начала или без ключа.
  def head($n): length as $len | .[:$n + 256] | (if $len > $n + 256 then sub("\\S{1,256}$"; "") else . end) | mask | if $len > $n then .[:$n] + "[обрезано: \($len - $n)]" else . end;
  def tail($n): length as $len | (if $len > $n + 256 then (.[:$len - $n - 256] | .[-8256:] | capture("(?<w>[\\s\\S]{0,64}\\S{0,8192})$").w) else "" end) + .[-($n + 256):] | mask | if $len > $n then "[обрезано: \($len - $n)]" + .[-$n:] else . end;

  {ts: (now | todate), session_id, prompt_id, agent_id, agent_type, project: $project, cwd, event: .hook_event_name} as $c
  | if .hook_event_name == "UserPromptExpansion" then
      if .command_name == "retro" then "skip" else empty end
    elif .hook_event_name == "UserPromptSubmit" then
      (.prompt // "") as $p
      | if $p | test("^/retro(\\s|$)") then "skip"
        else $c + {
          prompt: ($p | unpaste | head(4000)),
          origin: (if $p | startswith("<task-notification>") or startswith("Another Claude session sent a message:") then "harness" else "user" end)
        } end
    elif .hook_event_name == "Stop" then
      $c + {last_assistant_message: (.last_assistant_message // "" | tail(2000))}
    elif .hook_event_name == "SubagentStop" then
      if (.agent_type // "") == "" then empty
      else $c + {last_assistant_message: (.last_assistant_message // "" | head(2000))} end
    elif .hook_event_name == "PermissionDenied" then
      $c + {tool_name, tool_input: (.tool_input | tojson | head(1000)), reason}
    elif .hook_event_name == "PostToolUse" then
      $c + {tool_name} + (
        if .tool_name == "Agent" then
          {subagent_type: .tool_input.subagent_type, description: .tool_input.description,
           prompt: (.tool_input.prompt // "" | head(4000)), spawned_agent_id: .tool_response.agentId}
        elif .tool_name == "SendMessage" then
          {tool_input: (.tool_input | tojson | head(4000))}
        elif .tool_name == "AskUserQuestion" then
          {questions: (.tool_input.questions | walk(if type == "string" then mask else . end)),
           tool_response: (.tool_response | if type == "string" then . else tojson end | head(2000))}
        elif .tool_name == "SubagentHandback" then
          {message: (.tool_input.message // "" | head(4000))}
        else empty end)
    else empty end
' <<<"$input") || exit 0
[[ -n $line ]] || exit 0
[[ $line == '"skip"' ]] && { touch "$dir/.skip-$sid"; exit 0; }

file=$dir/$sid.jsonl
lock=$file.lock
# У async-хука нет таймаута: хук, убитый между mkdir и rmdir, оставил бы блокировку навсегда.
# Её снимает тот, кто увидел мёртвого владельца или прождал одну и ту же блокировку 2 с.
# ponytail: проверка владельца и снятие не атомарны, в окне в микросекунды два писателя могут совпасть.
tries=0
waited=0
seen=
until mkdir "$lock"; do
  owner=$(cat "$lock/pid")
  [[ $owner == "$seen" ]] || { seen=$owner; tries=0; }
  if { [[ -n $owner ]] && ! kill -0 "$owner"; } || ((++tries > 40)); then
    [[ $(cat "$lock/pid") == "$owner" ]] && { rm -f "$lock/pid"; rmdir "$lock"; }
    tries=0
  fi
  ((++waited > 400)) && exit 0
  sleep 0.05
done
echo $$ >"$lock/pid"
trap 'rm -f "$lock/pid"; rmdir "$lock"' EXIT
printf '%s\n' "$line" >>"$file"
exit 0
