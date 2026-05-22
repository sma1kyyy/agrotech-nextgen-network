#!/usr/bin/env python3

from mininet.net import Containernet
from mininet.node import Controller
from mininet.cli import CLI
from mininet.log import setLogLevel, info


def run():
    net = Containernet(controller=Controller)

    info('*** add controller\n')
    c0 = net.addController('c0', ip='127.0.0.1', port=6653)

    info('*** add switches\n')
    s1 = net.addSwitch('s1')
    s2 = net.addSwitch('s2')

    info('*** add hosts\n')
    h1 = net.addHost('h1', ip='10.10.10.10/24')
    h2 = net.addHost('h2', ip='10.10.10.20/24')

    info('*** links\n')
    net.addLink(s1, s2)
    net.addLink(h1, s1)
    net.addLink(h2, s2)

    info('*** start\n')
    net.build()
    c0.start()
    s1.start([c0])
    s2.start([c0])

    info('*** test\n')
    net.ping([h1, h2])

    CLI(net)
    net.stop()


if __name__ == '__main__':
    setLogLevel('info')
    run()