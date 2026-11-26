import gleam/dict.{type Dict}
import gleam/erlang/process

/// 订阅者字典
pub opaque type Subscribes(v) {
  Subscribes(subs: Dict(String, fn(v, v) -> Nil))
}

/// 创建新的订阅者字典
pub fn new() -> Subscribes(v) {
  Subscribes(dict.new())
}

/// 添加订阅
pub fn add(
  subscribes: Subscribes(v),
  name: String,
  body: fn(v, v) -> Nil,
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
  process.spawn(fn() { body(old, new) })
}
