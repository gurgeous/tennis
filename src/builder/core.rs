//! Fluent builder for loading data and configuring a table

use crate::{
  ColorScale, Grid, Table,
  builder::{
    ColumnOperation, Error, Result, grid,
    into_cells::IntoCells,
    into_json::IntoJsonMaps,
    options::{ColumnBig, Options},
    record::Record,
    types::{Border, ColorMode, ThemeMode, WidthMode},
  },
};

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Builder {
  grid: Option<Result<Grid>>,
  pub(crate) options: Options,
  record_options: Option<Options>,
  select: Vec<String>,
  deselect: Vec<String>,
}

//
// data loading & building
//

impl Builder {
  /// Keep only these columns, in this order.
  pub fn select<R: IntoCells>(mut self, columns: R) -> Self {
    self.select = columns.into_cells();
    self
  }

  /// Remove these columns after selection.
  pub fn deselect<R: IntoCells>(mut self, columns: R) -> Self {
    self.deselect = columns.into_cells();
    self
  }

  /// Load a rectangular cell matrix. In some ways this is the worst way to
  /// load data since we can't infer anything about headers.
  pub fn load_cells<R>(mut self, values: impl IntoIterator<Item = R>) -> Self
  where
    R: IntoCells,
  {
    let rows = values.into_iter().map(IntoCells::into_cells).collect::<Vec<_>>();
    self.grid = Some(grid::from_cells(rows));
    self
  }

  /// Load an already-built grid.
  pub fn load_grid(mut self, grid: Grid) -> Self {
    self.grid = Some(Ok(grid));
    self
  }

  // Load json rows
  pub fn load_json<J>(mut self, data: J) -> Self
  where
    J: IntoJsonMaps,
  {
    self.grid = Some(data.into_json_maps().and_then(grid::from_json));
    self
  }

  /// Load rows of maps, inferring headers from keys.
  pub fn load_maps<M, K, V>(mut self, maps: impl IntoIterator<Item = M>) -> Self
  where
    M: IntoIterator<Item = (K, V)>,
    K: Into<String>,
    V: ToString,
  {
    let maps = maps
      .into_iter()
      .map(|map| map.into_iter().map(|(key, value)| (key.into(), value.to_string())).collect::<Vec<_>>())
      .collect::<Vec<_>>();
    self.grid = Some(grid::from_maps(maps));
    self
  }

  /// Load rows of typed Records, including derived headers and options.
  pub fn load_records<R>(mut self, records: impl IntoIterator<Item = R>) -> Self
  where
    R: Record,
  {
    let headers = R::headers();
    self.record_options = Some(R::builder(Table::builder()).options);
    let rows = records.into_iter().map(|record| record.to_cells()).collect();
    self.grid = Some(grid::from_record_cells(headers, rows));
    self
  }

  /// Builds the table. This will return an error if something is off in the
  /// builder.
  pub fn build(self) -> Result<Table> {
    let Builder { grid, options, record_options, select, deselect } = self;
    let grid = match grid {
      Some(grid) => grid?,
      None => grid::from_cells(Vec::new())?,
    };

    // Finalize terminal-sensitive options before constructing Table. Renderers
    // assume color/theme are concrete and never start terminal probes.
    let options = record_options.unwrap_or_default().merge(options);
    let resolved = crate::resolved::Resolved::new(options);

    // (de)select, then make sure options work with the list of headers
    let grid = pick_columns(grid, &select, &deselect)?;
    validate_columns(&grid, &resolved)?;

    Ok(Table::from_grid(grid, resolved))
  }
}

//
// standalone helpers
//

fn pick_columns(mut grid: Grid, select: &[String], deselect: &[String]) -> Result<Grid> {
  if !select.is_empty() {
    grid = grid.select(select)?;
  }
  if !deselect.is_empty() {
    grid = grid.deselect(deselect)?;
  }
  Ok(grid)
}

fn validate_columns(grid: &Grid, options: &crate::resolved::Resolved) -> Result<()> {
  for (name, big) in &options.bigs {
    grid.position(name).map_err(|error| match error {
      Error::MissingColumn { column, headers, .. } => {
        Error::MissingColumn { column, operation: big.operation(), headers }
      }
      error => error,
    })?;
  }
  for (name, _) in &options.color_scales {
    grid.position(name).map_err(|error| match error {
      Error::MissingColumn { column, headers, .. } => {
        Error::MissingColumn { column, operation: Some(ColumnOperation::ColorScale), headers }
      }
      error => error,
    })?;
  }
  Ok(())
}

