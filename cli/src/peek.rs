use std::collections::HashSet;

use tennis::{
  ColumnType, Grid,
  number::{format_float, format_int},
};
use unicode_width::UnicodeWidthStr;

use crate::{args::Args, error::Result, util};

//
// `tennis --peek`
//
// Share inference and number formatting with the crate so stats match tables.
//

const SAMPLE_ROWS: usize = 5;
const DEFAULT_DIGITS: usize = 3;

pub fn render(input: &Grid, args: &Args) -> Result<String> {
  let mut out = String::new();
  out.push_str(&render_sample(input, args)?);
  out.push('\n');
  out.push_str(&render_stats(input, args)?);
  Ok(out)
}

//
// sample
//

fn render_sample(input: &Grid, args: &Args) -> Result<String> {
  let title = sample_title(input, args.title.as_deref());

  let n = SAMPLE_ROWS.min(input.rows().len());
  let footer =
    (input.rows().len() > n).then(|| format!("… {} …", util::pluralize("more row", input.rows().len() - n, true)));

  let taken = input.rows().iter().take(n).cloned().collect();
  let grid = Grid::new(input.headers().to_vec(), taken).expect("peek sample rows match source headers");
  let mut builder =
    tennis::Table::builder().load_grid(grid).row_numbers(args.row_numbers).vanilla(args.vanilla).zebra(args.zebra);

  // optionals
  builder = builder.title(title);
  if let Some(border) = args.border {
    builder = builder.border(border);
  }
  if let Some(color) = args.color {
    builder = builder.color(color);
  }
  if let Some(digits) = args.digits {
    builder = builder.digits(digits as usize);
  }
  if let Some(footer) = footer {
    builder = builder.footer(footer);
  }
  if let Some(theme) = args.theme {
    builder = builder.theme(theme);
  }
  if let Some(width) = args.width {
    builder = builder.width(width);
  }

  // big
  for raw in &args.big1 {
    builder = builder.big(raw);
  }
  for raw in &args.big2 {
    builder = builder.bigger(raw);
  }
  for raw in &args.big3 {
    builder = builder.biggest(raw);
  }
  builder.build().map(|table| table.into_text()).map_err(crate::error::Error::from)
}

fn sample_title(input: &Grid, title: Option<&str>) -> String {
  let r = util::pluralize("row", input.rows().len(), true);
  let c = util::pluralize("col", input.headers().len(), true);
  title.map_or_else(|| format!("{r} × {c}"), |t| format!("{t} ({r} × {c})"))
}

//
// stats
//

fn render_stats(input: &Grid, args: &Args) -> Result<String> {
  let stats_rows = stats_rows(input, args);
  let grid = Grid::new(stats_rows[0].clone(), stats_rows[1..].to_vec()).expect("peek stats rows match stats headers");
  let mut builder = tennis::Table::builder().load_grid(grid).vanilla(args.vanilla);

  builder = builder.title("stats");
  if let Some(border) = args.border {
    builder = builder.border(border);
  }
  if let Some(color) = args.color {
    builder = builder.color(color);
  }
  if let Some(digits) = args.digits {
    builder = builder.digits(digits as usize);
  }
  if let Some(theme) = args.theme {
    builder = builder.theme(theme);
  }
  if let Some(width) = args.width {
    builder = builder.width(width);
  }

  builder.build().map(|table| table.into_text()).map_err(crate::error::Error::from)
}

fn stats_rows(input: &Grid, args: &Args) -> Vec<Vec<String>> {
  let mut out = vec![vec![
    "column".to_owned(),
    "type".to_owned(),
    "fill".to_owned(),
    "uniq".to_owned(),
    "min".to_owned(),
    "max".to_owned(),
  ]];

  for (index, header) in input.headers().iter().enumerate() {
    let kind = input.column_type(index, args.vanilla);
    let stats = column_stats(input.rows(), index, kind, args);
    out.push(vec![header.clone(), kind.to_string(), stats.fill, stats.uniq, stats.min, stats.max]);
  }
  out
}

//
// Stats computation
//

#[derive(Debug, Eq, PartialEq)]
struct Stats {
  fill: String,
  uniq: String,
  min: String,
  max: String,
}

