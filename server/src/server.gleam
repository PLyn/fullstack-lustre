import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http.{Get, Post}
import gleam/json
import gleam/result
import lustre/attribute
import lustre/element
import lustre/element/html
import mist
import storail
import wisp.{type Request, type Response}
import wisp/wisp_mist

import shared/groceries.{type GroceryItem}

pub fn main() {
  wisp.configure_logger()
  let secret_key_base = wisp.random_string(64)

  // Set up our database
  let assert Ok(db) = setup_database()

  let assert Ok(priv_directory) = wisp.priv_directory("server")
  let static_directory = priv_directory <> "/static"

  let assert Ok(_) =
    handle_request(db, static_directory, _)
    |> wisp_mist.handler(secret_key_base)
    |> mist.new
    |> mist.port(3000)
    |> mist.start

  process.sleep_forever()
}

// REQUEST HANDLERS ------------------------------------------------------------

fn app_middleware(
  req: Request,
  static_directory: String,
  next: fn(Request) -> Response,
) -> Response {
  let req = wisp.method_override(req)
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use req <- wisp.handle_head(req)
  use <- wisp.serve_static(req, under: "/static", from: static_directory)

  next(req)
}

fn handle_request(
  db: storail.Collection(List(GroceryItem)),
  static_directory: String,
  req: Request,
) -> Response {
  use req <- app_middleware(req, static_directory)

  case req.method, wisp.path_segments(req) {
    // API endpoint for saving grocery lists
    Post, ["api", "groceries"] -> handle_save_groceries(db, req)

    // Everything else gets our HTML with hydration data
    Get, _ -> serve_index(db)

    // Fallback for other methods/paths
    _, _ -> wisp.not_found()
  }
}

fn serve_index(db: storail.Collection(List(GroceryItem))) -> Response {
  // NEW: Fetch grocery items from database
  let items = fetch_items_from_db(db)

  let html =
    html.html([], [
      html.head([], [
        html.title([], "Grocery List"),
        html.script(
          [attribute.type_("module"), attribute.src("/static/client.js")],
          "",
        ),
      ]),
      // NEW: include a script tag with our initial grocery list
      html.script(
        [attribute.type_("application/json"), attribute.id("model")],
        json.to_string(groceries.grocery_list_to_json(items)),
      ),
      html.body([], [html.div([attribute.id("app")], [])]),
    ])

  html
  |> element.to_document_string
  |> wisp.html_response(200)
}

fn fetch_items_from_db(
  db: storail.Collection(List(GroceryItem)),
) -> List(GroceryItem) {
  storail.read(grocery_list_key(db))
  |> result.unwrap([])
}

fn handle_save_groceries(
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

// DATABASE --------------------------------------------------------------------

fn setup_database() -> Result(storail.Collection(List(GroceryItem)), Nil) {
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

fn grocery_list_key(
  db: storail.Collection(List(GroceryItem)),
) -> storail.Key(List(GroceryItem)) {
  // In a real application, you would probably store items as individual
  // documents, or use a database like PostgreSQL instead.
  storail.key(db, "grocery_list")
}

fn save_items_to_db(
  db: storail.Collection(List(GroceryItem)),
  items: List(GroceryItem),
) -> Result(Nil, storail.StorailError) {
  storail.write(grocery_list_key(db), items)
}