// NOTE TO LLMS - please don't overwrite these comments without asking

#[rustfmt::skip]
impl Builder {
  //
  // terminal settings
  //

  /// Should we use color? [default=Auto]
  pub fn color(mut self, color: impl Into<ColorMode>) -> Self { self.options.color = Some(color.into()); self }
  /// Dark vs light color theme [default=Auto]
  pub fn theme(mut self, theme: ThemeMode) -> Self { self.options.theme = Some(theme); self }
  /// Render markdown links using terminal OSC8 [default=true]
  pub fn hyperlinks(mut self, on: bool) -> Self { self.options.hyperlinks = Some(on); self }

  //
  // table/column width
  //

  /// Make a column Bigger
  pub fn big(mut self, column: impl Into<String>) -> Self { self.options.add_big(column, ColumnBig::Big); self }
  /// Make a column even BIGGER (p90)
  pub fn bigger(mut self, column: impl Into<String>) -> Self { self.options.add_big(column, ColumnBig::Bigger); self }
  /// Make a column BIGGEST
  pub fn biggest(mut self, column: impl Into<String>) -> Self { self.options.add_big(column, ColumnBig::Biggest); self }
  /// How do we set table width? [default=Auto]
  pub fn width(mut self, width: impl Into<WidthMode>) -> Self { self.options.width = Some(width.into()); self }

  //
  // title/footer
  //

  /// Add a table title
  pub fn title(mut self, title: impl Into<String>) -> Self { self.options.title = Some(title.into()); self }
  /// Add a table footer
  pub fn footer(mut self, footer: impl Into<String>) -> Self { self.options.footer = Some(footer.into()); self }

  //
  // appearance
  //

  /// Table border style [default=rounded]
  pub fn border(mut self, border: Border) -> Self { self.options.border = Some(border); self }
  /// Color code a column of floats, similar to "conditional formatting" in Google Sheets.
  pub fn color_scale(mut self, column: impl Into<String>, scale: ColorScale) -> Self {
    self.options.set_color_scale(column, scale); self
  }
  /// Turn on row numbers
  pub fn row_numbers(mut self, on: bool) -> Self { self.options.row_numbers = Some(on); self }
  /// Titleize column headers, so person_id becomes Person
  pub fn titleize(mut self, on: bool) -> Self { self.options.titleize = Some(on); self }
  /// Turn on zebra stripes
  pub fn zebra(mut self, on: bool) -> Self { self.options.zebra = Some(on); self }

  //
  // numerics
  //

  /// Format floats to this number of digits. [default=3]
  pub fn digits(mut self, digits: usize) -> Self { self.options.digits = Some(digits); self }
  /// Do not infer numeric types from strings
  pub fn vanilla(mut self, on: bool) -> Self { self.options.vanilla = Some(on); self }
}

#[cfg(test)]
mod tests {
  use std::collections::{BTreeMap, HashMap};

  use serde_json::json;

  use super::*;
  use crate::{
    ColorScale,
    builder::{
      error::Error,
      types::{Border, ColorMode, ThemeMode, WidthMode},
    },
    resolved::{ResolvedTheme, ResolvedWidth},
  };

  fn build(builder: Builder) -> Table {
    builder.build().expect("builder should succeed")
  }

  fn named_grid(headers: &[&str], rows: &[Vec<&str>]) -> Grid {
    Grid::new(
      headers.iter().map(|s| s.to_string()).collect(),
      rows.iter().map(|r| r.iter().map(|s| s.to_string()).collect()).collect(),
    )
    .unwrap()
  }

  #[test]
  fn test_builder_api() {
    let out = build(
      Table::builder()
        .load_grid(named_grid(&["name", "score"], &[vec!["alice", "1234"]]))
        .border(Border::Basic)
        .color(ColorMode::Off)
        .width(80)
        .row_numbers(true),
    )
    .into_text();

    assert!(out.contains("| #  | name  | score |"));
    assert!(out.contains("|  1 | alice | 1,234 |"));
  }

