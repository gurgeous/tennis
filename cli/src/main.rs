mod args;
mod completion;
mod error;
mod input;
mod natsort;
pub(crate) mod peek;
pub(crate) mod util;

use std::{
  io::{self, IsTerminal, Read, Write},
  path::Path,
  process::{Child, ChildStdin, Command, ExitCode, Stdio},
};

use tennis::{ColorScale, Grid, Table};

use crate::{
  args::Args,
  error::{Error, Result},
  input::{csv, detect, detect::InputFormat, json, sniffer, sqlite},
};

//
// main/main0 around Main
//

fn main() -> ExitCode {
  match main0() {
    Ok(()) => ExitCode::SUCCESS,
    Err(message) => {
      eprint!("{message}");
      ExitCode::FAILURE
    }
  }
}

fn main0() -> std::result::Result<(), String> {
  let args = args::parse_from(std::env::args_os()).map_err(|msg| error::usage(msg.trim_end()))?;

  // early exits
  if args.completion.is_some() || args.help || args.version {
    if let Some(shell) = args.completion {
      let _ = write!(io::stdout(), "{}", completion::script(shell));
    };
    if args.help {
      let _ = write!(anstream::stdout(), "{}", args::help());
    }
    if args.version {
      let _ = writeln!(io::stdout(), "tennis: {}", version());
    }
    return Ok(());
  };

  // no file? either naked or an error
  if args.file.is_none() && std::io::stdin().is_terminal() {
    if args.argv_had_args {
      return Err(Error::StdinRead.to_string());
    }
    let _ = io::stdout().write_all(error::USAGE_HINT.as_bytes());
    return Ok(());
  }

  Main::new(args).run().map_err(|error| error.to_string())
}

fn version() -> String {
  let sha = option_env!("TENNIS_GIT_SHA").filter(|sha| !sha.is_empty()).unwrap_or("unknown sha");
  format!("{} ({sha})", env!("CARGO_PKG_VERSION"))
}

//
// Main orchestrates everything: loading, transforming, rendering.
//

pub struct Main {
  args: Args,
}

impl Main {
  pub fn new(args: Args) -> Self {
    Self { args }
  }

  pub fn run(&self) -> Result<()> {
    // read input
    let input = self.load()?;

    // --peek
    if self.args.peek {
      let input =
        if self.has_transforms() { tennis::verbose::time("transform", || self.transform(input))? } else { input };
      let output = peek::render(&input, &self.args)?;
      let _ = io::stdout().write_all(output.as_bytes());
      return Ok(());
    };

    // --select, --sort, --head, etc.
    let input =
      if self.has_transforms() { tennis::verbose::time("transform", || self.transform(input))? } else { input };

    // feed data and options into our crate
    let table = to_tennis(input, &self.args)?;

    // output to stdout or pager
    tennis::verbose::time("write", || self.write(table))
  }

  //
  // load data
  //

  fn load(&self) -> Result<Grid> {
    match &self.args.file {
      Some(path) if path != Path::new("-") => load_path(&self.args),
      _ => {
        let mut bytes = Vec::new();
        tennis::verbose::time("read stdin", || io::stdin().read_to_end(&mut bytes)).map_err(|_| Error::StdinRead)?;
        tennis::verbose::time("parse input", || load_bytes(&self.args, None, &bytes))
      }
    }
  }

  //
  // data transformation
  //

