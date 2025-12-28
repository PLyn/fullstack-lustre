import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/list
import gleam/otp/actor
import gleam/string

pub type PubSubMessage {
  Subscribe(id: process.Pid, client: Subject(String))
  Unsubscribe(id: process.Pid, client: Subject(String))
  Publish(String)
  PublishNewItem(String)
  PublishUpdateItem(String)
  PublishDeleteItem(String)
}

pub fn handle_pubsub_message(
  clients: List(Subject(String)),
  message: PubSubMessage,
) {
  case message {
    Subscribe(id, client) -> {
      io.println(string.inspect(id) <> " client connected")
      actor.continue([client, ..clients])
    }
    Unsubscribe(id, client) -> {
      io.println(string.inspect(id) <> " Client disconnected")
      clients
      |> list.filter(fn(c) { c != client })
      |> actor.continue
    }
    Publish(message) -> {
      publish_message(clients, message)
    }
    PublishNewItem(message) -> {
      publish_message(clients, message)
    }
    PublishUpdateItem(message) -> {
      publish_message(clients, message)
    }
    PublishDeleteItem(message) -> {
      publish_message(clients, message)
    }
  }
}

fn publish_message(clients: List(Subject(String)), message: String) {
  io.println("💬 " <> message)
  list.each(clients, fn(client) { process.send(client, message) })
  actor.continue(clients)
}
