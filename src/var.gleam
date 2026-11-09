import gleam/otp/actor.{type StartError}

import variable/internal/handle.{type HDLError, type Var}

pub fn scope(val: v, body: fn(Var(v)) -> Nil) -> Result(Nil, StartError) {
  case handle.new(val) {
    Error(error) -> Error(error)
    Ok(var) -> {
      body(var)
      handle.closure(var)
      Ok(Nil)
    }
  }
}

pub fn get(var: Var(v), timeout: Int) -> Result(v, HDLError) {
  handle.get(var, timeout)
}
