#!/usr/bin/env bash
# Обновляет файлы списков из upstream-источников (sources.txt).
# Запускается локально или из GitHub Action (.github/workflows/update.yml).
set -euo pipefail
export LC_ALL=C

[[ ${BASH_VERSINFO[0]:-0} -ge 4 ]] || { echo "bash 4+ required" >&2; exit 1; }

BASE_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_FILE="$BASE_DIR/sources.txt"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
mkdir -p "$WORK_DIR/raw" "$WORK_DIR/lists"

download() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --max-time 60 "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -T 60 -O "$2" "$1"
  else
    return 1
  fi
}

merge_lists() {
  # $1 — сервис; остальные аргументы — исходные файлы (Clash/v2fly).
  # Результат: матчеры Xray в "$WORK_DIR/lists/$1.txt", CIDR в "$WORK_DIR/lists/cidrs-$1.txt".
  local service="$1"
  shift
  local out="$WORK_DIR/lists/$service.txt"
  local cidrs="$WORK_DIR/lists/cidrs-$service.txt"
  : > "$out"
  : > "$cidrs"
  local f line cidr
  for f in "$@"; do
    [[ -f "$f" ]] || continue
    while IFS= read -r line; do
      line="${line%%#*}"
      line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      [[ -z "$line" ]] && continue
      line="${line%% *}" # v2fly: обрезаем атрибуты "@ads @telemetry" и комментарии
      case "$line" in
        DOMAIN-SUFFIX,*)  printf 'domain:%s\n' "${line#*,}" ;;
        DOMAIN,*)         printf 'full:%s\n' "${line#*,}" ;;
        DOMAIN-KEYWORD,*) printf '%s\n' "${line#*,}" ;;
        IP-CIDR,*)        cidr="${line#IP-CIDR,}"; cidr="${cidr%%,*}"; [[ "$cidr" == */* ]] && printf '%s\n' "$cidr" >> "$cidrs" ;;
        IP-CIDR6,*)       cidr="${line#IP-CIDR6,}"; cidr="${cidr%%,*}"; printf '%s\n' "$cidr" >> "$cidrs" ;;
        IP-ASN,*|PROCESS-NAME,*|USER-AGENT,*|include:*) continue ;;
        full:*|regexp:*)  printf '%s\n' "$line" ;;
        keyword:*)        printf '%s\n' "${line#keyword:}" ;;
        *)                printf 'domain:%s\n' "$line" ;;
      esac
    done < "$f" >> "$out"
  done

  if [[ "$service" == gemini ]]; then
    # Эти домены должны оставаться в прокси-списке при изменении upstream.
    printf '%s\n' 'domain:aicode.googleapis.com' 'full:cloudcode-pa.googleapis.com' >> "$out"
  fi

  awk '
    FILENAME == ARGV[1] {
      direct[$0] = direct["domain:" $0] = direct["full:" $0] = 1
      next
    }
    !($0 in direct)
  ' "$BASE_DIR/gemini-direct-domains.txt" "$out" | sort -u > "$out.tmp"
  mv "$out.tmp" "$out"

  # full:X избыточен, если уже покрыт domain:X
  while IFS= read -r line; do
    [[ "$line" == full:* ]] || continue
    if grep -qx "domain:${line#full:}" "$out"; then
      grep -vx "full:${line#full:}" "$out" > "$out.tmp" && mv "$out.tmp" "$out"
    fi
  done < "$out"
}

json_escape() {
  local esc="$1"
  esc="${esc//\\/\\\\}"
  esc="${esc//\"/\\\"}"
  printf '%s' "$esc"
}

append_quoted() {
  local -n arr="$1"
  local esc
  esc="$(json_escape "$2")"
  if [[ -z "$arr" ]]; then
    arr="\"$esc\""
  else
    arr="$arr,\"$esc\""
  fi
}

write_singbox() {
  local dom="" suf="" kw="" re="" ip4="" line
  while IFS= read -r line; do
    case "$line" in
      full:*)   append_quoted dom "${line#full:}" ;;
      domain:*) append_quoted suf "${line#domain:}" ;;
      regexp:*) append_quoted re "${line#regexp:}" ;;
      *)        append_quoted kw "$line" ;;
    esac
  done < <(cat "$BASE_DIR/openai.txt" "$BASE_DIR/anthropic.txt" "$BASE_DIR/gemini.txt" | sort -u)
  while IFS= read -r line; do
    [[ -n "$line" ]] && append_quoted ip4 "$line"
  done < "$BASE_DIR/ai-cidrs.txt"
  {
    printf '{\n  "version": 3,\n  "rules": [\n    {\n'
    printf '      "domain": [%s],\n' "$dom"
    printf '      "domain_suffix": [%s],\n' "$suf"
    printf '      "domain_keyword": [%s],\n' "$kw"
    printf '      "domain_regex": [%s],\n' "$re"
    printf '      "ip_cidr": [%s]\n' "$ip4"
    printf '    }\n  ]\n}\n'
  } > "$BASE_DIR/singbox-ai.json"
}

for service in openai anthropic gemini; do
  idx=0
  ok=0
  while IFS='|' read -r svc url; do
    [[ "$svc" == "$service" ]] || continue
    idx=$((idx + 1))
    raw_file="$WORK_DIR/raw/${service}-${idx}.txt"
    if download "$url" "$raw_file" && [[ -s "$raw_file" ]]; then
      ok=1
    else
      rm -f "$raw_file"
      echo "Warning: could not download $url" >&2
    fi
  done < "$SOURCES_FILE"
  if (( ok )); then
    merge_lists "$service" "$WORK_DIR/raw/${service}-"*.txt
  else
    echo "Error: no fresh lists for $service" >&2
    exit 1
  fi
done

cat "$WORK_DIR"/lists/cidrs-*.txt 2>/dev/null | sort -u > "$WORK_DIR/lists/ai-cidrs.txt"

cp "$WORK_DIR/lists/openai.txt" "$BASE_DIR/openai.txt"
cp "$WORK_DIR/lists/anthropic.txt" "$BASE_DIR/anthropic.txt"
cp "$WORK_DIR/lists/gemini.txt" "$BASE_DIR/gemini.txt"
cp "$WORK_DIR/lists/ai-cidrs.txt" "$BASE_DIR/ai-cidrs.txt"
cp "$BASE_DIR/ai-cidrs.txt" "$BASE_DIR/cidrs.txt"

# По-сервисные списки подсетей. У Anthropic и Gemini сервис-специфичных подсетей
# нет (fronts Cloudflare/Google), поэтому файлы содержат только комментарий —
# Podkop такие строки пропускает. Подключать их можно, но смысла нет.
for svc in openai anthropic gemini; do
  if [[ -s "$WORK_DIR/lists/cidrs-$svc.txt" ]]; then
    cp "$WORK_DIR/lists/cidrs-$svc.txt" "$BASE_DIR/$svc-cidrs.txt"
  else
    printf '# No service-specific subnets: %s is fronted by a CDN; route by domains from %s-domains.txt\n' \
      "$svc" "$svc" > "$BASE_DIR/$svc-cidrs.txt"
  fi
done

# Простые списки доменов: общий и по сервисам (для Podkop и любых клиентов)
for svc in openai anthropic gemini; do
  sed -n 's/^domain://p; s/^full://p' "$BASE_DIR/$svc.txt" | sort -u > "$BASE_DIR/$svc-domains.txt"
done
cat "$BASE_DIR/openai-domains.txt" "$BASE_DIR/anthropic-domains.txt" "$BASE_DIR/gemini-domains.txt" \
  | sort -u > "$BASE_DIR/domains.txt"

write_singbox

echo "Lists refreshed: openai.txt ($(wc -l < "$BASE_DIR/openai.txt")), anthropic.txt ($(wc -l < "$BASE_DIR/anthropic.txt")), gemini.txt ($(wc -l < "$BASE_DIR/gemini.txt")), domains.txt ($(wc -l < "$BASE_DIR/domains.txt"))"
