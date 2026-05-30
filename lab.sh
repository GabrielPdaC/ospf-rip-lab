#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OSPF_DIR="$SCRIPT_DIR/ospf"
RIP_DIR="$SCRIPT_DIR/rip"

usage() {
  echo "Uso: $0 {up|down|status|restart}"
  echo ""
  echo "  up              Sobe os dois labs"
  echo "  down            Derruba os dois labs"
  echo "  status          Mostra estado dos containers"
  echo "  restart         Derruba e sobe novamente"
  exit 1
}

up() {
  echo ">>> Subindo lab OSPF..."
  cd "$OSPF_DIR" && sudo containerlab deploy --topo topology.yml

  echo ""
  echo ">>> Subindo lab RIP..."
  cd "$RIP_DIR" && sudo containerlab deploy --topo topology.yml

  echo ""
  echo ">>> Aguardando convergência (45s)..."
  sleep 45

  echo ""
  echo ">>> Rotas OSPF (R0):"
  docker exec clab-ospf-lab-r0 vtysh -c "show ip ospf route" 2>/dev/null | grep -v vtysh.conf

  echo ""
  echo ">>> Rotas RIP (R0):"
  docker exec clab-rip-lab-r0 vtysh -c "show ip rip" 2>/dev/null | grep -v vtysh.conf
}

down() {
  echo ">>> Derrubando lab OSPF..."
  cd "$OSPF_DIR" && sudo containerlab destroy --topo topology.yml

  echo ""
  echo ">>> Derrubando lab RIP..."
  cd "$RIP_DIR" && sudo containerlab destroy --topo topology.yml
}

status() {
  echo ">>> Vizinhos OSPF (R0):"
  docker exec clab-ospf-lab-r0 vtysh -c "show ip ospf neighbor" 2>/dev/null | grep -v vtysh.conf

  echo ""
  echo ">>> Rotas OSPF (R0):"
  docker exec clab-ospf-lab-r0 vtysh -c "show ip ospf route" 2>/dev/null | grep -v vtysh.conf

  echo ""
  echo ">>> Rotas RIP (R0):"
  docker exec clab-rip-lab-r0 vtysh -c "show ip rip" 2>/dev/null | grep -v vtysh.conf
}

case "$1" in
  up)      up ;;
  down)    down ;;
  status)  status ;;
  restart) down && up ;;
  *)       usage ;;
esac
