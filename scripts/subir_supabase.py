"""
Carga dos CSVs do Delivery Center para o Supabase (Postgres).

O que faz, para cada tabela:
  1. lê o CSV e descobre sozinho a codificação (UTF-8 ou cp1252) e o tipo de cada coluna;
  2. recria a tabela no schema configurado e carrega os dados com COPY;
  3. confere se a quantidade de linhas no banco bate com a do arquivo.

Os dados sobem crus (sem limpeza), de propósito: o tratamento fica no Power Query.
Pode ser executado quantas vezes for preciso: cada tabela é recriada dentro de uma
transação, então se algo falhar a versão anterior da tabela continua no banco.

Uso:
    pip install psycopg2-binary
    python subir_supabase.py                 # sobe todas as tabelas
    python subir_supabase.py orders stores   # sobe só as tabelas informadas

As credenciais ficam no arquivo .env (mesma pasta deste script). Veja .env.example.
"""

import csv
import logging
import os
import re
import sys
import time
from pathlib import Path

import psycopg2
from psycopg2 import sql

PASTA = Path(__file__).resolve().parent

# tabela -> coluna usada como chave primária (só é aplicada se existir e não tiver repetição)
TABELAS = {
    "channels": "channel_id",
    "hubs": "hub_id",
    "drivers": "driver_id",
    "stores": "store_id",
    "orders": "order_id",
    "deliveries": "delivery_id",
    "payments": "payment_id",
}

RE_INTEIRO = re.compile(r"-?\d+")
RE_DECIMAL = re.compile(r"-?\d+\.\d+")
INT4_MAX = 2_147_483_647
INT8_MAX = 9_223_372_036_854_775_807

log = logging.getLogger("carga")


# --------------------------------------------------------------------------- configuração
def ler_env(caminho):
    """Lê um arquivo .env simples (CHAVE=valor). Variáveis já definidas no sistema têm prioridade."""
    if not caminho.exists():
        return
    for linha in caminho.read_text(encoding="utf-8-sig").splitlines():
        linha = linha.strip()
        if not linha or linha.startswith("#") or "=" not in linha:
            continue
        chave, valor = linha.split("=", 1)
        valor = valor.strip()
        if len(valor) >= 2 and valor[0] == valor[-1] and valor[0] in "\"'":
            valor = valor[1:-1]
        os.environ.setdefault(chave.strip(), valor)


def config():
    ler_env(PASTA / ".env")
    faltando = [k for k in ("SUPABASE_HOST", "SUPABASE_USER", "SUPABASE_PASSWORD") if not os.environ.get(k)]
    if faltando:
        sys.exit(f"ERRO: faltam no arquivo .env: {', '.join(faltando)} (veja .env.example)")
    return {
        "host": os.environ["SUPABASE_HOST"],
        "port": int(os.environ.get("SUPABASE_PORT") or 5432),
        "dbname": os.environ.get("SUPABASE_DB") or "postgres",
        "user": os.environ["SUPABASE_USER"],
        "password": os.environ["SUPABASE_PASSWORD"],
        "sslmode": os.environ.get("SUPABASE_SSLMODE") or "require",
        "schema": os.environ.get("DB_SCHEMA") or "delivery_center",
        "csv_dir": os.environ.get("CSV_DIR") or "",
        "pbi_user": os.environ.get("PBI_USER") or "",
        "pbi_password": os.environ.get("PBI_PASSWORD") or "",
    }


def achar_csv(tabela, csv_dir):
    """Procura <tabela>.csv em CSV_DIR; sem CSV_DIR, na pasta do script e na pasta acima."""
    pastas = [Path(csv_dir)] if csv_dir else [PASTA, PASTA.parent]
    for pasta in pastas:
        arquivo = pasta / f"{tabela}.csv"
        if arquivo.is_file():
            return arquivo
    return None


