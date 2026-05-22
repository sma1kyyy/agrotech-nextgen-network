> это руководство по запуску и решению проблем. в нём описаны системные требования (версия Docker, нужные модули ядра Linux), пошаговая инструкция как поднять стенд и проверить что каждый сервис работает. основная часть таблица с типичными ошибками: что случилось, почему, как починить. например конфликт подсетей Docker, незагруженный модуль openvswitch, заблокированный порт WireGuard. в конце шпаргалка с однострочными командами для отладки OVS, WireGuard, ONOS и FRR

# troubleshooting

## быстрые проверки
проверить состояние всех сервисов
docker compose ps

посмотреть логи проблемного сервиса
docker logs --tail 100 ovs1
docker logs --tail 100 ovs2
docker logs --tail 100 ovs-branch
docker logs --tail 100 onos

## частые проблемы и решение

ovs контейнер уходит в restarting
проверить что модуль openvswitch загружен на хосте
sudo modprobe openvswitch
после этого перезапустить сервис
docker compose restart ovs1 ovs2 ovs-branch

onos не видит устройства
проверить доступность порта 6653 и протокол openflow13
проверить контроллер на ovs
docker exec ovs1 ovs-vsctl get-controller ovs1
docker exec ovs2 ovs-vsctl get-controller ovs2

нет туннеля wireguard
проверить ключи и peer конфиги
docker exec wireguard wg show
проверить что udp 51820 доступен

нет failover в филиале
проверить маршруты и метрики
docker exec frr-branch vtysh -c "show ip route"
проверить bfd соседей
docker exec frr-branch vtysh -c "show bfd peers"

prometheus не видит цели
открыть http://localhost:9090/targets
сверить ip и порты в monitoring/prometheus.yml

## полезные команды
состояние ovs bridge
docker exec ovs1 ovs-vsctl show

таблица flow
docker exec ovs-branch ovs-ofctl -O OpenFlow13 dump-flows ovs-branch

проверка связности цод
curl -s http://localhost:8080/health

проверка onos api
curl -u onos:rocks http://localhost:8181/onos/v1/devices