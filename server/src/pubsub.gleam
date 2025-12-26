import gleam/bytes_tree
import gleam/erlang/process.{type Subject}
import gleam/http/response
import gleam/io
import gleam/list
import gleam/otp/actor
import mist

pub type PubSubMessage {
  Subscribe(client: Subject(String))
  Unsubscribe(client: Subject(String))
  Publish(String)
}

pub fn handle_pubsub_message(
  clients: List(Subject(String)),
  message: PubSubMessage,
) {
  case message {
    Subscribe(client) -> {
      io.println("➕ Client connected")
      actor.continue([client, ..clients])
    }
    Unsubscribe(client) -> {
      io.println("➖ Client disconnected")
      clients
      |> list.filter(fn(c) { c != client })
      |> actor.continue
    }
    Publish(message) -> {
      io.println("💬 " <> message)
      list.each(clients, fn(client) { process.send(client, message) })
      actor.continue(clients)
    }
  }
}

pub fn new_response(status: Int, body: String) {
  response.new(status)
  |> response.set_body(body |> bytes_tree.from_string |> mist.Bytes)
}
