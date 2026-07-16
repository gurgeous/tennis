//! Cell and header truncation after layout.

use crate::{context::Context, util};

pub(crate) fn run(ctx: &mut Context<'_>) {
  for (c, col) in ctx.columns.iter_mut().enumerate() {
    // `nice` is our final layout width
    let nice = col.nice;

    // if col already fits, nothing to do!
    if nice >= col.natural {
      continue;
    }

    // truncate header
    if util::display_width(&col.name) > nice {
      col.name = util::truncate(&col.name, nice);
    }

    // truncate cells
    for row in &mut ctx.grid.rows {
      let text = &row[c];
      if text.len() <= nice {
        // this check saves a copy and dramatically speeds up the common case
        continue;
      }
      row[c] = util::truncate(text, nice);
    }
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::{
    Grid, IntoCells, Table,
    context::Context,
    middleware,
    resolved::{Resolved, ResolvedWidth},
  };

  fn table<H, R>(headers: H, rows: impl IntoIterator<Item = R>) -> Table
  where
    H: IntoCells,
    R: IntoCells,
  {
    let rows = rows.into_iter().map(IntoCells::into_cells).collect();
    Table::builder().load_grid(Grid::new(headers.into_cells(), rows).expect("valid grid")).build().expect("valid table")
  }

  fn truncated(mut table: Table, f: impl FnOnce(&mut Resolved)) -> (Vec<String>, Vec<Vec<String>>) {
    f(&mut table.options);
    table.options.color = crate::ColorMode::Off;
    let mut out = Vec::new();
    let mut ctx = Context::new(table, &mut out);
    middleware::columns::run(&mut ctx);
    middleware::format::run(&mut ctx);
    middleware::layout::run(&mut ctx);
    run(&mut ctx);
    (ctx.columns.into_iter().map(|column| column.name).collect(), ctx.grid.rows)
  }

  #[test]
  fn test_truncate_headers_and_cells() {
    let (headers, rows) = truncated(table(["long_header"], [["abcdef"]]), |options| {
      options.width = ResolvedWidth::Fixed(8);
    });
    assert_eq!("lon…", headers[0]);
    assert_eq!("abc…", rows[0][0]);
  }

  #[test]
  fn test_truncate_leaves_cells_that_already_fit() {
    let (_headers, rows) =
      truncated(table(["long_header"], [["a"], ["abcdef"]]), |options| options.width = ResolvedWidth::Fixed(8));
    assert_eq!("a", rows[0][0]);
    assert_eq!("abc…", rows[1][0]);
  }
}
