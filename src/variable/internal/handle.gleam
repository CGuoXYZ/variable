import gleam/bool
import gleam/erlang/process.{type Pid, type Subject}
import gleam/otp/actor.{type Next, type StartError, Started}
import gleam/result

import variable/internal/subscribe.{type Subscribes}
import variable/internal/term.{type Term}

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
  Closure(term: Term)
  Get(term: Term, subject: Subject(v))
  Set(term: Term, subject: Subject(v), new: v)
  Update(term: Term, subject: Subject(v), update: fn(v) -> v)
  Subscribe(
    term: Term,
    subject: Subject(v),
    name: String,
    body: fn(v, v) -> Nil,
  )
  Unsubscribe(term: Term, subject: Subject(v), name: String)
  UnsubscribeAll(term: Term, subject: Subject(v))
}

pub type HDLError {
  /// 超时
  Timeout
  /// 死亡
  Death
}

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
  var.subject |> process.send(Closure(term: term.forever()))
}

/// 获取值
pub fn get(var: Var(v), timeout: Int) -> Result(v, HDLError) {
  receive(var, timeout, Get)
}

/// 设置值并返回新值
pub fn set(var: Var(v), timeout: Int, new: v) -> Result(v, HDLError) {
  use term, subject <- receive(var, timeout)
  Set(term:, subject:, new:)
}

/// 更新值并返回新值
pub fn update(
  var: Var(v),
  timeout: Int,
  update: fn(v) -> v,
) -> Result(v, HDLError) {
  use term, subject <- receive(var, timeout)
  Update(term:, subject:, update:)
}

/// 订阅函数
pub fn subscribe(
  var: Var(v),
  timeout: Int,
  name: String,
  body: fn(v, v) -> Nil,
) -> Result(Nil, HDLError) {
  fn(term, subject) { Subscribe(term:, subject:, name:, body:) }
  |> receive(var, timeout, _)
  |> result.map(fn(_) { Nil })
}

/// 取消订阅
pub fn unsubscribe(
  var: Var(v),
  timeout: Int,
  name: String,
) -> Result(Nil, HDLError) {
  fn(term, subject) { Unsubscribe(term:, subject:, name:) }
  |> receive(var, timeout, _)
  |> result.map(fn(_) { Nil })
}

/// 向进程获取获取响应
fn receive(
  var: Var(v),
  timeout: Int,
  msg: fn(Term, Subject(v)) -> Message(v),
) -> Result(v, HDLError) {
  // 新建通道
  let subject = process.new_subject()
  // 监控值进程
  let monitor = process.monitor(var.pid)
  // 选择器
  // 获取进程响应，同时监控进程存亡
  let selector =
    process.new_selector()
    |> process.select_map(subject, Ok)
    |> process.select_specific_monitor(monitor, fn(_) { Error(Death) })

  // 向进程发送消息
  process.send(var.subject, msg(term.deadline(timeout), subject))

  // 获取响应
  case process.selector_receive(selector, timeout) {
    // 超时
    Error(_) -> Error(Timeout)
    Ok(result) ->
      case result {
        // 进程死亡
        Error(_) as death -> death
        // 成功获取响应
        Ok(_) as ok -> ok
      }
  }
}

fn handle(val: Val(v), msg: Message(v)) -> Next(Val(v), Message(v)) {
  use <- bool.guard(term.is_expired(msg.term), actor.continue(val))
  case msg {
    Closure(..) -> actor.stop()
    Get(subject:, ..) -> get_msg(val, subject)
    Set(subject:, new:, ..) -> set_msg(val, subject, new)
    Update(subject:, update:, ..) -> update_msg(val, subject, update)
    Subscribe(subject:, name:, body:, ..) ->
      subscribe_msg(val, subject, name, body)
    Unsubscribe(subject:, name:, ..) -> unsubscribe_msg(val, subject, name)
    UnsubscribeAll(subject:, ..) -> unsubscribe_all_msg(val, subject)
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
