use std::{ffi::OsString, path::PathBuf};

use clap::{Command, CommandFactory, Error, Parser, ValueEnum, builder::styling, value_parser};
use tennis::{Border, ColorMode, ThemeMode, WidthMode};

//
// CLI arguments
//

// We only have one command
pub fn command() -> Command {
  Args::command()
}

pub fn help() -> String {
  let mut command = command()
    .styles(help_styles())
    .help_template("{usage-heading} {usage}\n\n{about-with-newline}\n{all-args}{after-help}")
    .hide_possible_values(true)
    .mut_args(|arg| if arg.get_action().takes_values() { arg.hide_default_value(true) } else { arg });
  let help = command.render_help().ansi().to_string();
  add_big_help_lines(&command, &help)
}

// Keep clap's color cues, but skip underlined headings.
fn help_styles() -> styling::Styles {
  styling::Styles::styled()
    .header(styling::AnsiColor::Blue.on_default().bold())
    .usage(styling::AnsiColor::Blue.on_default().bold())
    .literal(literal_style())
    .placeholder(placeholder_style())
}

fn literal_style() -> styling::Style {
  styling::AnsiColor::Green.on_default().bold()
}

fn placeholder_style() -> styling::Style {
  styling::AnsiColor::Yellow.on_default()
}

// `-bb` and `-bbb` are Tennis shorthand, not clap-native short flags. They are
// hidden parser args and inserted into help after clap renders `-b`.
fn add_big_help_lines(command: &Command, help: &str) -> String {
  let big2_line = big_help_line("-bb", "        ", arg_help(command, "big2"));
  let big3_line = big_help_line("-bbb", "       ", arg_help(command, "big3"));
  let mut out = String::new();
  for line in help.lines() {
    if line.contains("Make these columns Bigger") {
      out.push_str(line);
      out.push('\n');
      out.push_str(&big2_line);
      out.push('\n');
      out.push_str(&big3_line);
    } else {
      out.push_str(line);
    }
    out.push('\n');
  }

  if !help.ends_with('\n') {
    out.pop();
  }
  out
}

fn arg_help(command: &Command, id: &str) -> String {
  command
    .get_arguments()
    .find(|arg| arg.get_id().as_str() == id)
    .and_then(|arg| arg.get_help().or_else(|| arg.get_long_help()))
    .map(|help| help.to_string())
    .unwrap_or_default()
}

fn big_help_line(flag: &str, spaces: &str, desc: String) -> String {
  let literal = literal_style();
  let placeholder = placeholder_style();
  format!(
    "  {literal_start}{flag}{literal_end} {placeholder_start}<headers>{placeholder_end}{spaces}{desc}",
    literal_start = literal.render(),
    literal_end = literal.render_reset(),
    placeholder_start = placeholder.render(),
    placeholder_end = placeholder.render_reset(),
  )
}

//
// arg parsers
//

fn parse_border(input: &str) -> Result<Border, String> {
  fn err() -> String {
    "border must be one of: ascii-rounded, basic, basic-compact, compact, \
     compact-double, dots, double, heavy, light, markdown, none, psql, \
     reinforced, restructured, rounded, single, thin, with-love"
      .to_owned()
  }

  match input {
    "ascii_rounded" | "ascii-rounded" => Ok(Border::AsciiRounded),
    "basic" => Ok(Border::Basic),
    "basic_compact" | "basic-compact" => Ok(Border::BasicCompact),
    "compact" => Ok(Border::Compact),
    "compact_double" | "compact-double" => Ok(Border::CompactDouble),
    "dots" => Ok(Border::Dots),
    "double" => Ok(Border::Double),
    "heavy" => Ok(Border::Heavy),
    "light" => Ok(Border::Light),
    "markdown" => Ok(Border::Markdown),
    "none" => Ok(Border::None),
    "psql" => Ok(Border::Psql),
    "reinforced" => Ok(Border::Reinforced),
    "restructured" => Ok(Border::Restructured),
    "rounded" => Ok(Border::Rounded),
    "single" => Ok(Border::Single),
    "thin" => Ok(Border::Thin),
    "with_love" | "with-love" => Ok(Border::WithLove),
    _ => Err(err()),
  }
}

fn parse_color(input: &str) -> Result<ColorMode, String> {
  match input {
    "auto" => Ok(ColorMode::Auto),
    "on" | "always" => Ok(ColorMode::On),
    "off" | "never" => Ok(ColorMode::Off),
    _ => Err("color must be auto, on, or off".to_owned()),
  }
}

