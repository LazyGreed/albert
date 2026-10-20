#!/usr/bin/env bash
# Albert installer TUI. No external TUI programs required.
# Sourced by install.sh; opens /dev/tty so preview/install output may be redirected.

albert_tui() {
  if [[ ! -r /dev/tty || ! -w /dev/tty ]]; then
    printf 'Interactive installation needs a terminal. Use --no-tui with --harness/--scope flags.\n' >&2
    return 2
  fi
  exec 3<>/dev/tty || return 2

  local ti_pi=0 ti_claude=0 ti_scope="$scope" ti_target="${target:-$PWD}" ti_jev="$with_jev"
  case ",$harness," in
    ,pi,) ti_pi=1 ;;
    ,claude,) ti_claude=1 ;;
    ,pi,claude,|,claude,pi,) ti_pi=1; ti_claude=1 ;;
  esac
  local ti_focus=0 ti_message='' ti_preview='' ti_preview_file='' ti_key='' ti_next=''
  local ti_blue='' ti_bold='' ti_dim='' ti_reset='' ti_reverse=''
  if [[ -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
    ti_blue=$'\033[36m'; ti_bold=$'\033[1m'; ti_dim=$'\033[2m'; ti_reset=$'\033[0m'; ti_reverse=$'\033[7m'
  fi

  _albert_tui_cleanup() {
    trap - INT TERM RETURN
    printf '\033[?25h%s\n' "$ti_reset" >&3 2>/dev/null || true
    if [[ -n "$ti_preview_file" ]]; then rm -f -- "$ti_preview_file"; ti_preview_file=''; fi
    exec 3>&- 2>/dev/null || true
  }
  trap '_albert_tui_cleanup; trap - RETURN' RETURN
  trap '_albert_tui_cleanup; exit 130' INT
  trap '_albert_tui_cleanup; exit 143' TERM
  # No stty changes; Bash read -s handles each key and preserves terminal settings.
  _albert_tui_line() {
    local idx="$1" txt="$2" mark='  '
    [[ "$ti_focus" -eq "$idx" ]] && mark='> '
    if [[ "$ti_focus" -eq "$idx" ]]; then
      printf ' %s%s%s%s\n' "$ti_reverse" "$mark" "$txt" "$ti_reset" >&3
    else
      printf ' %s%s\n' "$mark" "$txt" >&3
    fi
  }
  _albert_tui_draw() {
    printf '\033[?25l\033[H\033[J' >&3
    printf '%sALBERT  /  INSTALL%s\n' "$ti_bold$ti_blue" "$ti_reset" >&3
    printf '%sNative Pi + Claude Code agents. No extra TUI dependencies.%s\n\n' "$ti_dim" "$ti_reset" >&3
    printf '%sHARNESS%s  (select one or both)\n' "$ti_bold" "$ti_reset" >&3
    _albert_tui_line 0 "[$([[ $ti_pi -eq 1 ]] && echo x || echo ' ')] Pi"
    _albert_tui_line 1 "[$([[ $ti_claude -eq 1 ]] && echo x || echo ' ')] Claude Code"
    printf '\n%sSCOPE%s\n' "$ti_bold" "$ti_reset" >&3
    _albert_tui_line 2 "($([[ "$ti_scope" == global ]] && echo '*' || echo ' ')) Global    (~/.pi/agent, ~/.claude)"
    _albert_tui_line 3 "($([[ "$ti_scope" == project ]] && echo '*' || echo ' ')) Project   (repo-local .pi, .claude)"
    if [[ "$ti_scope" == project ]]; then
      _albert_tui_line 4 "Project directory: $ti_target"
    else
      printf '%s   Project directory: (choose Project to edit)%s\n' "$ti_dim" "$ti_reset" >&3
    fi
    printf '\n%sOPTIONAL%s\n' "$ti_bold" "$ti_reset" >&3
    _albert_tui_line 5 "[$([[ $ti_jev -eq 1 ]] && echo x || echo ' ')] Jev semantic tools (requires npm and endpoint configuration)"
    printf '\n' >&3
    _albert_tui_line 6 'Review installation →'
    _albert_tui_line 7 'Cancel'
    printf '\n%s↑/↓ or j/k navigate  ·  Space/Enter select  ·  Esc quit%s\n' "$ti_dim" "$ti_reset" >&3
    [[ -z "$ti_message" ]] || printf '\n%s%s%s\n' "$ti_blue" "$ti_message" "$ti_reset" >&3
  }
  _albert_tui_readkey() {
    ti_key=''
    IFS= read -rsn1 ti_key <&3 || return 1
    if [[ "$ti_key" == $'\e' ]]; then
      ti_next=''
      if IFS= read -rsn1 -t 0.12 ti_next <&3; then
        if [[ "$ti_next" == '[' || "$ti_next" == 'O' ]]; then
          IFS= read -rsn1 -t 0.12 ti_next <&3 || true
          case "$ti_next" in A) ti_key=up ;; B) ti_key=down ;; C) ti_key=right ;; D) ti_key=left ;; *) ti_key=other ;; esac
        else
          ti_key=other
        fi
      else
        ti_key=escape
      fi
    elif [[ -z "$ti_key" ]]; then
      ti_key=enter
    fi
  }
  _albert_tui_harness() {
    if ((ti_pi && ti_claude)); then printf 'pi,claude';
    elif ((ti_pi)); then printf 'pi';
    else printf 'claude'; fi
  }
  _albert_tui_args() {
    ti_args=(--harness "$(_albert_tui_harness)" --scope "$ti_scope")
    [[ "$ti_scope" != project ]] || ti_args+=(--target "$ti_target")
    ((ti_jev == 0)) || ti_args+=(--with-jev)
  }
  _albert_tui_review() {
    if (( !ti_pi && !ti_claude )); then
      ti_message='Select at least one harness.'; return 1
    fi
    if [[ "$ti_scope" == project && ! -d "$ti_target" ]]; then
      ti_message='Project directory does not exist.'; return 1
    fi
    _albert_tui_args
    ti_preview_file="$(mktemp)"
    if ! "$source_dir/install.sh" "${ti_args[@]}" --dry-run > "$ti_preview_file" 2>&1; then
      ti_message="Preview failed: $(tail -n 1 "$ti_preview_file")"
      rm -f -- "$ti_preview_file"; ti_preview_file=''; return 1
    fi
    local n preview_focus=0 result=0
    n="$(grep -c '^WRITE ' "$ti_preview_file" || true)"
    while :; do
      printf '\033[?25l\033[H\033[J' >&3
      printf '%sALBERT  /  REVIEW%s\n\n' "$ti_bold$ti_blue" "$ti_reset" >&3
      printf ' Harness   %s\n Scope     %s\n' "$(_albert_tui_harness)" "$ti_scope" >&3
      [[ "$ti_scope" != project ]] || printf ' Target    %s\n' "$ti_target" >&3
      printf ' Jev       %s\n Planned   %s file writes\n' "$([[ $ti_jev -eq 1 ]] && echo enabled || echo disabled)" "$n" >&3
      printf '\n%sPreview (first 10 file operations)%s\n' "$ti_bold" "$ti_reset" >&3
      grep '^WRITE ' "$ti_preview_file" | head -n 10 >&3 || true
      if ((n > 10)); then printf '  ... and %s more\n' "$((n-10))" >&3; fi
      printf '\nExisting changed files are backed up. Model settings remain unchanged.\n\n' >&3
      if ((preview_focus == 0)); then printf ' %s> Install%s     Back     Cancel\n' "$ti_reverse" "$ti_reset" >&3
      elif ((preview_focus == 1)); then printf '   Install    %s> Back%s     Cancel\n' "$ti_reverse" "$ti_reset" >&3
      else printf '   Install     Back    %s> Cancel%s\n' "$ti_reverse" "$ti_reset" >&3; fi
      printf '\n%s←/→ or h/l select  ·  Enter confirm  ·  Esc back%s\n' "$ti_dim" "$ti_reset" >&3
      _albert_tui_readkey || { result=2; break; }
      case "$ti_key" in
        up|left|k|h) preview_focus=$(((preview_focus+2)%3)) ;;
        down|right|j|l) preview_focus=$(((preview_focus+1)%3)) ;;
        escape) result=1; break ;;
        enter|' ')
          case "$preview_focus" in 0) result=0 ;; 1) result=1 ;; *) result=2 ;; esac
          break ;;
      esac
    done
    rm -f -- "$ti_preview_file"; ti_preview_file=''
    return "$result"
  }
  while :; do
    _albert_tui_draw
    _albert_tui_readkey || return 2
    ti_message=''
    case "$ti_key" in
      up|k) ti_focus=$(((ti_focus+7)%8)) ;;
      down|j) ti_focus=$(((ti_focus+1)%8)) ;;
      escape) return 0 ;;
      enter|' ')
        case "$ti_focus" in
          0) ti_pi=$((1-ti_pi)) ;;
          1) ti_claude=$((1-ti_claude)) ;;
          2) ti_scope=global ;;
          3) ti_scope=project ;;
          4)
            if [[ "$ti_scope" == project ]]; then
              printf '\033[?25h\nProject directory [%s]: ' "$ti_target" >&3
              local new_target=''
              IFS= read -r new_target <&3 || return 2
              if [[ "$new_target" == '~' ]]; then new_target="$HOME";
              elif [[ "$new_target" == '~/'* ]]; then new_target="$HOME/${new_target:2}"; fi
              [[ -z "$new_target" ]] || ti_target="$new_target"
            fi ;;
          5) ti_jev=$((1-ti_jev)) ;;
          6)
            local review_status=0
            _albert_tui_review || review_status=$?
            if ((review_status == 0)); then
              _albert_tui_args
              printf '\033[?25h\033[H\033[J%sALBERT  /  INSTALLING%s\n\n' "$ti_bold$ti_blue" "$ti_reset" >&3
              "$source_dir/install.sh" "${ti_args[@]}"; return $?
            elif ((review_status == 2)); then return 0; fi ;;
          7) return 0 ;;
        esac ;;
    esac
  done
}