  fn transform(&self, mut grid: Grid) -> Result<Grid> {
    // --filter
    if let Some(ref needle) = self.args.filter {
      let needle = needle.as_str();
      grid = grid.filter(|row| row.iter().any(|cell| crate::util::has_ascii_case(cell, needle)));
    }

    // --sort
    if !self.args.sort.is_empty() {
      let sort = natsort::sort_keys(&grid, &self.args.sort).map_err(|error| match error {
        tennis::Error::MissingColumn { column, headers, .. } => Error::BadSort(column, headers),
        error => error.into(),
      })?;
      grid = grid.sort_by(|a, b| natsort::compare_rows(a, b, &sort, self.args.reverse));
    }

    // --shuffle
    if self.args.shuffle {
      grid = grid.shuffle();
    }

    // --reverse
    if self.args.reverse && self.args.sort.is_empty() {
      grid = grid.reverse();
    }

    // --head and --tail
    if let Some(n) = self.args.head {
      grid = grid.head(n as usize);
    }
    if let Some(n) = self.args.tail {
      grid = grid.tail(n as usize);
    }

    // --select and --deselect
    if !self.args.select.is_empty() {
      grid = grid.select(&self.args.select).map_err(|error| match error {
        tennis::Error::MissingColumn { column, headers, .. } => Error::BadSelect(column, headers),
        error => error.into(),
      })?;
    }
    if !self.args.deselect.is_empty() {
      let headers = grid.headers().to_vec();
      grid = grid.deselect(&self.args.deselect).map_err(|error| match error {
        tennis::Error::MissingColumn { column, headers, .. } => Error::BadDeselect(column, headers),
        error => error.into(),
      })?;
      if grid.headers().is_empty() {
        return Err(Error::BadDeselect(self.args.deselect.join(","), headers));
      }
    }

    Ok(grid)
  }

  fn has_transforms(&self) -> bool {
    self.args.filter.is_some()
      || !self.args.sort.is_empty()
      || self.args.shuffle
      || self.args.reverse
      || self.args.head.is_some()
      || self.args.tail.is_some()
      || !self.args.select.is_empty()
      || !self.args.deselect.is_empty()
  }

  //
  // write
  //

  // write table somewhere based on args
  fn write(&self, table: Table) -> Result<()> {
    if self.args.pager {
      let mut pager = self.pager()?;
      let _ = table.write_to(&mut pager.stdin as &mut dyn Write);
      pager.finish();
      return Ok(());
    }

    let mut stdout = io::stdout().lock();
    let _ = table.write_to(&mut stdout);
    Ok(())
  }

  fn pager(&self) -> Result<Pager> {
    let pager = env_pager();
    let mut parts = shell_words::split(&pager).map_err(|_| Error::PagerStart)?.into_iter();
    let program = parts.next().ok_or(Error::PagerStart)?;

    let mut child = Command::new(program)
      .args(parts)
      .stdin(Stdio::piped())
      .stdout(Stdio::inherit())
      .stderr(Stdio::inherit())
      .spawn()
      .map_err(|_| Error::PagerStart)?; // pager not found

    let stdin = child.stdin.take().ok_or(Error::PagerStart)?;

    Ok(Pager { child, stdin })
  }
}

//
// simple Pager struct
//

struct Pager {
  child: Child,
  stdin: ChildStdin,
}

impl Pager {
  fn finish(mut self) {
    drop(self.stdin);
    let _ = self.child.wait();
  }
}

fn env_pager() -> String {
  match std::env::var("PAGER") {
    Ok(v) if !v.is_empty() => v,
    _ => "less -RS".to_string(),
  }
}

//
// crate table conversion
//

fn to_tennis(grid: Grid, args: &Args) -> Result<Table> {
  let mut builder = Table::builder()
    .load_grid(grid) // fast path
    .row_numbers(args.row_numbers)
    .vanilla(args.vanilla)
    .zebra(args.zebra);

  // optionals
  if let Some(border) = args.border {
    builder = builder.border(border);
  }
  if let Some(color) = args.color {
    builder = builder.color(color);
  }
  if let Some(digits) = args.digits {
    builder = builder.digits(digits as usize);
  }
  if let Some(title) = &args.title {
    builder = builder.title(title);
  }
  if let Some(footer) = &args.footer {
    builder = builder.footer(footer);
  }
  if let Some(theme) = args.theme {
    builder = builder.theme(theme);
  }
  if let Some(width) = args.width {
    builder = builder.width(width);
  }

  // big(ger|gest)
  for raw in &args.big1 {
    builder = builder.big(raw);
  }
  for raw in &args.big2 {
    builder = builder.bigger(raw);
  }
  for raw in &args.big3 {
    builder = builder.biggest(raw);
  }
  for raw in &args.scale {
    builder = builder.color_scale(raw, ColorScale::RedGreen);
  }
  for raw in &args.rscale {
    builder = builder.color_scale(raw, ColorScale::GreenRed);
  }

  builder.build().map_err(Error::from)
}

