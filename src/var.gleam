import exception
import gleam/otp/actor.{type StartError}

import variable/internal/handle.{type Var}

/// 创建临时的可变值
pub fn scope(
  val: v,
  body: fn(Var(v)) -> response,
) -> Result(response, StartError) {
  case handle.new(val) {
    Error(error) -> Error(error)
    Ok(var) -> {
      use <- exception.defer(fn() { handle.closure(var) })
      body(var) |> Ok()
    }
  }
}

pub fn get(var: Var(v)) -> v {
  handle.get(var)
}
