import gleam/int
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

import gleam/uri.{type Uri}
import lustre/attribute.{type Attribute}
import modem

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

type Route {
  Home
  ItemList
  NotFound(uri: Uri)
}

fn parse_route(uri: Uri) -> Route {
  case uri.path_segments(uri.path) {
    [] | [""] -> Home

    ["itemlist"] -> ItemList

    _ -> NotFound(uri:)
  }
}

fn href(route: Route) -> Attribute(msg) {
  let url = case route {
    Home -> "/"
    ItemList -> "/itemlist"
    NotFound(_) -> "/404"
  }

  attribute.href(url)
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(
    home_model: home.Model,
    item_list_model: item_list.Model,
    global_setting: String,
    route: Route,
  )
}

fn init(items: List(groceries.GroceryItem)) -> #(Model, Effect(Msg)) {
  let route = case modem.initial_uri() {
    Ok(uri) -> parse_route(uri)
    Error(_) -> Home
  }

  let #(item_list_model, item_list_effect) = item_list.init(items)
  let model = Model(home.Model, item_list_model, "", route:)

  let modem_effect =
    modem.init(fn(uri) {
      uri
      |> parse_route
      |> UserNavigatedTo
    })

  let effect =
    effect.batch([modem_effect, effect.map(item_list_effect, ItemListMsg)])

  #(model, effect)
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  HomeMsg(home.Msg)
  ItemListMsg(item_list.Msg)
  UserNavigatedTo(route: Route)
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    HomeMsg(home_msg) -> {
      let #(new_model, effect) = home.update(home_msg, model.home_model)

      #(Model(..model, home_model: new_model), effect.map(effect, HomeMsg))
    }

    ItemListMsg(item_list_msg) -> {
      let #(new_model, effect) =
        item_list.update(item_list_msg, model.item_list_model)

      #(
        Model(..model, item_list_model: new_model),
        effect.map(effect, ItemListMsg),
      )
    }

    UserNavigatedTo(route:) -> #(Model(..model, route:), effect.none())
  }
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  html.div([], [
    html.nav([attribute.class("nav-header")], [
      html.h1([attribute.class("site-title")], [
        html.a([href(Home)], [html.text("My little Blog")]),
      ]),
      html.ul([attribute.class("nav-list")], [
        view_header_link(current: model.route, to: ItemList, label: "Item List"),
        view_header_link(current: model.route, to: Home, label: "Home"),
      ]),
    ]),
    case model.route {
      Home -> view_home(model)
      ItemList -> view_item_list(model)
      NotFound(_) -> view_not_found()
    },
  ])
}

fn view_header_link(
  to target: Route,
  current current: Route,
  label text: String,
) -> Element(msg) {
  let is_active = current == target

  html.li(
    [
      attribute.classes([
        #("nav-link", True),
        #("nav-link-active", is_active),
      ]),
    ],
    [html.a([href(target)], [html.text(text)])],
  )
}

// VIEW PAGES ------------------------------------------------------------------

fn view_home(model: Model) -> Element(Msg) {
  html.div([], [
    home.view(model.home_model)
    |> element.map(HomeMsg),
  ])
}

fn view_item_list(model: Model) -> Element(Msg) {
  html.div([], [
    item_list.view(model.item_list_model)
    |> element.map(ItemListMsg),
  ])
}

fn view_not_found() -> Element(msg) {
  html.div([], [
    html.h2([attribute.class("not-found-title")], [
      html.text("Not Found"),
    ]),
    html.p([attribute.class("not-found-text")], [
      html.text(
        "You glimpse into the void and see -- nothing? Well that was somewhat expected.",
      ),
    ]),
  ])
}
