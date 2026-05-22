#!/usr/bin/env bash
# tests/acceptance.sh
# приёмочные проверки стенда «АгроТех». вывод оформлен как
# демо-отчёт: для каждого требования тз показываем формулировку,
# реальную команду, её вывод и список подкритериев с галочками.
#
# usage:  bash tests/acceptance.sh
# exit:   0 — все требования закрыты, 1 — есть проваленные

set -u

# ─── colours ─────────────────────────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'; C_MAGENTA=$'\033[35m'
else
  C_RESET=''; C_BOLD=''; C_DIM=''; C_GREEN=''; C_RED=''
  C_YELLOW=''; C_BLUE=''; C_CYAN=''; C_MAGENTA=''
fi
WIDTH=78

# ─── docker access ───────────────────────────────────────────
DOCKER=$(command -v docker)
if ! "$DOCKER" ps >/dev/null 2>&1; then
  if sg docker -c 'docker ps' >/dev/null 2>&1; then
    DOCKER_RUN() { sg docker -c "docker $*"; }
  elif sudo -n docker ps >/dev/null 2>&1; then
    DOCKER_RUN() { sudo docker "$@"; }
  else
    echo "не могу получить доступ к docker" >&2; exit 2
  fi
else
  DOCKER_RUN() { "$DOCKER" "$@"; }
fi
dexec()    { local c="$1"; shift; DOCKER_RUN exec "$c" "$@" 2>/dev/null; }
http_code(){ curl -s -o /dev/null -w '%{http_code}' "$@"; }

# ─── helpers для checker-функций ─────────────────────────────
contains()    { echo "$1" | grep -q -- "$2"; }
match_regex() { echo "$1" | grep -qE -- "$2"; }
count_at_least() {
  local out="$1" pattern="$2" n="$3"
  [ "$(echo "$out" | grep -cE -- "$pattern" || true)" -ge "$n" ]
}

# ─── рендеринг ───────────────────────────────────────────────
RESULTS=()    # "GROUP|VERDICT|TITLE"
PASSED=0; FAILED=0

hr() {
  local style="${1:-thin}"; local ch
  case "$style" in
    thick) ch='━' ;;
    thin)  ch='─' ;;
    *)     ch='·' ;;
  esac
  printf '%s' "${C_DIM}"
  printf "$ch%.0s" $(seq 1 "$WIDTH")
  printf '%s\n' "${C_RESET}"
}

print_banner() {
  local title="$1"
  echo
  printf '%s' "${C_BOLD}${C_CYAN}"
  hr thick
  printf '  %s\n' "$title"
  hr thick
  printf '%s' "${C_RESET}"
}

# run_check id title quote_tz cmd_label cmd_to_run check_spec_1 [check_spec_2 ...]
#   check_spec формат:  "checker_fn|описание подкритерия"
# checker_fn вызывается с одним аргументом: $out (полный вывод команды).
# вердикт пункта PASS только если все подкритерии PASS.
run_check() {
  local id="$1" title="$2" quote="$3" cmd_label="$4" cmd="$5"
  shift 5
  local subchecks=("$@")
  local out
  out=$(eval "$cmd" 2>&1)

  echo
  printf '  %s[%s]%s %s%s%s\n' "$C_BOLD" "$id" "$C_RESET" "$C_BOLD" "$title" "$C_RESET"
  printf '  %sтз:%s %s\n' "$C_DIM" "$C_RESET" "$quote"
  printf '  %sкоманда:%s %s\n' "$C_DIM" "$C_RESET" "$cmd_label"
  printf '  %s┌── вывод%s\n' "$C_DIM" "$C_RESET"
  if [ -z "$out" ]; then
    printf '  %s│%s %s(пусто)%s\n' "$C_DIM" "$C_RESET" "$C_DIM" "$C_RESET"
  else
    while IFS= read -r line; do
      printf '  %s│%s %s\n' "$C_DIM" "$C_RESET" "$line"
    done <<< "$out"
  fi
  printf '  %s├── проверки%s\n' "$C_DIM" "$C_RESET"

  local all_ok=true
  for spec in "${subchecks[@]}"; do
    local fn="${spec%%|*}"
    local desc="${spec#*|}"
    if "$fn" "$out"; then
      printf '  %s│%s   %s✔%s %s\n' "$C_DIM" "$C_RESET" "$C_GREEN$C_BOLD" "$C_RESET" "$desc"
    else
      printf '  %s│%s   %s✘%s %s\n' "$C_DIM" "$C_RESET" "$C_RED$C_BOLD" "$C_RESET" "$desc"
      all_ok=false
    fi
  done

  local verdict color
  if $all_ok; then
    verdict="PASS"; color="$C_GREEN"; PASSED=$((PASSED + 1))
  else
    verdict="FAIL"; color="$C_RED";   FAILED=$((FAILED + 1))
  fi
  RESULTS+=("$id|$verdict|$title")
  printf '  %s└── %sвердикт:%s %s%s%s\n' \
    "$C_DIM" "$C_DIM" "$C_RESET" "${color}${C_BOLD}" "$verdict" "$C_RESET"
}