//
// file loading
//

fn load_bytes(args: &Args, filename: Option<&Path>, bytes: &[u8]) -> Result<Grid> {
  // skip BOM
  let bytes = bytes.strip_prefix(b"\xef\xbb\xbf").unwrap_or(bytes);

  match detect::detect_format(filename, bytes) {
    InputFormat::Sqlite => Err(Error::SqliteRequiresFile),
    _ if args.table.is_some() => Err(Error::SqliteTableRequiresSqlite),
    InputFormat::Json => json::load(bytes),
    InputFormat::Csv => {
      let text = String::from_utf8_lossy(bytes);
      let delimiter = args.delimiter.or_else(|| sniffer::sniff(&text)).unwrap_or(b',');
      csv::load(bytes, delimiter)
    }
  }
}

fn load_path(args: &Args) -> Result<Grid> {
  let path = args.file.as_deref().expect("load_path requires a file path");

  if detect::is_sqlite_path(path).map_err(|err| match err.kind() {
    std::io::ErrorKind::NotFound => Error::FileNotFound(path.to_owned()),
    _ => Error::FileRead,
  })? {
    return tennis::verbose::time("sqlite", || sqlite::load(path, args.table.as_deref()));
  }

  let bytes = tennis::verbose::time("read file", || std::fs::read(path)).map_err(|err| match err.kind() {
    std::io::ErrorKind::NotFound => Error::FileNotFound(path.to_owned()),
    _ => Error::FileRead,
  })?;
  tennis::verbose::time("parse input", || load_bytes(args, Some(path), &bytes))
}

#[cfg(test)]
mod tests {
  use std::path::PathBuf;

  use super::*;

  fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("..").join("tests").join(name)
  }

  fn test_input(headers: &[&str], rows: &[Vec<&str>]) -> Grid {
    Grid::new(
      headers.iter().map(|s| s.to_string()).collect(),
      rows.iter().map(|r| r.iter().map(|s| s.to_string()).collect()).collect(),
    )
    .unwrap()
  }

  #[test]
  fn test_load_bytes() {
    let input = load_bytes(&Args::default(), None, b"\xef\xbb\xbfa;b\n1;2\n3;4\n5;6\n").unwrap();
    assert_eq!(["a", "b"], input.headers());
    assert_eq!("1", input.rows()[0][0]);

    let args = Args { table: Some("users".to_owned()), ..Args::default() };
    assert_eq!(Err(Error::SqliteTableRequiresSqlite), load_bytes(&args, None, b"a,b\n1;2\n"));

    let args = Args::default();
    assert_eq!(Err(Error::SqliteRequiresFile), load_bytes(&args, Some(&fixture("test.db")), b"SQLite format 3\0"));
  }

  #[test]
  fn test_load_path() {
    let path = fixture("does-not-exist.csv");
    let args = Args { file: Some(path.clone()), ..Args::default() };
    assert_eq!(Err(Error::FileNotFound(path)), load_path(&args));
  }

  #[test]
  fn test_transform() {
    let args = Args::default();
    let main = Main::new(args.clone());
    let input = test_input(&["name", "score"], &[vec!["bob", "10"], vec!["Alice", "2"]]);
    let td = main.transform(input).unwrap();
    assert_eq!(["name", "score"], td.headers());
    assert_eq!(2, td.rows().len());
  }

  #[test]
  fn test_transform_select() {
    let args = Args { select: vec!["score".to_owned()], ..Args::default() };
    let main = Main::new(args);
    let input = test_input(&["name", "score"], &[vec!["bob", "10"]]);
    let td = main.transform(input).unwrap();
    assert_eq!(["score"], td.headers());
  }

  #[test]
  fn test_transform_select_deselect() {
    let args = Args {
      select: vec!["score".to_owned(), "name".to_owned()],
      deselect: vec!["score".to_owned()],
      ..Args::default()
    };
    let main = Main::new(args);
    let input = test_input(&["name", "score", "city"], &[vec!["bob", "10", "denver"]]);
    let td = main.transform(input).unwrap();
    assert_eq!(["name"], td.headers());
    assert_eq!(["bob"], td.rows()[0].as_slice());
  }

  #[test]
  fn test_transform_sort() {
    let args = Args { sort: vec!["score".to_owned()], ..Args::default() };
    let main = Main::new(args);
    let input = test_input(&["name", "score"], &[vec!["bob", "10"], vec!["Alice", "2"]]);
    let td = main.transform(input).unwrap();
    assert_eq!("Alice", td.rows()[0][0]);
    assert_eq!("bob", td.rows()[1][0]);
  }

  #[test]
  fn test_transform_sort_squishes_numeric_cells() {
    let args = Args { sort: vec!["score".to_owned()], ..Args::default() };
    let main = Main::new(args);
    let input = test_input(&["name", "score"], &[vec!["five", " -5 "], vec!["ten", " -10 "]]);
    let td = main.transform(input).unwrap();
    assert_eq!(names(&td), ["ten", "five"]);
    assert_eq!(["ten", "-10"], td.rows()[0].as_slice());
  }

  #[test]
  fn test_transform_sort_floats_and_negatives() {
    let args = Args { sort: vec!["score".to_owned()], ..Args::default() };
    let main = Main::new(args);
    let input =
      test_input(&["name", "score"], &[vec!["a", "0.3"], vec!["b", "-5"], vec!["c", "-10"], vec!["d", "0.21"]]);
    let td = main.transform(input).unwrap();
    assert_eq!(names(&td), ["c", "b", "d", "a"]);
  }

  #[test]
  fn test_transform_sort_mixed_values_use_natural_order() {
    let args = Args { sort: vec!["value".to_owned()], ..Args::default() };
    let main = Main::new(args);
    let input = test_input(&["value"], &[vec!["-10"], vec!["-5"], vec!["-5x"]]);
    let td = main.transform(input).unwrap();
    assert_eq!(["-5"], td.rows()[0].as_slice());
    assert_eq!(["-5x"], td.rows()[1].as_slice());
    assert_eq!(["-10"], td.rows()[2].as_slice());
  }

  #[test]
  fn test_transform_sort_keeps_blanks_at_bottom() {
    let args = Args { sort: vec!["score".to_owned()], ..Args::default() };
    let main = Main::new(args);
    let input = test_input(&["name", "score"], &[vec!["blank", ""], vec!["two", "2"], vec!["one", "1"]]);
    let td = main.transform(input).unwrap();
    assert_eq!(names(&td), ["one", "two", "blank"]);
  }

  #[test]
  fn test_transform_sort_reverse_keeps_blanks_at_bottom() {
    let args = Args { reverse: true, sort: vec!["score".to_owned()], ..Args::default() };
    let main = Main::new(args);
    let input = test_input(&["name", "score"], &[vec!["blank", ""], vec!["two", "2"], vec!["one", "1"]]);
    let td = main.transform(input).unwrap();
    assert_eq!(names(&td), ["two", "one", "blank"]);
  }

  #[test]
  fn test_transform_sort_vanilla_still_uses_numeric_inference() {
    let args = Args { sort: vec!["score".to_owned()], vanilla: true, ..Args::default() };
    let main = Main::new(args);
    let input = test_input(&["name", "score"], &[vec!["bob", "10"], vec!["Alice", "2"]]);
    let td = main.transform(input).unwrap();
    assert_eq!(names(&td), ["Alice", "bob"]);
  }

  #[test]
  fn test_transform_sort_header_forced_text() {
    let args = Args { sort: vec!["sku".to_owned()], ..Args::default() };
    let main = Main::new(args);
    let input = test_input(&["name", "sku"], &[vec!["ten", "-10"], vec!["five", "-5"]]);
    let td = main.transform(input).unwrap();
    assert_eq!(names(&td), ["five", "ten"]);
  }

  #[test]
  fn test_transform_sort_texty_numbers_use_natural_order() {
    let args = Args { sort: vec!["score".to_owned()], ..Args::default() };
    let main = Main::new(args);
    let input = test_input(&["name", "score"], &[vec!["exp", "1e2"], vec!["nan", "NaN"], vec!["num", "2"]]);
    let td = main.transform(input).unwrap();
    assert_eq!(names(&td), ["exp", "num", "nan"]);
  }

  #[test]
  fn test_transform_filter() {
    let args = Args { filter: Some("ali".to_owned()), ..Args::default() };
    let main = Main::new(args);
    let input = test_input(&["name"], &[vec!["Alice"], vec!["bob"]]);
    let td = main.transform(input).unwrap();
    assert_eq!(1, td.rows().len());
    assert_eq!("Alice", td.rows()[0][0]);
  }

  #[test]
  fn test_transform_reverse() {
    let args = Args { reverse: true, ..Args::default() };
    let main = Main::new(args);
    let input = test_input(&["name"], &[vec!["a"], vec!["b"]]);
    let td = main.transform(input).unwrap();
    assert_eq!("b", td.rows()[0][0]);
    assert_eq!("a", td.rows()[1][0]);
  }

  #[test]
  fn test_transform_shuffle() {
    let args = Args { shuffle: true, ..Args::default() };
    let main = Main::new(args);
    let input = test_input(&["name"], &[vec!["a"], vec!["b"], vec!["c"]]);
    let td = main.transform(input).unwrap();
    assert_eq!(3, td.rows().len());
  }

  #[test]
  fn test_transform_empty() {
    let args = Args::default();
    let main = Main::new(args);
    let td = main.transform(Grid::new(Vec::new(), Vec::new()).unwrap()).unwrap();
    assert!(td.headers().is_empty());
    assert!(td.is_empty());

    let input = Grid::new(vec!["name".to_string()], Vec::new()).unwrap();
    let td = main.transform(input).unwrap();
    assert_eq!(["name"], td.headers());
    assert!(td.is_empty());
  }

  #[test]
  fn test_transform_invalid_specs() {
    let args = Args { sort: vec!["missing".to_owned()], ..Args::default() };
    let main = Main::new(args);
    let input = test_input(&["name"], &[vec!["a"]]);
    assert!(main.transform(input).is_err());
  }

  fn names(grid: &Grid) -> Vec<&str> {
    grid.rows().iter().map(|row| row[0].as_str()).collect()
  }

  #[test]
  fn test_to_tennis_scale() {
    let args = Args {
      color: Some(tennis::ColorMode::On),
      scale: vec!["score".to_owned()],
      theme: Some(tennis::ThemeMode::Dark),
      width: Some(tennis::WidthMode::Fixed(80)),
      ..Args::default()
    };
    let input = test_input(&["name", "score"], &[vec!["alice", "10"], vec!["bob", "20"]]);
    let out = to_tennis(input, &args).unwrap().into_text();
    assert!(out.contains("\x1b[48;2;"), "{out:?}");
  }

  #[test]
  fn test_to_tennis_rscale_bad_column() {
    let args = Args { rscale: vec!["bogus".to_owned()], ..Args::default() };
    let input = test_input(&["name", "score"], &[vec!["alice", "10"]]);
    assert!(matches!(to_tennis(input, &args), Err(Error::MissingColumn { .. })));
  }

  #[test]
  fn test_tennis_error_conversion() {
    let headers = vec!["name".to_owned(), "score".to_owned()];
    assert_eq!(Error::JaggedCsv, Error::from(tennis::Error::Jagged { expected: 2, actual: 1 }));
    assert_eq!(Error::JaggedCsv, Error::from(tennis::Error::HeaderLength { expected: 2, actual: 1 }));
    assert_eq!(Error::Json, Error::from(tennis::Error::JsonArrayExpected));
    assert_eq!(Error::Json, Error::from(tennis::Error::JsonObjectExpected));

    let missing = Error::from(tennis::Error::MissingColumn {
      column: "bogus".to_owned(),
      operation: Some(tennis::ColumnOperation::Big),
      headers: headers.clone(),
    });
    assert_eq!(
      Error::MissingColumn { column: "bogus".to_owned(), operation: Some(tennis::ColumnOperation::Big), headers },
      missing
    );
  }
}
