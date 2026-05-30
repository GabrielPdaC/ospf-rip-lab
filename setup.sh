#!/bin/bash

set -e

echo "================================================"
echo " OSPF vs RIP Routing Lab — Setup"
echo "================================================"

# ── 1. Docker ────────────────────────────────────────
if command -v docker &>/dev/null; then
  echo "[✓] Docker já instalado"
else
  echo "[...] Instalando Docker..."
  sudo apt-get update -qq
  sudo apt-get install -y -qq ca-certificates curl gnupg

  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt-get update -qq
  sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin

  sudo usermod -aG docker $USER
  echo "[✓] Docker instalado"
fi

# ── 2. Docker service ────────────────────────────────
if ! docker info &>/dev/null; then
  echo "[...] Iniciando Docker..."
  sudo service docker start
  sleep 3
fi
echo "[✓] Docker rodando"

# ── 3. Containerlab ──────────────────────────────────
if command -v containerlab &>/dev/null; then
  echo "[✓] Containerlab já instalado"
else
  echo "[...] Instalando Containerlab..."
  bash -c "$(curl -sL https://get.containerlab.dev)"
  echo "[✓] Containerlab instalado"
fi

# ── 4. Copiar labs para home ─────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[...] Copiando arquivos dos labs..."

cp -r "$SCRIPT_DIR/ospf" ~/ospf-routing-lab
cp -r "$SCRIPT_DIR/rip"  ~/rip-routing-lab

echo "[✓] Arquivos copiados"
echo "    ~/ospf-routing-lab"
echo "    ~/rip-routing-lab"

# ── 5. Subir os labs ─────────────────────────────────
echo ""
echo "[...] Subindo lab OSPF..."
cd ~/ospf-routing-lab && sudo containerlab deploy --topo topology.yml

echo ""
echo "[...] Subindo lab RIP..."
cd ~/rip-routing-lab && sudo containerlab deploy --topo topology.yml

# ── 6. Aguardar convergência ─────────────────────────
echo ""
echo "[...] Aguardando convergência OSPF e RIP (45s)..."
sleep 45

# ── 7. Validar ───────────────────────────────────────
echo ""
echo "================================================"
echo " Rotas OSPF (R0)"
echo "================================================"
docker exec clab-ospf-lab-r0 vtysh -c "show ip ospf route" 2>/dev/null | grep -v vtysh.conf

echo ""
echo "================================================"
echo " Rotas RIP (R0)"
echo "================================================"
docker exec clab-rip-lab-r0 vtysh -c "show ip rip" 2>/dev/null | grep -v vtysh.conf

echo ""
echo "================================================"
echo " Ambiente pronto!"
echo ""
echo " Comandos úteis:"
echo "   Ver rotas OSPF : docker exec -it clab-ospf-lab-r0 vtysh -c 'show ip ospf route'"
echo "   Ver rotas RIP  : docker exec -it clab-rip-lab-r0 vtysh -c 'show ip rip'"
echo "   Falha de enlace: docker exec clab-ospf-lab-r1 ip link set eth1 down"
echo "   Restaurar      : docker exec clab-ospf-lab-r1 ip link set eth1 up"
echo "   Derrubar labs  : cd ~/ospf-routing-lab && sudo containerlab destroy --topo topology.yml"
echo "================================================"
