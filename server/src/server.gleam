import envoy
import gleam/bytes_tree
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/io
import gleam/list
import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import gleam/string_tree
import mist
import pog
import wisp
import wisp/wisp_mist

import database
import pubsub
import routes
import sql

pub fn main() {
  wisp.configure_logger()
  let secret_key_base = wisp.random_string(64)

  let assert Ok(db_url) = envoy.get("DATABASE_URL")
  echo db_url

  let db_pool_name = process.new_name("db_pool")

  let assert Ok(config) = pog.url_config(db_pool_name, db_url)
  echo config

  // make a child spec from the config for your pool
  let pool_child_spec =
    config
    |> pog.ip_version(pog.Ipv6)
    |> pog.ssl(pog.SslVerified)
    |> pog.pool_size(15)
    |> pog.supervised

  // start a supervisor with the child spec
  let _ =
    supervisor.new(supervisor.RestForOne)
    |> supervisor.add(pool_child_spec)
    |> supervisor.start

  // connect
  let db = pog.named_connection(db_pool_name)
  echo db

  // the query SQL
  let query_sql = "SELECT id, created_at::TEXT FROM test"
  // how to decode the results into gleam values
  let row_decoder = {
    use id <- decode.field(0, decode.int)
    use created_at <- decode.field(1, decode.string)
    decode.success(#(id, created_at))
  }
  // build a query from the sql, a parameter, and a decoder. run it.
  //let id_param = pog.int(1)
  let assert Ok(data) =
    pog.query(query_sql)
    //|> pog.parameter(id_param)
    |> pog.returning(row_decoder)
    |> pog.execute(db)

  // dig into the result data :
  assert data.count == 1
  assert data.rows == [#(1, "2025-12-27 11:45:44.859818+00")]
  echo data

  let assert Ok(data) = sql.get_test(db)
  echo data.rows

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
