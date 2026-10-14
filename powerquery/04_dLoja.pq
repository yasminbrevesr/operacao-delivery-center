// Consulta: dLoja
// Onde colar: Power Query › selecionar a consulta › Editor Avançado
let
    Lojas = Fonte_Supabase("stores"),
    Hubs = Fonte_Supabase("hubs"),
    // Loja + hub: cidade, UF e coordenadas do hub (usadas no mapa)
    Mescla = Table.NestedJoin(Lojas, {"hub_id"}, Hubs, {"hub_id"}, "hub", JoinKind.LeftOuter),
    Expandir = Table.ExpandTableColumn(Mescla, "hub", {"hub_name", "hub_city", "hub_state", "hub_latitude", "hub_longitude"}),
    // Remove espaços sobrando (887 nomes) e padroniza maiúsculas/minúsculas
    Limpar = Table.TransformColumns(Expandir, {
        {"store_name", Text.Trim, type text},
        {"hub_name", Text.Proper, type text},
        {"hub_city", each Text.Replace(Text.Proper(_), " De ", " de "), type text}}),
    Segmento = Table.AddColumn(Limpar, "Segmento", each
        if [store_segment] = "FOOD" then "Alimentos" else if [store_segment] = "GOOD" then "Bens" else "Não informado", type text),
    Colunas = Table.SelectColumns(Segmento, {"store_id", "store_name", "store_segment", "Segmento", "store_plan_price",
        "hub_id", "hub_name", "hub_city", "hub_state", "hub_latitude", "hub_longitude"}),
    Renomear = Table.RenameColumns(Colunas, {
        {"store_id", "ID Loja"}, {"store_name", "Loja"}, {"store_segment", "Segmento (código)"}, {"store_plan_price", "Preço do Plano"},
        {"hub_id", "ID Hub"}, {"hub_name", "Hub"}, {"hub_city", "Cidade"}, {"hub_state", "UF"},
        {"hub_latitude", "Latitude Hub"}, {"hub_longitude", "Longitude Hub"}})
in
    Renomear
