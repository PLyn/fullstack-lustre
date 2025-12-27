import gleam/erlang/process.{type Subject}
import gleam/http.{Get, Post}
import gleam/json
import gleam/otp/actor
import lustre/attribute
import lustre/element
import lustre/element/html
import storail
import wisp.{type Request, type Response}

import database
import pubsub.{type PubSubMessage}
import shared/groceries.{type GroceryItem}

// CONSIDER RENAMING TO ROUTER INSTEAD OF ROUTES

pub fn app_middleware(
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

pub fn handle_request(
  pubsubactor: Subject(PubSubMessage),
  db: storail.Collection(List(GroceryItem)),
  static_directory: String,
  req: Request,
) -> Response {
  use req <- app_middleware(req, static_directory)

  case req.method, wisp.path_segments(req) {
    // API endpoint for saving grocery lists
    Post, ["api", "groceries"] -> database.handle_save_groceries(db, req)

    //API endpoint for sending a message to publish via SSE
    Post, ["api", "sync"] -> {
      let test_json = "{\"name\": \"test\", \"quantity\": 1}"

      actor.send(pubsubactor, pubsub.Publish(test_json))
      wisp.ok()
    }

    // Everything else gets our HTML with hydration data
    Get, _ -> serve_index(db)

    // Fallback for other methods/paths
    _, _ -> wisp.not_found()
  }
}

pub fn serve_index(db: storail.Collection(List(GroceryItem))) -> Response {
  let items = database.fetch_items_from_db(db)

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
