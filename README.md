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

A estrutura de arquivos está organizada em dois diretórios independentes, um por protocolo:

```
ospf/
├── topology.yml
└── config/
    ├── r0/  (frr.conf  daemons)
    ├── r1/  (frr.conf  daemons)
    ├── r2/  (frr.conf  daemons)
    └── r3/  (frr.conf  daemons)

rip/
├── topology.yml
└── config/
    ├── r0/  (frr.conf  daemons)
    ├── r1/  (frr.conf  daemons)
    ├── r2/  (frr.conf  daemons)
    └── r3/  (frr.conf  daemons)

setup.sh
lab.sh
```

### 3.1 topology.yml

Define a topologia completa do laboratório: nós (roteadores, switches, cliente e servidor), imagens Docker utilizadas, mapeamento dos arquivos de configuração via `binds`, e os enlaces (`links`) entre as interfaces de cada nó.

| Lab | Arquivo |
|-----|---------|
| OSPF | [ospf/topology.yml](ospf/topology.yml) |
| RIP | [rip/topology.yml](rip/topology.yml) |

> **Diferença:** Os dois arquivos têm estrutura e enlaces idênticos. A única diferença deveria ser o campo `name` (`ospf-lab` vs `rip-lab`). No arquivo atual `rip/topology.yml`, o campo `name` está definido como `ospf-lab` — isso é uma inconsistência: o Containerlab usa esse nome para nomear os containers (ex.: `clab-ospf-lab-r0`), de modo que os containers do lab RIP seriam nomeados como se fossem OSPF, causando conflito caso os dois labs estejam rodando ao mesmo tempo.

### 3.2 daemons

Lido pelo FRR na inicialização do container para decidir quais daemons de roteamento ativar. Cada roteador possui o seu próprio, montado via bind em `/etc/frr/daemons` dentro do container. O conteúdo é idêntico entre r0, r1, r2 e r3 dentro de cada lab.

| Lab | Arquivo de referência |
|-----|-----------------------|
| OSPF | [ospf/config/r0/daemons](ospf/config/r0/daemons) |
| RIP | [rip/config/r0/daemons](rip/config/r0/daemons) |

> **Diferença:** No lab OSPF, o arquivo ativa `ospfd=yes` e mantém `ripd=no`, o que está correto. O arquivo do lab RIP deveria inverter isso (`ripd=yes` e `ospfd=no`), mas no estado atual do repositório ele é idêntico ao do lab OSPF — o daemon RIP não será iniciado.

### 3.3 frr.conf — por roteador

Arquivo de configuração principal do FRR. Define os endereços IP das interfaces e o bloco de configuração do protocolo de roteamento ativo. Cada roteador possui o seu em `config/<rX>/frr.conf`, montado no container em `/etc/frr/frr.conf`.

#### R0 — ponto de entrada da rede (três interfaces)

| Lab | Arquivo |
|-----|---------|
| OSPF | [ospf/config/r0/frr.conf](ospf/config/r0/frr.conf) |
| RIP | [rip/config/r0/frr.conf](rip/config/r0/frr.conf) |

Configura três interfaces: `eth1` (acesso via S1), `eth2` (enlace para R1) e `eth3` (enlace para R2). No lab OSPF, `eth2` recebe custo 10 e `eth3` custo 40, forçando a preferência pelo caminho via R1.

> **Diferença:** O arquivo do lab RIP é atualmente idêntico ao do lab OSPF — usa `router ospf` com custos de enlace. O esperado seria substituir o bloco por `router rip` anunciando as mesmas redes, sem custos (RIP não usa custo de enlace como métrica).

#### R1 — caminho preferido pelo OSPF (duas interfaces)

| Lab | Arquivo |
|-----|---------|
| OSPF | [ospf/config/r1/frr.conf](ospf/config/r1/frr.conf) |
| RIP | [rip/config/r1/frr.conf](rip/config/r1/frr.conf) |

Configura `eth1` (enlace para R0) e `eth2` (enlace para R3). Anuncia as duas sub-redes no protocolo ativo.

> **Diferença:** O arquivo do lab RIP é idêntico ao do lab OSPF — usa `router ospf` em vez de `router rip`.

#### R2 — caminho preferido pelo RIP / backup do OSPF (duas interfaces + rota estática)

| Lab | Arquivo |
|-----|---------|
| OSPF | [ospf/config/r2/frr.conf](ospf/config/r2/frr.conf) |
| RIP | [rip/config/r2/frr.conf](rip/config/r2/frr.conf) |

Configura `eth1` (enlace para R0, custo 40 no OSPF) e `eth2` (enlace direto para S2). É o único roteador com rota estática, necessária para alcançar a sub-rede além de S2 (`10.0.5.0/30`).

> **Diferença:** O arquivo do lab RIP é o único com conteúdo diferente do lab OSPF: adiciona `ip route 10.0.5.0/30 10.0.4.2` e `redistribute static` no bloco de roteamento. Porém ainda usa `router ospf` — o bloco deveria ser `router rip` para um lab RIP correto. A rota estática e o `redistribute` em si fazem sentido para ambos os protocolos.

#### R3 — ponto de saída via R1 (duas interfaces)

| Lab | Arquivo |
|-----|---------|
| OSPF | [ospf/config/r3/frr.conf](ospf/config/r3/frr.conf) |
| RIP | [rip/config/r3/frr.conf](rip/config/r3/frr.conf) |

Configura `eth1` (enlace para R1) e `eth2` (enlace para S2). Anuncia as duas sub-redes no protocolo ativo.

> **Diferença:** O arquivo do lab RIP é idêntico ao do lab OSPF — usa `router ospf` em vez de `router rip`.

### 3.4 setup.sh

[setup.sh](setup.sh)

Script de instalação e primeira execução. Verifica e instala Docker e Containerlab caso não estejam presentes, copia os diretórios `ospf/` e `rip/` para `~/ospf-routing-lab` e `~/rip-routing-lab`, sobe os dois labs com `containerlab deploy` e aguarda 45 segundos de convergência antes de exibir as tabelas de roteamento iniciais.

### 3.5 lab.sh

[lab.sh](lab.sh)

Script de operação do laboratório executado a partir do próprio diretório do repositório, sem necessidade de copiar arquivos. Suporta os subcomandos `up`, `down`, `status` e `restart`, gerenciando os dois labs simultaneamente.

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