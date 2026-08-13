//! Takes natural column widths and turns them into a nice layout that fits the
//! terminal.
//!
//! 1. Calculate each column's `natural` width, which would be large enough to contain the header
//!    and each cell without truncation. This happens in `columns` middleware for perf.
//! 2. Calculate `budget` - how much space is available in the terminal once we subtact the table
//!    borders we know we need to draw later?
//! 3. Sort columns by `natural`.
//! 4. Enumerate cols. For each col we have a sense of `fair` width, which is just sorta dividing
//!    available space by number of cols we still have to process.
//! 5. `narrow` cols are smaller than the current `fair` width. Let those use `natural` width. They
//!    can be full size.
//! 6. Once we hit a column that is wider than `fair`, switch to `wide` mode. Just give them
//!    leftover budget as best we can.
//!
//! Those are the basics. The user can also manually ask for columns to get
//! extra space by marking them as "big" levels 1, 2 and 3. Big1 columns get to
//! split half the terminal size, and we avoid overflowing the terminal. If the
//! user requests some big2 or big3 cols, those can get MUCH bigger and we don't
//! worry about overflow. "Just show me the data, please!"
//!
//! Glossary:
//!   natural    Measured full width of a column, including header and cells.
//!   budget     Space available after borders and chrome.
//!   narrow     "Narrow" columns get to keep natural width.
//!   wide       "Wide" columns split the leftover budget after narrow.

use crate::{
  render::{column::Column, context::Context, options::ColumnBig, resolved::ResolvedWidth},
  util::{self, display_width},
};

//
// main entrypoint
//

pub fn run(ctx: &mut Context<'_>) {
  match ctx.options.width {
    ResolvedWidth::Fixed(width) => autolayout(ctx, width),
    ResolvedWidth::Header => natural_headers(ctx),
    ResolvedWidth::Natural => natural_widths(ctx),
  }
}

// columns are always at least 2 chars wide
pub const MIN_COL: usize = 2;

fn autolayout(ctx: &mut Context<'_>, width: usize) {
  let mut cols = ctx.columns.clone();

  // calculate budget
  let mut budget = width.saturating_sub(ctx.border.chrome_width(cols.len()));

  // narrowest to widest
  cols.sort_by_key(|col| col.natural);

  // `big1` columns get half the budget.
  let (mut big1, mut work): (Vec<_>, Vec<_>) = cols.drain(..).partition(|col| col.big == ColumnBig::Big);
  apply_big1(&mut big1, &mut budget);

  // `narrow` columns get natural width.
  let mark = narrow(&mut work, &mut budget);

  // `wide` leftover wide columns split leftover budget.
  if mark < work.len() {
    wide(&mut work[mark..], budget);
  }

  // big23: bigger gets p90 width, biggest gets full width.
  let mut cols = big1;
  cols.extend(work);
  apply_big23(ctx, &mut cols);
  for col in cols {
    ctx.columns[col.index].nice = col.nice.max(MIN_COL);
  }
}

//
// guts of autolayout
//

fn narrow(cols: &mut [Column], budget: &mut usize) -> usize {
  for index in 0..cols.len() {
    let ncols = cols.len() - index;
    let fair_share = *budget / ncols;
    let cur = &mut cols[index];
    if cur.natural > fair_share {
      return index;
    }
    cur.nice = cur.natural;
    *budget = budget.saturating_sub(cur.nice);
  }
  cols.len()
}

fn wide(cols: &mut [Column], budget_in: usize) {
  let fair_share = budget_in / cols.len();
  let mut leftover = budget_in % cols.len();
  for col in cols {
    col.nice = fair_share;
    if leftover > 0 {
      col.nice += 1;
      leftover -= 1;
    }
  }
}

//
// bigness
//

fn apply_big1(cols: &mut [Column], budget: &mut usize) {
  if cols.is_empty() {
    return;
  }

  let per = MIN_COL.max((*budget / 2) / cols.len());
  for col in cols {
    col.nice = col.natural.min(per);
    *budget = budget.saturating_sub(col.nice);
  }
}

fn apply_big23(ctx: &Context<'_>, cols: &mut [Column]) {
  for col in cols {
    col.nice = match col.big {
      ColumnBig::Bigger => col.nice.max(p90_width(ctx, col.index)),
      ColumnBig::Biggest => col.nice.max(col.natural),
      ColumnBig::Normal | ColumnBig::Big => col.nice,
    };
  }
}

fn p90_width(ctx: &Context<'_>, col: usize) -> usize {
  let mut widths = ctx.grid.rows.iter().map(|row| display_width(&row[col]) as f64).collect::<Vec<_>>();
  display_width(&ctx.columns[col].name).max(util::percentile(&mut widths, 0.9).ceil() as usize)
}

