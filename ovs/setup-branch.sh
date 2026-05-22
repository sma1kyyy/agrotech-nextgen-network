#!/usr/bin/env bash
# ovs/setup-branch.sh коммутатор в филиале
# не подключается к onos (standalone), просто разделяет iot и cctv трафик
# dscp-маркировка навешивается через tc-rules.sh

set -euo pipefail

BRIDGE="ovs-branch"
DPID="0000000000000010"

echo "[ovs-branch] настройка коммутатора филиала"

for i in $(seq 1 20); do
  ovs-vsctl show > /dev/null 2>&1 && break
  echo "[ovs-branch] ожидаем ovsdb... попытка $i/20"
  sleep 1
done

if ! ovs-vsctl br-exists "$BRIDGE"; then
  ovs-vsctl add-br "$BRIDGE"
fi

ovs-vsctl set bridge "$BRIDGE" other-config:datapath-id="$DPID"
ovs-vsctl set bridge "$BRIDGE" protocols=OpenFlow13
ovs-vsctl set bridge "$BRIDGE" fail-mode=standalone

# uplink к frr-роутеру
ovs-vsctl --may-exist add-port "$BRIDGE" uplink \
  -- set Interface uplink type=internal

# порт iot-датчиков (vlan 10 критический трафик)
ovs-vsctl --may-exist add-port "$BRIDGE" iot-port \
  -- set Interface iot-port type=internal

# порт cctv-камер (vlan 20 видеопоток)
ovs-vsctl --may-exist add-port "$BRIDGE" cctv-port \
  -- set Interface cctv-port type=internal

# qos-очереди на uplink-порту (htb с тремя классами)
# queue 0 best-effort, queue 1 видеопоток (cctv), queue 2 критические iot-данные
# трафик в очередях ограничен по полосе и приоритезируется htb
ovs-vsctl -- set Port uplink qos=@qos1 \
  -- --id=@qos1 create qos type=linux-htb \
       other-config:max-rate=1000000000 \
       queues:0=@q0 queues:1=@q1 queues:2=@q2 \
  -- --id=@q0 create queue other-config:min-rate=100000000 other-config:max-rate=900000000 \
  -- --id=@q1 create queue other-config:min-rate=400000000 other-config:max-rate=1000000000 \
  -- --id=@q2 create queue other-config:min-rate=200000000 other-config:max-rate=1000000000 \
  2>/dev/null || echo "[ovs-branch] qos уже настроен или порт не поддерживает"

# flow-правила: iot (dscp cs6=48) → очередь 2, cctv (rtp udp 5004) → очередь 1
ovs-ofctl -O OpenFlow13 add-flow "$BRIDGE" \
  "priority=200,ip,nw_tos=48 actions=set_queue:2,output:uplink" 2>/dev/null || true

ovs-ofctl -O OpenFlow13 add-flow "$BRIDGE" \
  "priority=100,udp,tp_dst=5004 actions=set_queue:1,output:uplink" 2>/dev/null || true

ovs-ofctl -O OpenFlow13 add-flow "$BRIDGE" \
  "priority=1 actions=output:uplink" 2>/dev/null || true

echo "[ovs-branch] готово"
ovs-vsctl show