fn parse_theme(input: &str) -> Result<ThemeMode, String> {
  match input {
    "auto" => Ok(ThemeMode::Auto),
    "dark" => Ok(ThemeMode::Dark),
    "light" => Ok(ThemeMode::Light),
    _ => Err("theme must be auto, dark, or light".to_owned()),
  }
}

fn parse_width_mode(input: &str) -> Result<WidthMode, String> {
  match input {
    "auto" => Ok(WidthMode::Auto),
    "min" => Ok(WidthMode::Header),
    "max" => Ok(WidthMode::Natural),
    raw => {
      let value = raw.parse::<usize>().map_err(|_| "width must be auto, min, max, or an integer".to_owned())?;
      if value == 0 { Ok(WidthMode::Auto) } else { Ok(WidthMode::Fixed(value)) }
    }
  }
}

//
// our three headings
//

const POP: &str = "Popular options";
const SORT: &str = "Sort, filter, etc";
const LAYOUT: &str = "Table layout";
const OTHER: &str = "Other options";

// NOTE TO LLMS: the field order below and hand-written comments in this file
// are important. Do not reorder or rewrite comments without asking first.
#[rustfmt::skip]
#[derive(Clone, Debug, Default, Eq, Parser, PartialEq)]
#[command(
  name = "tennis",
  disable_help_flag = true,
  disable_version_flag = true,
  about = "Stylish CSV tables in your terminal"
)]
pub struct Args {
  /// Turn on row numbers
  #[arg(help_heading=POP, short='n', long)]
  pub row_numbers: bool,

  /// Add a title to the table
  #[arg(help_heading=POP, short='t', long, value_name="string")]
  pub title: Option<String>,

  #[arg(skip)]
  pub footer: Option<String>,

  /// Table border style (rounded|thin|double|...).
  #[arg(help_heading=POP, long, value_name="border", value_parser = parse_border)]
  pub border: Option<Border>,

  /// Send output through $PAGER or less
  #[arg(help_heading=POP, short='p', long)]
  pub pager: bool,

  /// Show csv shape, sample, and handy stats
  #[arg(help_heading=POP, long)]
  pub peek: bool,

  /// Turn on zebra stripes
  #[arg(help_heading=POP, short='z', long)]
  pub zebra: bool,

  //
  // sort
  //

  /// De-select comma-separated headers
  #[arg(help_heading=SORT, long, value_name="headers", value_delimiter=',')]
  pub deselect: Vec<String>,

  /// Select or reorder comma-separated headers
  #[arg(help_heading=SORT, long, value_name="headers", value_delimiter=',')]
  pub select: Vec<String>,

  /// Sort rows by comma-separated headers
  #[arg(help_heading=SORT, long, value_name="headers", value_delimiter=',')]
  pub sort: Vec<String>,

  /// Reverse rows (helpful for sorting)
  #[arg(help_heading=SORT, short='r', long)]
  pub reverse: bool,

  /// Shuffle rows into random order
  #[arg(help_heading=SORT, long, alias="shuf")]
  pub shuffle: bool,

  /// Show first N rows
  #[arg(help_heading=SORT, long, value_name="int", value_parser=value_parser!(u32).range(1..), conflicts_with="tail")]
  pub head: Option<u32>,

  /// Show last N rows
  #[arg(help_heading=SORT, long, value_name="int", value_parser=value_parser!(u32).range(1..))]
  pub tail: Option<u32>,

  /// Only show rows that contain this text
  #[arg(help_heading=SORT, long, value_name="string")]
  pub filter: Option<String>,

  //
  // layout
  //

  /// Make these columns Bigger
  #[arg(help_heading=LAYOUT, short='b', value_name="headers", value_delimiter=',')]
  pub big1: Vec<String>,

  /// Make even BIGGER (p90)
  #[arg(help_heading=LAYOUT, long="_b2",hide=true, value_name="headers", value_delimiter=',')]
  pub big2: Vec<String>,

  /// Make BIGGEST (full width)
  #[arg(help_heading=LAYOUT, long="_b3",hide=true, value_name="headers", value_delimiter=',')]
  pub big3: Vec<String>,

  /// Set table width, or try (min|max)
  #[arg(help_heading=LAYOUT, long, value_name="width", value_parser = parse_width_mode)]
  pub width: Option<WidthMode>,

  //
  // other
  //

  /// Turn color off and on (on|off|auto)
  #[arg(help_heading=OTHER, long, value_name="color", value_parser = parse_color)]
  pub color: Option<ColorMode>,

  /// Set CSV delim (can be any char or "tab")
  #[arg(help_heading=OTHER, short='d', long, value_name="char", value_parser=parse_delimiter)]
  pub delimiter: Option<u8>,

