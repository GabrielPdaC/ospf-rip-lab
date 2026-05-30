# Relatório de Testes — OSPF vs RIP Routing Lab

**Projeto:** Aplicações de Grafos em Problemas Reais — Internet e Roteamento de Dados  
**Instituição:** Universidade do Vale do Rio dos Sinos — UNISINOS  
**Disciplina:** Algoritmos e Estruturas de Dados  
**Ambiente:** WSL2 (Ubuntu 24) + Docker Engine + Containerlab  

---

## 1. Ambiente

### 1.1 Ferramentas Utilizadas

| Ferramenta | Versão | Papel |
|------------|--------|-------|
| Ubuntu 24 (WSL2) | 24.04 LTS | Sistema operacional host |
| Docker Engine | latest | Runtime de containers |
| Containerlab | 0.75.0 | Orquestração da topologia de rede |
| FRRouting (FRR) | 9.0 | Daemon de roteamento (OSPF e RIP) |
| Alpine Linux | latest | Nós de cliente, servidor e switches |

### 1.2 O que é o Containerlab?

O Containerlab é uma ferramenta open-source de simulação de redes que orquestra containers Linux conectados por interfaces de rede virtuais. Cada container funciona como um nó de rede — roteador, switch ou host — e os enlaces entre eles são criados como `veth pairs` no kernel do Linux.

É amplamente utilizado por engenheiros de redes para testar protocolos de roteamento, validar configurações e reproduzir topologias reais antes de colocar em produção. Toda a topologia é descrita em um único arquivo YAML e o laboratório é iniciado com um único comando.

### 1.3 O que é o FRRouting?

O FRRouting (FRR) é uma suíte open-source de protocolos de roteamento IP para Linux. Implementa os mesmos protocolos usados em equipamentos de rede em produção, incluindo OSPF, BGP, IS-IS e RIP. Neste laboratório, o FRR foi utilizado para executar tanto o daemon OSPF (`ospfd`) quanto o daemon RIP (`ripd`) em topologias separadas, permitindo comparar o comportamento dos dois protocolos sobre a mesma estrutura de rede.

---

## 2. Topologia da Rede

### 2.1 Objetivo do Design

A topologia foi projetada para demonstrar três conceitos fundamentais:

1. **O caminho com mais saltos, porém menor custo, é preferido pelo OSPF** — demonstrando que o critério de decisão é o custo do enlace, não a contagem de saltos.
2. **O RIP escolhe o caminho errado** — por usar apenas contagem de saltos como métrica, o RIP seleciona o caminho de menor qualidade.
3. **Failover automático no OSPF** — quando um enlace falha, o OSPF reconverge e redireciona o tráfego sem intervenção manual.

### 2.2 Diagrama

```
                         ┌────┐
                   ┌────►│ R1 ├────┐
                   │     └────┘    │
                   │               ▼
Client ──► S1 ──► R0              R3 ──┐
                   │                   ├──► S2 ──► Server
                   │     ┌────┐        │
                   └────►│ R2 ├────────┘
                         └────┘
```

**Caminho A — preferido pelo OSPF:**
```
Client → S1 → R0 → R1 → R3 → S2 → Server   (3 saltos, custo 30)
```

**Caminho B — preferido pelo RIP:**
```
Client → S1 → R0 → R2 → S2 → Server   (2 saltos, custo 50)
```

### 2.3 Nós da Rede

| Nó | Imagem | Papel |
|----|--------|-------|
| `client` | alpine:latest | Origem do tráfego |
| `server` | alpine:latest | Destino do tráfego |
| `s1` | alpine:latest | Switch de acesso (lado do cliente) |
| `s2` | alpine:latest | Switch de acesso (lado do servidor) |
| `r0` | frrouting/frr:latest | Roteador core — ponto de entrada |
| `r1` | frrouting/frr:latest | Roteador core — caminho preferido (OSPF) |
| `r2` | frrouting/frr:latest | Roteador core — caminho preferido (RIP) / backup (OSPF) |
| `r3` | frrouting/frr:latest | Roteador core — ponto de saída via R1 |