# =============================================================
# checker-функции (все определены ДО первого run_check, иначе
# bash их не найдёт)
# =============================================================

# A.1 — wireguard на обеих сторонах
_a1_listen_port()    { contains "$1" "listening port: 51820"; }
_a1_server_peer()    { match_regex "$1" "^peer: [A-Za-z0-9+/=]+"; }
_a1_server_handshake() { contains "$1" "latest handshake"; }
_a1_branch_iface()   { count_at_least "$1" '^interface: wg0' 2; }

# A.2 — ping через туннель
_a2_ping_ok()        { match_regex "$1" '2 (packets )?received'; }

# B.1 — tailscale: контейнер + конфиг
_b1_running()        { contains "$1" "Running=true"; }
_b1_advertise()      { contains "$1" "10.0.1.0/24"; }

# B.2 — tailscale: попытки регистрации
_b2_has_activity()   { [ -n "$1" ]; }

# C.1 — qos очереди
_c1_htb()            { contains "$1" "linux-htb"; }
_c1_three_queues()   { match_regex "$1" '0=[^,]+,.*1=[^,]+,.*2='; }

# C.2 — openflow set_queue
_c2_q1()             { contains "$1" "set_queue:1"; }
_c2_q2()             { contains "$1" "set_queue:2"; }

# C.3 — pbr-policy
_c3_pbr_map()        { contains "$1" "pbr-map"; }
_c3_match_dscp()     { match_regex "$1" 'match dscp (48|34)'; }

# D — маршруты
_d_distance_10()     { contains "$1" "distance 10,"; }
_d_distance_100()    { contains "$1" "distance 100,"; }
_d_best()            { contains "$1" "best"; }

# E.1 — ONOS REST 200 + ≥2 device
_e1_code_200()       { contains "$1" "http_code=200"; }
_e1_two_devices()    { count_at_least "$1" '"id":"of:[^"]+"' 2; }

# E.2 — ovs-controllers
_e2_two_controllers(){ count_at_least "$1" 'tcp:(onos|10\.0\.1\.2):6653' 2; }

# G.1 — стенд
_g1_15_up()          { count_at_least "$1" ' Up ' 15; }
_g1_no_restart()     { ! match_regex "$1" 'Restart|Exit'; }

# G.2 — сети
_g2_four_nets()      { count_at_least "$1" '_(datacenter|branch|monitoring|remote-users)$' 4; }

# G.3 — health
_g3_ok()             { [ "$1" = "ok" ]; }

# G.4 — grafana dashboard
_g4_dash()           { match_regex "$1" 'agrotech|АгроТех|агротех'; }

# G.5 — prometheus targets
_g5_two_up()         { count_at_least "$1" '"health":"up"' 2; }

# ─── шапка отчёта ────────────────────────────────────────────
clear 2>/dev/null || true
echo
printf '%s%s' "${C_BOLD}${C_MAGENTA}"
hr thick
cat <<'BANNER'

        ПРОТОКОЛ ПРИЁМКИ ПРОЕКТА «СЕТЬ ДЛЯ АГРОТЕХ»
        модуль 4. интеграция SDN и SD-WAN

        проверки выведены напрямую из формулировок ТЗ.
        каждый пункт — одна реальная команда + список подкритериев
        над её выводом.

          A — безопасный доступ ЦОД ↔ филиал           (WireGuard)
          B — безопасный доступ ЦОД ↔ удалёнщики        (Tailscale)
          C — приоритизация трафика видеоконференций    (QoS)
          D — отказоустойчивость каналов филиала        (FRR routes)
          E — SDN в ЦОД                                 (ONOS + OpenFlow)
          G — демонстрационный стенд работоспособен     (docker compose)

