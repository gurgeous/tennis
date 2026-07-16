use std::{cmp::Ordering, fmt::Write};

//
// Small generic helpers
// Public functions are alphabetical.
//

pub const PLACEHOLDER: &str = "—";

// ASCII-case-insensitive substring check.
pub fn has_ascii_case(haystack: &str, needle: &str) -> bool {
  if needle.is_empty() {
    return true;
  }
  let haystack = haystack.as_bytes();
  let needle = needle.as_bytes();
  if needle.len() > haystack.len() {
    return false;
  }
  haystack.windows(needle.len()).any(|window| window.iter().zip(needle).all(|(a, b)| a.eq_ignore_ascii_case(b)))
}

// Escape a string as a JSON string literal.
pub fn json_escape(text: &str) -> String {
  let mut out = String::with_capacity(text.len() + 2);
  out.push('"');
  for ch in text.chars() {
    match ch {
      '"' => out.push_str("\\\""),
      '\\' => out.push_str("\\\\"),
      '\u{08}' => out.push_str("\\b"),
      '\u{0c}' => out.push_str("\\f"),
      '\n' => out.push_str("\\n"),
      '\r' => out.push_str("\\r"),
      '\t' => out.push_str("\\t"),
      ch if ch <= '\u{1f}' => write!(out, "\\u{:04x}", ch as u32).expect("writing to String cannot fail"),
      _ => out.push(ch),
    }
  }
  out.push('"');
  out
}

// Return the smallest and largest value in one pass.
pub fn minmax<T>(values: impl IntoIterator<Item = T>) -> Option<(T, T)>
where
  T: Copy + Ord,
{
  minmax_by(values, Ord::cmp)
}

// Return min/max using a custom comparator.
pub fn minmax_by<T>(values: impl IntoIterator<Item = T>, compare: impl Fn(&T, &T) -> Ordering) -> Option<(T, T)>
where
  T: Copy,
{
  let mut values = values.into_iter();
  let first = values.next()?;
  Some(values.fold((first, first), |(min, max), value| {
    let min = if compare(&value, &min).is_lt() { value } else { min };
    let max = if compare(&value, &max).is_gt() { value } else { max };
    (min, max)
  }))
}

// Match the old JS helper: pluralize with optional count prefix.
pub fn pluralize(word: &str, count: usize, inclusive: bool) -> String {
  let word = if count == 1 { word.to_owned() } else { format!("{word}s") };
  if inclusive { format!("{count} {word}") } else { word }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_minmax() {
    assert_eq!(None, minmax::<i32>([]));
    assert_eq!(Some((7, 7)), minmax([7]));
    assert_eq!(Some((1, 9)), minmax([3, 1, 9, 2]));
    assert_eq!(Some((-5, 10)), minmax([-5, 10]));
  }

  #[test]
  fn test_minmax_by() {
    let values = [(2.0_f64, "b"), (1.0, "a"), (3.0, "c")];
    assert_eq!(Some(((1.0, "a"), (3.0, "c"))), minmax_by(values, |lhs, rhs| lhs.0.total_cmp(&rhs.0)));
  }

  #[test]
  fn test_pluralize() {
    assert_eq!("row", pluralize("row", 1, false));
    assert_eq!("rows", pluralize("row", 2, false));
    assert_eq!("1 row", pluralize("row", 1, true));
    assert_eq!("2 rows", pluralize("row", 2, true));
  }

  #[test]
  fn test_has_ascii_case() {
    assert!(has_ascii_case("Alice", "ali"));
    assert!(has_ascii_case("Alice", "ICE"));
    assert!(has_ascii_case("Alice", "Alice"));
    assert!(has_ascii_case("Alice", "e"));
    assert!(has_ascii_case("Alice", ""));
    assert!(!has_ascii_case("Ali", "Alice"));
    assert!(!has_ascii_case("Alice", "bob"));
  }

  #[test]
  fn test_json_escape() {
    assert_eq!("\"abc\"", json_escape("abc"));
    assert_eq!("\"a\\tb\"", json_escape("a\tb"));
    assert_eq!("\"he said \\\"hi\\\"\"", json_escape("he said \"hi\""));
    assert_eq!("\"slash\\\\path\"", json_escape("slash\\path"));
    assert_eq!("\"\\b\\f\\n\\r\\t\"", json_escape("\u{08}\u{0c}\n\r\t"));
    assert_eq!("\"\\u0001\"", json_escape("\u{01}"));
    assert_eq!("\"香港\"", json_escape("香港"));
  }
}
