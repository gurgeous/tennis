//! Main table type, returned by build() and ready to render

use std::io;

use anstream::{
  AutoStream, ColorChoice,
  stream::{AsLockedWrite, RawStream},
};

use crate::{
  builder::{Builder, types::ColorMode},
  context::Context,
  grid::Grid,
  middleware::{MIDDLEWARE, render},
  resolved::Resolved,
};

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Table {
  pub(crate) grid: Grid,
  pub(crate) options: Resolved,
}

impl Table {
  /// Starts a builder that can load cells, maps, JSON, or records.
  pub fn builder() -> Builder {
    Builder::default()
  }

  pub(crate) fn from_grid(grid: Grid, options: Resolved) -> Self {
    Self { grid, options }
  }

  #[cfg(test)]
  pub(crate) fn headers(&self) -> &[String] {
    self.grid.headers()
  }

  #[cfg(test)]
  pub(crate) fn rows(&self) -> &[Vec<String>] {
    self.grid.rows()
  }

  /// Consumes and renders the table to a string.
  pub fn into_text(self) -> String {
    let mut out = Vec::new();
    self.write_to(&mut out).expect("render to Vec cannot fail");
    String::from_utf8(out).expect("renderer writes valid utf-8")
  }

  /// Consumes and writes the table, taking color and theme into account.
  pub fn write_to<W: RawStream + AsLockedWrite + ?Sized>(self, writer: &mut W) -> io::Result<()> {
    // build context
    let color_choice = match self.options.color {
      ColorMode::Off => ColorChoice::Never,
      ColorMode::On => ColorChoice::Always,
      ColorMode::Auto => unreachable!("resolved color cannot be auto"),
    };
    let mut autostream = AutoStream::new(writer, color_choice);
    let mut ctx = Context::new(self, &mut autostream);

    // pipeline. note if we skip if empty, middleware doesn't attempt to handle
    // the empty case
    if !ctx.is_empty() {
      for middleware in MIDDLEWARE {
        crate::verbose::time(middleware.name, || (middleware.run)(&mut ctx));
      }
    }

    // now render
    crate::verbose::time("render", || render::run(&mut ctx))
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::builder::{
    error::{ColumnOperation, Error},
    types::{Border, ColorMode, ThemeMode},
  };

  fn table(headers: &[&str], rows: &[Vec<&str>]) -> Builder {
    let grid = Grid::new(
      headers.iter().map(|s| s.to_string()).collect(),
      rows.iter().map(|r| r.iter().map(|s| s.to_string()).collect()).collect(),
    )
    .unwrap();
    Table::builder().load_grid(grid)
  }

  #[test]
  fn test_struct_options_api() {
    let out = table(&["name"], &[vec!["alice"]])
      .border(Border::Basic)
      .color(ColorMode::Off)
      .theme(ThemeMode::Dark)
      .width(80)
      .build()
      .map(|table| table.into_text())
      .expect("valid table");
    assert!(out.contains("| alice |"));
  }

  #[test]
  fn test_builder_options_render_table() {
    let out = table(&["name", "score"], &[vec!["alice", "1234"]])
      .border(Border::Basic)
      .color(ColorMode::Off)
      .width(80)
      .build()
      .expect("literal rows are valid")
      .into_text();

    assert!(out.contains("| alice | 1,234 |"));
  }

  #[test]
  fn test_into_text_color_on_has_ansi() {
    let out = table(&["name", "score"], &[vec!["alice", "1234"]])
      .color(ColorMode::On)
      .theme(crate::ThemeMode::Dark)
      .width(80)
      .build()
      .expect("valid table")
      .into_text();
    assert!(out.contains("\x1b["), "into_text should contain ANSI codes when color is on");
  }

  #[test]
  fn test_into_text_color_off_has_no_ansi() {
    let out = table(&["name", "score"], &[vec!["alice", "1234"]])
      .color(ColorMode::Off)
      .theme(crate::ThemeMode::Dark)
      .width(80)
      .build()
      .expect("valid table")
      .into_text();
    assert!(!out.contains("\x1b["), "into_text should not contain ANSI codes when color is off");
  }

  #[test]
  fn test_builder_rejects_ragged_rows() {
    let error = Grid::new(vec!["name".to_owned(), "score".to_owned()], vec![vec!["alice".to_owned()]]).unwrap_err();
    assert_eq!(Error::Jagged { expected: 2, actual: 1 }, error);
  }

  #[test]
  fn test_builder_rejects_missing_big_column() {
    let error = table(&["name"], &[vec!["alice"]]).big("score").build().unwrap_err();
    assert_eq!(
      Error::MissingColumn {
        column: "score".to_owned(),
        operation: Some(ColumnOperation::Big),
        headers: vec!["name".to_owned()],
      },
      error
    );

    let error = table(&["name"], &[vec!["alice"]]).bigger("score").build().unwrap_err();
    assert_eq!(
      Error::MissingColumn {
        column: "score".to_owned(),
        operation: Some(ColumnOperation::Bigger),
        headers: vec!["name".to_owned()],
      },
      error
    );

    let error = table(&["name"], &[vec!["alice"]]).biggest("score").build().unwrap_err();
    assert_eq!(
      Error::MissingColumn {
        column: "score".to_owned(),
        operation: Some(ColumnOperation::Biggest),
        headers: vec!["name".to_owned()],
      },
      error
    );
  }

  #[test]
  fn test_builder_rejects_missing_color_scale_column() {
    let error = table(&["name"], &[vec!["alice"]]).color_scale("score", crate::ColorScale::Green).build().unwrap_err();
    assert_eq!(
      Error::MissingColumn {
        column: "score".to_owned(),
        operation: Some(ColumnOperation::ColorScale),
        headers: vec!["name".to_owned()],
      },
      error
    );
  }

  #[test]
  fn test_builder_validates_option_columns_against_raw_headers() {
    let error = table(&["person_id"], &[vec!["1"]]).titleize(true).big("Person").build().unwrap_err();
    assert_eq!(
      Error::MissingColumn {
        column: "Person".to_owned(),
        operation: Some(ColumnOperation::Big),
        headers: vec!["person_id".to_owned()],
      },
      error
    );
  }
}
