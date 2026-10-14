// Consulta: dEntregador
// Onde colar: Power Query › selecionar a consulta › Editor Avançado
let
    Origem = Fonte_Supabase("drivers"),
    Modal = Table.AddColumn(Origem, "Modal", each if [driver_modal] = "MOTOBOY" then "Moto" else if [driver_modal] = "BIKER" then "Bike" else [driver_modal], type text),
    Vinculo = Table.AddColumn(Modal, "Vínculo", each
        if [driver_type] = "FREELANCE" then "Freelancer" else if [driver_type] = "LOGISTIC OPERATOR" then "Operador logístico" else [driver_type], type text),
    Colunas = Table.SelectColumns(Vinculo, {"driver_id", "Modal", "Vínculo"}),
    Renomear = Table.RenameColumns(Colunas, {{"driver_id", "ID Entregador"}})
in
    Renomear
