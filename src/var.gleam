import exception
import gleam/otp/actor.{type StartError}

import variable/internal/handle.{type Death, type Var}

pub fn scope(val: v, body: fn(Var(v)) -> Nil) -> Result(Nil, StartError) {
  case handle.new(val) {
    Error(error) -> Error(error)
    Ok(var) -> {
      use <- exception.defer(fn() { handle.closure(var) })
      body(var) |> Ok()
    }
  }
}

pub fn get(var: Var(v)) -> Result(v, Death) {
  handle.get(var)
}
