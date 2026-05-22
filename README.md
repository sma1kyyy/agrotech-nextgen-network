# сеть для агротех

комплексное sdn и sd wan решение для агропромышленной компании на базе docker
учебный проект по модулю 4 для кейса компании агротех

## тз
компания агротех имеет
1. центральный офис и цод с высокопроизводительными серверами
2. удаленный филиал на ферме с iot датчиками и камерами видеонаблюдения, где есть два канала связи 4g и спутник
3. пять удаленных сотрудников, которым нужен доступ к приложениям в цод

задачи проекта
1. обеспечить безопасный доступ к приложениям в цод для филиала и удаленных сотрудников
2. приоритезировать трафик видеоконференций и критических iot данных через qos
3. обеспечить отказоустойчивость каналов связи филиала, чтобы при падении 4g включался спутниковый канал

## обзор решения
внутри цод используется sdn под управлением onos
onos управляет ovs коммутаторами через openflow 1.3
это дает централизованное управление политиками трафика и qos

для подключения филиала к цод используется wireguard
он работает в ядре linux и дает низкие задержки для видео и служебного трафика

для удаленных сотрудников используется tailscale
он упрощает подключение через nat и снижает объем ручных настроек

для отказоустойчивости филиала используется frrouting
маршрутизатор отслеживает доступность основного канала и переключает трафик на резервный

для мониторинга используются prometheus и grafana
для симуляции сетевой топологии используется containernet

## архитектура
```text
                         цод data center
          +------------------------------------------------+
          |                                                |
          |   onos controller   control plane              |
          |         |                                      |
          |    openflow 1.3                                |
          |         |                                      |
          |   ovs switch 1  ---  ovs switch 2              |
          |    data plane         data plane               |
          |         |                                      |
          |   сервер приложений   prometheus и grafana     |
          +--------------------+---------------------------+
                               |
                    wireguard tunnel udp 51820
                               |
          +--------------------+---------------------------+
          |        удаленный филиал ферма                 |
          |                                               |
          |   frr router                                   |
          |    /          \                                |
          |  4g        спутник   резервный канал          |
          |    \          /                                |
          |   ovs switch                                   |
          |      |            |                            |
          |   iot датчики   cctv камеры                   |
          +------------------------------------------------+

          удаленные сотрудники tailscale mesh

          ноутбук 1 \
          ноутбук 2  \
          ноутбук 3   tailscale overlay  в цод
          ноутбук 4  /
          ноутбук 5 /
```

## стек технологий
| инструмент | роль | почему выбран |
| onos | sdn контроллер в цод | поддерживает openflow 1.3 и доступен как docker образ |
| open vswitch ovs | программный коммутатор data plane | управляется onos и поддерживает dscp и qos очереди |
| wireguard | sd wan туннель филиала | работает в ядре linux и дает низкие задержки |
| tailscale | sd wan оверлей сотрудников | удобный nat traversal и быстрый запуск |
| frrouting frr | маршрутизация и failover в филиале | поддерживает bfd и статические маршруты |
| containernet | симуляция сети | позволяет запускать mininet внутри docker |
| prometheus и grafana | мониторинг и метрики | стандартная связка для мониторинга |
| docker compose | оркестрация сервисов | единая команда запуска всего стенда |

## что есть в стенде
в цод
onos как sdn контроллер
ovs1 и ovs2 как data plane
app server как тестовое приложение
wireguard сервер как точка безопасного доступа

в филиале
frr branch как маршрутизатор
ovs branch как локальный коммутатор
iot sim и cctv sim как генераторы трафика

наблюдаемость
prometheus
grafana
node exporter

симуляция
containernet с минимальной топологией

## требования к локальной машине
linux с docker
установлены docker и docker compose plugin
доступен модуль ядра openvswitch
свободные порты 3000 8080 8181 9090 6653 51820

## проверки перед запуском
```bash
docker --version
docker compose version
sudo modprobe openvswitch
lsmod | grep openvswitch
```