  #[test]
  fn test_builder_options() {
    let table = build(
      Table::builder()
        .load_grid(named_grid(&["score"], &[vec!["1234"]]))
        .color(ColorMode::Auto)
        .color(ColorMode::Off)
        .color(true)
        .theme(ThemeMode::Light)
        .width(42)
        .row_numbers(true)
        .row_numbers(false)
        .zebra(true)
        .zebra(false)
        .vanilla(true)
        .vanilla(false)
        .titleize(true)
        .hyperlinks(false)
        .color_scale("score", ColorScale::Green),
    );
    assert_eq!(ColorMode::On, table.options.color);
    assert_eq!(ResolvedTheme::Light, table.options.theme);
    assert_eq!(ResolvedWidth::Fixed(42), table.options.width);
    assert!(!table.options.row_numbers);
    assert!(!table.options.zebra);
    assert!(!table.options.vanilla);
    assert!(table.options.titleize);
    assert!(!table.options.hyperlinks);
    assert_eq!(vec![("score".to_owned(), ColorScale::Green)], table.options.color_scales);

    assert!(matches!(build(Table::builder().color(ColorMode::Auto)).options.color, ColorMode::On | ColorMode::Off));
    assert_eq!(ColorMode::On, build(Table::builder().color(ColorMode::On)).options.color);
    assert_eq!(ColorMode::Off, build(Table::builder().color(ColorMode::Off)).options.color);
    assert_eq!(ColorMode::On, build(Table::builder().color(true)).options.color);
    assert_eq!(ColorMode::Off, build(Table::builder().color(false)).options.color);
    assert!(matches!(
      build(Table::builder().theme(ThemeMode::Auto)).options.theme,
      ResolvedTheme::Dark | ResolvedTheme::Light
    ));
    assert_eq!(ResolvedTheme::Dark, build(Table::builder().color(ColorMode::On).theme(ThemeMode::Dark)).options.theme);
    assert_eq!(
      ResolvedTheme::Light,
      build(Table::builder().color(ColorMode::On).theme(ThemeMode::Light)).options.theme
    );
    assert!(build(Table::builder().row_numbers(true)).options.row_numbers);
    assert!(!build(Table::builder().zebra(false)).options.zebra);
    assert!(build(Table::builder().vanilla(true)).options.vanilla);
    assert!(!build(Table::builder().vanilla(false)).options.vanilla);
    assert!(matches!(build(Table::builder().width(WidthMode::Auto)).options.width, ResolvedWidth::Fixed(_)));
    assert_eq!(ResolvedWidth::Header, build(Table::builder().width(WidthMode::Header)).options.width);
    assert_eq!(ResolvedWidth::Natural, build(Table::builder().width(WidthMode::Natural)).options.width);
  }

  #[test]
  fn test_cells_generates_headers() {
    let table = build(Table::builder().load_cells([["alice", "1234"], ["bob", "5678"]]));
    assert_eq!(["1", "2"], table.headers());
    assert_eq!(
      vec![vec!["alice".to_owned(), "1234".to_owned()], vec!["bob".to_owned(), "5678".to_owned()]],
      table.rows()
    );
  }

  #[test]
  fn test_load_grid() {
    let grid =
      Grid::new(vec!["name".to_owned(), "score".to_owned()], vec![vec!["alice".to_owned(), "1234".to_owned()]])
        .unwrap();

    let table = build(Table::builder().load_grid(grid));
    assert_eq!(["name", "score"], table.headers());
    assert_eq!(vec![vec!["alice".to_owned(), "1234".to_owned()]], table.rows());
  }

  #[test]
  fn test_second_load_replaces_first_load() {
    let table = build(Table::builder().load_cells([["alice"]]).load_cells([["bob"]]));
    assert_eq!(["1"], table.headers());
    assert_eq!(vec![vec!["bob".to_owned()]], table.rows());
  }

  #[test]
  fn test_maps_infer_first_seen_headers() {
    let row1 = vec![("name", "alice"), ("score", "1234")];
    let row2 = vec![("city", "denver"), ("name", "bob")];
    let table = build(Table::builder().load_maps([row1, row2]));
    assert_eq!(["name", "score", "city"], table.headers());
  }

  #[test]
  fn test_maps_accept_stringifiable_values() {
    let rows = [[("name", "alice"), ("score", "1234")], [("name", "bob"), ("score", "5678")]];
    let table = build(Table::builder().load_maps(rows));
    assert_eq!(["name", "score"], table.headers());
    assert_eq!(vec!["bob".to_owned(), "5678".to_owned()], table.rows()[1]);
  }