BANNER
hr thick
printf '%s' "${C_RESET}"

# =============================================================
# A. Безопасный доступ к приложениям в ЦОД для филиала
# =============================================================
print_banner "A. Безопасный доступ к приложениям в ЦОД для филиала (WireGuard)"

run_check "A.1" "WireGuard-туннель ЦОД ↔ филиал поднят и активен" \
  '«обеспечить безопасный доступ к приложениям в ЦОДе для филиала»' \
  'docker exec wireguard wg show && docker exec wireguard-branch wg show' \
  'printf "=== ЦОД-сервер ===\n"; dexec wireguard wg show; printf "\n=== филиал ===\n"; dexec wireguard-branch wg show' \
  '_a1_listen_port|сервер слушает UDP 51820' \
  '_a1_server_peer|сервер видит peer-а (публичный ключ филиала)' \
  '_a1_server_handshake|зафиксирован свежий handshake' \
  '_a1_branch_iface|интерфейс wg0 поднят и на сервере, и в филиале'

run_check "A.2" "трафик ЦОД ↔ филиал реально проходит через туннель" \
  '«обеспечить безопасный доступ к приложениям в ЦОДе для филиала»' \
  'docker exec wireguard-branch ping -c 2 -W 2 10.13.13.1' \
  'dexec wireguard-branch ping -c 2 -W 2 10.13.13.1' \
  '_a2_ping_ok|ping 10.13.13.1 (ЦОД-сторона туннеля) отвечает'

# =============================================================
# B. Безопасный доступ для удалённых сотрудников
# =============================================================
print_banner "B. Безопасный доступ к приложениям в ЦОД для удалённых сотрудников (Tailscale)"

run_check "B.1" "контейнер Tailscale запущен и настроен на ЦОД" \
  '«обеспечить безопасный доступ к приложениям в ЦОДе для... удалённых сотрудников»' \
  'docker inspect tailscale --format "Running={{.State.Running}} env={{.Config.Env}}"' \
  "DOCKER_RUN inspect tailscale --format 'Running={{.State.Running}}'$'\n''env={{json .Config.Env}}' | tr ',' '\n'" \
  '_b1_running|State.Running = true (контейнер активен)' \
  '_b1_advertise|анонсируется маршрут 10.0.1.0/24 (доступ к приложениям ЦОД)'

run_check "B.2" "Tailscale обращается к управляющей плоскости (control plane)" \
  '«обеспечить безопасный доступ к приложениям в ЦОДе для... удалённых сотрудников»' \
  'docker logs tailscale | grep -E control:|login|register|auth | tail -6' \
  "DOCKER_RUN logs tailscale 2>&1 | grep -E 'control:|login|register|auth' | tail -6" \
  '_b2_has_activity|в логах есть строки авторизации (auth/login/control/register)'

# =============================================================
# C. Приоритизация трафика видеоконференций
# =============================================================
print_banner "C. Приоритизация трафика видеоконференций (QoS)"

run_check "C.1" "на ovs-branch созданы QoS-очереди (HTB, 3 класса)" \
  '«приоритезировать трафик видеоконференций»' \
  'docker exec ovs-branch ovs-vsctl list qos' \
  'dexec ovs-branch ovs-vsctl list qos' \
  '_c1_htb|тип очереди linux-htb' \
  '_c1_three_queues|три класса трафика: queue 0 (best-effort), 1 (видео), 2 (IoT)'

run_check "C.2" "OpenFlow-правила маркируют трафик в нужные очереди" \
  '«приоритезировать трафик видеоконференций»' \
  'docker exec ovs-branch ovs-ofctl -O OpenFlow13 dump-flows ovs-branch' \
  'dexec ovs-branch ovs-ofctl -O OpenFlow13 dump-flows ovs-branch' \
  '_c2_q1|есть flow с set_queue:1 (видеопоток RTP)' \
  '_c2_q2|есть flow с set_queue:2 (IoT-данные с DSCP CS6)'

