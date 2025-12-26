import gleam/bytes_tree
import gleam/erlang/process.{type Subject}
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/io
import gleam/list
import gleam/otp/actor
import gleam/string_tree
import mist
import wisp
import wisp/wisp_mist

import database
import pubsub
import routes

pub fn main() {
  wisp.configure_logger()
  let secret_key_base = wisp.random_string(64)

  let assert Ok(db) = database.setup_database()

  let assert Ok(priv_directory) = wisp.priv_directory("server")
  let static_directory = priv_directory <> "/static"

  let assert Ok(started) =
    actor.new([])
    |> actor.on_message(pubsub.handle_pubsub_message)
    |> actor.start()

  let pubsubactor = started.data

  let wisp_handler =
    routes.handle_request(pubsubactor, db, static_directory, _)
    |> wisp_mist.handler(secret_key_base)

  let assert Ok(_) =
    mist.new(fn(request) {
      case request.method, request.path {
        http.Get, "/sse" -> serve_sse(request, pubsubactor)
        _, _ -> wisp_handler(request)
      }
    })
    |> mist.port(3000)
    |> mist.start

  process.sleep_forever()
}

fn serve_sse(
  req: request.Request(mist.Connection),
  pubsubactor: Subject(pubsub.PubSubMessage),
) {
  mist.server_sent_events(
    req,
    response.new(200),
    init: fn(_conn) {
      let client = process.new_subject()
      actor.send(pubsubactor, pubsub.Subscribe(client))

      let selector =
        process.new_selector()
        |> process.select(client)

      actor.initialised(client)
      |> actor.selecting(selector)
      |> Ok
    },
    loop: fn(client, message, connection) {
      let event = message |> string_tree.from_string |> mist.event
      case mist.send_event(connection, event) {
        Ok(_) -> actor.continue(client)
        Error(_) -> {
          actor.send(pubsubactor, pubsub.Unsubscribe(client))
          actor.stop()
        }
      }
    },
  )
}