  #[test]
  fn test_select() {
    let rows = [BTreeMap::from([("name".to_owned(), "alice".to_owned()), ("score".to_owned(), "1234".to_owned())])];
    let table = build(Table::builder().select(["score"]).load_maps(rows));
    assert_eq!(["score"], table.headers());
    assert_eq!(vec![vec!["1234".to_owned()]], table.rows());

    let rows = [BTreeMap::from([("name".to_owned(), "alice".to_owned())])];
    let error = Table::builder().select(["score"]).load_maps(rows).build().unwrap_err();
    assert_eq!(
      Error::MissingColumn { column: "score".to_owned(), operation: None, headers: vec!["name".to_owned()] },
      error
    );
  }

  #[test]
  fn test_select_can_be_set_after_loading() {
    let rows = [BTreeMap::from([("name".to_owned(), "alice".to_owned()), ("score".to_owned(), "1234".to_owned())])];
    let table = build(Table::builder().load_maps(rows).select(["score"]));
    assert_eq!(["score"], table.headers());
    assert_eq!(vec![vec!["1234".to_owned()]], table.rows());

    let rows = [BTreeMap::from([("name".to_owned(), "alice".to_owned())])];
    let error = Table::builder().load_maps(rows).select(["score"]).build().unwrap_err();
    assert_eq!(
      Error::MissingColumn { column: "score".to_owned(), operation: None, headers: vec!["name".to_owned()] },
      error
    );
  }

  #[test]
  fn test_deselect() {
    let rows = [BTreeMap::from([
      ("name".to_owned(), "alice".to_owned()),
      ("score".to_owned(), "1234".to_owned()),
      ("city".to_owned(), "denver".to_owned()),
    ])];
    let table = build(Table::builder().select(["score", "name"]).deselect(["name"]).load_maps(rows));
    assert_eq!(["score"], table.headers());
    assert_eq!(vec![vec!["1234".to_owned()]], table.rows());
  }

  #[test]
  fn test_maps_allow_sparse_rows() {
    let rows = [
      BTreeMap::from([("name".to_owned(), "alice".to_owned()), ("score".to_owned(), "1234".to_owned())]),
      BTreeMap::from([("name".to_owned(), "bob".to_owned())]),
    ];

    let table = build(Table::builder().select(["name", "score"]).load_maps(rows));
    assert_eq!(["name", "score"], table.headers());
    assert_eq!(vec!["bob".to_owned(), String::new()], table.rows()[1]);
  }

  #[test]
  fn test_json_maps() {
    let row = json!({"name": "alice", "score": 1234, "tags": ["a", "b"], "meta": {"ok": true}});

    let table = build(Table::builder().select(["name", "score", "tags", "meta"]).load_json([row]));
    assert_eq!(vec!["alice", "1234", "a, b", "{\"ok\":true}"], table.rows()[0]);
  }

  #[test]
  fn test_json_value_accepts_array() {
    let rows = json!([
      {"name": "alice", "score": 1234},
      {"name": "bob", "score": 5678}
    ]);

    let table = build(Table::builder().load_json(rows));
    assert_eq!(["name", "score"], table.headers());
    assert_eq!(2, table.rows().len());
  }

  #[test]
  fn test_json_accepts_borrowed_value() {
    let rows = json!([
      {"name": "alice", "score": 1234}
    ]);

    let table = build(Table::builder().load_json(&rows));
    assert_eq!(["name", "score"], table.headers());
    assert_eq!(vec!["alice", "1234"], table.rows()[0]);
  }

  #[test]
  fn test_json_hash_maps() {
    let rows = [HashMap::from([("name".to_owned(), json!("alice")), ("score".to_owned(), json!(1234))])];

    let table = build(Table::builder().select(["name", "score"]).load_json(rows));
    assert_eq!(["name", "score"], table.headers());
    assert_eq!(vec!["alice", "1234"], table.rows()[0]);
  }

