use std::cmp::Ordering;

use crate::{cell::Cell, error::Result, grid::Grid, infer::ColumnType};

//
// Natural comparison
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
  Numeric,
}

// Plan sort columns once so numeric-vs-text behavior cannot vary by row pair.
pub fn sort_keys(grid: &Grid, names: &[String]) -> Result<Vec<SortKey>> {
  names
    .iter()
    .map(|name| {
      let index = grid.position(name)?;
      let kind = match grid.column_type(index) {
        ColumnType::String => SortKind::Natural,
        ColumnType::Int | ColumnType::Float | ColumnType::Percent => SortKind::Numeric,
      };
      Ok(SortKey { index, kind })
    })
    .collect()
}

// Compare rows by planned keys, using later keys only when earlier ones tie.
pub fn compare_rows(a: &[Cell], b: &[Cell], keys: &[SortKey], reverse: bool) -> Ordering {
  for key in keys {
    let ordering = compare_cells(&a[key.index], &b[key.index], key.kind, reverse);
    if ordering != Ordering::Equal {
      return ordering;
    }
  }
  Ordering::Equal
}

// Keep blanks at the bottom for both ascending and descending sorts.
fn compare_cells(a: &Cell, b: &Cell, kind: SortKind, reverse: bool) -> Ordering {
  match (a.is_empty(), b.is_empty()) {
    (true, true) => return Ordering::Equal,
    (true, false) => return Ordering::Greater,
    (false, true) => return Ordering::Less,
    (false, false) => {}
  }

  let ordering = match kind {
    SortKind::Natural => natcmp(a, b),
    SortKind::Numeric => {
      a.value().zip(b.value()).map(|(a, b)| a.cmp_same_type(*b)).expect("numeric columns contain numeric values")
    }
  };
  if reverse { ordering.reverse() } else { ordering }
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
    let kind = SortKind::Numeric;
    assert_eq!(Ordering::Greater, compare_cells(&Cell::from(""), &Cell::from("2"), kind, false));
    assert_eq!(Ordering::Greater, compare_cells(&Cell::from(""), &Cell::from("2"), kind, true));
    assert_eq!(Ordering::Less, compare_cells(&Cell::from("1"), &Cell::from("2"), kind, false));
    assert_eq!(Ordering::Greater, compare_cells(&Cell::from("1"), &Cell::from("2"), kind, true));
  }

  #[test]
  fn test_compare_cells_percent() {
    assert_eq!(Ordering::Less, compare_cells(&Cell::from("-3.5%"), &Cell::from("12%"), SortKind::Numeric, false));
  }

  #[test]
  fn test_compare_rows_continues_after_matching_blank_keys() {
    let keys = [SortKey { index: 0, kind: SortKind::Natural }, SortKey { index: 1, kind: SortKind::Natural }];
    let a = vec![Cell::from(""), Cell::from("a")];
    let b = vec![Cell::from(""), Cell::from("b")];
    assert_eq!(Ordering::Less, compare_rows(&a, &b, &keys, false));
  }
}
