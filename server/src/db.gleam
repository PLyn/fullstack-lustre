import envoy
import gleam/erlang/process.{type Name, type Subject}
import gleam/json
import gleam/list
import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import gleam/result
import pog
import sql

import pubsub
import shared/groceries.{type GroceryItem}

pub type Context {
  Context(pool: Name(pog.Message), pubsub: Subject(pubsub.PubSubMessage))
}

pub fn setup_db_pubsub() -> Context {
  let pool_name = process.new_name("db_pool")

  let assert Ok(db_config) = read_connection_uri(pool_name)
  let assert Ok(_) = start_application_supervisor(db_config)

  //setup pubsub
  let assert Ok(started) =
    actor.new([])
    |> actor.on_message(pubsub.handle_pubsub_message)
    |> actor.start()

  Context(pool: pool_name, pubsub: started.data)
}

// Helper to get a connection from the context
pub fn get_connection(ctx: Context) -> pog.Connection {
  pog.named_connection(ctx.pool)
}

fn read_connection_uri(pool_name: Name(pog.Message)) -> Result(pog.Config, Nil) {
  use database_url <- result.try(envoy.get("DATABASE_URL"))
  pog.url_config(pool_name, database_url)
}

fn start_application_supervisor(db_default_config: pog.Config) {
  let pool_child =
    db_default_config
    |> pog.ip_version(pog.Ipv6)
    |> pog.ssl(pog.SslVerified)
    |> pog.pool_size(15)
    |> pog.supervised

  supervisor.new(supervisor.RestForOne)
  |> supervisor.add(pool_child)
  |> supervisor.start
}

pub fn fetch_items(ctx: Context) -> List(GroceryItem) {
  let db = get_connection(ctx)
  let assert Ok(pog.Returned(_, item_list)) = sql.item_list(db)
  list.map(item_list, fn(row) {
    groceries.GroceryItem(name: row.name, quantity: row.quantity)
  })
}

pub fn insert_item(
  ctx: Context,
  item: GroceryItem,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let db = get_connection(ctx)
  sql.insert_item(db, item.name, item.quantity)
}

pub fn insert_publish_item(
  ctx: Context,
  item: GroceryItem,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let db = get_connection(ctx)
  case sql.insert_item(db, item.name, item.quantity) {
    Ok(ok) -> {
      let item_json = groceries.grocery_item_to_json(item)
      actor.send(ctx.pubsub, pubsub.Publish(json.to_string(item_json)))
      Ok(ok)
    }
    Error(err) -> Error(err)
  }
}
