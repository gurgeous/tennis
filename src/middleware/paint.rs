//! Adds color information to context. Ansi color codes to be used for various
//! parts of the table, like header, footer, chrome, etc. Can be complicated due
//! to things like color scales. Render diligently roots around in PaintState to
//! decorate cells with colors.

use std::collections::BTreeMap;

use crate::{ColorScale, column::ColumnType, context::Context, util};

pub(crate) fn run(ctx: &mut Context<'_>) {
  ctx.paint.title = ctx.theme.title.clone();
  ctx.paint.headers = (0..ctx.ncols()).map(|c| ctx.theme.headers[c % ctx.theme.headers.len()].clone()).collect();
  ctx.paint.footer = ctx.theme.chrome.clone();

  paint_color_scales(ctx);
  paint_columns(ctx);
  paint_rows(ctx);
}

//
// paint_xxx
//

// color scales, if any
fn paint_color_scales(ctx: &mut Context<'_>) {
  for col in ctx.columns.clone() {
    let Some(scale) = col.color_scale else { continue };
    match col.ty {
      ColumnType::Int | ColumnType::Float | ColumnType::Percent => paint_numeric_scale(ctx, col.index, scale),
      ColumnType::String => paint_string_scale(ctx, col.index, scale),
    }
  }
}

// some cols get colors
fn paint_columns(ctx: &mut Context<'_>) {
  ctx.paint.columns = ctx
    .columns
    .iter()
    .map(|col| {
      if col.row_number {
        ctx.theme.chrome.clone()
      } else if matches!(col.ty, ColumnType::Int | ColumnType::Float | ColumnType::Percent) {
        ctx.theme.headers[col.index % ctx.theme.headers.len()].clone()
      } else {
        String::new()
      }
    })
    .collect();
}

// zebra stripes
fn paint_rows(ctx: &mut Context<'_>) {
  if !ctx.options.zebra {
    return;
  }

  ctx.paint.rows =
    (0..ctx.nrows()).map(|r| if r.is_multiple_of(2) { ctx.theme.zebra.clone() } else { String::new() }).collect();
}

//
// color scale helpers
//

fn paint_numeric_scale(ctx: &mut Context<'_>, c: usize, scale: ColorScale) {
  // collect (r, value). this requires parsing back into floats, but this is not
  // we don't care
  let mut values = Vec::new();
  for r in 0..ctx.nrows() {
    let Some(x) = parse_numeric(&ctx.grid.rows[r][c], ctx.columns[c].ty) else {
      continue;
    };
    values.push((r, x));
  }
  if values.len() < 2 {
    return;
  }

  let (min, max) = util::minmax(values.iter().map(|(_, x)| *x)).expect("have values");
  if min == max {
    return;
  }

  for (r, value) in values {
    let t = (value - min) / (max - min);
    ctx.paint.cells.insert((r, c), scale.paint(t));
  }
}

// String scales are rank-based, not distance-based. Empty cells are ignored.
fn paint_string_scale(ctx: &mut Context<'_>, c: usize, scale: ColorScale) {
  let rows = &ctx.grid.rows;

  // build map from unique value => rank
  let mut values = BTreeMap::new();
  for row in &ctx.grid.rows {
    let value = row[c].as_str();
    if !value.is_empty() && !values.contains_key(value) {
      let rank = values.len();
      values.insert(value, rank);
    }
  }
  if values.len() < 2 {
    return;
  }

  // now apply "rank" as color scalue value to col
  let max_rank = (values.len() - 1) as f64;
  let cells = &mut ctx.paint.cells;
  for (r, row) in rows.iter().enumerate() {
    let value = row[c].as_str();
    if value.is_empty() {
      continue;
    }
    let rank = *values.get(value).expect("value index exists") as f64;
    let t = rank / max_rank;
    cells.insert((r, c), scale.paint(t));
  }
}

