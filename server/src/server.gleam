import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/otp/actor
import gleam/string_tree
import mist
import wisp
import wisp/wisp_mist

import db
import pubsub
import router

pub fn main() {
  wisp.configure_logger()
  let secret_key_base = wisp.random_string(64)

  let assert Ok(priv_directory) = wisp.priv_directory("server")
  let static_directory = priv_directory <> "/static"

  let db_ctx = db.setup_db_pubsub()

  let wisp_handler =
    router.handle_request(db_ctx, static_directory, _)
    |> wisp_mist.handler(secret_key_base)

  let assert Ok(_) =
    mist.new(fn(request) {
      case request.method, request.path {
        http.Get, "/sse" -> serve_sse(request, db_ctx)
        _, _ -> wisp_handler(request)
      }
    })
    |> mist.port(3000)
    |> mist.start

  process.sleep_forever()
}

fn serve_sse(req: request.Request(mist.Connection), ctx: db.Context) {
  mist.server_sent_events(
    req,
    response.new(200),
    init: fn(_conn) {
      let client = process.new_subject()
      let assert Ok(pid) = process.subject_owner(client)
      actor.send(ctx.pubsub, pubsub.Subscribe(pid, client))

      let selector =
        process.new_selector()
        |> process.select(client)

      actor.initialised(client)
      |> actor.selecting(selector)
      |> Ok
    },
    loop: fn(client, message, connection) {
      let assert Ok(pid) = process.subject_owner(client)
      let event = message |> string_tree.from_string |> mist.event
      case mist.send_event(connection, event) {
        Ok(_) -> actor.continue(client)
        Error(_) -> {
          actor.send(ctx.pubsub, pubsub.Unsubscribe(pid, client))
          actor.stop()
        }
      }
    },
  )
}
