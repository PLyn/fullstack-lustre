import gleam/dynamic/decode
import gleam/json

pub type GroceryItem {
  GroceryItem(name: String, quantity: Int)
}

fn grocery_item_decoder() -> decode.Decoder(GroceryItem) {
  use name <- decode.field("name", decode.string)
  use quantity <- decode.field("quantity", decode.int)
  decode.success(GroceryItem(name:, quantity:))
}

pub fn grocery_list_decoder() -> decode.Decoder(List(GroceryItem)) {
  decode.list(grocery_item_decoder())
}

fn grocery_item_to_json(grocery_item: GroceryItem) -> json.Json {
  let GroceryItem(name:, quantity:) = grocery_item
  json.object([#("name", json.string(name)), #("quantity", json.int(quantity))])
}

pub fn grocery_list_to_json(items: List(GroceryItem)) -> json.Json {
  json.array(items, grocery_item_to_json)
}
