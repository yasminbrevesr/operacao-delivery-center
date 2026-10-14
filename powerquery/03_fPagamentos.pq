// Consulta: fPagamentos
// Onde colar: Power Query › selecionar a consulta › Editor Avançado
let
    Pagamentos = Fonte_Supabase("payments"),
    Pedidos = Table.SelectColumns(Fonte_Supabase("orders"),
        {"order_id", "payment_order_id", "store_id", "channel_id", "order_created_year", "order_created_month", "order_created_day"}),
    Mescla = Table.NestedJoin(Pagamentos, {"payment_order_id"}, Pedidos, {"payment_order_id"}, "ped", JoinKind.LeftOuter),
    Expandir = Table.ExpandTableColumn(Mescla, "ped", {"order_id", "store_id", "channel_id", "order_created_year", "order_created_month", "order_created_day"}),
    ComData = Table.AddColumn(Expandir, "Data", each
        if [order_created_year] = null then null else #date([order_created_year], [order_created_month], [order_created_day]), type nullable date),
    // Tradução dos 15 meios de pagamento existentes na base
    Mapa = [ONLINE = "Online", VOUCHER = "Voucher", DEBIT = "Débito", MEAL_BENEFIT = "Vale-refeição",
            STORE_DIRECT_PAYMENT = "Pagamento direto na loja", CREDIT = "Crédito", DEBIT_STORE = "Débito na loja",
            VOUCHER_STORE = "Voucher da loja", PAYMENT_LINK = "Link de pagamento", CREDIT_STORE = "Crédito na loja",
            MONEY = "Dinheiro", VOUCHER_DC = "Voucher Delivery Center", INSTALLMENT_CREDIT_STORE = "Crédito parcelado na loja",
            VOUCHER_OL = "Voucher OL", BANK_TRANSFER_DC = "Transferência bancária"],
    Meio = Table.AddColumn(ComData, "Meio de Pagamento", each Record.FieldOrDefault(Mapa, [payment_method], [payment_method]), type text),
    Status = Table.AddColumn(Meio, "Status Pagamento", each
        if [payment_status] = "PAID" then "Pago" else if [payment_status] = "CHARGEBACK" then "Estornado"
        else if [payment_status] = "AWAITING" then "Aguardando" else [payment_status], type text),
    Colunas = Table.SelectColumns(Status, {"payment_id", "order_id", "store_id", "channel_id", "Data",
        "payment_amount", "payment_fee", "Meio de Pagamento", "Status Pagamento"}),
    Renomear = Table.RenameColumns(Colunas, {
        {"payment_id", "ID Pagamento"}, {"order_id", "ID Pedido"}, {"store_id", "ID Loja"}, {"channel_id", "ID Canal"},
        {"payment_amount", "Valor Pagamento"}, {"payment_fee", "Taxa"}}),
    Tipos = Table.TransformColumnTypes(Renomear, {{"Valor Pagamento", Currency.Type}, {"Taxa", Currency.Type}})
in
    Tipos