# --------------------------------------------------------------------------- análise do CSV
def _analisar(arquivo, encoding, pk):
    with open(arquivo, encoding=encoding, newline="") as f:
        leitor = csv.reader(f)
        colunas = [c.strip() for c in next(leitor)]
        if not all(colunas) or len(set(colunas)) != len(colunas):
            raise ValueError(f"cabeçalho inválido (coluna vazia ou repetida): {colunas}")
        n = len(colunas)
        so_inteiro = [True] * n      # todos os valores preenchidos são inteiros
        so_numero = [True] * n       # todos os valores preenchidos são inteiros ou decimais
        maior = [0] * n              # maior valor absoluto (para escolher integer/bigint)
        preenchidos = [0] * n
        i_pk = colunas.index(pk) if pk in colunas else -1
        vistos, pk_ok = set(), i_pk >= 0
        linhas = 0
        for linha in leitor:
            if len(linha) != n:
                raise ValueError(f"linha {leitor.line_num}: esperadas {n} colunas, encontradas {len(linha)}")
            linhas += 1
            for i, v in enumerate(linha):
                if v == "":
                    continue
                preenchidos[i] += 1
                if not so_numero[i]:
                    continue
                if so_inteiro[i] and RE_INTEIRO.fullmatch(v):
                    digitos = v.lstrip("-")
                    if len(digitos) > 1 and digitos[0] == "0":   # zero à esquerda: é código, não número
                        so_inteiro[i] = so_numero[i] = False
                    else:
                        maior[i] = max(maior[i], int(digitos))
                elif RE_DECIMAL.fullmatch(v) or RE_INTEIRO.fullmatch(v):
                    so_inteiro[i] = False
                else:
                    so_inteiro[i] = so_numero[i] = False
            if pk_ok:
                chave = linha[i_pk]
                if chave == "" or chave in vistos:
                    pk_ok = False
                    vistos = set()
                else:
                    vistos.add(chave)

    tipos = []
    for i in range(n):
        if preenchidos[i] == 0 or not so_numero[i]:
            tipos.append("text")
        elif not so_inteiro[i] or maior[i] > INT8_MAX:
            tipos.append("numeric")
        else:
            tipos.append("integer" if maior[i] <= INT4_MAX else "bigint")
    return {
        "arquivo": arquivo, "encoding": encoding, "colunas": colunas, "tipos": tipos,
        "linhas": linhas, "pk": pk if pk_ok else None,
        "nulos": {c: linhas - preenchidos[i] for i, c in enumerate(colunas) if preenchidos[i] < linhas},
    }


def analisar(arquivo, pk):
    """Tenta UTF-8; se o arquivo não for UTF-8 válido, usa cp1252 (padrão do Excel no Windows)."""
    for encoding in ("utf-8-sig", "cp1252", "latin-1"):
        try:
            return _analisar(arquivo, encoding, pk)
        except UnicodeDecodeError:
            continue
    raise ValueError("não foi possível identificar a codificação do arquivo")


# --------------------------------------------------------------------------- banco
def conectar(cfg, tentativas=3):
    for tentativa in range(1, tentativas + 1):
        try:
            conn = psycopg2.connect(
                host=cfg["host"], port=cfg["port"], dbname=cfg["dbname"],
                user=cfg["user"], password=cfg["password"], sslmode=cfg["sslmode"],
                connect_timeout=20, keepalives=1, keepalives_idle=30, application_name="carga_delivery_center",
            )
            conn.set_client_encoding("UTF8")
            with conn, conn.cursor() as cur:
                cur.execute("set statement_timeout = 0")   # cargas grandes passam do limite padrão
            return conn
        except psycopg2.OperationalError as e:
            msg = str(e).strip()
            # senha/usuário errado não adianta tentar de novo
            definitivo = any(t in msg.lower() for t in ("password", "authentication", "tenant or user not found"))
            if definitivo or tentativa == tentativas:
                sys.exit(f"ERRO ao conectar no banco: {msg}")
            espera = 5 * tentativa
            log.warning("falha de conexão (tentativa %s/%s): %s - nova tentativa em %ss", tentativa, tentativas, msg, espera)
            time.sleep(espera)


def carregar(conn, schema, tabela, info):
    """Recria a tabela e carrega o CSV. Tudo em uma transação: se falhar, nada muda no banco."""
    alvo = sql.Identifier(schema, tabela)
    colunas = [sql.Identifier(c) for c in info["colunas"]]
    definicao = sql.SQL(", ").join(
        sql.SQL("{} {}").format(c, sql.SQL(t)) for c, t in zip(colunas, info["tipos"])
    )
    with conn, conn.cursor() as cur:
        cur.execute(sql.SQL("drop table if exists {}").format(alvo))
        cur.execute(sql.SQL("create table {} ({})").format(alvo, definicao))
        copy = sql.SQL("copy {} ({}) from stdin with (format csv, header true)").format(
            alvo, sql.SQL(", ").join(colunas)
        )
        # campo vazio no CSV vira NULL no banco (padrão do COPY em formato csv)
        with open(info["arquivo"], encoding=info["encoding"], newline="") as f:
            cur.copy_expert(copy.as_string(conn), f)
        if info["pk"]:
            cur.execute(sql.SQL("alter table {} add primary key ({})").format(alvo, sql.Identifier(info["pk"])))
        cur.execute(sql.SQL("select count(*) from {}").format(alvo))
        no_banco = cur.fetchone()[0]
        if no_banco != info["linhas"]:
            raise RuntimeError(f"contagem não confere: {info['linhas']} no CSV, {no_banco} no banco")
    return no_banco


