# Operação do Delivery Center — Relatório Power BI

Relatório em Power BI com a visão operacional do **Delivery Center**, plataforma que liga lojistas e marketplaces por meio de hubs no Brasil, vendendo bens (GOOD) e alimentos (FOOD).

Arquivo do relatório: **`OPERAÇÃO DO DELIVERY CENTER – YASMIN.pbix`**

👉 [Clique aqui para acessar o Dashboard]([https://app.powerbi.com/view?r=eyJrIjoiZjMzNDIyZmItNjg1Ny00NGViLTkwNGUtOWM1MWJlY2E5YjEwIiwidCI6IjY1OWNlMmI4LTA3MTQtNDE5OC04YzM4LWRjOWI2MGFhYmI1NyJ9&pageName=a4bfe55e2f69635d53cb](https://app.powerbi.com/view?r=eyJrIjoiZjM5NTQ2ZDQtMDAyOS00OTZhLTk2MGItYzk3OTMwYmUxZDBhIiwidCI6IjY1OWNlMmI4LTA3MTQtNDE5OC04YzM4LWRjOWI2MGFhYmI1NyJ9))

<img width="2560" height="1440" alt="fundo_00_capa" src="https://github.com/user-attachments/assets/bb3aaed1-3e91-4ba9-a842-76e99c0e17b5" />


---

## Sumário

1. [Arquitetura](#1-arquitetura)
2. [Estrutura do repositório](#2-estrutura-do-repositório)
3. [Fonte de dados na nuvem (Supabase)](#3-fonte-de-dados-na-nuvem-supabase)
4. [Tratamento em Power Query (M)](#4-tratamento-em-power-query-m)
5. [Modelo de dados](#5-modelo-de-dados)
6. [Medidas DAX](#6-medidas-dax)
7. [Páginas do relatório](#7-páginas-do-relatório)
8. [Indicadores e premissas](#8-indicadores-e-premissas)
9. [Qualidade dos dados](#9-qualidade-dos-dados)
10. [Como reproduzir](#10-como-reproduzir)
11. [Limitações conhecidas](#11-limitações-conhecidas)

---

## 1. Arquitetura

```
CSVs originais ──► scripts/subir_supabase.py ──► Supabase (PostgreSQL, região São Paulo)
                                                     │  schema: delivery_center
                                                     ▼
                         Power BI Desktop (driver ODBC do PostgreSQL, modo Importar)
                                                     │
                         Power Query (M): tratamento, colunas e mesclagens
                                                     │
                         Modelo estrela + medidas DAX + 4 páginas + tooltips + bookmarks
```

- Os dados sobem **crus** para o banco; todo o tratamento acontece no Power Query.
- As tabelas ficam num schema próprio (`delivery_center`), fora do `public`, para não serem expostas pela API pública do Supabase.
- O Power BI se conecta com um usuário **somente leitura** (`pbi_leitura`), nunca com o administrador.

## 2. Estrutura do repositório

| Pasta | Conteúdo |
|---|---|
| `docs/` | Guia de montagem completo (Word e PDF): modelo, medidas, formatação e posição de cada visual |
| `scripts/` | Script de carga para o Supabase, modelo do arquivo de credenciais e dependências |
| `powerquery/` | Código M de cada consulta (cole no Editor Avançado) |
| `dax/` | Tabelas calculadas e todas as medidas, organizadas por pasta de exibição |
| `design/fundos/` | Planos de fundo das páginas (PNG 2560 × 1440) e versões editáveis em SVG (Figma) |
| `design/baloes/` | Balões de explicação usados com bookmarks |
| `data/` | Local dos CSVs originais (não versionados — ver `data/README.md`) |

## 3. Fonte de dados na nuvem (Supabase)

**Carga** — `scripts/subir_supabase.py`:

- detecta a codificação de cada arquivo (UTF-8 ou cp1252: `hubs.csv` e `stores.csv` vêm em cp1252);
- descobre o tipo de cada coluna a partir do próprio arquivo;
- recria cada tabela dentro de uma transação e carrega com `COPY` (se falhar, a versão anterior continua no banco);
- confere se a quantidade de linhas no banco bate com a do arquivo;
- cria o usuário somente leitura para o Power BI.

| Tabela | Linhas | Chave primária |
|---|---:|---|
| channels | 40 | channel_id |
| hubs | 32 | hub_id |
| drivers | 4.824 | driver_id |
| stores | 951 | store_id |
| orders | 368.999 | order_id |
| deliveries | 378.843 | delivery_id |
| payments | 400.834 | payment_id |

Tamanho do banco após a carga: **186 MB** (limite do plano gratuito: 500 MB).

**Conexão no Power BI** — função `Fonte_Supabase` (`powerquery/00_Fonte_Supabase.pq`), usando o **driver ODBC oficial do PostgreSQL** (psqlODBC) pelo *Session pooler* do Supabase (IPv4, porta 5432, SSL obrigatório).

> O conector PostgreSQL nativo do Power BI apresentou erros de protocolo com o pooler do Supabase (`Unknown message code`) e estouro do limite de 15 conexões no carregamento paralelo. O driver ODBC resolveu os dois casos. O carregamento paralelo foi limitado a 1 avaliação simultânea.

## 4. Tratamento em Power Query (M)

| Consulta | Tipo | Origem | Principais tratamentos |
|---|---|---|---|
| `Fonte_Supabase` | Função | — | Conexão única; recebe o nome da tabela |
| `fPedidos` | Fato | orders + payments + deliveries | Mescla pagamentos e entregas **resumidos por pedido** (1 linha por pedido); data a partir de ano/mês/dia; conversão dos momentos para data/hora; tempo de entrega e de resposta em minutos; flags `Cancelado`, `Estornado`, `Reentrega`; distância |
| `fEntregas` | Fato | deliveries + orders | Traz loja e data do pedido; distância em km (> 50 km = erro); status em português |
| `fPagamentos` | Fato | payments + orders | Traz loja, canal e data; tradução dos 15 meios de pagamento e dos status |
| `dLoja` | Dimensão | stores + hubs | Mescla loja → hub (cidade, UF, coordenadas); `Text.Trim` nos nomes; segmento em português |
| `dCanal` | Dimensão | channels | Tipo de canal (próprio × marketplace) |
| `dEntregador` | Dimensão | drivers | Modal (moto/bike) e vínculo em português |

## 5. Modelo de dados

Modelo estrela: 3 tabelas fato e 4 dimensões, todos os relacionamentos **1:N com filtro em direção única**. Tabelas fato **não** se relacionam entre si.

| Dimensão (1) | Fatos (N) |
|---|---|
| `dCalendario[Data]` | `fPedidos`, `fEntregas`, `fPagamentos` |
| `dLoja[ID Loja]` | `fPedidos`, `fEntregas`, `fPagamentos` |
| `dCanal[ID Canal]` | `fPedidos`, `fPagamentos` |
| `dEntregador[ID Entregador]` | `fEntregas` |

- `dCalendario` criada em DAX e marcada como tabela de datas.
- Colunas de texto ordenadas por colunas numéricas (`Mês`, `Mês/Ano`, `Dia da Semana`).
- Detecção automática de relacionamentos desativada.
- Tabelas de apoio: `_Medidas` (só medidas) e `Prazo Entrega` (parâmetro de 15 a 120 min).

## 6. Medidas DAX

Todas em `_Medidas`, em 4 pastas de exibição (código completo em `dax/02_medidas.dax`). Todas as divisões usam `DIVIDE`.

| Pasta | Medidas |
|---|---|
| 01 Vendas | Total Pedidos, Pedidos Concluídos, Pedidos Cancelados, Receita Total, Ticket Médio, % Cancelados, Pedidos Devolvidos, % Devolução |
| 02 Operação | Prazo Selecionado (min), Tempo Médio Entrega (min), Pedidos com Tempo, Pedidos no Prazo, Pedidos Fora do Prazo, % no Prazo, Custo Médio Entrega, Tempo Médio Resposta (min), Tempo Médio Produção, Tempo Médio Coleta, Tempo Médio Trânsito |
| 03 Parceiros | Lojas Parceiras, Cidades Atendidas, Hubs Ativos, Pedidos por Loja |
| 04 Adicionais | Crescimento Pedidos (MoM), Resultado do Frete, Custo por km, Distância Média (km), Taxa de Reentrega, Valor Pagamentos, Entregas Realizadas, Entregadores Ativos |

## 7. Páginas do relatório

| Página | Conteúdo |
|---|---|
| **01 · Desempenho de Vendas** | KPIs (pedidos, receita, ticket, % cancelados, % devolução), pedidos e receita ao longo do tempo, pedidos por tipo, por dia da semana e por status. Balão de explicação via bookmark. |
| **02 · Operação de Entregas** | KPIs (tempo de entrega, % no prazo, custo médio, tempo de resposta), evolução do tempo de entrega, entregas no prazo, tempo por etapa do pedido e desempenho por hub. Segmentação do prazo. |
| **03 · Parceiros e Demanda** | KPIs da rede de parceiros, mapa de demanda por hub, cidades com maior demanda e top lojas. |
| **04 · Análises Estratégicas** | Indicadores adicionais, **árvore de decomposição da receita** (canal › segmento › cidade › hub), pico de demanda dia × hora, meios de pagamento e frota. |
| Tooltips | Páginas de dica de ferramenta com KPIs e mini gráfico. |

**Padrão visual**

| Uso | Cor |
|---|---|
| Cards | `#53A1A5` |
| Barras, colunas e card de destaque | `#366C6E` |
| Realce claro | `#A8ECEF` |
| Linhas e grades | `#82C7CC` |
| Títulos | `#4A9A9C` |

Fundos desenhados em SVG (editáveis no Figma) e exportados em PNG 2560 × 1440.

## 8. Indicadores e premissas

| # | Indicador | Medida | Regra adotada | Motivo |
|---:|---|---|---|---|
| 1 | Total de pedidos por período | Total Pedidos | Contagem de pedidos por data de criação | — |
| 2 | Pedidos por tipo | Total Pedidos × `dLoja[Segmento]` | Alimentos (FOOD) × Bens (GOOD) | — |
| 3 | Receita total | Receita Total | Soma do valor dos pedidos **não cancelados** | Pedido cancelado não gera receita |
| 4 | Ticket médio | Ticket Médio | Receita ÷ pedidos concluídos | — |
| 5 | Tempo médio de entrega | Tempo Médio Entrega (min) | Finalizado em − Criado em | Momento de entrega vazio em 95% dos pedidos |
| 6 | % entregue no prazo | % no Prazo | Tempo de entrega ≤ prazo do parâmetro (padrão 60 min) | A base não tem prazo/SLA |
| 7 | % cancelados | % Cancelados | Status contendo "CANCEL" | Funciona para qualquer grafia |
| 8 | Lojas parceiras | Lojas Parceiras | Lojas com pedido no período | — |
| 9 | % devolução | % Devolução | Pedidos com pagamento estornado (CHARGEBACK) | A base não tem campo de devolução |
| 10 | Custo médio de entrega | Custo Médio Entrega | Média do custo, ignorando vazios | 7.205 pedidos sem custo |
| 11 | Pedidos por dia da semana | Total Pedidos × `dCalendario[Dia da Semana]` | — | — |
| 12 | Cidades com maior demanda | Total Pedidos × `dLoja[Cidade]` | Cidade do hub da loja | — |
| 13 | Produtos mais pedidos | Total Pedidos × `dLoja[Loja]` (Top N) | Ranking de **lojas** | A base não tem produtos/itens |
| 14 | Tempo médio de resposta | Tempo Médio Resposta (min) | Aceito em − Criado em | Aceite da loja = primeira resposta ao pedido |

## 9. Qualidade dos dados

- **Distâncias:** 509 entregas acima de 50 km (até 7.251 km) foram consideradas erro e descartadas; sem isso a distância média sobe de ~2,8 km para ~10 km.
- **Lojas:** 887 de 951 nomes com espaço sobrando no fim (tratado com `Text.Trim`); 951 lojas para 480 nomes distintos (redes em vários hubs aparecem somadas no ranking).
- **Entregas:** 15.886 sem entregador; 73 sem distância; 18.724 pedidos com mais de uma entrega.
- **Pagamentos:** 175 sem taxa; 48.818 pedidos com mais de um pagamento (resumidos por pedido antes da mesclagem, para não duplicar).
- **Período:** a base cobre pedidos de janeiro a abril de 2021.

## 10. Como reproduzir

1. **Banco:** crie um projeto no Supabase e copie os dados do *Session pooler* (botão **Connect**).
2. **Carga:**
   ```bash
   cd scripts
   pip install -r requirements.txt
   copy .env.example .env      # preencha host, usuário e senhas
   python subir_supabase.py
   ```
   Coloque os CSVs em `data/` e informe `CSV_DIR=../data` no `.env`.
3. **Certificado:** baixe o certificado do Supabase (**Project Settings › Database › SSL Configuration**) e instale em *Usuário Atual › Autoridades de Certificação Raiz Confiáveis*.
4. **Driver:** instale o driver ODBC do PostgreSQL (`psqlodbc_x64.msi`, em postgresql.org/ftp/odbc/releases).
5. **Power BI:** abra o `.pbix`, ajuste o servidor em `Fonte_Supabase` se necessário e informe as credenciais do usuário de leitura (`pbi_leitura.<ref-do-projeto>`) em **Banco de dados**.
6. Para montar do zero, siga `docs/Guia de Montagem - Delivery Center.pdf`.

## 11. Limitações conhecidas

- O plano gratuito do Supabase pausa o projeto após 7 dias sem uso; é preciso reativá-lo no painel antes de atualizar o relatório.
- Quem abrir o `.pbix` vê os dados importados normalmente. Para **atualizar**, precisa das credenciais, do certificado e do driver ODBC instalados.
- Indicadores 5, 6, 9, 13 e 14 dependem das premissas da seção 8, por falta de campo direto na base.
