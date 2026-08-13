//! Generic text helpers shared by layout, columns, and rendering.

use std::{borrow::Cow, cmp::Ordering, fmt::Write as _};

use unicode_truncate::UnicodeTruncateStr;
use unicode_width::UnicodeWidthStr;

pub const PLACEHOLDER: &str = "—";

// Measures display width, avoiding Unicode table lookup for plain ASCII.
pub fn display_width(text: &str) -> usize {
  if text.is_ascii() {
    return text.len();
  }
  text.width()
}

// Parses a whole-cell markdown link into its visible label and URL.
pub fn markdown_link(input: &str) -> Option<(&str, &str)> {
  if !input.starts_with('[') || !input.ends_with(')') {
    return None;
  }
  let label_end = input.find("](")?;
  let label = &input[1..label_end];
  let url = &input[label_end + 2..input.len() - 1];
  if label.is_empty() || !valid_link_url(url) {
    return None;
  }
  Some((label, url))
}

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

// Interpolates a percentile from sorted display widths.
pub fn percentile(values: &mut [f64], pct: f64) -> f64 {
  if values.is_empty() {
    return 0.0;
  }
  values.sort_by(f64::total_cmp);
  let pct = pct.clamp(0.0, 1.0);
  let rank = pct * (values.len() - 1) as f64;
  let low = rank.floor() as usize;
  let high = rank.ceil() as usize;
  if low == high {
    return values[low];
  }
  let weight = rank - low as f64;
  values[low] + (values[high] - values[low]) * weight
}

/// Check if env var is true or 1
pub fn read_bool_env(name: &str) -> bool {
  std::env::var(name).map(|value| value.eq_ignore_ascii_case("true") || value == "1").unwrap_or(false)
}

/// Trims leading/trailing whitespace and collapses internal whitespace
pub fn squish(s: &str) -> Cow<'_, str> {
  // fast path, most strings (99%) don't require squishing
  if is_squished(s) {
    return Cow::Borrowed(s);
  }

  let mut out = String::with_capacity(s.len());
  let mut in_run = false;

  for ch in s.chars() {
    if ch.is_ascii_whitespace() {
      in_run = true;
    } else {
      if in_run && !out.is_empty() {
        out.push(' ');
      }
      in_run = false;
      out.push(ch);
    }
  }

  Cow::Owned(out)
}

#[inline]
fn is_squished(s: &str) -> bool {
  let mut seen = false;
  let mut last = false;
  for byte in s.bytes() {
    let nxt = byte.is_ascii_whitespace();
    if nxt && (!seen || last || byte != b' ') {
      return false;
    }
    seen = true;
    last = nxt;
  }
  !last
}

// Truncates text w/ ellipsis, preserving Unicode grapheme boundaries.
pub fn truncate(text: &str, stop: usize) -> String {
  if stop == 0 {
    // edge case
    return String::new();
  }
  if text.len() <= stop {
    // already fits
    return text.to_owned();
  }
  if text.is_ascii() {
    // ascii is easy
    return format!("{}…", &text[..stop - 1]);
  }

  // slow unicode fallback
  if display_width(text) <= stop {
    return text.to_owned();
  }

  let (head, used) = text.unicode_truncate(stop - 1);
  let mut out = String::with_capacity(stop);
  out.push_str(head);
  out.extend(std::iter::repeat_n(' ', stop - 1 - used));
  out.push('…');
  out
}

// Allows only URLs that are safe to splice into an OSC8 sequence.
fn valid_link_url(url: &str) -> bool {
  (url.starts_with("http://") || url.starts_with("https://"))
    && !url.chars().any(|ch| ch.is_whitespace() || ch.is_control())
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_display_width() {
    assert_eq!(3, display_width("abc"));
    assert_eq!(4, display_width("a\tb\n"));
    assert_eq!(4, display_width("香港"));
    assert_eq!(6, display_width("a香港b"));
  }

  #[test]
  fn test_markdown_link() {
    assert_eq!(Some(("search", "https://google.com")), markdown_link("[search](https://google.com)"));
    assert_eq!(
      Some(("wiki", "https://example.com/David_Rees_(cantante)")),
      markdown_link("[wiki](https://example.com/David_Rees_(cantante))")
    );
    assert_eq!(None, markdown_link("see [search](https://google.com)"));
    assert_eq!(None, markdown_link("[](https://google.com)"));
    assert_eq!(None, markdown_link("[search]()"));
    assert_eq!(None, markdown_link("[search](ftp://example.com)"));
    assert_eq!(None, markdown_link("[search](https://exa mple.com)"));
    assert_eq!(None, markdown_link("[search]"));
  }

  #[test]
  fn test_has_ascii_case() {
    for (haystack, needle, expected) in [
      ("Alice", "ali", true),
      ("Alice", "ICE", true),
      ("Alice", "Alice", true),
      ("Alice", "e", true),
      ("Alice", "", true),
      ("Ali", "Alice", false),
      ("Alice", "bob", false),
    ] {
      assert_eq!(expected, has_ascii_case(haystack, needle));
    }
  }

  #[test]
  fn test_json_escape() {
    for (input, expected) in [
      ("abc", "\"abc\""),
      ("a\tb", "\"a\\tb\""),
      ("he said \"hi\"", "\"he said \\\"hi\\\"\""),
      ("slash\\path", "\"slash\\\\path\""),
      ("\u{08}\u{0c}\n\r\t", "\"\\b\\f\\n\\r\\t\""),
      ("\u{01}", "\"\\u0001\""),
      ("香港", "\"香港\""),
    ] {
      assert_eq!(expected, json_escape(input));
    }
  }

  #[test]
  fn test_minmax_by() {
    let values = [(2.0_f64, "b"), (1.0, "a"), (3.0, "c")];
    assert_eq!(Some(((1.0, "a"), (3.0, "c"))), minmax_by(values, |lhs, rhs| lhs.0.total_cmp(&rhs.0)));
  }

  #[test]
  fn test_percentile() {
    let mut values = [1.0, 10.0, 100.0, 1000.0];
    assert_eq!(0.0, percentile(&mut [], 0.9));
    assert_eq!(1.0, percentile(&mut values, 0.0));
    assert_eq!(55.0, percentile(&mut values, 0.5));
    assert!((percentile(&mut values, 0.9) - 730.0).abs() < 1e-9);
    assert_eq!(1000.0, percentile(&mut values, 1.0));
  }

  #[test]
  fn test_pluralize() {
    for (word, count, inclusive, expected) in
      [("row", 1, false, "row"), ("row", 2, false, "rows"), ("row", 1, true, "1 row"), ("row", 2, true, "2 rows")]
    {
      assert_eq!(expected, pluralize(word, count, inclusive));
    }
  }

  #[test]
  fn test_squish() {
    assert!(matches!(squish("a b c"), Cow::Borrowed(_)));

    assert_eq!(squish("  a \t b\n\nc  "), "a b c");
    assert_eq!(squish(" a"), "a");
    assert_eq!(squish(""), "");
    assert_eq!(squish("   "), "");
  }

  #[test]
  fn test_truncate() {
    assert_eq!("ab", truncate("ab", 5));
    assert_eq!("abc", truncate("abc", 3));
    assert_eq!("ab…", truncate("abcd", 3));
    assert_eq!("…", truncate("abcd", 1));
    assert_eq!("a…", truncate("a香港", 2));
    assert_eq!(" …", truncate("香港", 2));
    assert_eq!("a\tb…", truncate("a\tbcd", 4));
  }
}
