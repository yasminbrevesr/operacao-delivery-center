// Consulta: dCanal
// Onde colar: Power Query › selecionar a consulta › Editor Avançado
let
    Origem = Fonte_Supabase("channels"),
    Tipo = Table.AddColumn(Origem, "Tipo de Canal", each if [channel_type] = "MARKETPLACE" then "Marketplace" else "Canal próprio", type text),
    Colunas = Table.SelectColumns(Tipo, {"channel_id", "channel_name", "Tipo de Canal"}),
    Renomear = Table.RenameColumns(Colunas, {{"channel_id", "ID Canal"}, {"channel_name", "Canal"}})
in
    Renomear
