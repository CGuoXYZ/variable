import gleam/dict.{type Dict}
import gleam/erlang/process

/// 订阅者字典
pub opaque type Subscribes(v) {
  Subscribes(subs: Dict(String, fn(v, v) -> Nil))
}

/// 订阅函数
pub type Subscribe(v) =
  fn(v, v) -> Nil

/// 创建新的订阅者字典
pub fn new() -> Subscribes(v) {
  Subscribes(dict.new())
}

/// 添加订阅
/// 
/// 重名的订阅会覆盖
pub fn add(
  subscribes: Subscribes(v),
  name: String,
  body: Subscribe(v),
) -> Subscribes(v) {
  // 添加订阅
  Subscribes(dict.insert(subscribes.subs, name, body))
}

/// 取消订阅
pub fn delete(subscribes: Subscribes(v), name: String) -> Subscribes(v) {
  Subscribes(dict.delete(subscribes.subs, name))
}

/// 取消所有订阅
pub fn delete_all(_subscribes: Subscribes(v)) -> Subscribes(v) {
  new()
}

/// 通知订阅者
pub fn notify(subscribes: Subscribes(v), old: v, new: v) -> Nil {
  use _, body <- dict.each(subscribes.subs)
  use <- process.spawn()
  body(old, new)
}
