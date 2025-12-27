//// This module contains the code to run the sql queries defined in
//// `./src/sql`.
//// > 🐿️ This module was generated automatically using v4.6.0 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import pog

/// A row you get from running the `get_test` query
/// defined in `./src/sql/get_test.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.6.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type GetTestRow {
  GetTestRow(id: Int, created_at: String)
}

/// Runs the `get_test` query
/// defined in `./src/sql/get_test.sql`.
///
/// > 🐿️ This function was generated automatically using v4.6.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn get_test(
  db: pog.Connection,
) -> Result(pog.Returned(GetTestRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.int)
    use created_at <- decode.field(1, decode.string)
    decode.success(GetTestRow(id:, created_at:))
  }

  "SELECT
    id,
    created_at::TEXT
FROM
    test
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}
