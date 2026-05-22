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

# flow-правила: iot → очередь 2 (высокий приоритет), cctv → очередь 1
ovs-ofctl -O OpenFlow13 add-flow "$BRIDGE" \
  "priority=200,ip,nw_tos=48 actions=set_queue:2,output:uplink" 2>/dev/null || true

ovs-ofctl -O OpenFlow13 add-flow "$BRIDGE" \
  "priority=100,udp,tp_dst=5004 actions=set_queue:1,output:uplink" 2>/dev/null || true

ovs-ofctl -O OpenFlow13 add-flow "$BRIDGE" \
  "priority=1 actions=output:uplink" 2>/dev/null || true

echo "[ovs-branch] готово"
ovs-vsctl show