## быстрый запуск с нуля
шаг 1 клонировать репозиторий
```bash
git clone <url-репозитория>
cd agrotech-nextgen-network
```

шаг 2 проверить итоговый compose конфиг
```bash
docker compose config
```

шаг 3 поднять стенд
```bash
docker compose up -d
```

шаг 4 проверить состояние сервисов
```bash
docker compose ps
```

шаг 5 если ovs сервисы в restarting
```bash
sudo modprobe openvswitch
docker compose restart ovs1 ovs2 ovs-branch
```

## точки входа после запуска
onos ui
http://localhost:8181/onos/ui
логин onos
пароль rocks

grafana
http://localhost:3000
логин admin
пароль admin

app server
http://localhost:8080
health endpoint
http://localhost:8080/health

prometheus
http://localhost:9090/targets

## пошаговая проверка работоспособности
проверка onos api
```bash
curl -u onos:rocks http://localhost:8181/onos/v1/devices
```

проверка ovs в цод
```bash
docker exec ovs1 ovs-vsctl show
docker exec ovs2 ovs-vsctl show
```

проверка маршрутов frr
```bash
docker exec frr-branch vtysh -c "show ip route"
```

проверка wireguard туннеля
```bash
docker exec wireguard wg show
```

проверка приложения
```bash
curl -s http://localhost:8080/health
```

## демонстрация сценариев
сценарий 1 failover 4g на спутник
```bash
docker exec frr-branch vtysh -c "show ip route 10.0.1.0/24"
docker exec frr-branch ip link set eth0 down
docker exec frr-branch vtysh -c "show ip route 10.0.1.0/24"
docker exec frr-branch ip link set eth0 up
```

сценарий 2 qos приоритеты
```bash
docker exec ovs-branch ovs-ofctl -O OpenFlow13 dump-flows ovs-branch
```
в выводе должны быть правила с set_queue 2 и set_queue 1

## приёмка
формальные критерии соответствия стенда тз агротех
проверки выводятся напрямую из формулировок кейса
их закрывает скрипт tests/acceptance.sh который надо прогонять после docker compose up -d

каждый пункт показывает реальную команду, её фактический вывод
и список подкритериев (одна команда закрывает несколько критериев сразу)

A функциональное требование тз "безопасный доступ к приложениям в цод для филиала"
A.1 wireguard-туннель цод ↔ филиал поднят и активен
    одна команда: docker exec wireguard wg show && docker exec wireguard-branch wg show
    подкритерии: сервер слушает 51820, peer установлен, свежий handshake, wg0 поднят с обеих сторон
A.2 трафик цод ↔ филиал реально проходит через туннель
    docker exec wireguard-branch ping -c 2 10.13.13.1

B функциональное требование тз "безопасный доступ для удалённых сотрудников"
B.1 контейнер tailscale запущен и настроен на цод
    docker inspect tailscale (Running + TS_EXTRA_ARGS с --advertise-routes=10.0.1.0/24)
B.2 tailscale обращается к управляющей плоскости (auth/login/control/register в логах)

C функциональное требование тз "приоритизация трафика видеоконференций"
C.1 на ovs-branch созданы qos-очереди (linux-htb с 3 классами 0/1/2)
C.2 openflow-правила маркируют трафик (set_queue:1 для видео, set_queue:2 для iot)
C.3 frr-branch имеет pbr-политику по dscp af41 (видео) и cs6 (iot)

D функциональное требование тз "отказоустойчивость каналов связи филиала 4G и спутник"
D.1 frr-branch имеет 2 маршрута к цод с разной distance + один best
    docker exec frr-branch vtysh -c "show ip route 10.0.1.0/24"
    подкритерии: distance 10 (основной 4G), distance 100 (резерв спутник), кто-то best
    динамика failover проверяется отдельным скриптом tests/failover.sh