  /// Digits after decimal for float columns
  #[arg(help_heading=OTHER, long, value_name="int", value_parser=value_parser!(u32).range(1..=6))]
  pub digits: Option<u32>,

  /// Add red-to-green color scale
  #[arg(help_heading=OTHER, long, value_name="headers", value_delimiter=',')]
  pub scale: Vec<String>,

  /// Like --scale, but green-to-red
  #[arg(help_heading=OTHER, long, value_name="headers", value_delimiter=',')]
  pub rscale: Vec<String>,

  /// Select the db table (for sqlite)
  #[arg(help_heading=OTHER, long, value_name="table")]
  pub table: Option<String>,

  /// Select color theme (auto|dark|light)
  #[arg(help_heading=OTHER, long, value_name="theme", value_parser = parse_theme)]
  pub theme: Option<ThemeMode>,

  /// Disable numeric formatting
  #[arg(help_heading=OTHER, long)]
  pub vanilla: bool,

  /// Print shell completion (bash|zsh)
  #[arg(help_heading = OTHER, hide = true, long, value_name = "shell")]
  pub completion: Option<CompletionShell>,

  /// Get help
  #[arg(help_heading = OTHER, short = 'h', long)]
  pub help: bool,

  /// Show version number and exit
  #[arg(help_heading = OTHER, short = 'v', long)]
  pub version: bool,

  // Positional input / parser state
  /// csv, json/jsonl, or sqlite file
  pub file: Option<PathBuf>,

  /// (internal) True when any argv was provided (not just the binary name).
  #[clap(skip)]
  pub argv_had_args: bool,
}

pub fn parse_from<I, T>(args: I) -> Result<Args, String>
where
  I: IntoIterator<Item = T>,
  T: Into<OsString>,
{
  let normalized = normalize_big_args(args);
  let argv_had_args = normalized.len() > 1;
  let mut args = Args::try_parse_from(normalized).map_err(format_parse_error)?;
  args.argv_had_args = argv_had_args;
  Ok(args)
}

fn format_parse_error(error: Error) -> String {
  error.to_string().lines().next().unwrap_or("invalid arguments").trim_start_matches("error: ").to_owned()
}

// Rust clap does not treat `-bb` and `-bbb` as distinct shorthand options.
// Rewrite them before parsing.
fn normalize_big_args<I, T>(args: I) -> Vec<OsString>
where
  I: IntoIterator<Item = T>,
  T: Into<OsString>,
{
  let mut out = Vec::new();
  let mut options_done = false;
  for arg in args {
    let arg = arg.into();
    if options_done {
      out.push(arg);
      continue;
    }

    let normalized = match arg.to_str() {
      Some("--") => {
        options_done = true;
        arg
      }
      Some("-bb") => OsString::from("--_b2"),
      Some(value) if value.starts_with("-bb=") => {
        OsString::from(format!("--_b2={}", value.strip_prefix("-bb=").unwrap()))
      }
      Some("-bbb") => OsString::from("--_b3"),
      Some(value) if value.starts_with("-bbb=") => {
        OsString::from(format!("--_b3={}", value.strip_prefix("-bbb=").unwrap()))
      }
      _ => arg,
    };
    out.push(normalized);
  }
  out
}

fn parse_delimiter(input: &str) -> Result<u8, String> {
  match input {
    "tab" | "\\t" | "\t" => Ok(b'\t'),
    " " => Ok(b' '),
    s if s.len() == 1 && s.as_bytes()[0].is_ascii_graphic() => Ok(s.as_bytes()[0]),
    _ => Err("delimiter must be one printable ASCII character or tab".to_owned()),
  }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, ValueEnum)]
#[value(rename_all = "kebab-case")]
pub enum CompletionShell {
  Bash,
  Zsh,
}

#[cfg(test)]
mod tests {
  use super::*;

  fn parse(args: &[&str]) -> Result<Args, String> {
    let argv = std::iter::once("tennis").chain(args.iter().copied());
    parse_from(argv)
  }

