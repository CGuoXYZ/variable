# variable

使用OTP进程模拟的临时可变值

Gleam推荐以不变性优先，**建议只在确实需要时才考虑使用**

只支持**Erlang**端

[![Package Version](https://img.shields.io/hexpm/v/variable)](https://hex.pm/packages/variable)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://variable.hexdocs.pm/)

```sh
gleam add variable
```

***

## Example
使用`scope`函数创建可变值，回调结束时销毁

每个`Var`对应一个进程，读写靠消息传递
```gleam
import gleam/otp/actor.{type StartError}
import var

pub fn main() -> Result(Nil, StartError) {
  use val <- var.scope(0)

  // 获取值
  assert var.get(val) == 0

  // 设置并返回新的值
  assert var.set(val, 10) == 10

  // 使用函数更新并返回新的值
  assert var.update(val, fn(n) { n * 2 }) == 20

  assert var.get(val) == 20

  Nil
}
```

***

## Subscribe
订阅函数，在值变化时收到`旧值`和`新值`
```gleam
import gleam/io
import gleam/otp/actor.{type StartError}
import gleam/string
import var

pub fn main() -> Result(Nil, StartError) {
  use val <- var.scope("abc")

  // 使用名称订阅函数
  var.subscribe(val, "log", fn(old, new) { io.println(old <> " -> " <> new) })

  // 值发生变化时通知订阅
  var.set(val, "hello")
  var.update(val, string.append(_, " "))
  var.update(val, string.append(_, "world"))

  assert var.subscribe_count(val) == 1
  assert var.subscribe_names(val) == ["log"]
  assert var.is_subscribe(val, "log")

  // 使用名称取消订阅
  var.unsubscribe(val, "log")

  assert var.subscribe_count(val) == 0
  assert var.subscribe_names(val) == []
  assert !var.is_subscribe(val, "log")

  Nil
}
```
在订阅函数中`set`/`update`同一个`Var`会导致循环

***

`scope`在回调结束时会终止进程，之后再用则会`panic`

可以用`is_alive`函数检查进程是否存活
```gleam
case var.is_alive(val) {
  True -> todo
  False -> todo
}
```
