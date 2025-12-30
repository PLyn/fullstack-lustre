import gleam/http/response.{type Response}
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import rsvp
import shared/groceries.{type GroceryItem, GroceryItem}

pub type Model {
  Model(
    items: List(GroceryItem),
    new_item: String,
    saving: Bool,
    error: Option(String),
  )
}

pub type Msg {
  ServerSavedList(Result(Response(String), rsvp.Error))
  ServerSentItem(String)

  UserAddedItem
  UserTypedNewItem(String)
  UserUpdatedQuantity(index: Int, quantity: Int)
}

pub fn init(items: List(GroceryItem)) -> #(Model, Effect(Msg)) {
  let model =
    Model(items: items, new_item: "", saving: False, error: option.None)

  #(model, subscribe_to_sse())
}

fn subscribe_to_sse() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    do_subscribe_to_sse("/sse", fn(data) { dispatch(ServerSentItem(data)) })
  })
}

@external(javascript, "./ffi.mjs", "listen_to_sse")
fn do_subscribe_to_sse(url: String, dispatch: fn(String) -> Nil) -> Nil

pub fn update(msg: Msg, model: Model) -> #(Model, Effect(Msg)) {
  case msg {
    //these two are only here for future reference
    ServerSavedList(Ok(_)) -> #(
      Model(..model, saving: False, error: option.None),
      effect.none(),
    )

    ServerSavedList(Error(_)) -> #(
      Model(..model, saving: False, error: option.Some("Failed to save list")),
      effect.none(),
    )

    ServerSentItem(data) -> {
      let result = json.parse(data, groceries.grocery_item_decoder())
      io.println("message: " <> string.inspect(result))
      case result {
        Ok(item) -> {
          let updated_items = list.append(model.items, [item])
          #(Model(..model, items: updated_items), effect.none())
        }
        Error(_) -> #(model, effect.none())
      }
    }

    UserAddedItem -> {
      case model.new_item {
        "" -> #(model, effect.none())
        name -> {
          let item = GroceryItem(name: name, quantity: 1)
          #(Model(..model, new_item: ""), sync_list(item))
        }
      }
    }

    UserTypedNewItem(text) -> #(Model(..model, new_item: text), effect.none())

    UserUpdatedQuantity(index:, quantity:) -> {
      let updated_items =
        list.index_map(model.items, fn(item, item_index) {
          case item_index == index {
            True -> GroceryItem(..item, quantity:)
            False -> item
          }
        })

      #(Model(..model, items: updated_items), effect.none())
    }
  }
}

fn sync_list(item: GroceryItem) -> Effect(Msg) {
  let body = groceries.grocery_item_to_json(item)
  let url = "/api/sync"

  rsvp.post(url, body, rsvp.expect_ok_response(ServerSavedList))
}

pub fn view(model: Model) -> Element(Msg) {
  let styles = [
    #("max-width", "42ch"),
    #("margin", "0 auto"),
    #("display", "flex"),
    #("flex-direction", "column"),
    #("gap", "1em"),
  ]

  html.div([attribute.styles(styles)], [
    html.h1([], [html.text("Realtime Grocery List")]),
    html.h3([], [html.text("Collaborate with others")]),
    view_grocery_list(model.items),
    view_new_item(model.new_item),
    case model.error {
      option.None -> element.none()
      option.Some(error) ->
        html.div([attribute.style("color", "red")], [html.text(error)])
    },
  ])
}

fn view_new_item(new_item: String) -> Element(Msg) {
  html.div([], [
    html.input([
      attribute.placeholder("Enter item name"),
      attribute.value(new_item),
      event.on_input(UserTypedNewItem),
    ]),
    html.button([event.on_click(UserAddedItem)], [html.text("Add")]),
  ])
}

fn view_grocery_list(items: List(GroceryItem)) -> Element(Msg) {
  case items {
    [] -> html.p([], [html.text("No items in your list yet.")])
    _ -> {
      html.ul(
        [],
        list.index_map(items, fn(item, index) {
          html.li([], [view_grocery_item(item, index)])
        }),
      )
    }
  }
}

fn view_grocery_item(item: GroceryItem, index: Int) -> Element(Msg) {
  html.div([attribute.styles([#("display", "flex"), #("gap", "1em")])], [
    html.span([attribute.style("flex", "1")], [html.text(item.name)]),
    html.input([
      attribute.style("width", "4em"),
      attribute.type_("number"),
      attribute.value(int.to_string(item.quantity)),
      attribute.min("0"),
      event.on_input(fn(value) {
        result.unwrap(int.parse(value), 0)
        |> UserUpdatedQuantity(index, quantity: _)
      }),
    ]),
  ])
}