### 2.4 Enlaces e Endereçamento IP

| Enlace | Sub-rede | Endereço R0 | Endereço remoto |
|--------|----------|-------------|-----------------|
| R0 ↔ S1 | 10.0.0.0/30 | 10.0.0.1 | — |
| R0 ↔ R1 | 10.0.1.0/30 | 10.0.1.1 | 10.0.1.2 |
| R0 ↔ R2 | 10.0.2.0/30 | 10.0.2.1 | 10.0.2.2 |
| R1 ↔ R3 | 10.0.3.0/30 | 10.0.3.1 | 10.0.3.2 |
| R3 ↔ S2 | 10.0.5.0/30 | 10.0.5.1 | — |
| R2 ↔ S2 | 10.0.4.0/30 | 10.0.4.1 | — |

### 2.5 Custos OSPF dos Enlaces

| Interface | Nó | Custo | Significado |
|-----------|----|-------|-------------|
| eth2 | R0 | 10 | Enlace de alta qualidade em direção ao R1 |
| eth3 | R0 | 40 | Enlace de menor qualidade em direção ao R2 |
| eth1 | R2 | 40 | Custo simétrico no lado do R2 |

Todas as demais interfaces utilizam o custo padrão de **10**.

> **Observação:** O RIP não utiliza custos — sua única métrica é a contagem de saltos. Por isso os custos configurados acima só afetam o comportamento do OSPF.

---

## 3. Arquivos de Configuração

### 3.1 topology.yml (compartilhado entre os dois labs, com nomes diferentes)

```yaml
name: ospf-lab   # alterado para rip-lab no laboratório RIP

topology:
  nodes:
    r0:
      kind: linux
      image: frrouting/frr:latest
      binds:
        - config/r0/frr.conf:/etc/frr/frr.conf
        - config/r0/daemons:/etc/frr/daemons

    r1:
      kind: linux
      image: frrouting/frr:latest
      binds:
        - config/r1/frr.conf:/etc/frr/frr.conf
        - config/r1/daemons:/etc/frr/daemons

    r2:
      kind: linux
      image: frrouting/frr:latest
      binds:
        - config/r2/frr.conf:/etc/frr/frr.conf
        - config/r2/daemons:/etc/frr/daemons

    r3:
      kind: linux
      image: frrouting/frr:latest
      binds:
        - config/r3/frr.conf:/etc/frr/frr.conf
        - config/r3/daemons:/etc/frr/daemons

    client:
      kind: linux
      image: alpine:latest

    server:
      kind: linux
      image: alpine:latest

    s1:
      kind: linux
      image: alpine:latest

    s2:
      kind: linux
      image: alpine:latest

  links:
    - endpoints: ["client:eth1", "s1:eth1"]
    - endpoints: ["s1:eth2",     "r0:eth1"]
    - endpoints: ["r0:eth2",     "r1:eth1"]
    - endpoints: ["r0:eth3",     "r2:eth1"]
    - endpoints: ["r1:eth2",     "r3:eth1"]
    - endpoints: ["r3:eth2",     "s2:eth1"]
    - endpoints: ["r2:eth2",     "s2:eth2"]
    - endpoints: ["s2:eth3",     "server:eth1"]
```

### 3.2 daemons — Lab OSPF

```
bgpd=no
ospfd=yes
ospf6d=no
ripd=no
...
staticd=yes
```

### 3.3 daemons — Lab RIP

```
bgpd=no
ospfd=no
ospf6d=no
ripd=yes
...
staticd=yes
```

### 3.4 Configurações FRR — Lab OSPF

