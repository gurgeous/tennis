//! Formats columns - pretty prints numerics, extracts links, etc. also updates
//! col.natural since this is a great time to do it. Note that `natural` includes
//! header width and is always at least two chars wide. We never layout a col
//! less than two wide.

use super::layout::MIN_COL;
use crate::{ColumnType, Context, util};

pub fn run(ctx: &mut Context<'_>) {
  let digits = ctx.options.digits;

  // `natural` includes the header and is always at least `MIN_COL_WIDTH` (two).
  for col in &mut ctx.columns {
    col.natural = col.natural.max(util::display_width(&col.name)).max(MIN_COL);
  }

  for r in 0..ctx.nrows() {
    for c in 0..ctx.ncols() {
      // format cell, did anything change?
      if let Some(formatted) = format_cell(ctx, r, c, digits) {
        ctx.grid.rows[r][c].set_text(formatted);
      }

      // bump column.natural if necessary
      let cell = &ctx.grid.rows[r][c];
      let col = &mut ctx.columns[c];
      if cell.len() <= col.natural {
        continue;
      }
      let cell_width = util::display_width(cell);
      col.natural = col.natural.max(cell_width);
    }
  }
}

// format one cell, or None if no changes are required
fn format_cell(ctx: &mut Context<'_>, r: usize, c: usize, digits: usize) -> Option<String> {
  let cell = &ctx.grid.rows[r][c];
  if cell.is_empty() {
    return None;
  }
  match ctx.columns[c].ty {
    ColumnType::Float | ColumnType::Int => cell.value().copied().map(|value| value.format(digits)),
    ColumnType::Percent => None,
    ColumnType::String => {
      // Ordinary strings return None; links save the URL before the cell becomes its label.
      let (anchor, href) = util::markdown_link(cell)?;
      ctx.links.insert((r, c), href.to_owned());
      Some(util::squish(anchor).into_owned())
    }
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::{
    Cell, Context, Grid, ResolvedOptions, Value,
    middleware::columns,
    num_locale::NumLocale,
    render::{context::Links, test_grid, test_options},
  };

  fn formatted(grid: Grid, f: impl FnOnce(&mut ResolvedOptions)) -> (Vec<Vec<Cell>>, Links) {
    let mut options = test_options();
    f(&mut options);
    let mut out = Vec::new();
    let mut ctx = Context::new(grid, options, &mut out);
    columns::run(&mut ctx);
    run(&mut ctx);
    (ctx.grid.rows, ctx.links)
  }

  #[test]
  fn test_format_numbers_and_empty_cells() {
    let (rows, _) = formatted(test_grid(["a", "b"], [["1234", ""]]), |_| {});
    assert_eq!(NumLocale::current().format_int(1234), rows[0][0]);
    assert_eq!(Some(&Value::Int(1234)), rows[0][0].value());
    assert_eq!("", rows[0][1]);
  }

  #[test]
  fn test_format_uses_digits_option() {
    let (rows, _) = formatted(test_grid(["a"], [["1234.567"]]), |options| options.digits = 2);
    assert_eq!(NumLocale::current().format_float(1234.567, 2), rows[0][0]);
  }

  #[test]
  fn test_format_extracts_markdown_links() {
    let (rows, links) = formatted(test_grid(["site"], [["[  search \t](https://google.com)"]]), |_| {});
    assert_eq!("search", rows[0][0]);
    assert_eq!(Some("https://google.com"), links.get(&(0, 0)).map(String::as_str));
  }

  #[test]
  fn test_malformed_markdown_link_stays_raw() {
    let (rows, links) = formatted(test_grid(["site"], [["[search](world)"]]), |_| {});
    assert_eq!("[search](world)", rows[0][0]);
    assert!(!links.contains_key(&(0, 0)));
  }

  #[test]
  fn test_vanilla_still_extracts_markdown_links() {
    let (rows, links) = formatted(test_grid(["site"], [["[search](https://google.com)"]]), |options| {
      options.vanilla = true;
    });
    assert_eq!("search", rows[0][0]);
    assert_eq!(Some("https://google.com"), links.get(&(0, 0)).map(String::as_str));
  }
}