  #[test]
  fn test_json_select() {
    let rows = json!([
      {"name": "alice", "score": 1234}
    ]);
    let table = build(Table::builder().load_json(rows).select(["score"]));
    assert_eq!(["score"], table.headers());
    assert_eq!(vec![vec!["1234".to_owned()]], table.rows());

    let rows = json!([
      {"name": "alice"}
    ]);
    let error = Table::builder().load_json(rows).select(["score"]).build().unwrap_err();
    assert_eq!(
      Error::MissingColumn { column: "score".to_owned(), operation: None, headers: vec!["name".to_owned()] },
      error
    );
  }

  #[test]
  fn test_json_allows_sparse_rows() {
    let rows = json!([
      {"name": "alice", "score": 1234},
      {"name": "bob"}
    ]);

    let table = build(Table::builder().select(["name", "score"]).load_json(rows));
    assert_eq!(["name", "score"], table.headers());
    assert_eq!(vec!["bob".to_owned(), String::new()], table.rows()[1]);
  }

  #[test]
  fn test_json_btree_maps() {
    let rows = [BTreeMap::from([("name".to_owned(), json!("alice")), ("score".to_owned(), json!(1234))])];

    let table = build(Table::builder().load_json(rows));
    assert_eq!(["name", "score"], table.headers());
    assert_eq!(vec!["alice", "1234"], table.rows()[0]);
  }

  #[test]
  fn test_json_errors_for_non_objects() {
    let error = Table::builder().load_json([json!(123)]).build().unwrap_err();
    assert_eq!(Error::JsonObjectExpected, error);

    let error = Table::builder().load_json(json!({"name": "alice"})).build().unwrap_err();
    assert_eq!(Error::JsonArrayExpected, error);
  }

  #[test]
  fn test_records_with_derive() {
    #[derive(crate::Record)]
    struct Person {
      name: String,
      score: u32,
    }

    let people = [Person { name: "alice".to_owned(), score: 1234 }, Person { name: "bob".to_owned(), score: 5678 }];
    let table = build(Table::builder().select(["score"]).load_records(people));
    assert_eq!(["score"], table.headers());
    assert_eq!(vec![vec!["1234".to_owned()], vec!["5678".to_owned()]], table.rows());
  }

  #[test]
  fn test_records_with_derive_generics() {
    #[derive(crate::Record)]
    struct Entry<'a, T>
    where
      T: ToString,
    {
      name: &'a str,
      value: T,
    }

    let table = build(Table::builder().load_records([Entry { name: "alice", value: 1234_u32 }]));
    assert_eq!(["name", "value"], table.headers());
    assert_eq!(vec![vec!["alice".to_owned(), "1234".to_owned()]], table.rows());
  }

  #[test]
  fn test_records_select() {
    #[derive(crate::Record)]
    struct Person {
      name: String,
      score: u32,
    }

    let people = [Person { name: "alice".to_owned(), score: 1234 }];
    let table = build(Table::builder().load_records(people).select(["score"]));
    assert_eq!(["score"], table.headers());
    assert_eq!(vec![vec!["1234".to_owned()]], table.rows());

    let people = [Person { name: "alice".to_owned(), score: 1234 }];
    let error = Table::builder().load_records(people).select(["missing"]).build().unwrap_err();
    assert_eq!(
      Error::MissingColumn {
        column: "missing".to_owned(),
        operation: None,
        headers: vec!["name".to_owned(), "score".to_owned()],
      },
      error
    );
  }

  #[test]
  fn test_records_with_derive_option_fields() {
    #[derive(crate::Record)]
    struct Person {
      name: String,
      score: Option<u32>,
    }

    let people =
      [Person { name: "alice".to_owned(), score: Some(1234) }, Person { name: "bob".to_owned(), score: None }];
    let table = build(Table::builder().load_records(people));
    assert_eq!(["name", "score"], table.headers());
    assert_eq!(vec!["bob".to_owned(), String::new()], table.rows()[1]);
  }

  #[test]
  fn test_records_with_various_types() {
    #[derive(crate::Record)]
    struct Various {
      boolean: bool,
      unsigned: u8,
      signed: i32,
      float: f64,
      opt_bool: Option<bool>,
      opt_float: Option<f64>,
      slice: &'static str,
      string: String,
    }

    let records = [Various {
      boolean: true,
      unsigned: 42,
      signed: -10,
      float: 1.23,
      opt_bool: Some(false),
      opt_float: None,
      slice: "hello",
      string: "world".to_owned(),
    }];

    let table = build(Table::builder().load_records(records));
    assert_eq!(["boolean", "unsigned", "signed", "float", "opt_bool", "opt_float", "slice", "string"], table.headers());
    assert_eq!(
      vec![
        "true".to_owned(),
        "42".to_owned(),
        "-10".to_owned(),
        "1.23".to_owned(),
        "false".to_owned(),
        String::new(),
        "hello".to_owned(),
        "world".to_owned(),
      ],
      table.rows()[0]
    );
  }