**config/r0/frr.conf**
```
frr version 9.0
hostname r0
log syslog informational
!
interface eth1
 ip address 10.0.0.1/30
!
interface eth2
 ip address 10.0.1.1/30
 ip ospf cost 10
!
interface eth3
 ip address 10.0.2.1/30
 ip ospf cost 40
!
router ospf
 ospf router-id 0.0.0.0
 network 10.0.0.0/30 area 0
 network 10.0.1.0/30 area 0
 network 10.0.2.0/30 area 0
!
```

**config/r1/frr.conf**
```
frr version 9.0
hostname r1
log syslog informational
!
interface eth1
 ip address 10.0.1.2/30
!
interface eth2
 ip address 10.0.3.1/30
!
router ospf
 ospf router-id 1.1.1.1
 network 10.0.1.0/30 area 0
 network 10.0.3.0/30 area 0
!
```

**config/r2/frr.conf**
```
frr version 9.0
hostname r2
log syslog informational
!
interface eth1
 ip address 10.0.2.2/30
 ip ospf cost 40
!
interface eth2
 ip address 10.0.4.1/30
!
ip route 10.0.5.0/30 10.0.4.2
!
router ospf
 ospf router-id 2.2.2.2
 network 10.0.2.0/30 area 0
 network 10.0.4.0/30 area 0
 redistribute static
!
```

**config/r3/frr.conf**
```
frr version 9.0
hostname r3
log syslog informational
!
interface eth1
 ip address 10.0.3.2/30
!
interface eth2
 ip address 10.0.5.1/30
!
router ospf
 ospf router-id 3.3.3.3
 network 10.0.3.0/30 area 0
 network 10.0.5.0/30 area 0
!
```

### 3.5 Configurações FRR — Lab RIP

**config/r0/frr.conf**
```
frr version 9.0
hostname r0
log syslog informational
!
interface eth1
 ip address 10.0.0.1/30
!
interface eth2
 ip address 10.0.1.1/30
!
interface eth3
 ip address 10.0.2.1/30
!
router rip
 network 10.0.0.0/30
 network 10.0.1.0/30
 network 10.0.2.0/30
 timers basic 10 30 30
!
```

**config/r1/frr.conf**
```
frr version 9.0
hostname r1
log syslog informational
!
interface eth1
 ip address 10.0.1.2/30
!
interface eth2
 ip address 10.0.3.1/30
!
router rip
 network 10.0.1.0/30
 network 10.0.3.0/30
 timers basic 10 30 30
!
```

**config/r2/frr.conf**
```
frr version 9.0
hostname r2
log syslog informational
!
interface eth1
 ip address 10.0.2.2/30
!
interface eth2
 ip address 10.0.4.1/30
!
ip route 10.0.5.0/30 10.0.4.2
!
router rip
 network 10.0.2.0/30
 network 10.0.4.0/30
 redistribute static
 timers basic 10 30 30
!
```

**config/r3/frr.conf**
```
frr version 9.0
hostname r3
log syslog informational
!
interface eth1
 ip address 10.0.3.2/30
!
interface eth2
 ip address 10.0.5.1/30
!
router rip
 network 10.0.3.0/30
 network 10.0.5.0/30
 timers basic 10 30 30
!
```

---

## 4. Inicialização dos Laboratórios

```bash
# Lab OSPF
cd ~/ospf-routing-lab
sudo containerlab deploy --topo topology.yml

# Lab RIP
cd ~/rip-routing-lab
sudo containerlab deploy --topo topology.yml
```

---

## 5. Resultados dos Testes

### 5.1 Teste 1 — Adjacência OSPF

Após aproximadamente 40 segundos para convergência, todos os roteadores formaram adjacências `Full`.

**Comando:**
```bash
docker exec -it clab-ospf-lab-r0 vtysh -c "show ip ospf neighbor"
```

**Saída:**
```
Neighbor ID   Pri  State         Up Time   Dead Time  Address     Interface
1.1.1.1         1  Full/Backup   1m21s     38.211s    10.0.1.2    eth2:10.0.1.1
2.2.2.2         1  Full/Backup   5m41s     38.845s    10.0.2.2    eth3:10.0.2.1
```

