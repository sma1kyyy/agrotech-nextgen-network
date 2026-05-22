#!/usr/bin/env bash
# ovs/setup.sh создаёт бридж, подключает к onos через openflow 1.3
# аргументы: $1 = имя бриджа, $2 = ip onos-контроллера, $3 = порт openflow
# запускается внутри контейнера ovs1/ovs2

set -euo pipefail

BRIDGE="${1:-ovs1}"
CONTROLLER_IP="${2:-10.0.1.2}"
CONTROLLER_PORT="${3:-6653}"
DPID=""

case "$BRIDGE" in
  ovs1) DPID="0000000000000001" ;;
  ovs2) DPID="0000000000000002" ;;
  *)    DPID="0000000000000099" ;;
esac

echo "[ovs setup] бридж: $BRIDGE, контроллер: $CONTROLLER_IP:$CONTROLLER_PORT, dpid: $DPID"

# ждём пока ovsdb-server будет готов
for i in $(seq 1 20); do
  ovs-vsctl show > /dev/null 2>&1 && break
  echo "[ovs setup] ожидаем ovsdb... попытка $i/20"
  sleep 1
done

# создаём бридж если не существует
if ! ovs-vsctl br-exists "$BRIDGE"; then
  ovs-vsctl add-br "$BRIDGE"
  echo "[ovs setup] создан бридж $BRIDGE"
fi

# устанавливаем datapath-id для openflow
ovs-vsctl set bridge "$BRIDGE" other-config:datapath-id="$DPID"

# включаем openflow 1.3
ovs-vsctl set bridge "$BRIDGE" protocols=OpenFlow13

# подключаем к onos-контроллеру
ovs-vsctl set-controller "$BRIDGE" "tcp:${CONTROLLER_IP}:${CONTROLLER_PORT}"

# включаем отказоустойчивость: если onos недоступен — коммутатор работает автономно
ovs-vsctl set bridge "$BRIDGE" fail-mode=standalone

# добавляем внутренний порт для управления
ovs-vsctl --may-exist add-port "$BRIDGE" "${BRIDGE}-mgmt" \
  -- set Interface "${BRIDGE}-mgmt" type=internal

# настраиваем qos-очереди на портах (dscp-маркировка трафика)
# очередь 0: best-effort (обычный трафик)
# очередь 1: приоритет видеоконференций (dscp af41 = 34)
# очередь 2: критические iot-данные (dscp cs6 = 48)
ovs-vsctl set port "$BRIDGE" qos=@qos1 \
  -- --id=@qos1 create qos type=linux-htb \
     other-config:max-rate=1000000000 \
     queues:0=@q0 queues:1=@q1 queues:2=@q2 \
  -- --id=@q0 create queue other-config:min-rate=100000000 other-config:max-rate=900000000 \
  -- --id=@q1 create queue other-config:min-rate=400000000 other-config:max-rate=1000000000 \
  -- --id=@q2 create queue other-config:min-rate=200000000 other-config:max-rate=1000000000 \
  2>/dev/null || echo "[ovs setup] qos уже настроен или порт не поддерживает"

echo "[ovs setup] готово. статус бриджа $BRIDGE:"
ovs-vsctl show