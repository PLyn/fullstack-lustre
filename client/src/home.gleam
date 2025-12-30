import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type Model {
  Model
}

pub type Msg {
  ExampleButtonClicked
}

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model, effect.none())
}

pub fn update(msg: Msg, model: Model) -> #(Model, Effect(Msg)) {
  case msg {
    ExampleButtonClicked -> {
      #(model, effect.none())
    }
  }
}

pub fn view(_model: Model) -> Element(Msg) {
  let styles = [
    #("max-width", "42ch"),
    #("margin", "0 auto"),
    #("padding", "2em"),
    #("display", "flex"),
    #("flex-direction", "column"),
    #("gap", "1em"),
  ]

  html.div([attribute.styles(styles)], [
    html.h1([], [html.text("Home Page")]),
    html.p([], [html.text("Welcome to the home page!")]),
    html.button([event.on_click(ExampleButtonClicked)], [
      html.text("Example Button"),
    ]),
  ])
}
