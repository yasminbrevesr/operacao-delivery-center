# Dados originais

Coloque aqui os CSVs fornecidos no teste (não são versionados no Git):

| Arquivo | Conteúdo | Codificação |
|---|---|---|
| `channels.csv` | Canais de venda | UTF-8 |
| `deliveries.csv` | Entregas | UTF-8 |
| `drivers.csv` | Entregadores | UTF-8 |
| `hubs.csv` | Hubs | cp1252 |
| `orders.csv` | Pedidos | UTF-8 |
| `payments.csv` | Pagamentos | UTF-8 |
| `stores.csv` | Lojistas | cp1252 |

Depois, no `scripts/.env`, informe `CSV_DIR=../data` e rode `python subir_supabase.py`.
