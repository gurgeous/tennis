//! Cell and header truncation after layout.

use crate::{Context, util};

pub fn run(ctx: &mut Context<'_>) {
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
      let truncated = util::truncate(text, nice);
      row[c].set_text(truncated);
    }
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::{
    Cell, Context, Grid, Resolved, ResolvedWidth,
    middleware::{columns, format, layout},
    render::{test_grid, test_options},
  };

  fn truncated(grid: Grid, f: impl FnOnce(&mut Resolved)) -> (Vec<String>, Vec<Vec<Cell>>) {
    let mut options = test_options();
    f(&mut options);
    let mut out = Vec::new();
    let mut ctx = Context::new(grid, options, &mut out);
    columns::run(&mut ctx);
    format::run(&mut ctx);
    layout::run(&mut ctx);
    run(&mut ctx);
    (ctx.columns.into_iter().map(|column| column.name).collect(), ctx.grid.rows)
  }

  #[test]
  fn test_truncate_headers_and_cells() {
    let (headers, rows) = truncated(test_grid(["long_header"], [["abcdef"]]), |options| {
      options.width = ResolvedWidth::Fixed(8);
    });
    assert_eq!("lon…", headers[0]);
    assert_eq!("abc…", rows[0][0]);
  }

  #[test]
  fn test_truncate_leaves_cells_that_already_fit() {
    let (_headers, rows) =
      truncated(test_grid(["long_header"], [["a"], ["abcdef"]]), |options| options.width = ResolvedWidth::Fixed(8));
    assert_eq!("a", rows[0][0]);
    assert_eq!("abc…", rows[1][0]);
  }
}
