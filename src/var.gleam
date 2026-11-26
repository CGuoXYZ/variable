import exception
import gleam/otp/actor.{type StartError}

import variable/internal/handle.{type Var}
import variable/internal/subscribe.{type Subscribe}

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

pub fn set(var: Var(v), new: v) -> v {
  handle.set(var, new)
}

pub fn update(var: Var(v), update: fn(v) -> v) -> v {
  handle.update(var, update)
}

pub fn subscribe(var: Var(v), name: String, body: Subscribe(v)) -> Nil {
  handle.subscribe(var, name, body)
}

pub fn unsubscribe(var: Var(v), name: String) -> Nil {
  handle.unsubscribe(var, name)
}

pub fn unsubscribe_all(var: Var(v)) -> Nil {
  handle.unsubscribe_all(var)
}

pub fn is_alive(var: Var(v)) -> Bool {
  handle.is_alive(var)
}
