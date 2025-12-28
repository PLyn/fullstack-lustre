//// This module contains the code to run the sql queries defined in
//// `./src/sql`.
//// > 🐿️ This module was generated automatically using v4.6.0 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import pog

/// Runs the `insert_item` query
/// defined in `./src/sql/insert_item.sql`.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn insert_item(
  db: pog.Connection,
  arg_1: String,
  arg_2: Int,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "INSERT into item_list(name, quantity) VALUES
($1, $2)
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `item_list` query
/// defined in `./src/sql/item_list.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.6.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ItemListRow {
  ItemListRow(id: Int, name: String, quantity: Int, created_at: String)
}

/// Runs the `item_list` query
/// defined in `./src/sql/item_list.sql`.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn item_list(
  db: pog.Connection,
) -> Result(pog.Returned(ItemListRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.int)
    use name <- decode.field(1, decode.string)
    use quantity <- decode.field(2, decode.int)
    use created_at <- decode.field(3, decode.string)
    decode.success(ItemListRow(id:, name:, quantity:, created_at:))
  }

  "SELECT
    id,
    name,
    quantity,
    created_at::TEXT
FROM item_list
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}
