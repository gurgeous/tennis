//! Typed cell values.

use std::cmp::Ordering;

use crate::num_locale::NumLocale;

/// Numeric cell value after column inference.
/// Percent values retain display units: `12%` is `Percent(12.0)`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Value {
  Int(i64),
  Float(f64),
  Percent(f64),
}

impl Value {
  // Parsing

  pub(crate) fn parse(text: &str) -> Option<Self> {
    if let Some(text) = text.strip_suffix('%') {
      return text.parse().ok().filter(|x: &f64| x.is_finite()).map(Self::Percent);
    }
    if let Ok(x) = text.parse() {
      return Some(Self::Int(x));
    }
    text.parse().ok().filter(|x: &f64| x.is_finite()).map(Self::Float)
  }

  /// convert to f64 if possible (only used for colorscale)
  pub fn as_f64(self) -> f64 {
    match self {
      Self::Int(x) => x as f64,
      Self::Float(x) | Self::Percent(x) => x,
    }
  }

  /// Compares values to the same value type.
  pub fn cmp_same_type(self, other: Self) -> Ordering {
    match (self, other) {
      (Self::Int(a), Self::Int(b)) => a.cmp(&b),
      (Self::Float(a), Self::Float(b)) | (Self::Percent(a), Self::Percent(b)) => a.total_cmp(&b),
      _ => unreachable!("columns contain one value type"),
    }
  }

  /// Formats a value for display using the current numeric locale.
  pub fn format(self, digits: usize) -> String {
    let locale = NumLocale::current();
    match self {
      Self::Int(x) => locale.format_int(x),
      Self::Float(x) => locale.format_float(x, digits),
      Self::Percent(x) => locale.format_percent(x, digits),
    }
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_parse() {
    for (text, value) in [
      ("123", Value::Int(123)),
      ("-1.25", Value::Float(-1.25)),
      ("12%", Value::Percent(12.0)),
      ("-3.5%", Value::Percent(-3.5)),
      (".5", Value::Float(0.5)),
      ("1.", Value::Float(1.0)),
      ("+1", Value::Int(1)),
      ("1e3", Value::Float(1000.0)),
    ] {
      assert_eq!(Some(value), Value::parse(text));
    }
    for text in ["", "abc"] {
      assert_eq!(None, Value::parse(text), "{text}");
    }
  }

  #[test]
  fn test_parse_oversized_float() {
    assert_eq!(None, Value::parse(&format!("{}.0", "9".repeat(400))));
  }
}
