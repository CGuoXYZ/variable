import exception
import gleam/erlang/process
import gleam/list
import gleam/string
import gleeunit

import var.{type Var}
import variable/internal/handle

// ───────────────────────────── 工具 ─────────────────────────────

const timeout = 1000

pub fn main() -> Nil {
  gleeunit.main()
}

fn await_dead(var: Var(a), attempts: Int) -> Bool {
  case attempts <= 0 {
    True -> !handle.is_alive(var)
    False ->
      case handle.is_alive(var) {
        False -> True
        True -> {
          process.sleep(10)
          await_dead(var, attempts - 1)
        }
      }
  }
}

/// 创建值进程，跑完回调后显式关闭并等待退出
fn with_var(value: a, run: fn(Var(a)) -> Nil) -> Nil {
  let assert Ok(var) = handle.new(value)
  run(var)
  handle.closure(var)
  let assert True = await_dead(var, 100)
  Nil
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

fn assert_panics(run: fn() -> a) -> Nil {
  let assert Error(_) = exception.rescue(run)
  Nil
}

// ─────────────────────────── 基础读写 ───────────────────────────

pub fn new_get_test() {
  with_var(5, fn(var) {
    assert handle.get(var) == 5
  })
}

pub fn set_returns_new_value_test() {
  with_var(5, fn(var) {
    assert handle.set(var, 10) == 10
  })
}

pub fn set_then_get_test() {
  with_var(5, fn(var) {
    assert handle.set(var, 10) == 10
    assert handle.get(var) == 10
  })
}

pub fn update_returns_new_value_test() {
  with_var(5, fn(var) {
    assert handle.update(var, fn(n) { n + 1 }) == 6
  })
}

pub fn update_then_get_test() {
  with_var(5, fn(var) {
    assert handle.update(var, fn(n) { n * 2 }) == 10
    assert handle.get(var) == 10
  })
}

pub fn update_chain_test() {
  with_var(0, fn(var) {
    assert handle.update(var, fn(n) { n + 1 }) == 1
    assert handle.update(var, fn(n) { n * 10 }) == 10
    assert handle.update(var, fn(n) { n - 3 }) == 7
    assert handle.get(var) == 7
  })
}

type Point {
  Point(x: Int, y: Int)
}

pub fn custom_type_value_test() {
  with_var(Point(1, 2), fn(var) {
    assert handle.get(var) == Point(1, 2)
    assert handle.update(var, fn(p) { Point(x: p.x + 1, y: p.y + 1) })
      == Point(2, 3)
    assert handle.set(var, Point(9, 9)) == Point(9, 9)
  })
}

// ─────────────────────────── 关闭 / 存活 ───────────────────────────

pub fn closure_kills_process_test() {
  let assert Ok(var) = handle.new(0)
  handle.closure(var)
  assert await_dead(var, 100)
  assert handle.is_alive(var) == False
}

pub fn double_closure_is_safe_test() {
  let assert Ok(var) = handle.new(0)
  handle.closure(var)
  handle.closure(var)
  assert await_dead(var, 100)
  assert handle.is_alive(var) == False
}

pub fn is_alive_test() {
  let assert Ok(var) = handle.new(0)
  assert handle.is_alive(var) == True

  handle.closure(var)
  assert await_dead(var, 100)
  assert handle.is_alive(var) == False
}

pub fn get_after_closure_panics_test() {
  let assert Ok(var) = handle.new(0)
  handle.closure(var)
  assert await_dead(var, 100)
  assert_panics(fn() { handle.get(var) })
}

pub fn set_after_closure_panics_test() {
  let assert Ok(var) = handle.new(0)
  handle.closure(var)
  assert await_dead(var, 100)
  assert_panics(fn() { handle.set(var, 1) })
}

pub fn update_after_closure_panics_test() {
  let assert Ok(var) = handle.new(0)
  handle.closure(var)
  assert await_dead(var, 100)
  assert_panics(fn() { handle.update(var, fn(n) { n + 1 }) })
}

pub fn subscribe_after_closure_panics_test() {
  let assert Ok(var) = handle.new(0)
  handle.closure(var)
  assert await_dead(var, 100)
  assert_panics(fn() { handle.subscribe(var, "a", fn(_, _) { Nil }) })
}

pub fn subscribe_numbers_after_closure_panics_test() {
  let assert Ok(var) = handle.new(0)
  handle.closure(var)
  assert await_dead(var, 100)
  assert_panics(fn() { handle.subscribe_numbers(var) })
}

pub fn subscribe_names_after_closure_panics_test() {
  let assert Ok(var) = handle.new(0)
  handle.closure(var)
  assert await_dead(var, 100)
  assert_panics(fn() { handle.subscribe_names(var) })
}

// ─────────────────────────── 订阅 ───────────────────────────

pub fn subscribe_notifies_test() {
  with_var(0, fn(var) {
    let seen = process.new_subject()
    let _ =
      handle.subscribe(var, "a", fn(old, new) {
        process.send(seen, #(old, new))
      })

    assert handle.set(var, 1) == 1
    assert take(seen, 1) == [#(0, 1)]
  })
}

/// 当前实现：订阅回调 panic 会杀死值进程
///
/// 这个测试会打印 crash report，属于预期行为。
pub fn subscriber_panic_kills_value_process_test() {
  let box = process.new_subject()
  let ready = process.new_subject()
  let release = process.new_subject()

  let _ =
    process.spawn_unlinked(fn() {
      let assert Ok(var) = handle.new(0)
      let _ =
        handle.subscribe(var, "boom", fn(_, _) { panic as "subscriber boom" })
      process.send(box, var)
      process.send(ready, Nil)
      let _ = process.receive(release, 1000)
      handle.closure(var)
      Nil
    })

  let var = process.receive_forever(box)
  let assert Ok(Nil) = process.receive(ready, timeout)

  let _ =
    process.spawn_unlinked(fn() {
      let _ = handle.set(var, 1)
      Nil
    })

  assert await_dead(var, 100)
  process.send(release, Nil)
}

pub fn update_notifies_test() {
  with_var(0, fn(var) {
    let seen = process.new_subject()
    let _ =
      handle.subscribe(var, "a", fn(old, new) {
        process.send(seen, #(old, new))
      })

    assert handle.update(var, fn(n) { n + 1 }) == 1
    assert take(seen, 1) == [#(0, 1)]
  })
}

pub fn multiple_notifications_pairs_test() {
  with_var(0, fn(var) {
    let seen = process.new_subject()
    let _ =
      handle.subscribe(var, "a", fn(old, new) {
        process.send(seen, #(old, new))
      })

    assert handle.set(var, 1) == 1
    assert handle.set(var, 2) == 2
    assert handle.set(var, 3) == 3

    assert take(seen, 3) == [#(0, 1), #(1, 2), #(2, 3)]
  })
}

pub fn same_name_subscription_overwrites_test() {
  with_var(0, fn(var) {
    let old = process.new_subject()
    let new = process.new_subject()
    let _ =
      handle.subscribe(var, "a", fn(old_value, new_value) {
        process.send(old, #(old_value, new_value))
      })
    let _ =
      handle.subscribe(var, "a", fn(old_value, new_value) {
        process.send(new, #(old_value, new_value))
      })

    assert handle.set(var, 1) == 1

    assert take(new, 1) == [#(0, 1)]
    assert_no_message(old)
  })
}

pub fn unsubscribe_stops_notifications_test() {
  with_var(0, fn(var) {
    let seen = process.new_subject()
    let _ =
      handle.subscribe(var, "a", fn(old, new) {
        process.send(seen, #(old, new))
      })

    assert handle.set(var, 1) == 1
    assert take(seen, 1) == [#(0, 1)]

    handle.unsubscribe(var, "a")

    assert handle.set(var, 2) == 2
    assert_no_message(seen)
  })
}

pub fn unsubscribe_is_idempotent_test() {
  with_var(0, fn(var) {
    let _ = handle.subscribe(var, "a", fn(_, _) { Nil })

    handle.unsubscribe(var, "a")
    handle.unsubscribe(var, "a")

    assert handle.is_alive(var) == True
    assert handle.get(var) == 0
  })
}

pub fn unsubscribe_missing_is_safe_test() {
  with_var(0, fn(var) {
    handle.unsubscribe(var, "missing")
    handle.unsubscribe_all(var)
    assert handle.is_alive(var) == True
  })
}

pub fn subscribe_numbers_and_names_test() {
  with_var(0, fn(var) {
    assert handle.subscribe_numbers(var) == 0
    assert handle.subscribe_names(var) == []

    let _ = handle.subscribe(var, "b", fn(_, _) { Nil })
    let _ = handle.subscribe(var, "a", fn(_, _) { Nil })

    assert handle.subscribe_numbers(var) == 2
    assert list.sort(handle.subscribe_names(var), string.compare) == ["a", "b"]

    handle.unsubscribe(var, "a")

    assert handle.subscribe_numbers(var) == 1
    assert handle.subscribe_names(var) == ["b"]

    handle.unsubscribe_all(var)

    assert handle.subscribe_numbers(var) == 0
    assert handle.subscribe_names(var) == []
  })
}

pub fn unsubscribe_all_stops_notifications_test() {
  with_var(0, fn(var) {
    let a = process.new_subject()
    let b = process.new_subject()
    let _ =
      handle.subscribe(var, "a", fn(old, new) { process.send(a, #(old, new)) })
    let _ =
      handle.subscribe(var, "b", fn(old, new) { process.send(b, #(old, new)) })

    assert handle.set(var, 1) == 1
    assert take(a, 1) == [#(0, 1)]
    assert take(b, 1) == [#(0, 1)]

    handle.unsubscribe_all(var)

    assert handle.set(var, 2) == 2
    assert_no_message(a)
    assert_no_message(b)
  })
}

// ─────────────────────────── 并发 ───────────────────────────

pub fn concurrent_update_test() {
  let workers = 10

  with_var(0, fn(var) {
    let done = process.new_subject()

    list.repeat(Nil, workers)
    |> list.each(fn(_) {
      let _ =
        process.spawn_unlinked(fn() {
          let _ = handle.update(var, fn(n) { n + 1 })
          process.send(done, Nil)
          Nil
        })
      Nil
    })

    list.repeat(Nil, workers)
    |> list.each(fn(_) {
      let assert Ok(Nil) = process.receive(done, timeout)
      Nil
    })

    assert handle.get(var) == workers
  })
}
