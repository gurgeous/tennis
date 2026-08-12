//! Typed cell values.

use std::cmp::Ordering;

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

  /// Formats a value for display, grouping whole digits.
  pub fn format(self, digits: usize) -> String {
    match self {
      Self::Int(x) => group_digits(&x.to_string()),
      Self::Float(x) => format_float(x, digits),
      Self::Percent(x) => format!("{}%", format_float(x, digits)),
    }
  }
}

// Format helpers

fn format_float(x: f64, digits: usize) -> String {
  let rounded = format!("{x:.digits$}");
  let (whole, frac) = rounded.split_once('.').unwrap_or((rounded.as_str(), ""));
  let mut buf = group_digits(whole);
  if digits > 0 {
    buf.push('.');
    buf.push_str(frac);
  }
  buf
}

fn group_digits(text: &str) -> String {
  let (sign, digits) = text.strip_prefix('-').map_or(("", text), |digits| ("-", digits));
  let first = (digits.len() - 1) % 3 + 1;
  let mut out = String::with_capacity(text.len() + text.len() / 3);
  out.push_str(sign);
  out.push_str(&digits[..first]);
  for chunk in digits.as_bytes()[first..].chunks(3) {
    out.push(',');
    out.push_str(std::str::from_utf8(chunk).expect("decimal digits are UTF-8"));
  }
  out
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
  fn test_format() {
    for (value, digits, formatted) in [
      (Value::Int(-1234), 3, "-1,234"),
      (Value::Float(1234.567), 2, "1,234.57"),
      (Value::Float(999.6), 0, "1,000"),
      (Value::Float(1.9999), 3, "2.000"),
      (Value::Float(9.99), 1, "10.0"),
      (Value::Float(-0.0001), 3, "-0.000"),
    ] {
      assert_eq!(formatted, value.format(digits));
    }
  }

  #[test]
  fn test_parse_oversized_float() {
    assert_eq!(None, Value::parse(&format!("{}.0", "9".repeat(400))));
  }
}
