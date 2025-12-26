import gleam/http/response.{type Response}
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/result
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import rsvp
import shared/groceries.{type GroceryItem, GroceryItem}

import gleam/json
import plinth/browser/document
import plinth/browser/element as plinth_element

pub fn main() {
  let initial_items =
    document.query_selector("#model")
    |> result.map(plinth_element.inner_text)
    |> result.try(fn(json) {
      json.parse(json, groceries.grocery_list_decoder())
      |> result.replace_error(Nil)
    })
    |> result.unwrap([])

  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", initial_items)

  Nil
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(
    items: List(GroceryItem),
    new_item: String,
    saving: Bool,
    error: Option(String),
  )
}

fn init(items: List(GroceryItem)) -> #(Model, Effect(Msg)) {
  let model =
    Model(items: items, new_item: "", saving: False, error: option.None)

  #(model, effect.none())
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  ServerSavedList(Result(Response(String), rsvp.Error))
  UserAddedItem
  UserTypedNewItem(String)
  UserSavedList
  UserUpdatedQuantity(index: Int, quantity: Int)
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ServerSavedList(Ok(_)) -> #(
      Model(..model, saving: False, error: option.None),
      effect.none(),
    )

    ServerSavedList(Error(_)) -> #(
      Model(..model, saving: False, error: option.Some("Failed to save list")),
      effect.none(),
    )

    UserAddedItem -> {
      case model.new_item {
        "" -> #(model, effect.none())
        name -> {
          let item = GroceryItem(name: name, quantity: 1)
          let updated_items = list.append(model.items, [item])

          #(Model(..model, items: updated_items, new_item: ""), effect.none())
        }
      }
    }

    UserTypedNewItem(text) -> #(Model(..model, new_item: text), effect.none())

    UserSavedList -> #(Model(..model, saving: True), save_list(model.items))

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

fn save_list(items: List(GroceryItem)) -> Effect(Msg) {
  let body = groceries.grocery_list_to_json(items)
  let url = "/api/groceries"

  rsvp.post(url, body, rsvp.expect_ok_response(ServerSavedList))
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
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
    html.div([], [
      html.button(
        [event.on_click(UserSavedList), attribute.disabled(model.saving)],
        [
          html.text(case model.saving {
            True -> "Saving..."
            False -> "Save List"
          }),
        ],
      ),
    ]),
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
