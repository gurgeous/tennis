//! Formats columns - pretty prints numerics, extracts links, etc. also updates
//! col.natural since this is a great time to do it. Note that `natural` includes
//! header width and is always at least two chars wide. We never layout a col
//! less than two wide.

use crate::{column::ColumnType, context::Context, middleware::layout::MIN_COL, number, util};

pub(crate) fn run(ctx: &mut Context<'_>) {
  let digits = ctx.options.digits;

  // `natural` includes the header and is always at least `MIN_COL_WIDTH` (two).
  for col in &mut ctx.columns {
    col.natural = col.natural.max(util::display_width(&col.name)).max(MIN_COL);
  }

  for r in 0..ctx.nrows() {
    for c in 0..ctx.ncols() {
      // format cell, did anything change?
      if let Some(formatted) = format_cell(ctx, r, c, digits) {
        ctx.grid.rows[r][c] = formatted;
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
  let f = &ctx.grid.rows[r][c];
  if f.is_empty() {
    return None;
  }
  match ctx.columns[c].ty {
    ColumnType::Float => Some(number::format_float(f, digits)),
    ColumnType::Int if f.len() <= 3 && !f.starts_with('-') => None,
    ColumnType::Int => Some(number::format_int(f)),
    ColumnType::Percent => None,
    ColumnType::String => {
      // Ordinary strings return None; links save the URL before the cell becomes its label.
      let (anchor, href) = util::markdown_link(f)?;
      ctx.links.insert((r, c), href.to_owned());
      Some(util::squish(anchor).into_owned())
    }
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::{
    Grid, IntoCells, Table,
    context::{Context, Links},
    middleware,
    resolved::Resolved,
  };

  fn table<H, R>(headers: H, rows: impl IntoIterator<Item = R>) -> Table
  where
    H: IntoCells,
    R: IntoCells,
  {
    let rows = rows.into_iter().map(IntoCells::into_cells).collect();
    Table::builder().load_grid(Grid::new(headers.into_cells(), rows).expect("valid grid")).build().expect("valid table")
  }

  fn formatted(mut table: Table, f: impl FnOnce(&mut Resolved)) -> (Vec<Vec<String>>, Links) {
    f(&mut table.options);
    table.options.color = crate::ColorMode::Off;
    let mut out = Vec::new();
    let mut ctx = Context::new(table, &mut out);
    middleware::columns::run(&mut ctx);
    run(&mut ctx);
    (ctx.grid.rows, ctx.links)
  }

  #[test]
  fn test_format_numbers_and_empty_cells() {
    let (rows, _) = formatted(table(["a", "b"], [["1234", ""]]), |_| {});
    assert_eq!("1,234", rows[0][0]);
    assert_eq!("", rows[0][1]);
  }

  #[test]
  fn test_format_uses_digits_option() {
    let (rows, _) = formatted(table(["a"], [["1234.567"]]), |options| options.digits = 2);
    assert_eq!("1,234.57", rows[0][0]);
  }

  #[test]
  fn test_format_extracts_markdown_links() {
    let (rows, links) = formatted(table(["site"], [["[  search \t](https://google.com)"]]), |_| {});
    assert_eq!("search", rows[0][0]);
    assert_eq!(Some("https://google.com"), links.get(&(0, 0)).map(String::as_str));
  }

  #[test]
  fn test_malformed_markdown_link_stays_raw() {
    let (rows, links) = formatted(table(["site"], [["[search](world)"]]), |_| {});
    assert_eq!("[search](world)", rows[0][0]);
    assert!(!links.contains_key(&(0, 0)));
  }

  #[test]
  fn test_vanilla_still_extracts_markdown_links() {
    let (rows, links) = formatted(table(["site"], [["[search](https://google.com)"]]), |options| {
      options.vanilla = true;
    });
    assert_eq!("search", rows[0][0]);
    assert_eq!(Some("https://google.com"), links.get(&(0, 0)).map(String::as_str));
  }
}