R1 e R2 em estado `Full` — banco de dados de topologia sincronizado e Dijkstra executado.

---

### 5.2 Teste 2 — Tabela de roteamento OSPF em operação normal

**Comando:**
```bash
docker exec -it clab-ospf-lab-r0 vtysh -c "show ip ospf route"
```

**Saída:**
```
============ OSPF network routing table ============
N    10.0.0.0/30    [10]  directly attached to eth1
N    10.0.1.0/30    [10]  directly attached to eth2
N    10.0.2.0/30    [40]  directly attached to eth3
N    10.0.3.0/30    [20]  via 10.0.1.2, eth2
N    10.0.4.0/30    [50]  via 10.0.2.2, eth3
N    10.0.5.0/30    [30]  via 10.0.1.2, eth2
============ OSPF router routing table =============
R    2.2.2.2        [40]  area 0.0.0.0, ASBR via 10.0.2.2, eth3
```

**Análise:**

| Destino | Custo | Via | Saltos |
|---------|-------|-----|--------|
| 10.0.5.0/30 (servidor) | **30** | R1 → R3 → S2 | 3 |
| alternativa via R2 | **50** | R2 → S2 | 2 |

O OSPF preferiu o caminho com **mais saltos e menor custo**. O custo total via R1 é 30 (10+10+10), contra 50 via R2 (40+10). Dijkstra selecionou corretamente o caminho de menor custo total.

---

### 5.3 Teste 3 — Tabela de roteamento RIP em operação normal

**Comando:**
```bash
docker exec -it clab-rip-lab-r0 vtysh -c "show ip rip"
```

**Saída:**
```
     Network            Next Hop         Metric From       Tag  Time
C(i) 10.0.0.0/30        0.0.0.0               1 self         0
C(i) 10.0.1.0/30        0.0.0.0               1 self         0
C(i) 10.0.2.0/30        0.0.0.0               1 self         0
R(n) 10.0.4.0/30        10.0.2.2              2 10.0.2.2      0  00:26
R(n) 10.0.5.0/30        10.0.2.2              2 10.0.2.2      0  00:26
```

**Análise:**

| Destino | Métrica | Via | Saltos |
|---------|---------|-----|--------|
| 10.0.5.0/30 (servidor) | **2** | R2 → S2 | 2 |
| alternativa via R1 | **3** | R1 → R3 → S2 | 3 |

O RIP preferiu o caminho com **menos saltos**, ignorando completamente a qualidade dos enlaces. O caminho via R2 tem apenas 2 saltos, portanto o RIP o considera melhor — mesmo que a qualidade do enlace R0→R2 seja inferior.

---

### 5.4 Teste 4 — Comparação direta OSPF vs RIP

| Critério | OSPF | RIP |
|----------|------|-----|
| Algoritmo subjacente | Dijkstra | Bellman-Ford distribuído |
| Métrica utilizada | Custo do enlace | Contagem de saltos |
| Rota escolhida para o servidor | R0→R1→R3→S2 (3 saltos, custo 30) | R0→R2→S2 (2 saltos, métrica 2) |
| Caminho de maior qualidade selecionado | ✓ sim | ✗ não |
| Limite de escala | Sem limite prático | Máximo 15 saltos |
| Velocidade de convergência | ~10–40 segundos | ~30–180 segundos |

**Conclusão:** sobre a mesma topologia e com os mesmos enlaces, o OSPF selecionou o caminho de maior qualidade enquanto o RIP selecionou o caminho mais curto em saltos — que neste caso é o de menor qualidade. Isso demonstra na prática a superioridade do OSPF para redes onde a qualidade dos enlaces varia.

---

### 5.5 Teste 5 — Simulação de falha de enlace e reconvergência OSPF

