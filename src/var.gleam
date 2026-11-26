import exception
import gleam/otp/actor.{type StartError}

import variable/internal/handle.{type Var}
import variable/internal/subscribe.{type Subscribe}

/// 创建临时的可变值, 回调结束自动关闭(关闭是异步的)
/// 
/// # Panic
/// 函数异常
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

/// 获取值
/// 
/// # Panic
/// 进程关闭
pub fn get(var: Var(v)) -> v {
  handle.get(var)
}

/// 设置值并通知订阅，最后返回新值
/// 
/// # Panic
/// 进程关闭
pub fn set(var: Var(v), new: v) -> v {
  handle.set(var, new)
}

/// 更新值并通知订阅，最后返回新值
/// 
/// # Panic
/// 进程关闭
/// 
/// 函数异常
pub fn update(var: Var(v), update: fn(v) -> v) -> v {
  handle.update(var, update)
}

/// 订阅函数
/// 
/// # Notice
/// 会覆盖重名订阅
/// 
/// # Panic
/// 进程关闭
pub fn subscribe(var: Var(v), name: String, body: Subscribe(v)) -> Nil {
  handle.subscribe(var, name, body)
}

/// 取消订阅函数
/// 
/// # Panic
/// 进程关闭
pub fn unsubscribe(var: Var(v), name: String) -> Nil {
  handle.unsubscribe(var, name)
}

/// 取消订阅所有函数
/// 
/// # Panic
/// 进程关闭
pub fn unsubscribe_all(var: Var(v)) -> Nil {
  handle.unsubscribe_all(var)
}

/// 进程是否存活
pub fn is_alive(var: Var(v)) -> Bool {
  handle.is_alive(var)
}
