import gleam/erlang/process
import gleam/list
import gleam/string
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

/// 关闭订阅进程，避免测试之间泄漏
fn stop(subscribes: subscribe.Subscribes(a)) -> Nil {
  let _ = subscribe.delete_all(subscribes)
  process.sleep(10)
  Nil
}

@external(erlang, "erlang", "processes")
fn processes() -> List(process.Pid)

fn process_count() -> Int {
  list.length(processes())
}

fn await_process_count_at_most(max: Int, attempts: Int) -> Bool {
  case process_count() <= max {
    True -> True
    False ->
      case attempts <= 0 {
        True -> False
        False -> {
          process.sleep(10)
          await_process_count_at_most(max, attempts - 1)
        }
      }
  }
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
  stop(subscribes)
}

pub fn notify_runs_in_separate_process_test() {
  let seen = process.new_subject()
  let subscribes =
    subscribe.new()
    |> subscribe.add("a", fn(_, _) { process.send(seen, process.self()) })

  subscribe.notify(subscribes, 0, 1)

  let assert Ok(pid) = process.receive(seen, timeout)
  assert pid != process.self()
  stop(subscribes)
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
  stop(subscribes)
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
  assert subscribe.is_exists(subscribes, "a") == True
  assert subscribe.count(subscribes) == 1
  stop(subscribes)
}

pub fn notify_multiple_times_test() {
  let seen = process.new_subject()
  let subscribes =
    subscribe.new()
    |> subscribe.add("a", fn(old, new) { process.send(seen, #(old, new)) })

  subscribe.notify(subscribes, 0, 1)
  subscribe.notify(subscribes, 1, 2)

  assert take(seen, 2) == [#(0, 1), #(1, 2)]
  stop(subscribes)
}

pub fn count_empty_test() {
  assert subscribe.count(subscribe.new()) == 0
}

pub fn count_after_add_test() {
  let subscribes =
    subscribe.new()
    |> subscribe.add("a", fn(_, _) { Nil })

  assert subscribe.count(subscribes) == 1
  stop(subscribes)
}

pub fn names_after_add_test() {
  let subscribes =
    subscribe.new()
    |> subscribe.add("b", fn(_, _) { Nil })
    |> subscribe.add("a", fn(_, _) { Nil })

  assert list.sort(subscribe.names(subscribes), string.compare) == ["a", "b"]
  stop(subscribes)
}

pub fn count_and_names_after_delete_test() {
  let subscribes =
    subscribe.new()
    |> subscribe.add("a", fn(_, _) { Nil })
    |> subscribe.add("b", fn(_, _) { Nil })
    |> subscribe.delete("a")

  assert subscribe.count(subscribes) == 1
  assert subscribe.names(subscribes) == ["b"]
  stop(subscribes)
}

pub fn count_and_names_after_delete_all_test() {
  let subscribes =
    subscribe.new()
    |> subscribe.add("a", fn(_, _) { Nil })
    |> subscribe.add("b", fn(_, _) { Nil })
    |> subscribe.delete_all()

  assert subscribe.count(subscribes) == 0
  assert subscribe.names(subscribes) == []
}

pub fn is_exists_empty_test() {
  assert subscribe.is_exists(subscribe.new(), "a") == False
}

pub fn is_exists_after_add_test() {
  let subscribes =
    subscribe.new()
    |> subscribe.add("a", fn(_, _) { Nil })

  assert subscribe.is_exists(subscribes, "a") == True
  assert subscribe.is_exists(subscribes, "b") == False
  stop(subscribes)
}

pub fn is_exists_after_delete_test() {
  let subscribes =
    subscribe.new()
    |> subscribe.add("a", fn(_, _) { Nil })
    |> subscribe.delete("a")

  assert subscribe.is_exists(subscribes, "a") == False
}

pub fn is_exists_after_delete_all_test() {
  let subscribes =
    subscribe.new()
    |> subscribe.add("a", fn(_, _) { Nil })
    |> subscribe.delete_all()

  assert subscribe.is_exists(subscribes, "a") == False
}

/// 同名覆盖时旧订阅进程会被关闭，只剩新进程
pub fn add_overwrite_stops_old_process_test() {
  let base = process_count()

  let subscribes =
    subscribe.new()
    |> subscribe.add("a", fn(_, _) { Nil })

  let subscribes = subscribe.add(subscribes, "a", fn(_, _) { Nil })

  assert await_process_count_at_most(base + 1, 100)
  stop(subscribes)
}

/// delete 会关闭订阅进程
pub fn delete_stops_process_test() {
  let base = process_count()

  let subscribes =
    subscribe.new()
    |> subscribe.add("a", fn(_, _) { Nil })

  let _ = subscribe.delete(subscribes, "a")

  assert await_process_count_at_most(base, 100)
}

/// delete_all 会关闭所有订阅进程
pub fn delete_all_stops_processes_test() {
  let base = process_count()

  let subscribes =
    subscribe.new()
    |> subscribe.add("a", fn(_, _) { Nil })
    |> subscribe.add("b", fn(_, _) { Nil })

  let _ = subscribe.delete_all(subscribes)

  assert await_process_count_at_most(base, 100)
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