E решение тз "sdn используется в цод (onos + openflow)"
E.1 onos управляет data-plane: rest api 200 + видит ≥2 устройства (ovs1 ovs2)
E.2 ovs подключены к контроллеру по openflow 1.3 (tcp:onos:6653 или tcp:10.0.1.2:6653)

(требование тз "sd-wan для филиала и удалённых сотрудников" покрывается группами A + B)

G требование тз "демонстрационный стенд работоспособен"
G.1 все сервисы стенда работают без рестартов (15 контейнеров Up)
G.2 архитектура: 4 изолированные docker-сети datacenter/branch/monitoring/remote-users
G.3 приложение в цод доступно: curl http://localhost:8080/health -> ok
G.4 grafana подгрузила дашборд агротех (наблюдаемость работает)
G.5 prometheus собирает метрики (≥2 цели в статусе up)

запуск приёмки
```bash
bash tests/acceptance.sh
```
выведет подробный отчёт по каждому пункту + итоговую таблицу.
ожидаемый результат: 15 / 15 пунктов, код выхода 0

запуск демонстрационного сценария failover
```bash
bash tests/failover.sh
```
покажет 4 шага: исходное состояние → имитация падения 4G → ping через резерв → восстановление.
ожидаемый результат: 2 маршрута → 1 маршрут → 2 маршрута

### ручная приёмка по командам

шаг 0. стенд поднят
```bash
# 0.1 показать, что все 15 сервисов в running
docker compose ps
# ожидаем: 15 строк, все в статусе Up

# 0.2 показать, что docker-сети созданы (архитектура: 4 плоскости трафика)
docker network ls | grep agrotech-nextgen-network_
# ожидаем: branch, datacenter, monitoring, remote-users
```

A. безопасный доступ к приложениям в цод для филиала (wireguard)
```bash
# A.1 сервер wireguard в цод слушает 51820 и видит peer-а филиала
docker exec wireguard wg show
# что доказываем: listening port: 51820 + строка peer: <ключ> + latest handshake

# A.2 филиал поднял туннель wg0 и установил handshake
docker exec wireguard-branch wg show
# что доказываем: interface: wg0 + latest handshake N seconds ago

# A.3 трафик из филиала к цоду реально проходит через шифрованный туннель
docker exec wireguard-branch ping -c 3 10.13.13.1
# что доказываем: 0% packet loss — связь по wg есть
```

B. безопасный доступ к приложениям в цод для удалённых сотрудников (tailscale)
```bash
# B.1 контейнер tailscale запущен и настроен на анонс подсети цод
docker inspect tailscale --format '{{.State.Running}} {{.Config.Env}}'
# что доказываем: Running=true + строка --advertise-routes=10.0.1.0/24

# B.2 tailscale обращается к управляющей плоскости
docker logs tailscale 2>&1 | grep -E 'control:|login|register|auth' | tail -5
# что доказываем: есть строки auth/login/register/control — оверлей живой
```

C. приоритизация трафика видеоконференций (qos)
```bash
# C.1 на ovs-branch созданы htb-очереди для трёх классов трафика
docker exec ovs-branch ovs-vsctl list qos
# что доказываем: type: linux-htb + queues: {0=..., 1=..., 2=...}

# C.2 openflow-правила маркируют трафик в нужные очереди
docker exec ovs-branch ovs-ofctl -O OpenFlow13 dump-flows ovs-branch
# что доказываем: есть правила с set_queue:1 (видео rtp:5004) и set_queue:2 (iot dscp 48)

# C.3 frr-branch имеет policy-based routing по dscp-меткам
docker exec frr-branch vtysh -c "show running-config" | grep -E 'pbr-map|match dscp'
# что доказываем: есть pbr-map PRIORITY-TRAFFIC + match dscp 48 и 34
```

