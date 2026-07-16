use std::cmp::Ordering;

use tennis::{ColumnType, Grid};

//
// Natural sort
//
// See: https://github.com/sourcefrog/natsort
//

pub fn natcmp(a: &str, b: &str) -> Ordering {
  natord::compare_ignore_case(a, b)
}

//
// sort keys
//

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct SortKey {
  index: usize,
  kind: SortKind,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum SortKind {
  Natural,
  Numeric(ColumnType),
}

// Plan sort columns once so numeric-vs-text behavior cannot vary by row pair.
pub fn sort_keys(grid: &Grid, names: &[String]) -> tennis::Result<Vec<SortKey>> {
  names
    .iter()
    .map(|name| {
      let index = grid.position(name)?;
      let kind = match grid.column_type(index, false) {
        ColumnType::String => SortKind::Natural,
        ty => SortKind::Numeric(ty),
      };
      Ok(SortKey { index, kind })
    })
    .collect()
}

// Compare rows by planned keys, using later keys only when earlier ones tie.
pub fn compare_rows(a: &[String], b: &[String], keys: &[SortKey], reverse: bool) -> Ordering {
  for key in keys {
    let ordering = compare_cells(&a[key.index], &b[key.index], key.kind, reverse);
    if ordering != Ordering::Equal {
      return ordering;
    }
  }
  Ordering::Equal
}

// Keep blanks at the bottom for both ascending and descending sorts.
fn compare_cells(a: &str, b: &str, kind: SortKind, reverse: bool) -> Ordering {
  match (a.is_empty(), b.is_empty()) {
    (true, true) => return Ordering::Equal,
    (true, false) => return Ordering::Greater,
    (false, true) => return Ordering::Less,
    (false, false) => {}
  }

  let ordering = match kind {
    SortKind::Natural => natcmp(a, b),
    SortKind::Numeric(ty) => numeric_cmp(a, b, ty),
  };
  if reverse { ordering.reverse() } else { ordering }
}

// Numeric columns use f64 ordering; column inference keeps mixed text out.
fn numeric_cmp(a: &str, b: &str, ty: ColumnType) -> Ordering {
  let a = parse_sort_number(a, ty).expect("sort inference guarantees numeric cells");
  let b = parse_sort_number(b, ty).expect("sort inference guarantees numeric cells");
  a.total_cmp(&b)
}

fn parse_sort_number(input: &str, ty: ColumnType) -> Option<f64> {
  let input = if ty == ColumnType::Percent { input.strip_suffix('%')? } else { input };
  input.parse().ok()
}

#[cfg(test)]
mod tests {
  use super::*;

  fn lt(a: &str, b: &str) {
    assert_eq!(Ordering::Less, natcmp(a, b), "{a:?} < {b:?}");
  }

  #[test]
  fn test_compare_ignore_case_plain_strings() {
    lt("a", "b");
    assert_eq!(Ordering::Greater, natcmp("b", "a"));
    assert_eq!(Ordering::Equal, natcmp("abc", "ABC"));
    lt("a", "B");
    assert_eq!(Ordering::Greater, natcmp("B", "a"));
  }

  #[test]
  fn test_compare_ignore_case_numeric_runs() {
    lt("a2", "a10");
    lt("rfc1.txt", "rfc822.txt");
    lt("rfc822.txt", "rfc2086.txt");
    lt("A2", "a10");
    assert_eq!(Ordering::Equal, natcmp("RFC1.txt", "rfc1.TXT"));
  }

  #[test]
  fn test_compare_ignore_case_numeric_strings() {
    lt("9", "10");
    lt("2", "100");
    assert_eq!(Ordering::Greater, natcmp("100", "2"));
  }

  #[test]
  fn test_compare_ignore_case_mixed_runs() {
    lt("x2-g8", "x2-y08");
    lt("x2-y08", "x2-y7");
    lt("x2-y7", "x8-y8");
  }

  #[test]
  fn test_compare_ignore_case_decimal_like_strings() {
    for pair in ["1.001", "1.002", "1.010", "1.02", "1.1", "1.3"].windows(2) {
      lt(pair[0], pair[1]);
    }
  }

  #[test]
  fn test_compare_ignore_case_numeric_values() {
    lt("9", "10");
  }

  #[test]
  fn test_compare_ignore_case_leading_whitespace() {
    assert_eq!(Ordering::Equal, natcmp("  a2", "a2"));
    lt("  a2", "a10");
  }

  #[test]
  fn test_compare_ignore_case_negative_signs_are_plain_text() {
    assert_eq!(Ordering::Greater, natcmp("-10", "-5"));
  }

  #[test]
  fn test_compare_cells_keeps_blanks_at_bottom() {
    let kind = SortKind::Numeric(ColumnType::Int);
    assert_eq!(Ordering::Greater, compare_cells("", "2", kind, false));
    assert_eq!(Ordering::Greater, compare_cells("", "2", kind, true));
    assert_eq!(Ordering::Less, compare_cells("1", "2", kind, false));
    assert_eq!(Ordering::Greater, compare_cells("1", "2", kind, true));
  }

  #[test]
  fn test_parse_sort_number() {
    assert_eq!(Some(-10.0), parse_sort_number("-10", ColumnType::Int));
    assert_eq!(Some(0.21), parse_sort_number("0.21", ColumnType::Float));
    assert_eq!(Some(-3.5), parse_sort_number("-3.5%", ColumnType::Percent));
    assert_eq!(None, parse_sort_number("-3.5%", ColumnType::Float));
  }

  #[test]
  fn test_compare_rows_continues_after_matching_blank_keys() {
    let keys = [SortKey { index: 0, kind: SortKind::Natural }, SortKey { index: 1, kind: SortKind::Natural }];
    let a = vec!["".to_owned(), "a".to_owned()];
    let b = vec!["".to_owned(), "b".to_owned()];
    assert_eq!(Ordering::Less, compare_rows(&a, &b, &keys, false));
  }
}
