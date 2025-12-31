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

import gleam/dict.{type Dict}
import gleam/list
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
  ListById(id: Int)
  /// It's good practice to store whatever `Uri` we failed to match in case we
  /// want to log it or hint to the user that maybe they made a typo.
  NotFound(uri: Uri)
}

fn parse_route(uri: Uri) -> Route {
  case uri.path_segments(uri.path) {
    [] | [""] -> Home

    ["ItemList"] -> ItemList

    ["ItemList", item_list_id] ->
      case int.parse(item_list_id) {
        Ok(list_id) -> ListById(id: list_id)
        Error(_) -> NotFound(uri:)
      }

    _ -> NotFound(uri:)
  }
}

/// We also need a way to turn a Route back into a an `href` attribute that we
/// can then use on `html.a` elements. It is important to keep this function in
/// sync with the parsing, but once you do, all links are guaranteed to work!
///
fn href(route: Route) -> Attribute(msg) {
  let url = case route {
    Home -> "/"
    ItemList -> "/itemlist"
    ListById(list_id) -> "/list/" <> int.to_string(list_id)
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
    lists: Dict(Int, Post),
    route: Route,
  )
}

type Post {
  Post(id: Int, title: String, summary: String, text: String)
}

fn init(items: List(groceries.GroceryItem)) -> #(Model, Effect(Msg)) {
  // The server for a typical SPA will often serve the application to *any*
  // HTTP request, and let the app itself determine what to show. Modem stores
  // the first URL so we can parse it for the app's initial route.
  let route = case modem.initial_uri() {
    Ok(uri) -> parse_route(uri)
    Error(_) -> Home
  }

  let posts =
    posts
    |> list.map(fn(post) { #(post.id, post) })
    |> dict.from_list

  let #(item_list_model, item_list_effect) = item_list.init(items)
  let model = Model(home.Model, item_list_model, "", route:, lists: posts)

  let modem_effect =
    modem.init(fn(uri) {
      uri
      |> parse_route
      |> UserNavigatedTo
    })

  // 2. Merge them using batch
  // We map the sub-module effect (item_list_effect) to the parent Msg type
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
    html.nav([attribute.class("flex justify-between items-center my-16")], [
      html.h1([attribute.class("text-red-600 font-medium text-xl")], [
        html.a([href(Home)], [html.text("My little Blog")]),
      ]),
      html.ul([attribute.class("flex space-x-8")], [
        view_header_link(current: model.route, to: ItemList, label: "Item List"),
        view_header_link(current: model.route, to: Home, label: "Home"),
      ]),
    ]),
    html.main([attribute.class("my-16")], {
      // Just like we would show different HTML based on some other state in the
      // model, we can also pattern match on our Route value to show different
      // views based on the current page!
      case model.route {
        Home -> view_home()
        ItemList -> view_item_list(model)
        ListById(post_id) -> view_list(model, post_id)
        //About -> view_about()
        NotFound(_) -> view_not_found()
      }
    }),
    home.view(model.home_model)
      |> element.map(HomeMsg),

    html.hr([]),
    html.hr([]),

    // Visual separator
    item_list.view(model.item_list_model)
      |> element.map(ItemListMsg),
  ])
}

fn view_header_link(
  to target: Route,
  current current: Route,
  label text: String,
) -> Element(msg) {
  let is_active = case current, target {
    ListById(_), ItemList -> True
    _, _ -> current == target
  }

  html.li(
    [
      attribute.classes([
        #("border-transparent border-b-2 hover:border-purple-600", True),
        #("text-purple-600", is_active),
      ]),
    ],
    [html.a([href(target)], [html.text(text)])],
  )
}

// VIEW PAGES ------------------------------------------------------------------

