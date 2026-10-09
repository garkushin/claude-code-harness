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

# Регулярки jq (Oniguruma) падают на повторении больше 100000: только ограниченные {m,n},
# а вставки режутся split по строкам-границам, без регулярки по содержимому.
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
  def digits3: if (gsub("[^0-9]"; "") | length) >= 3 then "[секрет]" else . end;
  def mask:
    gsub("(?<k>[A-Za-z0-9_.-]{0,64}(token|secret|password|passwd|key))(?<s>\\\\?\"?\\s{0,3}[=:]\\s{0,3})(?<q>\\\\?[\"\u0027]?)[^\\s\"\u0027\\\\,;]{1,512}"; "\(.k)\(.s)\(.q)[секрет]"; "i")
    | gsub("(?<b>Bearer\\s{1,3})[A-Za-z0-9._~+/=-]{8,8192}"; "\(.b)[секрет]"; "i")
    | gsub("(?<t>[A-Za-z0-9+=]{40,8192})"; .t | digits3)
    | gsub("(?<t>[0-9a-fA-F]{32,8192})"; .t | digits3);
  def head($n): if length > $n then .[:$n] + "[обрезано: \(length - $n)]" else . end;
  def tail($n): if length > $n then "[обрезано: \(length - $n)]" + .[-$n:] else . end;

  {ts: (now | todate), session_id, prompt_id, agent_id, agent_type, project: $project, cwd, event: .hook_event_name} as $c
  | if .hook_event_name == "UserPromptExpansion" then
      if .command_name == "retro" then "skip" else empty end
    elif .hook_event_name == "UserPromptSubmit" then
      (.prompt // "") as $p
      | if $p | test("^/retro(\\s|$)") then "skip"
        else $c + {
          prompt: ($p | unpaste | mask | head(4000)),
          origin: (if $p | startswith("<task-notification>") or startswith("Another Claude session sent a message:") then "harness" else "user" end)
        } end
    elif .hook_event_name == "Stop" then
      $c + {last_assistant_message: (.last_assistant_message // "" | mask | tail(2000))}
    elif .hook_event_name == "SubagentStop" then
      if (.agent_type // "") == "" then empty
      else $c + {last_assistant_message: (.last_assistant_message // "" | mask | head(2000))} end
    elif .hook_event_name == "PermissionDenied" then
      $c + {tool_name, tool_input: (.tool_input | tojson | mask | head(1000)), reason}
    elif .hook_event_name == "PostToolUse" then
      $c + {tool_name} + (
        if .tool_name == "Agent" then
          {subagent_type: .tool_input.subagent_type, description: .tool_input.description,
           prompt: (.tool_input.prompt // "" | mask | head(4000)), spawned_agent_id: .tool_response.agentId}
        elif .tool_name == "SendMessage" then
          {tool_input: (.tool_input | tojson | mask | head(4000))}
        elif .tool_name == "AskUserQuestion" then
          {questions: (.tool_input.questions | walk(if type == "string" then mask else . end)),
           tool_response: (.tool_response | if type == "string" then . else tojson end | mask | head(2000))}
        elif .tool_name == "SubagentHandback" then
          {message: (.tool_input.message // "" | mask | head(4000))}
        else empty end)
    else empty end
' <<<"$input") || exit 0
[[ -n $line ]] || exit 0
[[ $line == '"skip"' ]] && { touch "$dir/.skip-$sid"; exit 0; }

file=$dir/$sid.jsonl
lock=$file.lock
# У async-хука нет таймаута: хук, убитый между mkdir и rmdir, оставит блокировку навсегда,
# поэтому ждём ограниченно и считаем блокировку брошенной.
tries=0
until mkdir "$lock"; do
  if ((++tries == 40)); then
    rmdir "$lock"
    mkdir "$lock" || exit 0
    break
  fi
  sleep 0.05
done
trap 'rmdir "$lock"' EXIT
printf '%s\n' "$line" >>"$file"
exit 0