fn parse_numeric(text: &str, ty: ColumnType) -> Option<f64> {
  if text.is_empty() {
    return None;
  }
  let text = match ty {
    ColumnType::Percent => text.strip_suffix('%')?,
    ColumnType::Int | ColumnType::Float => text,
    ColumnType::String => return None,
  };
  text.replace(',', "").parse::<f64>().ok()
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::{
    Grid, IntoCells, Table,
    builder::types::ColorMode,
    context::{Context, PaintState},
    middleware,
    resolved::{Resolved, ResolvedTheme, ResolvedWidth},
  };

  fn table<H, R>(headers: H, rows: impl IntoIterator<Item = R>) -> Table
  where
    H: IntoCells,
    R: IntoCells,
  {
    let rows = rows.into_iter().map(IntoCells::into_cells).collect();
    Table::builder().load_grid(Grid::new(headers.into_cells(), rows).expect("valid grid")).build().expect("valid table")
  }

  fn painted(mut table: Table, f: impl FnOnce(&mut Resolved)) -> PaintState {
    table.options.color = ColorMode::On;
    table.options.theme = ResolvedTheme::Dark;
    table.options.width = ResolvedWidth::Fixed(80);
    f(&mut table.options);

    let mut out = Vec::new();
    let mut ctx = Context::new(table, &mut out);
    middleware::columns::run(&mut ctx);
    middleware::format::run(&mut ctx);
    middleware::layout::run(&mut ctx);
    run(&mut ctx);
    middleware::truncate::run(&mut ctx);
    ctx.paint
  }

  #[test]
  fn test_paint_headers() {
    let paint = painted(table(["name", "score"], [["alice", "1234"]]), |_| {});
    assert_eq!(2, paint.headers.len());
    assert!(!paint.headers[0].is_empty());
    assert!(!paint.headers[1].is_empty());
    assert_ne!(paint.headers[0], paint.headers[1]);
  }

  #[test]
  fn test_paint_row_numbers_are_chrome() {
    let paint = painted(table(["name", "score"], [["alice", ""]]), |options| {
      options.row_numbers = true;
    });
    assert!(!paint.columns[0].is_empty());
  }

  #[test]
  fn test_paint_numeric_cells_use_header_paint() {
    let paint = painted(table(["name", "score"], [["alice", "1234"]]), |_| {});
    assert_eq!(paint.headers[1], paint.columns[1]);
  }

  #[test]
  fn test_paint_zebra_rows() {
    let paint = painted(table(["name"], [["alice"], ["bob"]]), |options| {
      options.zebra = true;
    });
    assert!(!paint.rows[0].is_empty());
    assert!(paint.rows[1].is_empty());
  }

  #[test]
  fn test_paint_numeric_color_scale() {
    let paint = painted(table(["name", "score"], [["alice", "1"], ["bob", "10"]]), |options| {
      options.color_scales.push(("score".to_owned(), ColorScale::RedGreen));
    });
    assert_eq!(2, paint.cells.len());
    assert!(paint.cells.contains_key(&(0, 1)));
    assert!(paint.cells.contains_key(&(1, 1)));
  }

  #[test]
  fn test_paint_negative_numeric_color_scale() {
    let paint = painted(table(["delta"], [["-10"], ["10"]]), |options| {
      options.color_scales.push(("delta".to_owned(), ColorScale::GreenRed));
    });
    assert_eq!(2, paint.cells.len());
    assert_ne!(paint.cells.get(&(0, 0)), paint.cells.get(&(1, 0)));
  }

  #[test]
  fn test_paint_percent_color_scale() {
    let paint = painted(table(["pct"], [["10%"], ["90%"]]), |options| {
      options.color_scales.push(("pct".to_owned(), ColorScale::GreenRed));
    });
    assert_eq!(2, paint.cells.len());
  }

  #[test]
  fn test_paint_string_color_scale() {
    let paint = painted(table(["status"], [["ok"], ["warn"], ["down"]]), |options| {
      options.color_scales.push(("status".to_owned(), ColorScale::GreenYellowRed));
    });
    assert_eq!(3, paint.cells.len());
  }

  #[test]
  fn test_paint_string_color_scale_skips_empty() {
    let paint = painted(table(["status"], [[""], ["warn"], ["down"]]), |options| {
      options.color_scales.push(("status".to_owned(), ColorScale::GreenYellowRed));
    });
    assert_eq!(2, paint.cells.len());
    assert!(!paint.cells.contains_key(&(0, 0)));
  }

  #[test]
  fn test_paint_color_scale_uniform_numeric_is_empty() {
    let paint = painted(table(["score"], [["10"], ["10"]]), |options| {
      options.color_scales.push(("score".to_owned(), ColorScale::GreenRed));
    });
    assert!(paint.cells.is_empty());
  }

  #[test]
  fn test_paint_color_scale_uniform_string_is_empty() {
    let paint = painted(table(["status"], [["ok"], ["ok"]]), |options| {
      options.color_scales.push(("status".to_owned(), ColorScale::GreenRed));
    });
    assert!(paint.cells.is_empty());
  }
}