def usuario_leitura(conn, schema, usuario, senha):
    """Cria (ou atualiza) um usuário que só consegue ler o schema. É o que vai no Power BI."""
    u, s = sql.Identifier(usuario), sql.Identifier(schema)
    with conn, conn.cursor() as cur:
        cur.execute("select 1 from pg_roles where rolname = %s", (usuario,))
        comando = "alter role {} with login password {}" if cur.fetchone() else "create role {} with login password {}"
        cur.execute(sql.SQL(comando).format(u, sql.Literal(senha)))
        cur.execute(sql.SQL("grant usage on schema {} to {}").format(s, u))
        cur.execute(sql.SQL("grant select on all tables in schema {} to {}").format(s, u))
        cur.execute(sql.SQL("alter default privileges in schema {} grant select on tables to {}").format(s, u))


# --------------------------------------------------------------------------- execução
def main():
    logging.basicConfig(
        level=logging.INFO, format="%(asctime)s %(levelname)-7s %(message)s", datefmt="%H:%M:%S",
        handlers=[logging.StreamHandler(sys.stdout),
                  logging.FileHandler(PASTA / "subir_supabase.log", encoding="utf-8")],
    )
    cfg = config()
    pedidas = sys.argv[1:] or list(TABELAS)
    desconhecidas = [t for t in pedidas if t not in TABELAS]
    if desconhecidas:
        sys.exit(f"ERRO: tabela(s) desconhecida(s): {', '.join(desconhecidas)}. Opções: {', '.join(TABELAS)}")

    conn = conectar(cfg)
    log.info("conectado em %s (banco %s, schema %s)", cfg["host"], cfg["dbname"], cfg["schema"])
    with conn, conn.cursor() as cur:
        cur.execute(sql.SQL("create schema if not exists {}").format(sql.Identifier(cfg["schema"])))

    resultado = {}
    for tabela in pedidas:
        arquivo = achar_csv(tabela, cfg["csv_dir"])
        if not arquivo:
            log.warning("%-10s arquivo %s.csv não encontrado - tabela ignorada", tabela, tabela)
            resultado[tabela] = "CSV NÃO ENCONTRADO"
            continue
        try:
            inicio = time.time()
            info = analisar(arquivo, TABELAS[tabela])
            log.info("%-10s %s | %s | %s linhas | %s", tabela, arquivo, info["encoding"], info["linhas"],
                     ", ".join(f"{c} {t}" for c, t in zip(info["colunas"], info["tipos"])))
            if info["nulos"]:
                log.info("%-10s vazios por coluna: %s", tabela, info["nulos"])
            if not info["pk"]:
                log.warning("%-10s sem chave primária (%s ausente, vazia ou repetida)", tabela, TABELAS[tabela])
            linhas = carregar(conn, cfg["schema"], tabela, info)
            log.info("%-10s OK - %s linhas carregadas em %.1fs", tabela, linhas, time.time() - inicio)
            resultado[tabela] = f"OK ({linhas} linhas)"
        except Exception as e:   # uma tabela com problema não impede as outras
            if conn.closed:
                conn = conectar(cfg)
            log.error("%-10s FALHOU: %s", tabela, str(e).strip())
            resultado[tabela] = "FALHOU"

    if cfg["pbi_user"] and cfg["pbi_password"]:
        try:
            usuario_leitura(conn, cfg["schema"], cfg["pbi_user"], cfg["pbi_password"])
            log.info("usuário somente leitura '%s' pronto para o Power BI", cfg["pbi_user"])
        except Exception as e:
            log.error("não foi possível criar o usuário de leitura: %s", str(e).strip())
            resultado["usuário de leitura"] = "FALHOU"
    else:
        log.warning("PBI_USER/PBI_PASSWORD não definidos - usuário somente leitura não foi criado")

    with conn, conn.cursor() as cur:
        cur.execute("select pg_size_pretty(pg_database_size(current_database()))")
        tamanho = cur.fetchone()[0]
    conn.close()

    log.info("---------------- resumo ----------------")
    for nome, status in resultado.items():
        log.info("%-20s %s", nome, status)
    log.info("tamanho do banco: %s (limite do plano Free: 500 MB)", tamanho)
    if any(not s.startswith("OK") for s in resultado.values()):
        sys.exit(1)


if __name__ == "__main__":
    main()