D. отказоустойчивость каналов связи филиала (4G + спутник)
```bash
# D.1 frr имеет 2 маршрута к цоду с разной distance
docker exec frr-branch vtysh -c "show ip route 10.0.1.0/24"
# что доказываем:
#   distance 10, ... best  ← основной (4G), активный
#   distance 100, ...      ← резервный (спутник), в резерве

# D.2 имитация падения 4G — удаляем основной next-hop
docker exec frr-branch vtysh -c "configure terminal" -c "no ip route 10.0.1.0/24 10.0.2.31 10" -c "end"
docker exec frr-branch vtysh -c "show ip route 10.0.1.0/24"
# что доказываем: остался только маршрут с distance 100 — failover отработал

# D.3 связь по резерву работает (ping не теряется)
docker exec wireguard-branch ping -c 3 10.13.13.1
# что доказываем: трафик идёт через резервный канал

# D.4 восстанавливаем основной канал
docker exec frr-branch vtysh -c "configure terminal" -c "ip route 10.0.1.0/24 10.0.2.31 10" -c "end"
docker exec frr-branch vtysh -c "show ip route 10.0.1.0/24"
# что доказываем: снова 2 маршрута, основной снова best
```

E. sdn в цод (onos + openflow 1.3)
```bash
# E.1 контроллер onos поднят и доступен по rest api
curl -s -u onos:rocks http://localhost:8181/onos/v1/devices | head -c 400
# что доказываем: json с двумя устройствами of:000...01 и of:000...02

# E.2 ovs-коммутаторы привязаны к контроллеру onos по tcp
docker exec ovs1 ovs-vsctl get-controller ovs1
docker exec ovs2 ovs-vsctl get-controller ovs2
# что доказываем: оба возвращают tcp:10.0.1.2:6653 (или tcp:onos:6653)

# E.3 (опционально) посмотреть устройства глазами в ui
# открыть в браузере http://localhost:8181/onos/ui  логин onos / пароль rocks
```

G. демонстрация работоспособности
```bash
# G.1 приложение в цод доступно
curl -s http://localhost:8080/health
# что доказываем: ответ ok

# G.2 наблюдаемость: grafana загрузила наш дашборд
curl -s -u admin:admin 'http://localhost:3000/api/search?type=dash-db'
# что доказываем: json со словом agrotech / АгроТех
# или открыть в браузере http://localhost:3000  admin / admin

# G.3 мониторинг: prometheus собирает метрики
curl -s 'http://localhost:9090/api/v1/targets?state=active' | grep -oE '"health":"[a-z]+"'
# что доказываем: минимум 2 строки "health":"up"
# или открыть в браузере http://localhost:9090/targets
```

или одной строкой запустить всё через автотест
```bash
bash tests/acceptance.sh   # 15 пунктов с подробным выводом
bash tests/failover.sh     # 4-шаговая демонстрация отказоустойчивости
```

## запуск containernet демо
```bash
docker exec -it containernet python3 /topology.py
```
внутри cli
```bash
pingall
```

## остановка и очистка
остановка стенда
```bash
docker compose down
```

остановка стенда с удалением томов
```bash
docker compose down -v
```

## дерево проекта
```text
agrotech-nextgen-network/
├── readme.md
├── new.md
├── work.md
├── troubleshooting.md
├── docker-compose.yaml
├── onos/config/network-cfg.json
├── ovs/setup.sh
├── ovs/setup-branch.sh
├── wireguard/wg_confs/wg0.conf
├── wireguard/wg0-branch.conf
├── frr/frr.conf
├── containernet/topology.py
└── monitoring/prometheus.yml
```

## где лежит остальная документация
подробная техническая документация в work.md
диагностика типовых проблем в troubleshooting.md

## команда проекта
куликов кирилл
роль team lead
задачи общая архитектура, координация команды, подготовка и защита презентации

гутник вадим
роль simulation engineer
задачи сборка демо стенда в containernet, работа с docker compose, проверка failover

хафизов айгиз
роль network designer
задачи топология, ip адресация, настройка onos и ovs, политики qos

gарипов самат
роль network designer
задачи настройка wireguard и tailscale, конфигурация frr, dscp маркировка

василков арсений
роль documentation and budget specialist
задачи документация, расчет бюджета и tco, оформление readme и work