//
// exotic Width::xxx
//

// nice = header (for Width::Header)
fn natural_headers(ctx: &mut Context<'_>) {
  for col in &mut ctx.columns {
    col.nice = display_width(&col.name).max(MIN_COL);
  }
}

// nice = natural (for Width::Natural)
fn natural_widths(ctx: &mut Context<'_>) {
  for col in &mut ctx.columns {
    col.nice = col.natural;
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::{
    grid::Grid,
    middleware::{columns, format},
    render::{
      border::get_border,
      context::Context,
      options::Border,
      resolved::{ResolvedOptions, ResolvedWidth},
      test_grid, test_options,
    },
  };

  fn layout(grid: Grid, f: impl FnOnce(&mut ResolvedOptions)) -> Vec<usize> {
    let mut options = test_options();
    f(&mut options);
    let mut out = Vec::new();
    let mut ctx = Context::new(grid, options, &mut out);
    columns::run(&mut ctx);
    format::run(&mut ctx);
    run(&mut ctx);
    ctx.columns.iter().map(|column| column.nice).collect()
  }

  #[test]
  fn test_layout_new() {
    assert_eq!(
      vec![5, 2],
      layout(test_grid(["alpha", "b"], [["x", "longer"]]), |options| options.width = ResolvedWidth::Header)
    );

    assert_eq!(
      vec![5, 6],
      layout(test_grid(["alpha", "b"], [["x", "longer"]]), |options| options.width = ResolvedWidth::Natural)
    );
  }

  #[test]
  fn test_autolayout() {
    let widths = layout(test_grid(["alpha", "beta"], [["short", "very very long"]]), |options| {
      options.width = ResolvedWidth::Fixed(20);
      options.row_numbers = true;
    });
    assert_eq!(3, widths.len());
    assert!(widths.iter().sum::<usize>() + get_border(Border::Rounded).chrome_width(widths.len()) <= 20);
  }

  #[test]
  fn test_autolayout_tiny_width_target() {
    let widths =
      layout(test_grid(["alpha", "beta"], [["short", "long"]]), |options| options.width = ResolvedWidth::Fixed(4));
    assert_eq!(vec![2, 2], widths);
    assert!(widths.iter().sum::<usize>() + get_border(Border::Rounded).chrome_width(widths.len()) > 4);
  }

  #[test]
  fn test_table_width_empty() {
    let widths = layout(test_grid([] as [&str; 0], [] as [[&str; 0]; 0]), |options| {
      options.width = ResolvedWidth::Fixed(80);
    });
    assert!(widths.is_empty());
  }

  #[test]
  fn test_big_columns() {
    let biggest = layout(test_grid(["alpha", "beta"], [["short", "very very long"]]), |options| {
      options.width = ResolvedWidth::Fixed(18);
      options.bigs.push(("beta".to_owned(), ColumnBig::Biggest));
    });
    assert_eq!(14, biggest[1]);

    let big = layout(test_grid(["alpha", "beta"], [["short", "very very long"]]), |options| {
      options.width = ResolvedWidth::Fixed(18);
      options.bigs.push(("beta".to_owned(), ColumnBig::Big));
    });
    assert_eq!(vec![5, 5], big);
  }

  #[test]
  fn test_big2() {
    let mut rows = Vec::new();
    for _ in 0..18 {
      rows.push(["x", "xx"]);
    }
    rows.push(["x", "medium"]);
    rows.push(["x", "very very very long"]);

    let widths = layout(test_grid(["alpha", "beta"], rows), |options| {
      options.width = ResolvedWidth::Fixed(16);
      options.bigs.push(("beta".to_owned(), ColumnBig::Bigger));
    });
    assert_eq!(vec![5, 4], widths);
  }

  #[test]
  fn test_bigger_uses_display_index_after_sorting() {
    let mut rows = Vec::new();
    for _ in 0..18 {
      rows.push(["very very very long", "xx"]);
    }
    rows.push(["very very very long", "medium"]);
    rows.push(["very very very long", "medium"]);

    let widths = layout(test_grid(["beta", "alpha"], rows), |options| {
      options.width = ResolvedWidth::Fixed(30);
      options.bigs.push(("alpha".to_owned(), ColumnBig::Bigger));
    });
    assert_eq!(vec![17, 6], widths);
  }

  #[test]
  fn test_calc_chrome_width_none_border() {
    assert_eq!(8, get_border(Border::None).chrome_width(3));
  }

  #[test]
  fn test_calc_chrome_width_light_border() {
    assert_eq!(8, get_border(Border::Light).chrome_width(3));
  }
}