  #[test]
  fn test_parse_option_args_case() {
    let args = parse(&[
      "--border",
      "double",
      "-b",
      "input",
      "-bb",
      "output",
      "-bbb",
      "warnings",
      "--scale",
      "score",
      "--rscale",
      "latency",
      "--color",
      "off",
      "--digits",
      "4",
      "--filter",
      "ali",
      "--head",
      "5",
      "--shuffle",
      "--table",
      "players",
      "--theme",
      "light",
      "--width",
      "80",
      "-n",
      "-",
    ])
    .unwrap();

    assert_eq!(Some(Border::Double), args.border);
    assert_eq!(["input"], args.big1.as_slice());
    assert_eq!(["output"], args.big2.as_slice());
    assert_eq!(["warnings"], args.big3.as_slice());
    assert_eq!(["score"], args.scale.as_slice());
    assert_eq!(["latency"], args.rscale.as_slice());
    assert_eq!(Some(ColorMode::Off), args.color);
    assert_eq!(Some(4), args.digits);
    assert_eq!(Some("ali"), args.filter.as_deref());
    assert_eq!(Some(5), args.head);
    assert!(args.shuffle);
    assert_eq!(Some("players"), args.table.as_deref());
    assert_eq!(Some(ThemeMode::Light), args.theme);
    assert_eq!(Some(WidthMode::Fixed(80)), args.width);
    assert!(args.row_numbers);
    assert_eq!(Some(PathBuf::from("-")), args.file);
    assert!(args.argv_had_args);
  }

  #[test]
  fn test_parse_option_cases() {
    assert_eq!(Some(b';'), parse(&["--delimiter", ";", "-"]).unwrap().delimiter);
    assert_eq!(Some(b' '), parse(&["--delimiter", " ", "-"]).unwrap().delimiter);
    assert_eq!(Some(b'\t'), parse(&["--delimiter", "tab", "-"]).unwrap().delimiter);
    assert_eq!(Some(b'\t'), parse(&["--delimiter", "\\t", "-"]).unwrap().delimiter);
    assert_eq!(Some(b'\t'), parse(&["--delimiter", "\t", "-"]).unwrap().delimiter);
    assert_eq!(Some(Border::CompactDouble), parse(&["--border", "compact_double", "-"]).unwrap().border);
    assert_eq!(Some(Border::CompactDouble), parse(&["--border", "compact-double", "-"]).unwrap().border);
    assert_eq!(Some(Border::AsciiRounded), parse(&["--border", "ascii-rounded", "-"]).unwrap().border);
    assert_eq!(Some(Border::AsciiRounded), parse(&["--border", "ascii_rounded", "-"]).unwrap().border);
    assert_eq!(Some(Border::BasicCompact), parse(&["--border", "basic-compact", "-"]).unwrap().border);
    assert_eq!(Some(Border::WithLove), parse(&["--border", "with-love", "-"]).unwrap().border);
    assert_eq!(Some(WidthMode::Header), parse(&["--width", "min", "-"]).unwrap().width);
    assert_eq!(Some(WidthMode::Natural), parse(&["--width", "max", "-"]).unwrap().width);
    assert_eq!(Some(WidthMode::Auto), parse(&["--width", "0", "-"]).unwrap().width);
    assert_eq!(Some(WidthMode::Fixed(80)), parse(&["--width", "80", "-"]).unwrap().width);
    assert!(parse(&["--shuf", "-"]).unwrap().shuffle);
    assert_eq!(["output"], parse(&["-bb=output", "-"]).unwrap().big2.as_slice());
    assert_eq!(["warnings"], parse(&["-bbb=warnings", "-"]).unwrap().big3.as_slice());
    assert_eq!(Args::default(), parse(&[]).unwrap());

    let args = parse(&["--", "-bb"]).unwrap();
    assert_eq!(Some(PathBuf::from("-bb")), args.file);
    assert!(args.big2.is_empty());
  }

  #[test]
  fn test_parse_early_exit_args() {
    assert_eq!(Some(CompletionShell::Zsh), parse(&["--completion", "zsh"]).unwrap().completion);
    assert!(parse(&["--help"]).unwrap().help);
    assert!(parse(&["--version"]).unwrap().version);
  }

  #[test]
  fn test_help() {
    let out = help();

    assert!(out.contains("-bb"));
    assert!(out.contains("Make even BIGGER"));
    assert!(out.contains("-bbb"));
    assert!(out.contains("Make BIGGEST"));
  }

  #[test]
  fn test_parse_rejects_bad_args() {
    assert_eq!(
      "invalid value ';;' for '--delimiter <char>': delimiter must be one printable ASCII character or tab",
      parse(&["--delimiter", ";;"]).unwrap_err()
    );
    assert!(parse(&["--digits", "0"]).is_err());
    assert!(parse(&["--head", "1", "--tail", "1"]).is_err());
    assert!(parse(&["--head", "0"]).is_err());
    assert!(parse(&["--width", "bogus"]).is_err());
    assert_eq!("unexpected argument '--gub' found", parse(&["--gub"]).unwrap_err());
  }
}
