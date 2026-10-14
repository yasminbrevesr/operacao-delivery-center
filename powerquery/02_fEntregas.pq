// Consulta: fEntregas
// Onde colar: Power Query › selecionar a consulta › Editor Avançado
let
    Entregas = Fonte_Supabase("deliveries"),
    // Traz do pedido: ID, loja e data (para filtrar entregas por período, loja e cidade)
    Pedidos = Table.SelectColumns(Fonte_Supabase("orders"),
        {"order_id", "delivery_order_id", "store_id", "order_created_year", "order_created_month", "order_created_day"}),
    Mescla = Table.NestedJoin(Entregas, {"delivery_order_id"}, Pedidos, {"delivery_order_id"}, "ped", JoinKind.LeftOuter),
    Expandir = Table.ExpandTableColumn(Mescla, "ped", {"order_id", "store_id", "order_created_year", "order_created_month", "order_created_day"}),
    ComData = Table.AddColumn(Expandir, "Data", each
        if [order_created_year] = null then null else #date([order_created_year], [order_created_month], [order_created_day]), type nullable date),
    Distancia = Table.AddColumn(ComData, "Distância (km)", each
        if [delivery_distance_meters] = null or [delivery_distance_meters] > 50000 then null else [delivery_distance_meters] / 1000, type nullable number),
    Status = Table.AddColumn(Distancia, "Status Entrega", each
        if [delivery_status] = "DELIVERED" then "Entregue"
        else if [delivery_status] = "CANCELLED" then "Cancelada"
        else if [delivery_status] = "DELIVERING" then "Em rota" else [delivery_status], type text),
    Colunas = Table.SelectColumns(Status, {"delivery_id", "order_id", "driver_id", "store_id", "Data", "Distância (km)", "Status Entrega"}),
    Renomear = Table.RenameColumns(Colunas, {
        {"delivery_id", "ID Entrega"}, {"order_id", "ID Pedido"}, {"driver_id", "ID Entregador"}, {"store_id", "ID Loja"}})
in
    Renomear
