//! Display column metadata used by the render pipeline.

pub(crate) use crate::ColumnType;
use crate::{ColorScale, builder::options::ColumnBig, context::Context, util};

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
  pub(crate) raw_name: String,                // original header
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
    let mut this = Self { raw_name: name.clone(), name, ty: ColumnType::Int, row_number: true, ..Self::default() };
    this.compute_natural();
    this
  }

  fn compute_big(&mut self, ctx: &Context<'_>) {
    self.big = ctx.options.column_big(&self.raw_name);
  }

  fn compute_color_scale(&mut self, ctx: &Context<'_>) {
    self.color_scale = ctx.options.color_scale(&self.raw_name);
  }

  fn compute_name(&mut self, ctx: &Context<'_>) {
    self.raw_name = ctx.grid.headers[self.index].clone();
    self.name = if ctx.options.titleize { util::titleize(&self.raw_name) } else { self.raw_name.clone() };
  }

  fn compute_natural(&mut self) {
    self.natural = util::display_width(&self.name);
  }

  fn compute_ty(&mut self, ctx: &Context<'_>) {
    self.ty = ctx.grid.column_type(self.index, ctx.options.vanilla);
  }

  pub(crate) fn align(&self) -> Align {
    if !matches!(self.ty, ColumnType::String) { Align::Right } else { Align::Left }
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::{Grid, IntoCells, Table, context::Context};

  fn table<H, R>(headers: H, rows: impl IntoIterator<Item = R>) -> Table
  where
    H: IntoCells,
    R: IntoCells,
  {
    let rows = rows.into_iter().map(IntoCells::into_cells).collect();
    Table::builder().load_grid(Grid::new(headers.into_cells(), rows).expect("valid grid")).build().expect("valid table")
  }

  #[test]
  fn test_titleize_does_not_affect_type_inference() {
    let mut table = table(["person_id"], [["1234"]]);
    table.options.color = crate::ColorMode::Off;
    table.options.titleize = true;
    let mut out = Vec::new();
    let ctx = Context::new(table, &mut out);
    let column = Column::new(&ctx, 0);
    assert_eq!("Person", column.name);
    assert_eq!(ColumnType::Int, column.ty);
  }
}
