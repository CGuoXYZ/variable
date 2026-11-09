import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}

/// 订阅者字典
pub opaque type Subscribes(v) {
  Subscribes(subs: Dict(String, Subject(SubMessage(v))))
}

/// 订阅循环接收的消息
pub opaque type SubMessage(v) {
  /// 关闭
  Closure
  /// 通知
  Notify(old: v, new: v)
}

/// 新的订阅者字典
pub fn new() -> Subscribes(v) {
  Subscribes(dict.new())
}

/// 订阅循环
fn sub_loop(msg: Subject(SubMessage(v)), body: fn(v, v) -> Nil) -> Nil {
  case process.receive_forever(msg) {
    Closure -> Nil
    Notify(old:, new:) -> {
      body(old, new)
      sub_loop(msg, body)
    }
  }
}

/// 添加订阅
pub fn add(
  subscribes: Subscribes(v),
  name: String,
  body: fn(v, v) -> Nil,
) -> Subscribes(v) {
  // 如果已存在同名订阅，则先取消订阅
  let subscribes = case dict.has_key(subscribes.subs, name) {
    False -> subscribes
    True -> delete(subscribes, name)
  }

  // 准备接收订阅循环的接收器
  let ready = process.new_subject()

  process.spawn(fn() {
    // 订阅循环的接收器
    let sub_msg = process.new_subject()
    // 向外部发送接收器
    process.send(ready, sub_msg)
    // 开始订阅循环
    sub_loop(sub_msg, body)
  })

  // 获取订阅循环的接收器
  let sub_msg = process.receive_forever(ready)

  // 添加订阅
  Subscribes(dict.insert(subscribes.subs, name, sub_msg))
}

/// 取消订阅
pub fn delete(subscribes: Subscribes(v), name: String) -> Subscribes(v) {
  case dict.get(subscribes.subs, name) {
    Error(_) -> subscribes
    Ok(msg) -> {
      process.send(msg, Closure)
      Subscribes(dict.delete(subscribes.subs, name))
    }
  }
}

/// 取消所有订阅
pub fn delete_all(subscribes: Subscribes(v)) -> Subscribes(v) {
  dict.each(subscribes.subs, fn(_, msg) { process.send(msg, Closure) })
  new()
}

/// 通知订阅者
pub fn notify(subscribes: Subscribes(v), old: v, new: v) -> Nil {
  use _, msg <- dict.each(subscribes.subs)
  process.send(msg, Notify(old:, new:))
}
