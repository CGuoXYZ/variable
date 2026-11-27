import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}

/// 订阅句柄
pub opaque type Subscribes(v) {
  Subscribes(subs: Dict(String, Subject(Message(v))))
}

/// 订阅函数
pub type Subscribe(v) =
  fn(v, v) -> Nil

/// 订阅的消息
type Message(v) {
  /// 关闭订阅
  Closure
  /// 通知订阅
  Notify(old: v, new: v)
}

/// 创建订阅者字典
pub fn new() -> Subscribes(v) {
  Subscribes(dict.new())
}

/// 获取订阅数量
pub fn count(subscribes: Subscribes(v)) -> Int {
  dict.size(subscribes.subs)
}

/// 获取订阅名称列表
pub fn names(subscribes: Subscribes(v)) -> List(String) {
  use acc, name, _ <- dict.fold(subscribes.subs, [])
  [name, ..acc]
}

/// 添加订阅
/// 
/// # Notice
/// 会覆盖重名订阅
pub fn add(
  subscribes: Subscribes(v),
  name: String,
  body: Subscribe(v),
) -> Subscribes(v) {
  // 若订阅已存在则删除
  let subscribes = delete(subscribes, name)

  // 准备接收订阅的subject
  let ready = process.new_subject()

  // 为订阅创建链接进程
  process.spawn(fn() {
    // 订阅进程用于接收消息
    let subject = process.new_subject()
    // 发送订阅的subject
    process.send(ready, subject)

    // 订阅循环
    loop(body, subject)
  })

  // 接收订阅的subject
  let subject = process.receive_forever(ready)
  // 添加订阅
  Subscribes(subs: dict.insert(subscribes.subs, name, subject))
}

/// 取消订阅
pub fn delete(subscribes: Subscribes(v), name: String) -> Subscribes(v) {
  case dict.get(subscribes.subs, name) {
    // 订阅不存在原样返回
    Error(_) -> subscribes
    Ok(subject) -> {
      // 发送消息关闭订阅
      process.send(subject, Closure)
      // 从字典删除订阅
      Subscribes(dict.delete(subscribes.subs, name))
    }
  }
}

/// 取消所有订阅
pub fn delete_all(subscribes: Subscribes(v)) -> Subscribes(v) {
  dict.each(subscribes.subs, fn(_, v) { process.send(v, Closure) })
  new()
}

/// 通知订阅者
/// 
/// # Panic
/// 订阅异常
pub fn notify(subscribes: Subscribes(v), old: v, new: v) -> Nil {
  use _, subject <- dict.each(subscribes.subs)
  process.send(subject, Notify(old, new))
}

/// 订阅循环
fn loop(body: Subscribe(v), subject: Subject(Message(v))) -> Nil {
  // 等待消息
  case process.receive_forever(subject) {
    Closure -> Nil
    Notify(old:, new:) -> {
      // 执行订阅函数
      body(old, new)
      // 循环
      loop(body, subject)
    }
  }
}
