import gleam/erlang/process.{type Pid, type Subject}
import gleam/otp/actor.{type Next, type StartError, Started}
import gleam/result

import variable/internal/subscribe.{type Subscribe, type Subscribes}

/// 进程句柄
pub opaque type Var(v) {
  Var(pid: Pid, subject: Subject(Message(v)))
}

/// 进程状态
type Val(v) {
  Val(v: v, subs: Subscribes(v))
}

/// 进程的消息
type Message(v) {
  /// 关闭进程
  Closure
  /// 获取值
  Get(subject: Subject(v))
  /// 设置值
  Set(subject: Subject(v), new: v)
  /// 更新值
  Update(subject: Subject(v), update: fn(v) -> v)
  /// 订阅数量
  SubscribeCount(subject: Subject(Int))
  /// 订阅名称列表
  SubscribeNames(subject: Subject(List(String)))
  /// 订阅是否存在
  HasSubscribe(subject: Subject(Bool), name: String)
  /// 订阅
  Subscribe(subject: Subject(Nil), name: String, body: fn(v, v) -> Nil)
  /// 取消订阅
  Unsubscribe(subject: Subject(Nil), name: String)
  /// 取消全部订阅
  UnsubscribeAll(subject: Subject(Nil))
}

/// 使用初始值创建新的值进程
pub fn new(val: v) -> Result(Var(v), StartError) {
  let started =
    Val(v: val, subs: subscribe.new())
    |> actor.new()
    |> actor.on_message(handle)
    |> actor.start()

  use started <- result.try(started)
  let Started(pid:, data: subject) = started
  Var(pid:, subject:) |> Ok()
}

/// 关闭值进程
pub fn closure(var: Var(v)) -> Nil {
  process.send(var.subject, Closure)
}

/// 获取值
/// 
/// # Panic
/// 进程关闭
pub fn get(var: Var(v)) -> v {
  Get(subject: _)
  |> process.call_forever(var.subject, _)
}

/// 设置值并通知订阅，最后返回新值
/// 
/// # Panic
/// 进程关闭
pub fn set(var: Var(v), new: v) -> v {
  Set(subject: _, new:)
  |> process.call_forever(var.subject, _)
}

/// 更新值并通知订阅，最后返回新值
/// 
/// # Panic
/// 进程关闭
/// 
/// 回调函数异常
pub fn update(var: Var(v), update: fn(v) -> v) -> v {
  Update(subject: _, update:)
  |> process.call_forever(var.subject, _)
}

/// 获取订阅数量
/// 
/// # Panic
/// 进程关闭
pub fn subscribe_count(var: Var(v)) -> Int {
  SubscribeCount(subject: _)
  |> process.call_forever(var.subject, _)
}

/// 获取订阅名称列表
/// 
/// # Panic
/// 进程关闭
pub fn subscribe_names(var: Var(v)) -> List(String) {
  SubscribeNames(subject: _)
  |> process.call_forever(var.subject, _)
}

/// 指定名称的订阅是否存在
/// 
/// # Panic
/// 进程关闭
pub fn has_subscribe(var: Var(v), name: String) -> Bool {
  HasSubscribe(subject: _, name:)
  |> process.call_forever(var.subject, _)
}

/// 订阅函数
/// 
/// # Notice
/// 会覆盖重名订阅
/// 
/// # Panic
/// 进程关闭
/// 
/// 订阅函数异常
pub fn subscribe(var: Var(v), name: String, body: Subscribe(v)) -> Nil {
  Subscribe(subject: _, name:, body:)
  |> process.call_forever(var.subject, _)
}

/// 取消订阅
/// 
/// # Panic
/// 进程关闭
pub fn unsubscribe(var: Var(v), name: String) -> Nil {
  Unsubscribe(subject: _, name:)
  |> process.call_forever(var.subject, _)
}

/// 取消全部订阅
/// 
/// # Panic
/// 进程关闭
pub fn unsubscribe_all(var: Var(v)) -> Nil {
  UnsubscribeAll(subject: _)
  |> process.call_forever(var.subject, _)
}

