import gleam/dynamic/decode
import gleam/result
import wisp.{type Request, type Response}

import shared/groceries.{type GroceryItem}
import storail

pub fn setup_database() -> Result(storail.Collection(List(GroceryItem)), Nil) {
  let config = storail.Config(storage_path: "./data")

  let items =
    storail.Collection(
      name: "grocery_list",
      to_json: groceries.grocery_list_to_json,
      decoder: groceries.grocery_list_decoder(),
      config:,
    )

  Ok(items)
}

pub fn grocery_list_key(
  db: storail.Collection(List(GroceryItem)),
) -> storail.Key(List(GroceryItem)) {
  // In a real application, you would probably store items as individual
  // documents, or use a database like PostgreSQL instead.
  storail.key(db, "grocery_list")
}

pub fn save_items_to_db(
  db: storail.Collection(List(GroceryItem)),
  items: List(GroceryItem),
) -> Result(Nil, storail.StorailError) {
  storail.write(grocery_list_key(db), items)
}

pub fn fetch_items_from_db(
  db: storail.Collection(List(GroceryItem)),
) -> List(GroceryItem) {
  storail.read(grocery_list_key(db))
  |> result.unwrap([])
}

pub fn handle_save_groceries(
  db: storail.Collection(List(GroceryItem)),
  req: Request,
) -> Response {
  use json <- wisp.require_json(req)

  case decode.run(json, groceries.grocery_list_decoder()) {
    Ok(items) ->
      case save_items_to_db(db, items) {
        Ok(_) -> wisp.ok()
        Error(_) -> wisp.internal_server_error()
      }
    Error(_) -> wisp.bad_request("Request failed")
  }
}
