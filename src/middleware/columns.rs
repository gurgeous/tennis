//! Populates ctx.columns.

use crate::{column::Column, context::Context};

pub(crate) fn run(ctx: &mut Context<'_>) {
  let mut columns: Vec<Column> = ctx.grid.headers.iter().enumerate().map(|(ii, _)| Column::new(ctx, ii)).collect();

  // prepend row numbers if required
  if ctx.options.row_numbers {
    columns.insert(0, Column::row_number());
    for (ii, row) in ctx.grid.rows.iter_mut().enumerate() {
      row.insert(0, (ii + 1).to_string());
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
  use crate::{Grid, IntoCells, Table, column::Column, context::Context, resolved::Resolved};

  fn table<H, R>(headers: H, rows: impl IntoIterator<Item = R>) -> Table
  where
    H: IntoCells,
    R: IntoCells,
  {
    let rows = rows.into_iter().map(IntoCells::into_cells).collect();
    Table::builder().load_grid(Grid::new(headers.into_cells(), rows).expect("valid grid")).build().expect("valid table")
  }

  fn columns(mut table: Table, f: impl FnOnce(&mut Resolved)) -> (Vec<Column>, Vec<Vec<String>>) {
    f(&mut table.options);
    table.options.color = crate::ColorMode::Off;
    let mut out = Vec::new();
    let mut ctx = Context::new(table, &mut out);
    run(&mut ctx);
    (ctx.columns, ctx.grid.rows)
  }

  #[test]
  fn test_row_numbers() {
    let (columns, rows) = columns(table(["name"], [["alice"], ["bob"]]), |options| options.row_numbers = true);
    assert_eq!("#", columns[0].name);
    assert!(columns[0].row_number);
    assert_eq!(vec!["1".to_owned(), "alice".to_owned()], rows[0]);
    assert_eq!(vec!["2".to_owned(), "bob".to_owned()], rows[1]);
  }
}
