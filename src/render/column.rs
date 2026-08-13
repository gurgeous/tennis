//! Display column metadata used by the render pipeline.

use super::{color_scale::ColorScale, context::Context, options::ColumnBig};
pub(crate) use crate::infer::ColumnType;
use crate::util;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum Align {
  Left,
  Center,
  Right,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub(crate) struct Column {
  pub(crate) big: ColumnBig,                  // big(er)(est)
  pub(crate) color_scale: Option<ColorScale>, // color scale, if any
  pub(crate) index: usize,                    // index in table
  pub(crate) name: String,                    // final header name
  pub(crate) natural: usize,                  // full width
  pub(crate) nice: usize,                     // computed layout width
  pub(crate) row_number: bool,                // synthetic row #
  pub(crate) ty: ColumnType,                  // string/float/int/etc
}

impl Column {
  pub(crate) fn new(ctx: &Context<'_>, index: usize) -> Self {
    let mut this = Self { index, ..Self::default() };
    this.compute_name(ctx);
    this.compute_big(ctx);
    this.compute_color_scale(ctx);
    this.compute_ty(ctx);
    this.compute_natural();
    this
  }

  // make this a row_number col
  pub(crate) fn row_number() -> Self {
    let name = "#".to_owned();
    let mut this = Self { name, ty: ColumnType::Int, row_number: true, ..Self::default() };
    this.compute_natural();
    this
  }

  fn compute_big(&mut self, ctx: &Context<'_>) {
    self.big = ctx.options.column_big(&self.name);
  }

  fn compute_color_scale(&mut self, ctx: &Context<'_>) {
    self.color_scale = ctx.options.color_scale(&self.name);
  }

  fn compute_name(&mut self, ctx: &Context<'_>) {
    self.name = ctx.grid.headers[self.index].clone();
  }

  fn compute_natural(&mut self) {
    self.natural = util::display_width(&self.name);
  }

  fn compute_ty(&mut self, ctx: &Context<'_>) {
    self.ty = if ctx.options.vanilla { ColumnType::String } else { ctx.grid.column_type(self.index) };
  }

  pub(crate) fn align(&self) -> Align {
    if !matches!(self.ty, ColumnType::String) { Align::Right } else { Align::Left }
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::render::{context::Context, test_grid, test_options};

  #[test]
  fn test_new() {
    let grid = test_grid(["person_id"], [["1234"]]);
    let mut out = Vec::new();
    let ctx = Context::new(grid, test_options(), &mut out);
    let column = Column::new(&ctx, 0);
    assert_eq!("person_id", column.name);
    assert_eq!(ColumnType::Int, column.ty);
  }
}
