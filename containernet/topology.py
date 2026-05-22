#!/usr/bin/env python3
# containernet/topology.py
# симуляция топологии АгроТех в Mininet/Containernet
#
# что моделируется:
#   - цод (DC): сервер приложений app, мониторинг mon
#   - филиал (BR): iot-датчик, cctv-камера
#   - два uplink-канала между филиалом и цод:
#       link_4g  — основной (полоса 50 Мбит/с, задержка 30 мс, потери 1%)
#       link_sat — резервный (полоса 5 Мбит/с, задержка 600 мс, потери 5%)
#   - sdn-коммутаторы s_dc и s_br, оба под контроллером ONOS
#
# демо-сценарии (запускать в CLI mininet после старта):
#   pingall                   — базовая связность
#   net.iperf((iot, app))     — проверка пропускной способности через 4G
#   link s_br s_dc_4g down    — имитация падения 4G
#   pingall                   — должен сработать резерв через спутник
#   link s_br s_dc_4g up      — возврат основного канала

from mininet.net import Containernet
from mininet.node import RemoteController, OVSSwitch
from mininet.link import TCLink
from mininet.cli import CLI
from mininet.log import setLogLevel, info


def build():
    # подключаемся к существующему onos-контроллеру в docker (host network)
    # порт 6653 — openflow 1.3
    net = Containernet(controller=RemoteController, switch=OVSSwitch, link=TCLink)

    info('*** контроллер ONOS\n')
    c0 = net.addController('c0', controller=RemoteController,
                           ip='127.0.0.1', port=6653)

    info('*** коммутаторы\n')
    s_dc = net.addSwitch('s_dc', protocols='OpenFlow13')
    s_br = net.addSwitch('s_br', protocols='OpenFlow13')
    # два независимых "линка" для 4G и спутника — это разные ovs-порты на s_dc
    # имитируется через два TCLink с разными характеристиками
    s_dc_4g = net.addSwitch('s_dc4g', protocols='OpenFlow13')
    s_dc_sat = net.addSwitch('s_dcsat', protocols='OpenFlow13')

    info('*** хосты цод\n')
    app = net.addHost('app', ip='10.0.1.20/24', mac='00:00:00:00:01:20')
    mon = net.addHost('mon', ip='10.0.1.21/24', mac='00:00:00:00:01:21')

    info('*** хосты филиала\n')
    iot = net.addHost('iot', ip='10.0.2.20/24', mac='00:00:00:00:02:20')
    cctv = net.addHost('cctv', ip='10.0.2.21/24', mac='00:00:00:00:02:21')

    info('*** линки внутри цод и филиала\n')
    net.addLink(app, s_dc)
    net.addLink(mon, s_dc)
    net.addLink(iot, s_br)
    net.addLink(cctv, s_br)

    info('*** uplink 4G: 50 Мбит/с, задержка 30 мс, потери 1%\n')
    net.addLink(s_br, s_dc_4g,
                bw=50, delay='30ms', loss=1, max_queue_size=1000, use_htb=True)
    net.addLink(s_dc_4g, s_dc, bw=100)

    info('*** uplink спутник: 5 Мбит/с, задержка 600 мс, потери 5%\n')
    net.addLink(s_br, s_dc_sat,
                bw=5, delay='600ms', loss=5, max_queue_size=200, use_htb=True)
    net.addLink(s_dc_sat, s_dc, bw=100)

    info('*** старт сети\n')
    net.build()
    c0.start()
    for sw in (s_dc, s_br, s_dc_4g, s_dc_sat):
        sw.start([c0])

    info('*** базовая проверка связности\n')
    net.pingAll(timeout='2')

    info('*** CLI доступен. полезные команды:\n')
    info('***   pingall\n')
    info('***   link s_br s_dc4g down   # падение 4G\n')
    info('***   pingall                 # резерв через спутник\n')
    info('***   iperf iot app           # пропускная способность\n')
    info('***   exit                    # завершение\n')
    CLI(net)

    info('*** остановка\n')
    net.stop()


if __name__ == '__main__':
    setLogLevel('info')
    build()
