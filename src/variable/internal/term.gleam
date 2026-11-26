pub opaque type Term {
  Term(deadline: Int)
  Forever
}

/// 根据超时时间获取期限
pub fn deadline(timeout: Int) -> Term {
  Term(deadline: monotonic_ms() + timeout)
}

/// 永久期限
pub fn forever() -> Term {
  Forever
}

/// 是否到期
pub fn is_expired(term: Term) -> Bool {
  case term {
    Forever -> False
    Term(deadline:) -> monotonic_ms() >= deadline
  }
}

@external(erlang, "term_ffi", "monotonic_ms")
pub fn monotonic_ms() -> Int
