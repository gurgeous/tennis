//! Generic text helpers shared by layout, columns, and rendering.

use std::borrow::Cow;

use unicode_truncate::UnicodeTruncateStr;
use unicode_width::UnicodeWidthStr;

// Capitalizes one titleized word, lowercasing the rest.
pub(crate) fn capitalize(word: &str) -> String {
  let mut chars = word.chars();
  let Some(first) = chars.next() else {
    return String::new();
  };
  first.to_uppercase().chain(chars.flat_map(char::to_lowercase)).collect()
}

// Measures display width, avoiding Unicode table lookup for plain ASCII.
pub(crate) fn display_width(text: &str) -> usize {
  if text.is_ascii() {
    return text.len();
  }
  text.width()
}

// Parses a whole-cell markdown link into its visible label and URL.
pub(crate) fn markdown_link(input: &str) -> Option<(&str, &str)> {
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

// Scans a numeric iterator once and returns its min and max.
pub(crate) fn minmax(values: impl IntoIterator<Item = f64>) -> Option<(f64, f64)> {
  let mut values = values.into_iter();
  let first = values.next()?;
  Some(values.fold((first, first), |(min, max), value| (min.min(value), max.max(value))))
}

// Interpolates a percentile from sorted display widths.
pub(crate) fn percentile(values: &mut [f64], pct: f64) -> f64 {
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
pub(crate) fn read_bool_env(name: &str) -> bool {
  std::env::var(name).map(|value| value.eq_ignore_ascii_case("true") || value == "1").unwrap_or(false)
}

/// Trims leading/trailing whitespace and collapses internal whitespace
pub(crate) fn squish(s: &str) -> Cow<'_, str> {
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

// Converts machine-style headers like `person_id` into display labels.
pub(crate) fn titleize(input: &str) -> String {
  let input = input.strip_suffix("_id").unwrap_or(input);
  let mut spaced = String::new();
  let mut prev_word = false;

  for ch in input.chars() {
    if ch == '_' {
      spaced.push(' ');
      prev_word = false;
    } else if ch.is_uppercase() && prev_word {
      spaced.push(' ');
      spaced.push(ch);
      prev_word = true;
    } else {
      spaced.push(ch);
      prev_word = ch.is_alphanumeric();
    }
  }

  spaced.split_whitespace().map(capitalize).collect::<Vec<_>>().join(" ")
}

// Truncates text w/ ellipsis, preserving Unicode grapheme boundaries.
pub(crate) fn truncate(text: &str, stop: usize) -> String {
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
  fn test_minmax() {
    assert_eq!(None, minmax([]));
    assert_eq!(Some((3.0, 3.0)), minmax([3.0]));
    assert_eq!(Some((-2.0, 10.0)), minmax([3.0, -2.0, 10.0, 4.0]));
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
  fn test_squish() {
    assert!(matches!(squish("a b c"), Cow::Borrowed(_)));

    assert_eq!(squish("  a \t b\n\nc  "), "a b c");
    assert_eq!(squish(" a"), "a");
    assert_eq!(squish(""), "");
    assert_eq!(squish("   "), "");
  }

  #[test]
  fn test_titleize_matches_ruby_cases() {
    let cases = [
      ("action", "Action"),
      ("action_id", "Action"),
      ("created_at", "Created At"),
      ("HTTP_status", "H T T P Status"),
      ("serp_total_time", "Serp Total Time"),
      ("serp time", "Serp Time"),
      ("SerpTime", "Serp Time"),
    ];
    for (input, want) in cases {
      assert_eq!(want, titleize(input));
    }
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