  #[test]
  fn test_records_with_derive_field_attributes() {
    #[derive(crate::Record)]
    struct Person {
      #[tennis(rename = "Name")]
      name: String,
      #[tennis(biggest)]
      notes: String,
      #[tennis(scale = "green_red")]
      score: u32,
      #[tennis(skip)]
      _internal_id: String,
    }

    let people = [Person {
      name: "alice".to_owned(),
      notes: "long biography".to_owned(),
      score: 1234,
      _internal_id: "1".to_owned(),
    }];
    let table = build(Table::builder().load_records(people));
    assert_eq!(["Name", "notes", "score"], table.headers());
    assert_eq!(vec![vec!["alice".to_owned(), "long biography".to_owned(), "1234".to_owned()]], table.rows());
    assert_eq!(crate::builder::options::ColumnBig::Biggest, table.options.column_big("notes"));
    assert_eq!(Some(ColorScale::GreenRed), table.options.color_scale("score"));
  }

  #[test]
  fn test_records_with_derive_struct_attributes() {
    #[derive(crate::Record)]
    #[tennis(
      title = "People",
      footer = "done",
      border = "basic",
      width = 72,
      digits = 2,
      zebra = true,
      row_numbers = true,
      vanilla,
      titleize,
      hyperlinks = false
    )]
    struct Person {
      name: String,
    }

    let table = build(Table::builder().load_records([Person { name: "alice".to_owned() }]));
    assert_eq!(Some("People"), table.options.title.as_deref());
    assert_eq!(Some("done"), table.options.footer.as_deref());
    assert_eq!(Border::Basic, table.options.border);
    assert_eq!(ResolvedWidth::Fixed(72), table.options.width);
    assert_eq!(2, table.options.digits);
    assert!(table.options.zebra);
    assert!(table.options.row_numbers);
    assert!(table.options.vanilla);
    assert!(table.options.titleize);
    assert!(!table.options.hyperlinks);
  }

  #[test]
  fn test_records_with_derive_crate_path_attribute() {
    #[derive(crate::Record)]
    #[tennis(crate_path = "crate")]
    struct Person {
      name: String,
    }

    let table = build(Table::builder().load_records([Person { name: "alice".to_owned() }]));
    assert_eq!(["name"], table.headers());
    assert_eq!(vec![vec!["alice".to_owned()]], table.rows());
  }

  #[test]
  fn test_builder_options_override_record_defaults() {
    #[derive(crate::Record)]
    #[tennis(
      title = "People",
      footer = "done",
      border = "basic",
      width = 72,
      zebra,
      row_numbers,
      vanilla,
      titleize,
      hyperlinks = false
    )]
    struct Person {
      #[tennis(big)]
      name: String,
    }

    let table = build(
      Table::builder()
        .title("Users")
        .footer("total")
        .border(Border::Light)
        .color(ColorMode::Off)
        .theme(ThemeMode::Light)
        .width(80)
        .digits(1)
        .row_numbers(false)
        .zebra(false)
        .vanilla(false)
        .titleize(false)
        .hyperlinks(true)
        .biggest("name")
        .load_records([Person { name: "alice".to_owned() }]),
    );
    assert_eq!(Some("Users"), table.options.title.as_deref());
    assert_eq!(Some("total"), table.options.footer.as_deref());
    assert_eq!(Border::Light, table.options.border);
    assert_eq!(ColorMode::Off, table.options.color);
    assert_eq!(ResolvedTheme::Dark, table.options.theme);
    assert_eq!(ResolvedWidth::Fixed(80), table.options.width);
    assert_eq!(1, table.options.digits);
    assert!(!table.options.row_numbers);
    assert!(!table.options.zebra);
    assert!(!table.options.vanilla);
    assert!(!table.options.titleize);
    assert!(table.options.hyperlinks);
    assert_eq!(crate::builder::options::ColumnBig::Biggest, table.options.column_big("name"));
  }
}