fn view_home() -> List(Element(msg)) {
  [
    title("Hello, Joe"),
    leading(
      "Or whoever you may be! This is were I will share random ramblings
       and thoughts about life.",
    ),
    html.p([attribute.class("text-blue-600 mt-14 font-bold")], [
      html.text("There is not much going on at the moment, but you can still "),
      link(ItemList, "read my ramblings ->"),
    ]),
    paragraph("If you like <3"),
  ]
}

fn view_item_list(model: Model) -> List(Element(msg)) {
  let posts =
    model.lists
    |> dict.values
    |> list.sort(fn(a, b) { int.compare(a.id, b.id) })
    |> list.map(fn(post) {
      html.article([attribute.class("mt-14")], [
        html.h3([attribute.class("text-xl text-purple-600 font-light")], [
          html.a([attribute.class("hover:underline"), href(ListById(post.id))], [
            html.text(post.title),
          ]),
        ]),
        html.p([attribute.class("mt-1")], [html.text(post.summary)]),
      ])
    })

  [title("Posts"), ..posts]
}

fn view_list(model: Model, post_id: Int) -> List(Element(msg)) {
  case dict.get(model.lists, post_id) {
    Error(_) -> view_not_found()
    Ok(post) -> [
      html.article([], [
        title(post.title),
        leading(post.summary),
        paragraph(post.text),
      ]),
      html.p([attribute.class("mt-14")], [link(ItemList, "<- Go back?")]),
    ]
  }
}

fn view_not_found() -> List(Element(msg)) {
  [
    title("Not found"),
    paragraph(
      "You glimpse into the void and see -- nothing?
       Well that was somewhat expected.",
    ),
  ]
}

// VIEW HELPERS ----------------------------------------------------------------

fn title(title: String) -> Element(msg) {
  html.h2([attribute.class("text-3xl text-purple-800 font-light")], [
    html.text(title),
  ])
}

fn leading(text: String) -> Element(msg) {
  html.p([attribute.class("mt-8 text-lg")], [html.text(text)])
}

fn paragraph(text: String) -> Element(msg) {
  html.p([attribute.class("mt-14")], [html.text(text)])
}

/// In other frameworks you might see special `<Link />` components that are
/// used to handle navigation logic. Using modem, we can just use normal HTML
/// `<a>` elements and pass in the `href` attribute. This means we have the option
/// of rendering our app as static HTML in the future!
///
fn link(target: Route, title: String) -> Element(msg) {
  html.a(
    [
      href(target),
      attribute.class("text-purple-600 hover:underline cursor-pointer"),
    ],
    [html.text(title)],
  )
}

// DATA ------------------------------------------------------------------------

const posts: List(Post) = [
  Post(
    id: 1,
    title: "The Empty Chair",
    summary: "A guide to uninvited furniture and its temporal implications",
    text: "
      There's an empty chair in my home that wasn't there yesterday. When I sit
      in it, I start to remember things that haven't happened yet. The chair is
      getting closer to my bedroom each night, though I never caught it move.
      Last night, I dreamt it was watching me sleep. This morning, it offered
      me coffee.
    ",
  ),
  Post(
    id: 2,
    title: "The Library of Unwritten Books",
    summary: "Warning: Reading this may shorten your narrative arc",
    text: "
      Between the shelves in the public library exists a thin space where
      books that were never written somehow exist. Their pages change when you
      blink. Forms shifting to match the souls blueprint. Librarians warn
      against reading the final chapter of any unwritten book – those who do
      find their own stories mysteriously concluding. Yourself is just another
      draft to be rewritten.
    ",
  ),
  Post(
    id: 3,
    title: "The Hum",
    summary: "A frequency analysis of the collective forgetting",
    text: "
      The citywide hum started Tuesday. Not everyone can hear it, but those who
      can't are slowly being replaced by perfect copies who smile too widely.
      The hum isn't sound – it's the universe forgetting our coordinates.
      Reports suggest humming back in harmony might postpone whatever comes
      next. Or perhaps accelerate it.
    ",
  ),
]