fn column_stats(rows: &[Vec<String>], index: usize, kind: ColumnType, args: &Args) -> Stats {
  let fields: Vec<&str> = rows
    .iter()
    .filter_map(|row| {
      let value = row[index].as_str();
      (!value.is_empty()).then_some(value)
    })
    .collect();
  let seen: HashSet<&str> = fields.iter().copied().collect();

  let fill = fill_pct(fields.len(), rows.len());
  let digits = args.digits.map_or(DEFAULT_DIGITS, |digits| digits as usize);
  let (min, max) = match kind {
    ColumnType::Int => int_minmax(&fields, args),
    ColumnType::Float => float_minmax(&fields, digits),
    ColumnType::Percent => percent_minmax(&fields, digits),
    ColumnType::String => len_minmax(&fields),
  };

  Stats { fill: format!("{fill}%"), uniq: seen.len().to_string(), min, max }
}

fn fill_pct(nonempty: usize, nrows: usize) -> usize {
  nonempty.saturating_mul(100).checked_div(nrows).unwrap_or(0)
}

fn int_minmax(fields: &[&str], args: &Args) -> (String, String) {
  let Some((min, max)) = util::minmax(fields.iter().filter_map(|f| f.parse::<i128>().ok())) else {
    return placeholders();
  };
  if args.vanilla {
    (min.to_string(), max.to_string())
  } else {
    (format_int(&min.to_string()), format_int(&max.to_string()))
  }
}

fn float_minmax(fields: &[&str], digits: usize) -> (String, String) {
  let values = fields.iter().filter_map(|f| f.parse::<f64>().ok().map(|v| (v, *f)));
  let Some(((_, min), (_, max))) = util::minmax_by(values, |a, b| a.0.total_cmp(&b.0)) else {
    return placeholders();
  };
  (format_float(min, digits), format_float(max, digits))
}

fn percent_minmax(fields: &[&str], digits: usize) -> (String, String) {
  let values = fields.iter().filter_map(|f| {
    let raw = f.strip_suffix('%')?;
    raw.parse::<f64>().ok().map(|v| (v, raw))
  });
  let Some(((_, min), (_, max))) = util::minmax_by(values, |a, b| a.0.total_cmp(&b.0)) else {
    return placeholders();
  };
  (format!("{}%", format_float(min, digits)), format!("{}%", format_float(max, digits)))
}

fn len_minmax(fields: &[&str]) -> (String, String) {
  let Some((min, max)) = util::minmax(fields.iter().map(|f| f.width())) else {
    return placeholders();
  };
  (util::pluralize("width", min, true), util::pluralize("width", max, true))
}

fn placeholders() -> (String, String) {
  (util::PLACEHOLDER.to_owned(), util::PLACEHOLDER.to_owned())
}

#[cfg(test)]
mod tests {
  use super::*;

  fn make_input(input: &[Vec<&str>]) -> Grid {
    let headers: Vec<String> = input[0].iter().map(|s| s.to_string()).collect();
    let rows: Vec<Vec<String>> = input[1..].iter().map(|r| r.iter().map(|s| s.to_string()).collect()).collect();
    Grid::new(headers, rows).unwrap()
  }

  #[test]
  fn test_sample_title() {
    let input = make_input(&[vec!["a", "b"], vec!["1", "2"], vec!["3", "4"]]);
    assert_eq!("2 rows × 2 cols", sample_title(&input, None));
    assert_eq!("foo (2 rows × 2 cols)", sample_title(&input, Some("foo")));

    let input = make_input(&[vec!["a"], vec!["x"]]);
    assert_eq!("1 row × 1 col", sample_title(&input, None));
  }

  #[test]
  fn test_stats_rows() {
    let args = Args::default();
    let input = make_input(&[
      vec!["name", "score", "city"],
      vec!["alice", "10", "boston"],
      vec!["bob", "20", ""],
      vec!["cara", "20", "chicago"],
    ]);
    let sr = stats_rows(&input, &args);
    assert_eq!(["name", "string", "100%", "3", "3 widths", "5 widths"], sr[1].as_slice());
    assert_eq!(["score", "int", "100%", "2", "10", "20"], sr[2].as_slice());
    assert_eq!(["city", "string", "66%", "2", "6 widths", "7 widths"], sr[3].as_slice());
  }

  #[test]
  fn test_stats_rows_empty_column() {
    let args = Args::default();
    let input = make_input(&[vec!["empty"], vec![""], vec![""]]);
    let rows = stats_rows(&input, &args);
    assert_eq!(["empty", "string", "0%", "0", "—", "—"], rows[1].as_slice());
  }

  #[test]
  fn test_stats_rows_negative_ints() {
    let args = Args::default();
    let input = make_input(&[vec!["score"], vec!["-5000"], vec!["10"]]);
    let rows = stats_rows(&input, &args);
    assert_eq!(["score", "int", "100%", "2", "-5,000", "10"], rows[1].as_slice());
  }

