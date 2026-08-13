//! Populates ctx.columns.

use super::super::{column::Column, context::Context};

pub(crate) fn run(ctx: &mut Context<'_>) {
  let mut columns: Vec<Column> = ctx.grid.headers.iter().enumerate().map(|(ii, _)| Column::new(ctx, ii)).collect();

  // prepend row numbers if required
  if ctx.options.row_numbers {
    columns.insert(0, Column::row_number());
    for (ii, row) in ctx.grid.rows.iter_mut().enumerate() {
      row.insert(0, (ii + 1).to_string().into());
    }
  }

  for (ii, col) in columns.iter_mut().enumerate() {
    col.index = ii;
  }

  ctx.columns = columns;
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::{cell::Cell, grid::Grid};

  fn columns(grid: Grid) -> (Vec<Column>, Vec<Vec<Cell>>) {
    let mut options = crate::render::test_options();
    options.row_numbers = true;
    let mut out = Vec::new();
    let mut ctx = Context::new(grid, options, &mut out);
    run(&mut ctx);
    (ctx.columns, ctx.grid.rows)
  }

  #[test]
  fn test_row_numbers() {
    let (columns, rows) = columns(crate::render::test_grid(["name"], [["alice"], ["bob"]]));
    assert_eq!("#", columns[0].name);
    assert!(columns[0].row_number);
    assert_eq!(vec!["1".to_owned(), "alice".to_owned()], rows[0]);
    assert_eq!(vec!["2".to_owned(), "bob".to_owned()], rows[1]);
  }
}
