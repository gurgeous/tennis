use std::collections::HashSet;

use rand::seq::SliceRandom;

#[cfg(test)]
use crate::{Border, ColorMode, Error, WidthMode};
use crate::{ColumnBig, ColumnType, Grid, RenderOptions, Result, args::Args, render, util};

//
// `tennis --peek`
//
// Share inference and number formatting with the crate so stats match tables.
//

const SAMPLE_ROWS: usize = 5;

pub fn render(input: &Grid, args: &Args) -> Result<String> {
  let mut out = String::new();
  out.push_str(&render_sample(input, args)?);
  out.push('\n');
  let columns = columns_rows(input, args);
  let columns = Grid::new(columns[0].clone(), columns[1..].to_vec()).expect("peek rows match headers");
  out.push_str(&render_table(columns, "columns", args));
  let numerics = numerics_rows(input, args);
  if numerics[0].len() > 1 {
    out.push('\n');
    let args = Args { digits: Some(NUMERICS_DIGITS as _), ..args.clone() };
    out.push_str(&render_table(numerics_grid(numerics), "numerics", &args));
  }
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

  let grid = input.clone().head(n);
  let mut options = RenderOptions {
    border: args.border.unwrap_or_default(),
    color: args.color,
    digits: args.digits.unwrap_or(3) as usize,
    footer,
    row_numbers: args.row_numbers,
    theme: args.theme,
    title: Some(title),
    vanilla: args.vanilla,
    width: args.width.unwrap_or_default(),
    zebra: args.zebra,
    ..RenderOptions::default()
  };
  options.bigs.extend(args.big1.iter().cloned().map(|column| (column, ColumnBig::Big)));
  options.bigs.extend(args.big2.iter().cloned().map(|column| (column, ColumnBig::Bigger)));
  options.bigs.extend(args.big3.iter().cloned().map(|column| (column, ColumnBig::Biggest)));
  options.validate(&grid)?;
  Ok(render::text(grid, options.resolve()))
}

fn sample_title(input: &Grid, title: Option<&str>) -> String {
  let r = util::pluralize("row", input.rows().len(), true);
  let c = util::pluralize("col", input.headers().len(), true);
  title.map_or_else(|| format!("{r} × {c}"), |t| format!("{t} ({r} × {c})"))
}

// Render one stats table (columns, numerics).
fn render_table(grid: Grid, title: &str, args: &Args) -> String {
  let options = RenderOptions {
    border: args.border.unwrap_or_default(),
    color: args.color,
    digits: args.digits.unwrap_or(3) as usize,
    theme: args.theme,
    title: Some(title.to_owned()),
    vanilla: false, // our stats, not user data
    width: args.width.unwrap_or_default(),
    ..RenderOptions::default()
  };
  render::text(grid, options.resolve())
}

fn column_type(input: &Grid, index: usize, args: &Args) -> ColumnType {
  if args.vanilla { ColumnType::String } else { input.column_type(index) }
}

//
// columns
//

fn columns_rows(input: &Grid, args: &Args) -> Vec<Vec<String>> {
  let mut out = vec![headers(&["column", "type", "fill", "uniq", "bytes", "sample"])];
  for (index, header) in input.headers().iter().enumerate() {
    let fields: Vec<&str> =
      input.rows().iter().map(|row| row[index].as_str()).filter(|value| !value.is_empty()).collect();
    let uniq = fields.iter().copied().collect::<HashSet<_>>().len();
    let fill = fill_pct(fields.len(), input.rows().len());
    let bytes: usize = fields.iter().map(|field| field.len()).sum();
    // empty sample renders as a placeholder
    let sample = fields.choose(&mut rand::thread_rng()).copied().unwrap_or_default();
    out.push(vec![
      header.clone(),
      column_type(input, index, args).to_string(),
      format!("{fill}%"),
      uniq.to_string(),
      bytes.to_string(),
      sample.to_owned(),
    ]);
  }
  out
}

