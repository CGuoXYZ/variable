import exception
import gleam/erlang/process
import gleam/list
import gleam/string
import gleeunit

import var.{type Var}

// ───────────────────────────── 工具 ─────────────────────────────

const timeout = 1000

pub fn main() -> Nil {
  gleeunit.main()
}

/// 在 scope 里跑断言；回调返回 Nil，scope 正常结束则测试通过
fn with(value: a, run: fn(Var(a)) -> Nil) -> Nil {
  let assert Ok(Nil) = var.scope(value, run)
  Nil
}

/// 等值进程真正退出（closure 是异步发送消息的）
fn await_dead(var: Var(a), attempts: Int) -> Bool {
  case attempts <= 0 {
    True -> !var.is_alive(var)
    False ->
      case var.is_alive(var) {
        False -> True
        True -> {
          process.sleep(10)
          await_dead(var, attempts - 1)
        }
      }
  }
}

/// 拿到一个已经逃出 scope 的 Var
fn escaped_var() -> Var(Int) {
  let box = process.new_subject()
  let assert Ok(Nil) =
    var.scope(5, fn(var) {
      process.send(box, var)
      Nil
    })
  process.receive_forever(box)
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

// ─────────────────────────── 读取 / 设置 ───────────────────────────

pub fn get_initial_test() {
  with(5, fn(var) {
    assert var.get(var) == 5
  })
}

pub fn get_repeated_test() {
  with(5, fn(var) {
    assert var.get(var) == 5
    assert var.get(var) == 5
    assert var.get(var) == 5
  })
}

pub fn set_returns_new_value_test() {
  with(5, fn(var) {
    assert var.set(var, 10) == 10
  })
}

pub fn set_then_get_test() {
  with(5, fn(var) {
    assert var.set(var, 10) == 10
    assert var.get(var) == 10
  })
}

pub fn set_many_test() {
  with(0, fn(var) {
    assert var.set(var, 1) == 1
    assert var.set(var, 2) == 2
    assert var.set(var, 3) == 3
    assert var.get(var) == 3
  })
}

// ─────────────────────────── 更新 ───────────────────────────

pub fn update_returns_new_value_test() {
  with(5, fn(var) {
    assert var.update(var, fn(n) { n + 1 }) == 6
  })
}

pub fn update_then_get_test() {
  with(5, fn(var) {
    assert var.update(var, fn(n) { n * 2 }) == 10
    assert var.get(var) == 10
  })
}

pub fn update_chain_test() {
  with(0, fn(var) {
    assert var.update(var, fn(n) { n + 1 }) == 1
    assert var.update(var, fn(n) { n * 10 }) == 10
    assert var.update(var, fn(n) { n - 3 }) == 7
    assert var.get(var) == 7
  })
}

// ─────────────────────────── 类型无关 ───────────────────────────

pub fn string_value_test() {
  with("hello", fn(var) {
    assert var.get(var) == "hello"
    assert var.set(var, "world") == "world"
    assert var.update(var, fn(s) { s <> "!" }) == "world!"
    assert var.get(var) == "world!"
  })
}

pub fn list_value_test() {
  with([1, 2, 3], fn(var) {
    assert var.update(var, fn(list) { list.append(list, [4]) }) == [1, 2, 3, 4]
    assert var.get(var) == [1, 2, 3, 4]
  })
}

type Point {
  Point(x: Int, y: Int)
}

pub fn custom_type_value_test() {
  with(Point(1, 2), fn(var) {
    assert var.get(var) == Point(1, 2)
    assert var.update(var, fn(p) { Point(x: p.x + 1, y: p.y + 1) })
      == Point(2, 3)
    assert var.set(var, Point(9, 9)) == Point(9, 9)
    assert var.get(var) == Point(9, 9)
  })
}

// ─────────────────────────── scope 生命周期 ───────────────────────────

/// 回调的返回值会被 scope 带出来
pub fn scope_returns_callback_value_test() {
  let assert Ok(42) = var.scope(5, fn(var) { var.get(var) + 37 })
  Nil
}

/// 嵌套作用域互不影响
pub fn nested_scope_test() {
  with(1, fn(outer) {
    assert var.set(outer, 2) == 2

    with(10, fn(inner) {
      assert var.set(inner, 20) == 20
      assert var.get(inner) == 20
    })

    assert var.get(outer) == 2
  })
}

pub fn is_alive_in_scope_test() {
  with(5, fn(var) {
    assert var.is_alive(var) == True
  })
}

/// scope 返回后值进程会被关闭
pub fn escaped_var_is_dead_after_scope_test() {
  let escaped = escaped_var()
  assert await_dead(escaped, 100)
  assert var.is_alive(escaped) == False
}

/// 回调 panic 时 defer 仍然会关闭值进程
pub fn scope_closes_on_callback_panic_test() {
  let box = process.new_subject()

  let assert Error(_) =
    exception.rescue(fn() {
      var.scope(5, fn(var) {
        process.send(box, var)
        panic as "scope boom"
      })
    })

  let escaped = process.receive_forever(box)
  assert await_dead(escaped, 100)
}

@external(erlang, "erlang", "throw")
fn throw(value: a) -> b

/// 回调 throw 时 defer 仍然会关闭值进程，并重新抛出异常
pub fn scope_closes_on_callback_throw_test() {
  let box = process.new_subject()

  let assert Error(_) =
    exception.rescue(fn() {
      var.scope(5, fn(var) {
        process.send(box, var)
        throw("scope boom")
      })
    })

  let escaped = process.receive_forever(box)
  assert await_dead(escaped, 100)
}

@external(erlang, "erlang", "exit")
fn exit(reason: a) -> b

/// 回调 exit 时 defer 仍然会关闭值进程，并重新抛出异常
pub fn scope_closes_on_callback_exit_test() {
  let box = process.new_subject()

  let assert Error(_) =
    exception.rescue(fn() {
      var.scope(5, fn(var) {
        process.send(box, var)
        exit("scope boom")
      })
    })

  let escaped = process.receive_forever(box)
  assert await_dead(escaped, 100)
}

/// 当前实现：update 回调 panic 会杀死值进程
///
/// 这个测试会打印 crash report，属于预期行为。
pub fn update_panic_kills_value_process_test() {
  let box = process.new_subject()
  let completed = process.new_subject()

  let _ =
    process.spawn_unlinked(fn() {
      let assert Ok(Nil) =
        var.scope(0, fn(var) {
          process.send(box, var)
          let _ = var.update(var, fn(_) { panic as "update boom" })
          process.send(completed, Nil)
          Nil
        })
      Nil
    })

  let escaped = process.receive_forever(box)
  assert await_dead(escaped, 100)
  // update 没有正常返回，不应该收到 completed
  assert process.receive(completed, 100) == Error(Nil)
}

// ─────────────────────────── 死亡后的访问 ───────────────────────────

pub fn get_on_dead_var_panics_test() {
  let escaped = escaped_var()
  let assert True = await_dead(escaped, 100)
  assert_panics(fn() { var.get(escaped) })
}

pub fn set_on_dead_var_panics_test() {
  let escaped = escaped_var()
  let assert True = await_dead(escaped, 100)
  assert_panics(fn() { var.set(escaped, 1) })
}

pub fn update_on_dead_var_panics_test() {
  let escaped = escaped_var()
  let assert True = await_dead(escaped, 100)
  assert_panics(fn() { var.update(escaped, fn(n) { n + 1 }) })
}

pub fn subscribe_numbers_on_dead_var_panics_test() {
  let escaped = escaped_var()
  let assert True = await_dead(escaped, 100)
  assert_panics(fn() { var.subscribe_numbers(escaped) })
}

pub fn subscribe_names_on_dead_var_panics_test() {
  let escaped = escaped_var()
  let assert True = await_dead(escaped, 100)
  assert_panics(fn() { var.subscribe_names(escaped) })
}

pub fn subscribe_on_dead_var_panics_test() {
  let escaped = escaped_var()
  let assert True = await_dead(escaped, 100)
  assert_panics(fn() { var.subscribe(escaped, "a", fn(_, _) { Nil }) })
}

pub fn unsubscribe_on_dead_var_panics_test() {
  let escaped = escaped_var()
  let assert True = await_dead(escaped, 100)
  assert_panics(fn() { var.unsubscribe(escaped, "a") })
}

pub fn unsubscribe_all_on_dead_var_panics_test() {
  let escaped = escaped_var()
  let assert True = await_dead(escaped, 100)
  assert_panics(fn() { var.unsubscribe_all(escaped) })
}

// ─────────────────────────── 订阅 ───────────────────────────

/// set 通知时同时给出旧值和新值
pub fn subscribe_notifies_old_and_new_test() {
  with(0, fn(var) {
    let seen = process.new_subject()
    let _ =
      var.subscribe(var, "a", fn(old, new) { process.send(seen, #(old, new)) })

    assert var.set(var, 1) == 1
    assert take(seen, 1) == [#(0, 1)]
  })
}

/// update 通知时同时给出旧值和新值
pub fn update_notifies_old_and_new_test() {
  with(0, fn(var) {
    let seen = process.new_subject()
    let _ =
      var.subscribe(var, "a", fn(old, new) { process.send(seen, #(old, new)) })

    assert var.update(var, fn(n) { n + 1 }) == 1
    assert take(seen, 1) == [#(0, 1)]
  })
}

/// 每个订阅者有自己的 mailbox，通知按 set 顺序到达
pub fn multiple_notifications_pairs_test() {
  with(0, fn(var) {
    let seen = process.new_subject()
    let _ =
      var.subscribe(var, "a", fn(old, new) { process.send(seen, #(old, new)) })

    assert var.set(var, 1) == 1
    assert var.set(var, 2) == 2
    assert var.set(var, 3) == 3

    assert take(seen, 3) == [#(0, 1), #(1, 2), #(2, 3)]
  })
}

/// 设成相同的值也会通知，此时旧值等于新值
pub fn set_same_value_still_notifies_test() {
  with(0, fn(var) {
    let seen = process.new_subject()
    let _ =
      var.subscribe(var, "a", fn(old, new) { process.send(seen, #(old, new)) })

    assert var.set(var, 5) == 5
    assert var.set(var, 5) == 5

    assert take(seen, 2) == [#(0, 5), #(5, 5)]
  })
}

/// 多个订阅者都能收到
pub fn multiple_subscribers_receive_test() {
  with(0, fn(var) {
    let a = process.new_subject()
    let b = process.new_subject()
    let _ =
      var.subscribe(var, "a", fn(old, new) { process.send(a, #(old, new)) })
    let _ =
      var.subscribe(var, "b", fn(old, new) { process.send(b, #(old, new)) })

    assert var.set(var, 9) == 9
    assert take(a, 1) == [#(0, 9)]
    assert take(b, 1) == [#(0, 9)]
  })
}

/// 同名订阅会覆盖
pub fn same_name_subscription_overwrites_test() {
  with(0, fn(var) {
    let old = process.new_subject()
    let new = process.new_subject()
    let _ =
      var.subscribe(var, "a", fn(old_value, new_value) {
        process.send(old, #(old_value, new_value))
      })
    let _ =
      var.subscribe(var, "a", fn(old_value, new_value) {
        process.send(new, #(old_value, new_value))
      })

    assert var.set(var, 1) == 1

    assert take(new, 1) == [#(0, 1)]
    assert_no_message(old)
  })
}

/// 取消订阅后不再收到通知
pub fn unsubscribe_stops_notifications_test() {
  with(0, fn(var) {
    let seen = process.new_subject()
    let _ =
      var.subscribe(var, "a", fn(old, new) { process.send(seen, #(old, new)) })

    assert var.set(var, 1) == 1
    assert take(seen, 1) == [#(0, 1)]

    var.unsubscribe(var, "a")

    assert var.set(var, 2) == 2
    assert_no_message(seen)
  })
}

/// 重复退订不崩，也不影响值进程
pub fn unsubscribe_is_idempotent_test() {
  with(0, fn(var) {
    let _ = var.subscribe(var, "a", fn(_, _) { Nil })

    var.unsubscribe(var, "a")
    var.unsubscribe(var, "a")
    var.unsubscribe(var, "a")

    assert var.is_alive(var) == True
    assert var.get(var) == 0
  })
}

/// 取消订阅只影响自己，别的订阅者照常
pub fn unsubscribe_only_affects_itself_test() {
  with(0, fn(var) {
    let a = process.new_subject()
    let b = process.new_subject()
    let _ =
      var.subscribe(var, "a", fn(old, new) { process.send(a, #(old, new)) })
    let _ =
      var.subscribe(var, "b", fn(old, new) { process.send(b, #(old, new)) })

    var.unsubscribe(var, "a")

    assert var.set(var, 1) == 1
    assert_no_message(a)
    assert take(b, 1) == [#(0, 1)]
  })
}

/// 取消全部订阅后不再收到通知
pub fn unsubscribe_all_stops_notifications_test() {
  with(0, fn(var) {
    let a = process.new_subject()
    let b = process.new_subject()
    let _ =
      var.subscribe(var, "a", fn(old, new) { process.send(a, #(old, new)) })
    let _ =
      var.subscribe(var, "b", fn(old, new) { process.send(b, #(old, new)) })

    assert var.set(var, 1) == 1
    assert take(a, 1) == [#(0, 1)]
    assert take(b, 1) == [#(0, 1)]

    var.unsubscribe_all(var)

    assert var.set(var, 2) == 2
    assert_no_message(a)
    assert_no_message(b)
  })
}

/// 没有订阅时取消全部订阅也安全
pub fn unsubscribe_all_empty_test() {
  with(0, fn(var) {
    var.unsubscribe_all(var)
    var.unsubscribe_all(var)
    assert var.is_alive(var) == True
  })
}

/// 订阅数量和名称列表随订阅/退订变化
pub fn subscribe_numbers_and_names_test() {
  with(0, fn(var) {
    assert var.subscribe_numbers(var) == 0
    assert var.subscribe_names(var) == []

    let _ = var.subscribe(var, "b", fn(_, _) { Nil })
    let _ = var.subscribe(var, "a", fn(_, _) { Nil })

    assert var.subscribe_numbers(var) == 2
    assert list.sort(var.subscribe_names(var), string.compare) == ["a", "b"]

    var.unsubscribe(var, "a")

    assert var.subscribe_numbers(var) == 1
    assert var.subscribe_names(var) == ["b"]

    var.unsubscribe_all(var)

    assert var.subscribe_numbers(var) == 0
    assert var.subscribe_names(var) == []
  })
}

/// 同名订阅会覆盖，数量和名称不增加
pub fn subscribe_names_overwrite_test() {
  with(0, fn(var) {
    let _ = var.subscribe(var, "a", fn(_, _) { Nil })
    let _ = var.subscribe(var, "a", fn(_, _) { Nil })

    assert var.subscribe_numbers(var) == 1
    assert var.subscribe_names(var) == ["a"]
  })
}

/// scope 关闭时会取消所有订阅，订阅进程随之退出
pub fn scope_closure_stops_subscriber_processes_test() {
  let base = process_count()

  let assert Ok(Nil) =
    var.scope(0, fn(var) {
      let _ = var.subscribe(var, "a", fn(_, _) { Nil })
      let _ = var.subscribe(var, "b", fn(_, _) { Nil })
      Nil
    })

  // closure 是异步的，等待订阅进程收到 Closure 后退出
  assert await_process_count_at_most(base + 5, 100)
}

/// 慢回调不会阻塞值进程的 set/get
pub fn slow_callback_does_not_block_set_test() {
  with(0, fn(var) {
    let started = process.new_subject()
    let done = process.new_subject()

    let _ =
      var.subscribe(var, "slow", fn(_, _) {
        process.send(started, Nil)
        process.sleep(100)
        process.send(done, Nil)
      })

    assert var.set(var, 1) == 1
    let assert Ok(Nil) = process.receive(started, timeout)

    // 回调还在 sleep，值进程仍然可以处理其他操作
    assert var.set(var, 2) == 2
    assert var.get(var) == 2

    let assert Ok(Nil) = process.receive(done, timeout)
    Nil
  })
}

/// 慢回调期间通知会排队，但每个订阅者内部仍然保序
pub fn slow_callback_keeps_notifications_ordered_test() {
  with(0, fn(var) {
    let seen = process.new_subject()

    let _ =
      var.subscribe(var, "slow", fn(old, new) {
        process.sleep(50)
        process.send(seen, #(old, new))
      })

    assert var.set(var, 1) == 1
    assert var.set(var, 2) == 2
    assert var.set(var, 3) == 3

    assert take(seen, 3) == [#(0, 1), #(1, 2), #(2, 3)]
  })
}

/// 慢订阅者不会阻塞其他订阅者
pub fn slow_subscriber_does_not_delay_others_test() {
  with(0, fn(var) {
    let fast = process.new_subject()

    let _ = var.subscribe(var, "slow", fn(_, _) { process.sleep(300) })
    let _ =
      var.subscribe(var, "fast", fn(old, new) {
        process.send(fast, #(old, new))
      })

    assert var.set(var, 1) == 1
    assert process.receive(fast, 100) == Ok(#(0, 1))
  })
}

/// 订阅回调里 set 同一个 Var 不会死锁
pub fn callback_can_set_same_var_test() {
  with(0, fn(var) {
    let done = process.new_subject()
    let _ =
      var.subscribe(var, "a", fn(_, new) {
        case new {
          1 -> {
            let _ = var.set(var, 101)
            process.send(done, Nil)
          }
          _ -> Nil
        }
      })

    assert var.set(var, 1) == 1

    let assert Ok(Nil) = process.receive(done, timeout)
    assert var.get(var) == 101
  })
}

/// 订阅回调里 update 同一个 Var 不会死锁
pub fn callback_can_update_same_var_test() {
  with(0, fn(var) {
    let done = process.new_subject()
    let _ =
      var.subscribe(var, "a", fn(_, new) {
        case new {
          1 -> {
            let _ = var.update(var, fn(n) { n + 100 })
            process.send(done, Nil)
          }
          _ -> Nil
        }
      })

    assert var.set(var, 1) == 1

    let assert Ok(Nil) = process.receive(done, timeout)
    assert var.get(var) == 101
  })
}

// ─────────────────────────── 并发 ───────────────────────────

/// 多个进程同时 update：值进程串行处理，结果不会丢更新
pub fn concurrent_update_test() {
  let workers = 10

  with(0, fn(var) {
    let done = process.new_subject()

    list.repeat(Nil, workers)
    |> list.each(fn(_) {
      let _ =
        process.spawn_unlinked(fn() {
          let _ = var.update(var, fn(n) { n + 1 })
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

    assert var.get(var) == workers
  })
}

/// 另一个进程设置值，本进程能立刻读到
pub fn cross_process_set_test() {
  with(0, fn(var) {
    let done = process.new_subject()
    let _ =
      process.spawn_unlinked(fn() {
        process.send(done, var.set(var, 7))
        Nil
      })

    let assert Ok(7) = process.receive(done, timeout)
    assert var.get(var) == 7
  })
}