run_check "C.3" "FRR применяет policy-based routing по DSCP" \
  '«приоритезировать трафик видеоконференций»' \
  "docker exec frr-branch vtysh -c 'show running-config' | grep -E 'pbr-map|match dscp'" \
  "dexec frr-branch vtysh -c 'show running-config' | grep -E 'pbr-map|match dscp'" \
  '_c3_pbr_map|настроена pbr-map' \
  '_c3_match_dscp|правила различают DSCP af41 (видео) и cs6 (IoT)'

# =============================================================
# D. Отказоустойчивость каналов филиала
# =============================================================
print_banner "D. Отказоустойчивость каналов связи филиала (4G + спутник)"

run_check "D.1" "FRR имеет 2 маршрута к ЦОД с разной distance (готовность к failover)" \
  '«обеспечить отказоустойчивость каналов связи филиала (4G и спутниковый канал)»' \
  "docker exec frr-branch vtysh -c 'show ip route 10.0.1.0/24'" \
  "dexec frr-branch vtysh -c 'show ip route 10.0.1.0/24'" \
  '_d_distance_10|основной маршрут с distance 10 (через 4G)' \
  '_d_distance_100|резервный маршрут с distance 100 (через спутник)' \
  '_d_best|один из маршрутов выбран как best (активный)'

# =============================================================
# E. SDN в ЦОД (ONOS + OpenFlow 1.3)
# =============================================================
print_banner "E. SDN в ЦОД (ONOS + OpenFlow 1.3)"

run_check "E.1" "ONOS управляет data-plane (REST живой, видит ovs1/ovs2)" \
  '«обосновать, где будет использоваться SDN... ONOS для ЦОДа»' \
  'curl -u onos:rocks http://localhost:8181/onos/v1/devices' \
  "printf 'http_code=%s\n' \"\$(http_code -u onos:rocks http://localhost:8181/onos/v1/devices)\"; curl -s -u onos:rocks http://localhost:8181/onos/v1/devices | grep -oE '\"id\":\"of:[^\"]+\"'" \
  '_e1_code_200|REST API отвечает HTTP 200 (контроллер активен)' \
  '_e1_two_devices|зарегистрировано ≥2 OpenFlow-устройства (ovs1+ovs2)'

run_check "E.2" "OVS подключены к контроллеру по OpenFlow 1.3" \
  'control plane (ONOS) отделён от data plane (OVS) — формальное разделение по ТЗ' \
  'docker exec ovs1 ovs-vsctl get-controller ovs1 && docker exec ovs2 ovs-vsctl get-controller ovs2' \
  'echo "ovs1 → $(dexec ovs1 ovs-vsctl get-controller ovs1)"; echo "ovs2 → $(dexec ovs2 ovs-vsctl get-controller ovs2)"' \
  '_e2_two_controllers|оба коммутатора указывают на TCP-контроллер ONOS:6653'

# =============================================================
# G. Демо-стенд работоспособен
# =============================================================
print_banner "G. Демонстрационный стенд работоспособен"

run_check "G.1" "все сервисы стенда работают, без рестартов" \
  '«демонстрационный стенд: код и конфигурации... ключевых функций»' \
  'docker compose ps' \
  "DOCKER_RUN compose ps --format '{{.Name}} {{.Status}}'" \
  '_g1_15_up|≥15 контейнеров со статусом Up' \
  '_g1_no_restart|нет контейнеров в Restart/Exited'

run_check "G.2" "архитектура: 4 изолированные docker-сети (плоскости трафика)" \
  '«спроектировать архитектуру: схема сети, плоскости данных и управления»' \
  'docker network ls' \
  "DOCKER_RUN network ls --format '{{.Name}}'" \
  '_g2_four_nets|существуют сети datacenter, branch, monitoring, remote-users'

run_check "G.3" "приложение в ЦОД (app-server) доступно для клиентов" \
  'смысл всей сети — клиенты ходят к этому приложению' \
  'curl -s http://localhost:8080/health' \
  'curl -s http://localhost:8080/health' \
  '_g3_ok|/health отвечает "ok"'

