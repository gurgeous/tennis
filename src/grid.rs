//! Rectangular normalized table data.

use std::{borrow::Cow, cmp::Ordering};

use rand::seq::SliceRandom;

use crate::{
  builder::{Error, Result},
  infer::{self, ColumnType},
  util,
};

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Grid {
  pub(crate) headers: Vec<String>,
  pub(crate) rows: Vec<Vec<String>>,
}

impl Grid {
  /// Builds a rectangular grid, trimming ASCII whitespace and collapsing
  /// internal whitespace runs in every header and cell.
  pub fn new(mut headers: Vec<String>, mut rows: Vec<Vec<String>>) -> Result<Self> {
    if let Some(row) = rows.iter().find(|row| row.len() != headers.len()) {
      return Err(Error::Jagged { expected: headers.len(), actual: row.len() });
    }

    for cell in headers.iter_mut().chain(rows.iter_mut().flatten()) {
      if let Cow::Owned(clean) = util::squish(cell) {
        *cell = clean;
      }
    }

    Ok(Self::from_parts(headers, rows))
  }

  fn from_parts(headers: Vec<String>, rows: Vec<Vec<String>>) -> Self {
    debug_assert!(rows.iter().all(|row| row.len() == headers.len()));
    Self { headers, rows }
  }

  pub fn headers(&self) -> &[String] {
    &self.headers
  }

  pub fn rows(&self) -> &[Vec<String>] {
    &self.rows
  }

  pub fn is_empty(&self) -> bool {
    self.rows.is_empty()
  }

  /// Infers the display type for one column.
  ///
  /// # Panics
  ///
  /// Panics if `index` is outside the grid's columns.
  pub fn column_type(&self, index: usize, vanilla: bool) -> ColumnType {
    let header = &self.headers[index];
    let cells = self.rows.iter().map(|row| row[index].as_str());
    infer::infer_column_type(header, cells, vanilla)
  }

  pub fn position(&self, name: &str) -> Result<usize> {
    self.headers.iter().position(|str| str.eq_ignore_ascii_case(name)).ok_or_else(|| Error::MissingColumn {
      column: name.to_owned(),
      operation: None,
      headers: self.headers.clone(),
    })
  }

  pub fn positions(&self, names: &[String]) -> Result<Vec<usize>> {
    names.iter().map(|name| self.position(name)).collect()
  }

  //
  // Column operations
  //

  /// Keep only the columns with the given names, in the given order.
  pub fn select(self, names: &[String]) -> Result<Self> {
    let positions = self.positions(names)?;
    let project = |source: &[String]| positions.iter().map(|&i| source[i].clone()).collect();
    Ok(Self::from_parts(project(&self.headers), self.rows.iter().map(|r| project(r)).collect()))
  }

  /// Remove the columns with the given names.
  pub fn deselect(self, names: &[String]) -> Result<Self> {
    let positions = self.positions(names)?;
    let keep = self
      .headers
      .iter()
      .enumerate()
      .filter_map(|(ii, header)| (!positions.contains(&ii)).then_some(header.clone()))
      .collect::<Vec<_>>();
    self.select(&keep)
  }

  //
  // Row operations
  //

  /// Keep only rows for which `predicate` returns true.
  pub fn filter(mut self, mut pred: impl FnMut(&[String]) -> bool) -> Self {
    self.rows.retain(|row| pred(row));
    self
  }

  /// Sort rows using the given comparator.
  pub fn sort_by(mut self, mut cmp: impl FnMut(&[String], &[String]) -> Ordering) -> Self {
    self.rows.sort_by(|a, b| cmp(a, b));
    self
  }

  /// Randomize row order.
  pub fn shuffle(mut self) -> Self {
    self.rows.shuffle(&mut rand::thread_rng());
    self
  }

  /// Reverse row order.
  pub fn reverse(mut self) -> Self {
    self.rows.reverse();
    self
  }

  /// Keep only the first `n` rows.
  pub fn head(mut self, n: usize) -> Self {
    self.rows.truncate(n);
    self
  }

