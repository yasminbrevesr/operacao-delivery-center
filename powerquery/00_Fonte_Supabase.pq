// Consulta: Fonte_Supabase
// Onde colar: Power Query › selecionar a consulta › Editor Avançado
// Lê uma tabela do schema delivery_center no Supabase via driver ODBC (psqlODBC)
(tabela as text) as table =>
    Odbc.Query(
        "Driver={PostgreSQL Unicode(x64)};Server=aws-1-sa-east-1.pooler.supabase.com;Port=5432;Database=postgres;SSLmode=require",
        "select * from delivery_center." & tabela
    )
