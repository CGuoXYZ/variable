import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/order.{Eq}
import gleeunit

import variable/internal/subscribe

// ───────────────────────────── 工具 ─────────────────────────────

const timeout = 1000

pub fn main() -> Nil {
  gleeunit.main()
}

fn take(subject: process.Subject(a), n: Int) -> List(a) {
  case n <= 0 {
    True -> []
    False -> {
      let assert Ok(message) = process.receive(subject, timeout)
      [message, ..take(subject, n - 1)]
    }
  }
}

fn assert_no_message(subject: process.Subject(a)) -> Nil {
  case process.receive(subject, 100) {
    Ok(_) -> panic as "不应该再收到通知"
    Error(_) -> Nil
  }
}

fn compare_pair(a: #(Int, Int), b: #(Int, Int)) {
  case int.compare(a.0, b.0) {
    Eq -> int.compare(a.1, b.1)
    other -> other
  }
}

fn sorted_pairs(subject: process.Subject(#(Int, Int)), n: Int) {
  take(subject, n) |> list.sort(compare_pair)
}

// ─────────────────────────── 订阅表 ───────────────────────────

pub fn no_subscribers_test() {
  let subscribes = subscribe.new()
  assert subscribe.notify(subscribes, 0, 1) == Nil
}

pub fn add_notify_test() {
  let seen = process.new_subject()
  let subscribes =
    subscribe.new()
    |> subscribe.add("a", fn(old, new) { process.send(seen, #(old, new)) })

  subscribe.notify(subscribes, 0, 1)

  assert take(seen, 1) == [#(0, 1)]
}

pub fn notify_runs_in_separate_process_test() {
  let seen = process.new_subject()
  let subscribes =
    subscribe.new()
    |> subscribe.add("a", fn(_, _) { process.send(seen, process.self()) })

  subscribe.notify(subscribes, 0, 1)

  let assert Ok(pid) = process.receive(seen, timeout)
  assert pid != process.self()
}

pub fn multiple_subscribers_test() {
  let a = process.new_subject()
  let b = process.new_subject()
  let subscribes =
    subscribe.new()
    |> subscribe.add("a", fn(old, new) { process.send(a, #(old, new)) })
    |> subscribe.add("b", fn(old, new) { process.send(b, #(old, new)) })

  subscribe.notify(subscribes, 0, 1)

  assert take(a, 1) == [#(0, 1)]
  assert take(b, 1) == [#(0, 1)]
}

pub fn same_name_overwrites_test() {
  let old = process.new_subject()
  let new = process.new_subject()
  let subscribes =
    subscribe.new()
    |> subscribe.add("a", fn(old_value, new_value) {
      process.send(old, #(old_value, new_value))
    })
    |> subscribe.add("a", fn(old_value, new_value) {
      process.send(new, #(old_value, new_value))
    })

  subscribe.notify(subscribes, 0, 1)

  assert take(new, 1) == [#(0, 1)]
  assert_no_message(old)
}

pub fn notify_multiple_times_test() {
  let seen = process.new_subject()
  let subscribes =
    subscribe.new()
    |> subscribe.add("a", fn(old, new) { process.send(seen, #(old, new)) })

  subscribe.notify(subscribes, 0, 1)
  subscribe.notify(subscribes, 1, 2)

  assert sorted_pairs(seen, 2) == [#(0, 1), #(1, 2)]
}

// ─────────────────────────── 取消订阅 ───────────────────────────

pub fn delete_test() {
  let seen = process.new_subject()
  let subscribes =
    subscribe.new()
    |> subscribe.add("a", fn(old, new) { process.send(seen, #(old, new)) })
    |> subscribe.delete("a")

  subscribe.notify(subscribes, 0, 1)

  assert_no_message(seen)
}

pub fn delete_missing_is_safe_test() {
  let subscribes =
    subscribe.new()
    |> subscribe.delete("missing")

  assert subscribe.notify(subscribes, 0, 1) == Nil
}

pub fn delete_all_test() {
  let a = process.new_subject()
  let b = process.new_subject()
  let subscribes =
    subscribe.new()
    |> subscribe.add("a", fn(old, new) { process.send(a, #(old, new)) })
    |> subscribe.add("b", fn(old, new) { process.send(b, #(old, new)) })
    |> subscribe.delete_all()

  subscribe.notify(subscribes, 0, 1)

  assert_no_message(a)
  assert_no_message(b)
}

pub fn delete_all_empty_is_safe_test() {
  let subscribes = subscribe.new() |> subscribe.delete_all()
  assert subscribe.notify(subscribes, 0, 1) == Nil
}