  /// Keep only the last `n` rows.
  pub fn tail(mut self, n: usize) -> Self {
    let n = n.min(self.rows.len());
    let start = self.rows.len() - n;
    self.rows = self.rows.split_off(start);
    self
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  fn abc() -> Grid {
    Grid::new(
      vec!["name".to_owned(), "score".to_owned()],
      vec![
        vec!["bob".to_owned(), "10".to_owned()],
        vec!["Alice".to_owned(), "2".to_owned()],
        vec!["cara".to_owned(), "20".to_owned()],
      ],
    )
    .unwrap()
  }

  #[test]
  fn test_new() {
    let grid = abc();
    assert_eq!(["name", "score"], grid.headers());
    assert_eq!("bob", grid.rows()[0][0]);
    assert_eq!(
      Err(Error::Jagged { expected: 2, actual: 1 }),
      Grid::new(vec!["name".to_owned(), "score".to_owned()], vec![vec!["alice".to_owned()]])
    );
  }

  #[test]
  fn test_new_squishes_headers_and_cells() {
    let grid = Grid::new(
      vec![" name ".to_owned(), "\tscore\n".to_owned()],
      vec![vec![" alice \t smith ".to_owned(), "  -10  ".to_owned()], vec!["   ".to_owned(), " 2 ".to_owned()]],
    )
    .unwrap();
    assert_eq!(["name", "score"], grid.headers());
    assert_eq!(["alice smith", "-10"], grid.rows()[0].as_slice());
    assert_eq!(["", "2"], grid.rows()[1].as_slice());

    let selected = grid.select(&["score".to_owned()]).unwrap();
    assert_eq!(["score"], selected.headers());
    assert_eq!(["-10"], selected.rows()[0].as_slice());
  }

  #[test]
  fn test_column_type() {
    let grid = Grid::new(vec!["score".to_owned()], vec![vec!["2".to_owned()], vec!["10.5".to_owned()]]).unwrap();
    assert_eq!(ColumnType::Float, grid.column_type(0, false));
    assert_eq!(ColumnType::String, grid.column_type(0, true));
  }

  #[test]
  fn test_position() {
    assert_eq!(Ok(1), abc().position("SCORE"));
    assert_eq!(
      Err(Error::MissingColumn {
        column: "missing".to_owned(),
        operation: None,
        headers: vec!["name".to_owned(), "score".to_owned()],
      }),
      abc().position("missing")
    );
  }

  #[test]
  fn test_positions() {
    assert_eq!(Ok(vec![1, 0]), abc().positions(&["score".to_owned(), "name".to_owned()]));
    assert_eq!(
      Err(Error::MissingColumn {
        column: "missing".to_owned(),
        operation: None,
        headers: vec!["name".to_owned(), "score".to_owned()],
      }),
      abc().positions(&["score".to_owned(), "missing".to_owned()])
    );
  }

  #[test]
  fn test_select() {
    let grid = abc().select(&["score".to_owned(), "name".to_owned()]).unwrap();
    assert_eq!(["score", "name"], grid.headers());
    assert_eq!(["10", "bob"], grid.rows()[0].as_slice());
  }

  #[test]
  fn test_deselect() {
    let grid = abc().deselect(&["score".to_owned()]).unwrap();
    assert_eq!(["name"], grid.headers());
    assert_eq!(["bob"], grid.rows()[0].as_slice());
  }

  #[test]
  fn test_filter() {
    let grid = abc().filter(|row| row.iter().any(|cell| cell.eq_ignore_ascii_case("alice")));
    assert_eq!(1, grid.rows().len());
    assert_eq!("Alice", grid.rows()[0][0]);
  }

  #[test]
  fn test_sort_by() {
    let grid = abc().sort_by(|a, b| a[0].cmp(&b[0]));
    assert_eq!("Alice", grid.rows()[0][0]);
    assert_eq!("bob", grid.rows()[1][0]);
    assert_eq!("cara", grid.rows()[2][0]);
  }

  #[test]
  fn test_shuffle() {
    assert_eq!(3, abc().shuffle().rows().len());
  }

  #[test]
  fn test_reverse() {
    let grid = abc().reverse();
    assert_eq!("cara", grid.rows()[0][0]);
    assert_eq!("bob", grid.rows()[2][0]);
  }

  #[test]
  fn test_head() {
    let grid = abc().head(2);
    assert_eq!(2, grid.rows().len());
    assert_eq!("bob", grid.rows()[0][0]);
  }

  #[test]
  fn test_tail() {
    let grid = abc().tail(2);
    assert_eq!(2, grid.rows().len());
    assert_eq!("Alice", grid.rows()[0][0]);
  }
}
