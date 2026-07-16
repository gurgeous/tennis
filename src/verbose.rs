//! TENNIS_VERBOSE

use std::{fmt, time::Instant};

/// log if TENNIS_VERBOSE
pub fn log(args: fmt::Arguments<'_>) {
  if enabled() {
    eprintln!("tennis: {args}");
  }
}

/// time lambda, print timing if TENNIS_VERBOSE
pub fn time<T>(label: &str, f: impl FnOnce() -> T) -> T {
  let tm = Instant::now();
  let out = f();
  log(format_args!("{label:<14} {:>10.3} ms", tm.elapsed().as_secs_f64() * 1000.0));
  out
}

// internal

const TENNIS_VERBOSE: &str = "TENNIS_VERBOSE";

fn enabled() -> bool {
  std::env::var_os(TENNIS_VERBOSE).is_some_and(|value| !value.is_empty())
}