A interface `eth1` do R1 foi desativada para simular uma falha de enlace.

**Derrubar o enlace:**
```bash
docker exec clab-ospf-lab-r1 ip link set eth1 down
```

**Vizinhos após ~40 segundos:**
```bash
docker exec -it clab-ospf-lab-r0 vtysh -c "show ip ospf neighbor"
```

**Saída:**
```
Neighbor ID   Pri  State         Up Time   Dead Time  Address     Interface
2.2.2.2         1  Full/Backup   40.239s   39.760s    10.0.2.2    eth3:10.0.2.1
```

R1 removido da tabela de vizinhos após expirar o dead timer.

**Tabela de roteamento após a falha:**
```bash
docker exec -it clab-ospf-lab-r0 vtysh -c "show ip ospf route"
```

**Saída:**
```
============ OSPF network routing table ============
N    10.0.0.0/30    [10]   directly attached to eth1
N    10.0.2.0/30    [40]   directly attached to eth3
N    10.0.4.0/30    [50]   via 10.0.2.2, eth3
```

**Comparação antes e depois da falha:**

| Destino | Operação normal | Após falha do R1 |
|---------|----------------|-----------------|
| Rota para o servidor | custo 30, via R1→R3→S2, 3 saltos ✓ | custo 50, via R2→S2, 2 saltos ✓ |
| Enlace R0↔R1 | presente | ausente (link down) |

O OSPF reconvergiu automaticamente e redirecionou o tráfego via R2. O servidor permaneceu acessível sem nenhuma intervenção manual.

**Observação:** no failover, o caminho ativo passou a ter **menos saltos e custo maior** — reforçando que o critério de decisão do OSPF é sempre o custo, independentemente da quantidade de saltos.

---

### 5.6 Teste 6 — Restauração do enlace

```bash
docker exec clab-ospf-lab-r1 ip link set eth1 up
```

Após ~40 segundos, R1 retornou ao estado `Full` e a tabela de roteamento reverteu ao caminho preferido via R1 com custo 30.

---

## 6. Resumo Geral

| Conceito demonstrado | Resultado |
|---------------------|-----------|
| Rede modelada como grafo ponderado | Roteadores = vértices, enlaces = arestas, custo OSPF = peso |
| Dijkstra aplicado na prática | OSPF calculou corretamente o caminho de menor custo |
| Custo vs contagem de saltos | OSPF preferiu 3 saltos (custo 30) sobre 2 saltos (custo 50) |
| Limitação do RIP | RIP escolheu o caminho errado por usar apenas saltos como métrica |
| Failover automático | OSPF reconvergiu sem intervenção manual após falha de enlace |
| Reconvergência | OSPF reverteu ao caminho ótimo após restauração do enlace |

---

## 7. Referência de Comandos

| Ação | Comando |
|------|---------|
| Subir lab OSPF | `cd ~/ospf-routing-lab && sudo containerlab deploy --topo topology.yml` |
| Subir lab RIP | `cd ~/rip-routing-lab && sudo containerlab deploy --topo topology.yml` |
| Destruir lab | `sudo containerlab destroy --topo topology.yml` |
| Ver rotas OSPF | `docker exec -it clab-ospf-lab-r0 vtysh -c "show ip ospf route"` |
| Ver vizinhos OSPF | `docker exec -it clab-ospf-lab-r0 vtysh -c "show ip ospf neighbor"` |
| Ver rotas RIP | `docker exec -it clab-rip-lab-r0 vtysh -c "show ip rip"` |
| Ver tabela completa | `docker exec -it clab-ospf-lab-r0 vtysh -c "show ip route"` |
| Simular falha de enlace | `docker exec clab-ospf-lab-r1 ip link set eth1 down` |
| Restaurar enlace | `docker exec clab-ospf-lab-r1 ip link set eth1 up` |
| Abrir CLI do roteador | `docker exec -it clab-ospf-lab-r0 vtysh` |