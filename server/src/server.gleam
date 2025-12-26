import gleam/erlang/process
import mist
import wisp
import wisp/wisp_mist

import database
import routes

pub fn main() {
  wisp.configure_logger()
  let secret_key_base = wisp.random_string(64)

  let assert Ok(db) = database.setup_database()

  let assert Ok(priv_directory) = wisp.priv_directory("server")
  let static_directory = priv_directory <> "/static"

  let assert Ok(_) =
    routes.handle_request(db, static_directory, _)
    |> wisp_mist.handler(secret_key_base)
    |> mist.new
    |> mist.port(3000)
    |> mist.start

  process.sleep_forever()
}