/// 进程是否存活
pub fn is_alive(var: Var(v)) -> Bool {
  process.is_alive(var.pid)
}

fn handle(val: Val(v), message: Message(v)) -> Next(Val(v), Message(v)) {
  case message {
    Closure -> closure_msg(val)
    Get(subject:) -> get_msg(val, subject)
    Set(subject:, new:) -> set_msg(val, subject, new)
    Update(subject:, update:) -> update_msg(val, subject, update)
    SubscribeCount(subject:) -> subscribe_count_msg(val, subject)
    SubscribeNames(subject:) -> subscribe_names_msg(val, subject)
    HasSubscribe(subject:, name:) -> has_subscribe_msg(val, subject, name)
    Subscribe(subject:, name:, body:) -> subscribe_msg(val, subject, name, body)
    Unsubscribe(subject:, name:) -> unsubscribe_msg(val, subject, name)
    UnsubscribeAll(subject:) -> unsubscribe_all_msg(val, subject)
  }
}

fn closure_msg(val: Val(v)) -> Next(Val(v), Message(v)) {
  // 取消所有订阅
  subscribe.delete_all(val.subs)
  actor.stop()
}

fn get_msg(val: Val(v), subject: Subject(v)) -> Next(Val(v), Message(v)) {
  // 返回值
  process.send(subject, val.v)
  actor.continue(val)
}

fn set_msg(
  val: Val(v),
  subject: Subject(v),
  new: v,
) -> Next(Val(v), Message(v)) {
  // 返回新值
  process.send(subject, new)
  // 通知订阅
  subscribe.notify(val.subs, val.v, new)
  // 设置新值
  Val(..val, v: new)
  |> actor.continue()
}

fn update_msg(
  val: Val(v),
  subject: Subject(v),
  update: fn(v) -> v,
) -> Next(Val(v), Message(v)) {
  // 获取新值
  let new = update(val.v)
  // 返回新值
  process.send(subject, new)
  // 通知订阅
  subscribe.notify(val.subs, val.v, new)
  // 设置新值
  Val(..val, v: new)
  |> actor.continue()
}

fn subscribe_count_msg(
  val: Val(v),
  subject: Subject(Int),
) -> Next(Val(v), Message(v)) {
  // 返回订阅数量
  process.send(subject, subscribe.count(val.subs))
  actor.continue(val)
}

fn subscribe_names_msg(
  val: Val(v),
  subject: Subject(List(String)),
) -> Next(Val(v), Message(v)) {
  // 返回订阅名称列表
  process.send(subject, subscribe.names(val.subs))
  actor.continue(val)
}

fn has_subscribe_msg(
  val: Val(v),
  subject: Subject(Bool),
  name: String,
) -> Next(Val(v), Message(v)) {
  // 返回结果
  process.send(subject, subscribe.is_exists(val.subs, name))
  actor.continue(val)
}

fn subscribe_msg(
  val: Val(v),
  subject: Subject(Nil),
  name: String,
  body: fn(v, v) -> Nil,
) -> Next(Val(v), Message(v)) {
  // 返回
  process.send(subject, Nil)
  // 添加订阅
  Val(..val, subs: subscribe.add(val.subs, name, body))
  |> actor.continue()
}

fn unsubscribe_msg(
  val: Val(v),
  subject: Subject(Nil),
  name: String,
) -> Next(Val(v), Message(v)) {
  // 返回
  process.send(subject, Nil)
  // 取消订阅
  Val(..val, subs: subscribe.delete(val.subs, name))
  |> actor.continue()
}

fn unsubscribe_all_msg(
  val: Val(v),
  subject: Subject(Nil),
) -> Next(Val(v), Message(v)) {
  // 返回
  process.send(subject, Nil)
  // 取消所有订阅
  Val(..val, subs: subscribe.delete_all(val.subs))
  |> actor.continue()
}