  #[test]
  fn test_stats_rows_oversized_ints() {
    let args = Args::default();
    let input = make_input(&[vec!["count"], vec!["99999999999999999999"]]);
    let rows = stats_rows(&input, &args);
    assert_eq!(
      ["count", "int", "100%", "1", "99,999,999,999,999,999,999", "99,999,999,999,999,999,999"],
      rows[1].as_slice()
    );
  }

  #[test]
  fn test_stats_rows_floats() {
    let args = Args::default();
    let input = make_input(&[vec!["score"], vec!["1.23456"], vec!["20.9999"]]);
    let rows = stats_rows(&input, &args);
    assert_eq!(["score", "float", "100%", "2", "1.235", "21.000"], rows[1].as_slice());
  }

  #[test]
  fn test_stats_rows_percent() {
    let args = Args::default();
    let input = make_input(&[vec!["score", "other"], vec!["12%", "x"], vec!["-3.5%", "y"], vec!["", "z"]]);
    let rows = stats_rows(&input, &args);
    assert_eq!(["score", "percent", "66%", "2", "-3.500%", "12.000%"], rows[1].as_slice());
  }

  #[test]
  fn test_stats_rows_unicode_width() {
    let args = Args::default();
    let input = make_input(&[vec!["city"], vec!["a"], vec!["香港"]]);
    let rows = stats_rows(&input, &args);
    assert_eq!(["city", "string", "100%", "2", "1 width", "4 widths"], rows[1].as_slice());
  }

  #[test]
  fn test_stats_rows_args_formatting() {
    let args = Args { digits: Some(2), ..Args::default() };
    let input = make_input(&[vec!["float", "percent"], vec!["1.23456", "12.345%"], vec!["20.9999", "-3.5%"]]);
    let rows = stats_rows(&input, &args);
    assert_eq!(["float", "float", "100%", "2", "1.23", "21.00"], rows[1].as_slice());
    assert_eq!(["percent", "percent", "100%", "2", "-3.50%", "12.35%"], rows[2].as_slice());

    let args = Args { vanilla: true, ..Args::default() };
    let input = make_input(&[vec!["score"], vec!["-5000"], vec!["10"]]);
    let rows = stats_rows(&input, &args);
    assert_eq!(["score", "string", "100%", "2", "2 widths", "5 widths"], rows[1].as_slice());
  }

  #[test]
  fn test_peek_render() {
    let args = Args { width: Some(tennis::WidthMode::Fixed(80)), ..Args::default() };
    let input = make_input(&[vec!["name", "score"], vec!["alice", "10"], vec!["bob", "20"]]);
    let out = render(&input, &args).unwrap();
    assert!(out.contains("\n\n"));
    assert!(out.contains("alice"));
    assert!(out.contains("stats"));
    assert!(out.contains("score"));
    assert!(out.contains("int"));
  }

  #[test]
  fn test_peek_render_empty_shape() {
    let args = Args { width: Some(tennis::WidthMode::Fixed(80)), ..Args::default() };
    let input = make_input(&[vec!["name", "score"], vec!["alice", "10"]]);
    let args = Args { filter: Some("missing".to_owned()), width: Some(tennis::WidthMode::Fixed(80)), ..args };
    // empty transform result means 0 data rows but headers remain
    let input = Grid::new(input.headers().to_vec(), Vec::new()).unwrap();
    let out = render(&input, &args).unwrap();
    assert!(out.contains("0 rows × 2 cols"));
  }

  #[test]
  fn test_peek_render_footer() {
    let args = Args { width: Some(tennis::WidthMode::Fixed(80)), ..Args::default() };
    let input = make_input(&[
      vec!["customer_name_or_identifier"],
      vec!["alice"],
      vec!["bob"],
      vec!["cara"],
      vec!["dave"],
      vec!["erin"],
      vec!["frank"],
    ]);
    let out = render(&input, &args).unwrap();
    assert!(out.contains("… 1 more row …"));
  }

  #[test]
  fn test_peek_render_bad_big() {
    let args = Args { big1: vec!["missing".to_owned()], width: Some(tennis::WidthMode::Fixed(80)), ..Args::default() };
    let input = make_input(&[vec!["name", "score"], vec!["alice", "10"]]);
    assert!(matches!(render(&input, &args), Err(crate::error::Error::MissingColumn { .. })));
  }
}