fn fill_pct(nonempty: usize, nrows: usize) -> usize {
  nonempty.saturating_mul(100).checked_div(nrows).unwrap_or(0)
}

//
// numerics
//

const NUMERICS_DIGITS: usize = 1;
const INT_STATS: [&str; 2] = ["count", "outliers"];
const PERCENTILES: [(&str, f64); 5] = [("p10", 0.10), ("p25", 0.25), ("p50", 0.50), ("p75", 0.75), ("p90", 0.90)];

// Numeric columns only, transposed (one row per stat, one table column per
// source column). Each table column has a single type, so render can infer and
// format raw values. No source columns (header only) if there aren't any.
fn numerics_rows(input: &Grid, args: &Args) -> Vec<Vec<String>> {
  // min/mean/max, percentiles, counts. Empty separator rows render as placeholders.
  let mut stats = vec!["min", "mean", "max", ""];
  stats.extend(PERCENTILES.iter().map(|(name, _)| *name));
  stats.push("");
  stats.extend(INT_STATS);
  let mut out = vec![vec!["stat".to_owned()]];
  out.extend(stats.iter().map(|stat| vec![(*stat).to_owned()]));

  for (index, header) in input.headers().iter().enumerate() {
    let kind = column_type(input, index, args);
    if kind == ColumnType::String {
      continue;
    }
    let mut sorted: Vec<f64> = input.rows().iter().filter_map(|row| row[index].value()).map(|v| v.as_f64()).collect();
    if sorted.is_empty() {
      continue;
    }
    sorted.sort_by(f64::total_cmp);

    // raw values for render to format, except percents (render leaves those
    // as-is). Not localized, so `10,0%` can't turn the column into text.
    let format = |x: f64| {
      if kind == ColumnType::Percent { format!("{x:.NUMERICS_DIGITS$}%") } else { format!("{x}") }
    };
    let mean = sorted.iter().sum::<f64>() / sorted.len() as f64;
    let mut values = vec![format(sorted[0]), format(mean), format(sorted[sorted.len() - 1]), String::new()];
    values.extend(PERCENTILES.iter().map(|(_, p)| format(percentile(&sorted, *p))));
    values.extend([String::new(), sorted.len().to_string(), outliers(&sorted).to_string()]);

    out[0].push(header.clone());
    for (row, value) in out[1..].iter_mut().zip(values) {
      row.push(value);
    }
  }
  out
}

// Linear interpolation between closest ranks, like numpy/pandas default.
fn percentile(sorted: &[f64], p: f64) -> f64 {
  let rank = p * (sorted.len() - 1) as f64;
  let (lo, hi) = (rank.floor() as usize, rank.ceil() as usize);
  sorted[lo] + (sorted[hi] - sorted[lo]) * (rank - lo as f64)
}

// count/outliers are ints, but they live in float/percent columns. Leave them
// empty while Grid infers column types (empty cells don't vote), then fill them
// in as text. Render leaves cells without a numeric value as-is, right-aligned.
fn numerics_grid(mut rows: Vec<Vec<String>>) -> Grid {
  let ints: Vec<(usize, Vec<String>)> = rows
    .iter_mut()
    .enumerate()
    .skip(1)
    .filter(|(_, row)| INT_STATS.contains(&row[0].as_str()))
    .map(|(index, row)| (index, row[1..].iter_mut().map(std::mem::take).collect()))
    .collect();

  let mut grid = Grid::new(rows[0].clone(), rows[1..].to_vec()).expect("peek rows match headers");
  for (index, values) in ints {
    for (col, text) in values.into_iter().enumerate() {
      // set_text keeps value None, so render won't reformat it
      grid.rows[index - 1][col + 1].set_text(text);
    }
  }
  grid
}

// Tukey's fences, same as box plots: outside p25 - 1.5 IQR .. p75 + 1.5 IQR
fn outliers(sorted: &[f64]) -> usize {
  let (p25, p75) = (percentile(sorted, 0.25), percentile(sorted, 0.75));
  let fence = 1.5 * (p75 - p25);
  sorted.iter().filter(|&&x| x < p25 - fence || x > p75 + fence).count()
}

