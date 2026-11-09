import gleam/erlang/process.{type Pid, type Subject}
import gleam/otp/actor.{type Next, type StartError, Started}
import gleam/result

import variable/internal/subscribe.{type Subscribes}

/// 外部携带的句柄
pub opaque type Var(v) {
  Var(pid: Pid, subject: Subject(Message(v)))
}

/// 进程的状态
type Val(v) {
  Val(v: v, subscribes: Subscribes(v))
}

/// 进程的消息
type Message(v) {
  Closure
  Get(subject: Subject(v))
  Set(subject: Subject(v), new: v)
  Update(subject: Subject(v), update: fn(v) -> v)
  Subscribe(subject: Subject(v), name: String, body: fn(v, v) -> Nil)
  Unsubscribe(subject: Subject(v), name: String)
  UnsubscribeAll(subject: Subject(v))
}

/// 死亡
pub type Death

/// 使用指定初始值创建新的值进程
pub fn new(val: v) -> Result(Var(v), StartError) {
  Val(v: val, subscribes: subscribe.new())
  |> actor.new()
  |> actor.on_message(handle)
  |> actor.start()
  |> result.try(fn(started) {
    let Started(pid:, data: subject) = started
    Var(pid:, subject:) |> Ok()
  })
}

/// 关闭值进程
pub fn closure(var: Var(v)) -> Nil {
  var.subject |> process.send(Closure)
}

/// 获取值
pub fn get(var: Var(v)) -> Result(v, Death) {
  receive(var, Get)
}

/// 设置值并返回新值
pub fn set(var: Var(v), new: v) -> Result(v, Death) {
  receive(var, Set(subject: _, new:))
}

/// 更新值并返回新值
pub fn update(var: Var(v), update: fn(v) -> v) -> Result(v, Death) {
  receive(var, Update(subject: _, update:))
}

/// 订阅函数
pub fn subscribe(
  var: Var(v),
  name: String,
  body: fn(v, v) -> Nil,
) -> Result(Nil, Death) {
  receive(var, Subscribe(subject: _, name:, body:))
  |> result.map(fn(_) { Nil })
}

/// 取消订阅
pub fn unsubscribe(var: Var(v), name: String) -> Result(Nil, Death) {
  receive(var, Unsubscribe(subject: _, name:))
  |> result.map(fn(_) { Nil })
}

/// 向进程获取获取响应
fn receive(var: Var(v), msg: fn(Subject(v)) -> Message(v)) -> Result(v, Death) {
  let subject = process.new_subject()
  let selector =
    process.new_selector()
    |> process.select_map(subject, Ok)

  process.send(var.subject, msg(subject))

  process.selector_receive_forever(selector)
}

fn handle(val: Val(v), msg: Message(v)) -> Next(Val(v), Message(v)) {
  case msg {
    Closure -> actor.stop()
    Get(subject:) -> get_msg(val, subject)
    Set(subject:, new:) -> set_msg(val, subject, new)
    Update(subject:, update:) -> update_msg(val, subject, update)
    Subscribe(subject:, name:, body:) -> subscribe_msg(val, subject, name, body)
    Unsubscribe(subject:, name:) -> unsubscribe_msg(val, subject, name)
    UnsubscribeAll(subject:) -> unsubscribe_all_msg(val, subject)
  }
}

fn get_msg(val: Val(v), subject: Subject(v)) -> Next(Val(v), Message(v)) {
  process.send(subject, val.v)
  actor.continue(val)
}

fn set_msg(
  val: Val(v),
  subject: Subject(v),
  new: v,
) -> Next(Val(v), Message(v)) {
  process.send(subject, new)
  subscribe.notify(val.subscribes, val.v, new)
  actor.continue(Val(..val, v: new))
}

fn update_msg(
  val: Val(v),
  subject: Subject(v),
  update: fn(v) -> v,
) -> Next(Val(v), Message(v)) {
  let new = update(val.v)
  process.send(subject, new)
  subscribe.notify(val.subscribes, val.v, new)
  actor.continue(Val(..val, v: new))
}

fn subscribe_msg(
  val: Val(v),
  subject: Subject(v),
  name: String,
  body: fn(v, v) -> Nil,
) -> Next(Val(v), Message(v)) {
  process.send(subject, val.v)
  actor.continue(
    Val(..val, subscribes: subscribe.add(val.subscribes, name, body)),
  )
}

fn unsubscribe_msg(
  val: Val(v),
  subject: Subject(v),
  name: String,
) -> Next(Val(v), Message(v)) {
  process.send(subject, val.v)
  actor.continue(Val(..val, subscribes: subscribe.delete(val.subscribes, name)))
}

fn unsubscribe_all_msg(
  val: Val(v),
  subject: Subject(v),
) -> Next(Val(v), Message(v)) {
  process.send(subject, val.v)
  actor.continue(Val(..val, subscribes: subscribe.delete_all(val.subscribes)))
}
