// Consulta: fPedidos
// Onde colar: Power Query › selecionar a consulta › Editor Avançado
let
    // Formato das colunas order_moment_*: "en-US" para 1/1/2021 12:01:36 AM | "pt-BR" para 01/01/2021 00:01:36
    Cultura = "en-US",
    Pedidos = Fonte_Supabase("orders"),

    // Pagamentos resumidos por pedido: total pago, taxas e se houve estorno (devolução)
    Pagamentos = Table.Group(
        Fonte_Supabase("payments"),
        {"payment_order_id"},
        {
            {"Valor Pago", each List.Sum([payment_amount]), type nullable number},
            {"Taxa Pagamento", each List.Sum([payment_fee]), type nullable number},
            {"Estornado", each if List.Contains([payment_status], "CHARGEBACK") then 1 else 0, Int64.Type}
        }),

    // Entregas resumidas por pedido: quantidade (reentrega) e distância (> 50 km = erro, vira nulo)
    Entregas = Table.Group(
        Fonte_Supabase("deliveries"),
        {"delivery_order_id"},
        {
            {"Qtd Entregas", each Table.RowCount(_), Int64.Type},
            {"Distância (km)", each
                let validas = List.Select([delivery_distance_meters], (d) => d <> null and d <= 50000)
                in if List.IsEmpty(validas) then null else List.Max(validas) / 1000,
             type nullable number}
        }),

    // Mesclagens (1 linha por pedido, não duplica)
    MesclaPag = Table.NestedJoin(Pedidos, {"payment_order_id"}, Pagamentos, {"payment_order_id"}, "pag", JoinKind.LeftOuter),
    ExpPag = Table.ExpandTableColumn(MesclaPag, "pag", {"Valor Pago", "Taxa Pagamento", "Estornado"}),
    MesclaEnt = Table.NestedJoin(ExpPag, {"delivery_order_id"}, Entregas, {"delivery_order_id"}, "ent", JoinKind.LeftOuter),
    ExpEnt = Table.ExpandTableColumn(MesclaEnt, "ent", {"Qtd Entregas", "Distância (km)"}),

    // Data do pedido a partir das colunas numéricas (não depende de formato de texto)
    ComData = Table.AddColumn(ExpEnt, "Data", each #date([order_created_year], [order_created_month], [order_created_day]), type date),

    // Texto -> data/hora
    ParaDataHora = (t) => if t = null or t = "" then null else try DateTime.FromText(t, [Culture = Cultura]) otherwise null,
    Momentos = Table.TransformColumns(ComData, {
        {"order_moment_created", ParaDataHora, type nullable datetime},
        {"order_moment_accepted", ParaDataHora, type nullable datetime},
        {"order_moment_finished", ParaDataHora, type nullable datetime}}),

    // Diferença em minutos (nulo se faltar um dos momentos ou se der negativo)
    Minutos = (inicio, fim) => if inicio = null or fim = null then null
        else let m = Duration.TotalMinutes(fim - inicio) in if m < 0 then null else m,
    AddResposta = Table.AddColumn(Momentos, "Tempo Resposta (min)", each Minutos([order_moment_created], [order_moment_accepted]), type nullable number),
    AddEntrega = Table.AddColumn(AddResposta, "Tempo Entrega (min)", each Minutos([order_moment_created], [order_moment_finished]), type nullable number),

    // Indicadores 0/1
    AddCancelado = Table.AddColumn(AddEntrega, "Cancelado", each
        if [order_status] <> null and Text.Contains(Text.Upper([order_status]), "CANCEL") then 1 else 0, Int64.Type),
    AddReentrega = Table.AddColumn(AddCancelado, "Reentrega", each if [Qtd Entregas] <> null and [Qtd Entregas] > 1 then 1 else 0, Int64.Type),

    Colunas = Table.SelectColumns(AddReentrega, {
        "order_id", "store_id", "channel_id", "Data", "order_created_hour", "order_status", "Cancelado",
        "order_amount", "order_delivery_fee", "order_delivery_cost", "Valor Pago", "Taxa Pagamento", "Estornado",
        "Qtd Entregas", "Reentrega", "Distância (km)",
        "order_moment_created", "order_moment_accepted", "order_moment_finished",
        "Tempo Resposta (min)", "Tempo Entrega (min)",
        "order_metric_production_time", "order_metric_collected_time", "order_metric_walking_time",
        "order_metric_expediton_speed_time", "order_metric_transit_time", "order_metric_cycle_time"}),
    Renomear = Table.RenameColumns(Colunas, {
        {"order_id", "ID Pedido"}, {"store_id", "ID Loja"}, {"channel_id", "ID Canal"},
        {"order_created_hour", "Hora"}, {"order_status", "Status"},
        {"order_amount", "Valor Pedido"}, {"order_delivery_fee", "Frete Cobrado"}, {"order_delivery_cost", "Custo Entrega"},
        {"order_moment_created", "Criado em"}, {"order_moment_accepted", "Aceito em"}, {"order_moment_finished", "Finalizado em"},
        {"order_metric_production_time", "Tempo Produção"}, {"order_metric_collected_time", "Tempo Coleta"},
        {"order_metric_walking_time", "Tempo Caminhada"}, {"order_metric_expediton_speed_time", "Tempo Expedição"},
        {"order_metric_transit_time", "Tempo Trânsito"}, {"order_metric_cycle_time", "Tempo Ciclo (original)"}}),
    Tipos = Table.TransformColumnTypes(Renomear, {
        {"ID Pedido", Int64.Type}, {"ID Loja", Int64.Type}, {"ID Canal", Int64.Type}, {"Hora", Int64.Type},
        {"Valor Pedido", Currency.Type}, {"Frete Cobrado", Currency.Type}, {"Custo Entrega", Currency.Type},
        {"Valor Pago", Currency.Type}, {"Taxa Pagamento", Currency.Type}})
in
    Tipos
