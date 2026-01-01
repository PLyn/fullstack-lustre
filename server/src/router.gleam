import gleam/dynamic/decode
import gleam/http.{Get, Post}
import gleam/json
import lustre/attribute
import lustre/element
import lustre/element/html
import wisp.{type Request, type Response}

import db
import shared/groceries

pub fn handle_request(
  ctx: db.Context,
  static_directory: String,
  req: Request,
) -> Response {
  use req <- app_middleware(req, static_directory)

  case req.method, wisp.path_segments(req) {
    //API endpoint for inserting db item and publishing via SSE
    Post, ["api", "sync"] -> insert_publish_item(ctx, req)

    // Everything else gets our HTML with hydration data
    Get, _ -> serve_index(ctx)

    // Fallback for other methods/paths
    _, _ -> wisp.not_found()
  }
}

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

pub fn serve_index(ctx: db.Context) -> Response {
  let items = db.fetch_items(ctx)

  let html =
    html.html([], [
      html.head([], [
        html.title([], "Grocery List"),
        html.link([
          attribute.rel("stylesheet"),
          attribute.href("/static/styles.css"),
          // Add this line
        ]),
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

fn insert_publish_item(ctx: db.Context, req: Request) -> Response {
  use json <- wisp.require_json(req)

  case decode.run(json, groceries.grocery_item_decoder()) {
    Ok(item) -> {
      case db.insert_publish_item(ctx, item) {
        Ok(_) -> wisp.ok()
        Error(_) -> wisp.internal_server_error()
      }
    }
    Error(_) -> wisp.bad_request("Invalid JSON")
  }
}