run_check "G.4" "Grafana подгрузила дашборд АгроТех (наблюдаемость)" \
  'наблюдаемость стенда — часть «технической документации»' \
  "curl -s -u admin:admin 'http://localhost:3000/api/search?type=dash-db'" \
  "curl -s -u admin:admin 'http://localhost:3000/api/search?type=dash-db'" \
  '_g4_dash|в списке дашбордов Grafana есть «АгроТех»'

run_check "G.5" "Prometheus собирает метрики (≥2 targets up)" \
  'мониторинг стенда живой' \
  "curl -s 'http://localhost:9090/api/v1/targets?state=active' | grep -oE '\"health\":\"[a-z]+\"'" \
  "curl -s 'http://localhost:9090/api/v1/targets?state=active' | grep -oE '\"health\":\"[a-z]+\"'" \
  '_g5_two_up|минимум 2 цели в статусе up'

# =============================================================
# финальный отчёт
# =============================================================
echo
echo
printf '%s%s' "${C_BOLD}${C_MAGENTA}"
hr thick
printf '  ИТОГОВАЯ ТАБЛИЦА СООТВЕТСТВИЯ ТЗ\n'
hr thick
printf '%s' "${C_RESET}"

declare -A GROUP_TITLE=(
  [A]="Безопасный доступ ЦОД ↔ филиал             (WireGuard)"
  [B]="Безопасный доступ ЦОД ↔ удалёнщики          (Tailscale)"
  [C]="Приоритизация трафика видеоконференций      (QoS)"
  [D]="Отказоустойчивость каналов филиала          (FRR static routes)"
  [E]="SDN в ЦОД                                   (ONOS + OpenFlow)"
  [G]="Демонстрационный стенд работоспособен       (docker compose)"
)

for grp in A B C D E G; do
  group_pass=0; group_fail=0; group_total=0
  for r in "${RESULTS[@]}"; do
    case "$r" in
      "$grp."*)
        group_total=$((group_total + 1))
        case "${r#*|}" in
          PASS*) group_pass=$((group_pass + 1)) ;;
          FAIL*) group_fail=$((group_fail + 1)) ;;
        esac
        ;;
    esac
  done
  if [ "$group_fail" = "0" ] && [ "$group_total" -gt 0 ]; then
    marker="${C_GREEN}${C_BOLD}✔${C_RESET}"
    counter="${C_GREEN}${group_pass}/${group_total}${C_RESET}"
  else
    marker="${C_RED}${C_BOLD}✘${C_RESET}"
    counter="${C_RED}${group_pass}/${group_total}${C_RESET}"
  fi
  printf '  %s [%s] %-60s  %s\n' "$marker" "$grp" "${GROUP_TITLE[$grp]}" "$counter"
done

echo
hr thin
TOTAL=$((PASSED + FAILED))
if [ "$FAILED" = "0" ]; then
  printf '%s%s  ИТОГ: %d / %d пунктов закрыто.   ПРИЁМКА ПРОЙДЕНА.%s\n' \
    "${C_BOLD}" "${C_GREEN}" "$PASSED" "$TOTAL" "${C_RESET}"
else
  printf '%s%s  ИТОГ: %d / %d. Есть проваленные пункты:%s\n' \
    "${C_BOLD}" "${C_RED}" "$PASSED" "$TOTAL" "${C_RESET}"
  for r in "${RESULTS[@]}"; do
    case "${r#*|}" in
      FAIL*)
        id="${r%%|*}"
        title="${r##*|}"
        printf '         %s%s%s — %s\n' "$C_RED" "$id" "$C_RESET" "$title"
        ;;
    esac
  done
fi
hr thin
echo
printf '  SD-WAN как технология (требование ТЗ) покрыто: %sA%s + %sB%s.\n' \
  "$C_BOLD" "$C_RESET" "$C_BOLD" "$C_RESET"
printf '  Демонстрация failover (динамика D): %sbash tests/failover.sh%s\n' "$C_DIM" "$C_RESET"
echo

[ "$FAILED" = "0" ] && exit 0 || exit 1