fn headers(names: &[&str]) -> Vec<String> {
  names.iter().map(|name| (*name).to_owned()).collect()
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
  fn test_columns_rows() {
    let args = Args::default();
    let input = make_input(&[
      vec!["name", "score", "city"],
      vec!["alice", "10", "boston"],
      vec!["bob", "20", ""],
      vec!["cara", "20", "chicago"],
    ]);
    let rows = columns_rows(&input, &args);
    assert_eq!(["column", "type", "fill", "uniq", "bytes", "sample"], rows[0].as_slice());
    assert_eq!(["name", "string", "100%", "3", "12"], rows[1][..5]);
    assert_eq!(["score", "int", "100%", "2", "6"], rows[2][..5]);
    assert_eq!(["city", "string", "66%", "2", "13"], rows[3][..5]);

    // sample is random, but always a non-empty value from the column
    for _ in 0..20 {
      let rows = columns_rows(&input, &args);
      assert!(["alice", "bob", "cara"].contains(&rows[1][5].as_str()));
      assert!(["boston", "chicago"].contains(&rows[3][5].as_str()));
    }
  }

  #[test]
  fn test_columns_rows_cases() {
    for (input, expected) in [
      // empty column, sample renders as a placeholder
      (vec![vec!["empty"], vec![""], vec![""]], ["empty", "string", "0%", "0", "0", ""]),
      // utf-8 bytes, not display width
      (vec![vec!["city"], vec!["香港"]], ["city", "string", "100%", "1", "6", "香港"]),
      (
        vec![vec!["count"], vec!["99999999999999999999"]],
        ["count", "string", "100%", "1", "20", "99999999999999999999"],
      ),
    ] {
      assert_eq!(expected, columns_rows(&make_input(&input), &Args::default())[1].as_slice());
    }

    let args = Args { vanilla: true, ..Args::default() };
    let rows = columns_rows(&make_input(&[vec!["score"], vec!["10"]]), &args);
    assert_eq!(["score", "string", "100%", "1", "2", "10"], rows[1].as_slice());
  }

  #[test]
  fn test_numerics_rows() {
    let input = make_input(&[
      vec!["name", "score", "pct", "float"],
      vec!["alice", "1", "10%", "1.23456"],
      vec!["bob", "2", "-5%", "20.9999"],
      vec!["cara", "3", "", "3"],
      vec!["dave", "4", "20%", "4"],
    ]);
    // transposed, strings are skipped
    let rows = numerics_rows(&input, &Args::default());
    assert_eq!(["stat", "score", "pct", "float"], rows[0].as_slice());
    let column = |c: usize| rows[1..].iter().map(|row| row[c].as_str()).collect::<Vec<_>>();
    // empty separator rows between min/mean/max, percentiles and counts
    let names = ["min", "mean", "max", "", "p10", "p25", "p50", "p75", "p90", "", "count", "outliers"];
    assert_eq!(names, column(0).as_slice());

    // raw values for render to format, except percents which are formatted here
    let score = column(1);
    assert_eq!(["1", "2.5", "4", "", "2.5", "", "4", "0"], [0, 1, 2, 3, 6, 9, 10, 11].map(|i| score[i]));
    let pct = ["-5.0%", "8.3%", "20.0%", "", "-2.0%", "2.5%", "10.0%", "15.0%", "18.0%", "", "3", "0"];
    assert_eq!(pct, column(2).as_slice());

    // no numeric columns, header only
    assert_eq!(1, numerics_rows(&make_input(&[vec!["name"], vec!["alice"]]), &Args::default())[0].len());
    assert_eq!(1, numerics_rows(&input, &Args { vanilla: true, ..Args::default() })[0].len());
  }

  #[test]
  fn test_percentile() {
    for (sorted, p, expected) in [
      (vec![5.0], 0.5, 5.0),
      (vec![1.0, 2.0], 0.5, 1.5),
      (vec![1.0, 2.0, 3.0, 4.0], 0.1, 1.3),
      (vec![1.0, 2.0, 3.0, 4.0], 0.9, 3.7),
      (vec![1.0, 2.0, 3.0, 4.0], 0.0, 1.0),
      (vec![1.0, 2.0, 3.0, 4.0], 1.0, 4.0),
    ] {
      assert!((expected - percentile(&sorted, p)).abs() < 1e-9, "{sorted:?} {p}");
    }
  }

  #[test]
  fn test_numerics_grid() {
    let input = make_input(&[vec!["score", "pct"], vec!["1", "10%"], vec!["2", "-5%"], vec!["40", "20%"]]);
    let grid = numerics_grid(numerics_rows(&input, &Args::default()));

    // ints don't change the inferred column types, and keep their text
    assert_eq!([ColumnType::String, ColumnType::Float, ColumnType::Percent], grid.types.as_slice());
    let count = grid.rows.iter().find(|row| row[0].as_str() == "count").unwrap();
    assert_eq!(["3", "3"], [count[1].as_str(), count[2].as_str()]);
    assert!(count[1..].iter().all(|cell| cell.value().is_none()));
  }

  #[test]
  fn test_outliers() {
    for (sorted, expected) in [
      (vec![5.0], 0),
      (vec![1.0, 2.0, 3.0, 4.0], 0),
      (vec![1.0, 2.0, 3.0, 4.0, 100.0], 1),
      (vec![-100.0, 1.0, 2.0, 3.0, 4.0, 100.0], 2),
      (vec![3.0, 3.0, 3.0, 9.0], 1),
    ] {
      assert_eq!(expected, outliers(&sorted), "{sorted:?}");
    }
  }

  #[test]
  fn test_peek_render() {
    let args = Args { width: Some(WidthMode::Fixed(80)), ..Args::default() };
    let input = make_input(&[vec!["name", "score"], vec!["alice", "10"], vec!["bob", "20"]]);
    let out = render(&input, &args).unwrap();
    assert!(out.contains("\n\n"));
    assert!(out.contains("alice"));
    assert!(out.contains("columns"));
    assert!(out.contains("numerics"));
    assert!(out.contains("p50"));
    assert!(out.contains("int"));

    // no numeric columns, no numerics table
    let input = make_input(&[vec!["name"], vec!["alice"]]);
    assert!(!render(&input, &args).unwrap().contains("numerics"));

    // numerics honors presentation flags and formats with 1 digit
    let input = make_input(&[vec!["n"], vec!["10"], vec!["31"]]);
    let out = render(&input, &Args { border: Some(Border::Basic), color: Some(ColorMode::Off), ..args }).unwrap();
    let numerics = out.split("numerics").nth(1).unwrap();
    assert!(numerics.contains("| stat     | n    |"), "{numerics}");
    assert!(numerics.contains("| p10      | 12.1 |"), "{numerics}");
    assert!(!out.contains('\x1b'));
  }

  #[test]
  fn test_peek_render_empty_shape() {
    let args = Args { width: Some(WidthMode::Fixed(80)), ..Args::default() };
    let input = make_input(&[vec!["name", "score"], vec!["alice", "10"]]);
    let args = Args { filter: Some("missing".to_owned()), width: Some(WidthMode::Fixed(80)), ..args };
    // empty transform result means 0 data rows but headers remain
    let input = Grid::new(input.headers().to_vec(), Vec::new()).unwrap();
    let out = render(&input, &args).unwrap();
    assert!(out.contains("0 rows × 2 cols"));
  }

  #[test]
  fn test_peek_render_footer() {
    let args = Args { width: Some(WidthMode::Fixed(80)), ..Args::default() };
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
    let args = Args { big1: vec!["missing".to_owned()], width: Some(WidthMode::Fixed(80)), ..Args::default() };
    let input = make_input(&[vec!["name", "score"], vec!["alice", "10"]]);
    assert!(matches!(render(&input, &args), Err(Error::MissingColumn { .. })));
  }
}
