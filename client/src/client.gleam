import gleam/json
import gleam/result
import home
import item_list
import lustre
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import plinth/browser/document
import plinth/browser/element as plinth_element
import shared/groceries

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

pub type Model {
  Model(current_page: Page)
}

pub type Page {
  HomePage(home.Model)
  ItemListPage(item_list.Model)
}

fn init(items: List(groceries.GroceryItem)) -> #(Model, Effect(Msg)) {
  let #(item_list_model, item_list_effect) = item_list.init(items)
  let model = Model(current_page: ItemListPage(item_list_model))

  #(model, effect.map(item_list_effect, ItemListMsg))
}

// UPDATE ----------------------------------------------------------------------

pub type Msg {
  HomeMsg(home.Msg)
  ItemListMsg(item_list.Msg)
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    HomeMsg(home_msg) -> {
      case model.current_page {
        HomePage(home_model) -> {
          let #(new_home_model, home_effect) = home.update(home_msg, home_model)
          #(
            Model(current_page: HomePage(new_home_model)),
            effect.map(home_effect, HomeMsg),
          )
        }
        _ -> #(model, effect.none())
      }
    }

    ItemListMsg(item_list_msg) -> {
      case model.current_page {
        ItemListPage(item_list_model) -> {
          let #(new_item_list_model, item_list_effect) =
            item_list.update(item_list_msg, item_list_model)
          #(
            Model(current_page: ItemListPage(new_item_list_model)),
            effect.map(item_list_effect, ItemListMsg),
          )
        }
        _ -> #(model, effect.none())
      }
    }
  }
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  html.div([], [
    case model.current_page {
      HomePage(home_model) ->
        home.view(home_model)
        |> element.map(HomeMsg)

      ItemListPage(item_list_model) ->
        item_list.view(item_list_model)
        |> element.map(ItemListMsg)
    },
  ])
}
