//! Final table rendering middleware.

use std::io;

use unicode_width::UnicodeWidthStr;

use crate::{
  border::{BorderDraw, BorderRule},
  column::Align,
  context::Context,
  theme::{BOLD, RESET},
};

// Middleware entry point.
pub(crate) fn run(ctx: &mut Context<'_>) -> io::Result<()> {
  Render::new(ctx).run()
}

const PLACEHOLDER: &str = "—";

struct Render<'w, 'ctx> {
  ctx: &'ctx mut Context<'w>,
  buf: String,
  row_style: String,
  nice: Vec<usize>,
}

impl<'w, 'ctx> Render<'w, 'ctx> {
  // Build one render pass around a fresh Context.
  fn new(ctx: &'ctx mut Context<'w>) -> Self {
    let nice = ctx.columns.iter().map(|column| column.nice).collect();
    Self { ctx, buf: String::new(), row_style: String::new(), nice }
  }

  // main event
  fn run(mut self) -> io::Result<()> {
    if self.ctx.ncols() == 0 {
      return self.empty_table();
    }

    let has_title = self.ctx.options.title.is_some();
    let has_footer = self.ctx.options.footer.is_some();

    // top rule
    let top = if has_title || has_footer { self.ctx.border.top.span() } else { self.ctx.border.top.clone() };
    self.rule(&top)?;

    // title and title rule below
    if let Some(title) = self.ctx.options.title.clone() {
      let code = self.ctx.paint.title.clone();
      self.text_row(&code, &title)?;
      let rule = self.ctx.border.top.title_rule(&self.ctx.border.header);
      self.rule(&rule)?;
    }

    // headers and header rule below
    self.header_row()?;
    let header = self.ctx.border.header.clone();
    self.rule(&header)?;

    // rows
    let row_rule = rendered_rule(&self.ctx.theme.chrome, &self.ctx.border, &self.ctx.border.row, &self.nice);
    for index in 0..self.ctx.nrows() {
      self.body_row(index)?;
      if index + 1 < self.ctx.nrows()
        && let Some(rule) = &row_rule
      {
        self.ctx.writer.write_all(rule.as_bytes())?;
      }
    }

    // footer
    if let Some(footer) = self.ctx.options.footer.clone() {
      let above =
        if matches!(self.ctx.border.row, BorderRule::None) { &self.ctx.border.header } else { &self.ctx.border.row };
      let footer_top = above.footer_rule(&self.ctx.border.bottom);
      self.rule(&footer_top)?;
      let code = self.ctx.paint.footer.clone();
      self.text_row(&code, &footer)?;
    }

    // bottom rule
    let bottom = if has_footer { self.ctx.border.bottom.span() } else { self.ctx.border.bottom.clone() };
    self.rule(&bottom)?;
    Ok(())
  }

  //
  // empty table
  //

  fn empty_table(&mut self) -> io::Result<()> {
    let title = self.ctx.options.title.clone().unwrap_or_else(|| "empty table".to_owned());
    let body = "no data";
    let width = title.width().max(body.width());
    let widths = [width];
    let top = self.ctx.border.top.clone();
    write_rule(self.ctx.writer, &self.ctx.theme.chrome, &self.ctx.border, &top, &widths)?;
    let code = self.ctx.theme.cell.clone();
    self.centered_row(&title, width, &code, false, true)?;
    let header = self.ctx.border.header.clone();
    write_rule(self.ctx.writer, &self.ctx.theme.chrome, &self.ctx.border, &header, &widths)?;
    self.centered_row(body, width, &code, false, true)?;
    let bottom = self.ctx.border.bottom.clone();
    write_rule(self.ctx.writer, &self.ctx.theme.chrome, &self.ctx.border, &bottom, &widths)
  }

  //
  // header row
  //

  fn header_row(&mut self) -> io::Result<()> {
    push_chrome(&mut self.buf, &self.row_style, &self.ctx.left, false);
    for index in 0..self.ctx.ncols() {
      let name = self.ctx.columns[index].name.clone();
      let nice = self.ctx.columns[index].nice;
      let code = self.ctx.paint.headers.get(index).map(String::as_str).unwrap_or("").to_owned();
      self.header_cell(&name, index, nice, &code);
    }
    self.eol()
  }

  fn header_cell(&mut self, text: &str, col: usize, width: usize, code: &str) {
    self.buf.push(' ');
    let paint = CellPaint { code, row_style: &self.row_style, bold: true };
    fill_cell(&mut self.buf, text, width, Align::Left, &paint, None);
    self.buf.push(' ');
    self.end_cell(col, false);
  }

  //
  // body row
  //

  fn body_row(&mut self, index: usize) -> io::Result<()> {
    self.body_start(index);
    push_chrome(&mut self.buf, &self.row_style, &self.ctx.left, true);

    for column_index in 0..self.ctx.ncols() {
      self.body_cell(index, column_index);
    }
    self.eol()
  }

  // Start one body row, including zebra style if any.
  fn body_start(&mut self, index: usize) {
    if let Some(style) = self.ctx.paint.rows.get(index).filter(|style| !style.is_empty()) {
      self.row_style.push_str(style);
    } else {
      self.row_style.push_str(RESET);
    }
    self.buf.push_str(&self.row_style);
  }

  fn body_cell(&mut self, row: usize, col: usize) {
    let column = &self.ctx.columns[col];
    let align = column.align();
    let width = column.nice;
    let text = &self.ctx.grid.rows[row][col];

    // Empty cells render as placeholders and use chrome paint.
    let empty = text.is_empty();
    let display_text = if empty { PLACEHOLDER } else { text.as_str() };
    let code = if empty {
      self.ctx.theme.chrome.as_str()
    } else {
      self
        .ctx
        .paint
        .cells
        .get(&(row, col))
        .or_else(|| self.ctx.paint.columns.get(col).filter(|c| !c.is_empty()))
        .map_or(self.ctx.theme.cell.as_str(), String::as_str)
    };
    let link =
      if self.ctx.options.hyperlinks && !empty { self.ctx.links.get(&(row, col)).map(String::as_str) } else { None };
    self.buf.push(' ');
    let paint = CellPaint { code, row_style: &self.row_style, bold: false };
    fill_cell(&mut self.buf, display_text, width, align, &paint, link);
    self.buf.push(' ');
    self.end_cell(col, !self.row_style.is_empty());
  }

  //
  // title/footer/etc
  //

  // Render a centered title or footer row.
  fn text_row(&mut self, code: &str, text: &str) -> io::Result<()> {
    let width = content_width(&self.nice, &self.ctx.border).saturating_sub(2);
    self.centered_row(text, width, code, true, false)
  }

  fn centered_row(&mut self, text: &str, width: usize, code: &str, bold: bool, restore: bool) -> io::Result<()> {
    push_chrome(&mut self.buf, &self.row_style, &self.ctx.left, restore);
    self.buf.push(' ');
    let paint = CellPaint { code, row_style: &self.row_style, bold };
    fill_cell(&mut self.buf, text, width, Align::Center, &paint, None);
    self.buf.push(' ');
    push_chrome(&mut self.buf, &self.row_style, &self.ctx.right, restore);
    self.eol()
  }

  //
  // helpers
  //

  // Write one border rule line.
  fn rule(&mut self, rule: &BorderRule) -> io::Result<()> {
    write_rule(self.ctx.writer, &self.ctx.theme.chrome, &self.ctx.border, rule, &self.nice)
  }

  // Close one cell with mid or right chrome.
  fn end_cell(&mut self, col: usize, restore: bool) {
    let sep = if col + 1 == self.ctx.columns.len() { &self.ctx.right } else { &self.ctx.mid };
    push_chrome(&mut self.buf, &self.row_style, sep, restore);
  }

  // flush the current buf and write a newline
  fn eol(&mut self) -> io::Result<()> {
    self.buf.push_str(RESET);
    self.buf.push('\n');
    self.ctx.writer.write_all(self.buf.as_bytes())?;
    self.buf.clear();
    self.row_style.clear();
    Ok(())
  }
}

//
// standalone helpers
//

// Write one rendered rule if this border uses one.
fn write_rule(
  writer: &mut dyn io::Write,
  chrome: &str,
  border: &BorderDraw,
  rule: &BorderRule,
  widths: &[usize],
) -> io::Result<()> {
  if let Some(rule) = rendered_rule(chrome, border, rule, widths) {
    writer.write_all(rule.as_bytes())?;
  }
  Ok(())
}

// Build one fully rendered border rule line.
fn rendered_rule(chrome: &str, border: &BorderDraw, rule: &BorderRule, widths: &[usize]) -> Option<String> {
  let mut out = String::new();
  match rule {
    BorderRule::None => return None,

    // Continuous rules span the full inner table width.
    BorderRule::Continuous { left, fill, right } => {
      out.push_str(chrome);
      out.push_str(left);
      for _ in 0..content_width(widths, border) {
        out.push_str(fill);
      }
      out.push_str(right);
    }

    // Segmented rules track per-column widths, including cell padding.
    BorderRule::Segmented { left, fill, mid, right } => {
      debug_assert!(!widths.is_empty());
      out.push_str(chrome);
      for (index, width) in widths.iter().enumerate() {
        out.push_str(if index == 0 { left } else { mid });
        for _ in 0..width + 2 {
          out.push_str(fill);
        }
      }
      out.push_str(right);
    }
  }
  out.push_str(RESET);
  out.push('\n');
  Some(out)
}

// Body width including cell padding and inner separators.
fn content_width(widths: &[usize], border: &BorderDraw) -> usize {
  widths.iter().sum::<usize>() + 2 * widths.len() + border.mid.width() * widths.len().saturating_sub(1)
}

// Write one styled border fragment, then restore row paint if needed.
fn push_chrome(out: &mut String, row_style: &str, styled_value: &str, restore_row_style: bool) {
  out.push_str(styled_value);
  if restore_row_style {
    if row_style.is_empty() {
      out.push_str(RESET);
    } else {
      out.push_str(row_style);
    }
  }
}

// ANSI paint for one cell.
struct CellPaint<'a> {
  code: &'a str,
  row_style: &'a str,
  bold: bool,
}

// Render one padded cell, truncating only when needed.
fn fill_cell(out: &mut String, text: &str, width: usize, align: Align, paint: &CellPaint<'_>, link: Option<&str>) {
  let CellPaint { code, row_style, bold } = *paint;
  if bold {
    out.push_str(BOLD);
  }
  out.push_str(code);

  // Most cells fit. When they do not, truncate() returns exactly `width`.
  let display_width = crate::util::display_width(text);
  if display_width > width {
    push_text(out, &crate::util::truncate(text, width), link);
  } else {
    let pad = width - display_width;
    let (lpad, rpad) = match align {
      Align::Left => (0, pad),
      Align::Right => (pad, 0),
      Align::Center => (pad / 2, pad - pad / 2),
    };
    push_spaces(out, lpad);
    push_text(out, text, link);
    push_spaces(out, rpad);
  }

  if bold || row_style.is_empty() {
    out.push_str(RESET);
  }
  out.push_str(row_style);
}

// Write visible text, optionally wrapped in OSC8 hyperlink escapes.
fn push_text(out: &mut String, text: &str, link: Option<&str>) {
  if let Some(link) = link {
    out.push_str("\x1b]8;;");
    out.push_str(link);
    out.push_str("\x1b\\");
    out.push_str(text);
    out.push_str("\x1b]8;;\x1b\\");
  } else {
    out.push_str(text);
  }
}

// Write N spaces with a chunked static buffer.
fn push_spaces(out: &mut String, count: usize) {
  const SPACES: &str = "                                                                ";
  let mut remaining = count;
  while remaining > 0 {
    let take = remaining.min(SPACES.len());
    out.push_str(&SPACES[..take]);
    remaining -= take;
  }
}

//
// tests
//

#[cfg(test)]
mod tests {
  use std::io::{self, Write};

  use super::*;
  use crate::{
    Grid, IntoCells, Table,
    builder::{
      options::ColumnBig,
      types::{Border, ColorMode},
    },
    resolved::{Resolved, ResolvedTheme, ResolvedWidth},
  };

  #[derive(Default)]
  struct LineWriter {
    chunks: Vec<String>,
  }

  impl Write for LineWriter {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
      self.chunks.push(String::from_utf8(buf.to_vec()).unwrap());
      Ok(buf.len())
    }

    fn flush(&mut self) -> io::Result<()> {
      Ok(())
    }
  }

  fn table<H, R>(headers: H, rows: impl IntoIterator<Item = R>) -> Table
  where
    H: IntoCells,
    R: IntoCells,
  {
    let rows = rows.into_iter().map(IntoCells::into_cells).collect();
    Table::builder().load_grid(Grid::new(headers.into_cells(), rows).expect("valid grid")).build().expect("valid table")
  }

  fn configured(mut table: Table, f: impl FnOnce(&mut Resolved)) -> Table {
    f(&mut table.options);

    table
  }

  #[test]
  fn test_render_streams_lines() {
    let table = configured(table(["name"], [["alice"]]), |options| {
      options.color = ColorMode::Off;
      options.width = ResolvedWidth::Fixed(80);
    });
    let mut writer = LineWriter::default();
    table.write_to(&mut writer as &mut dyn Write).unwrap();
    assert!(writer.chunks.len() > 1);
    assert!(writer.chunks.concat().contains("alice"));
  }

  #[test]
  fn test_render_basic() {
    let out = configured(table(["name", "score"], [["alice", "1234"]]), |options| {
      options.border = Border::Basic;
      options.color = ColorMode::Off;
      options.width = ResolvedWidth::Fixed(80);
    })
    .into_text();
    assert!(out.contains("+-------+-------+"));
    assert!(out.contains("| name  | score |"));
    assert!(out.contains("| alice | 1,234 |"));
  }

  #[test]
  fn test_render_colored_rule_has_single_chrome_prefix() {
    let out = configured(table(["a", "b"], [["1", "2"]]), |options| {
      options.border = Border::Basic;
      options.color = ColorMode::On;
      options.theme = ResolvedTheme::Dark;
      options.width = ResolvedWidth::Fixed(80);
    })
    .into_text();
    let top = out.lines().next().unwrap();

    assert_eq!("\x1b[38;5;243m+----+----+\x1b[0m", top);
  }

  #[test]
  fn test_render_placeholder_uses_chrome_paint() {
    let out = configured(table(["name", "score"], [["alice", ""]]), |options| {
      options.color = ColorMode::On;
      options.theme = ResolvedTheme::Dark;
      options.width = ResolvedWidth::Fixed(80);
    })
    .into_text();

    assert!(out.contains("\x1b[38;5;243m—    \x1b[0m"), "{out:?}");
  }

  #[test]
  fn test_render_color_scale_uses_cell_paint() {
    let out = configured(table(["service", "latency_ms"], [["api", "37"], ["worker", "950"]]), |options| {
      options.color = ColorMode::On;
      options.theme = ResolvedTheme::Dark;
      options.width = ResolvedWidth::Fixed(80);
      options.color_scales.push(("latency_ms".to_owned(), crate::ColorScale::GreenRed));
    })
    .into_text();

    assert!(out.contains("\x1b[38;2;"), "{out:?}");
  }

  #[test]
  fn test_render_footer() {
    let out = configured(table(["name"], [["alice"]]), |options| {
      options.color = ColorMode::Off;
      options.width = ResolvedWidth::Fixed(80);
      options.footer = Some("done".into());
    })
    .into_text();
    assert!(out.contains("done"));
  }

  #[test]
  fn test_render_markdown_link_uses_label_when_color_is_off() {
    let out = configured(table(["site"], [["[search](https://google.com)"]]), |options| {
      options.color = ColorMode::Off;
      options.hyperlinks = false;
      options.width = ResolvedWidth::Fixed(80);
    })
    .into_text();

    assert!(out.contains("search"));
    assert!(!out.contains("\x1b]8;;"));
    assert!(!out.contains("[search](https://google.com)"));
  }

  #[test]
  fn test_render_markdown_link_as_osc8_when_color_is_on() {
    let out = configured(table(["site"], [["[search](https://google.com)"]]), |options| {
      options.color = ColorMode::On;
      options.theme = ResolvedTheme::Dark;
      options.width = ResolvedWidth::Fixed(80);
    })
    .into_text();

    assert!(out.contains("\x1b]8;;https://google.com\x1b\\search\x1b]8;;\x1b\\"));
    assert!(!out.contains("[search](https://google.com)"));
  }

  #[test]
  fn test_render_markdown_link_can_disable_hyperlinks() {
    let out = configured(table(["site"], [["[search](https://google.com)"]]), |options| {
      options.color = ColorMode::On;
      options.theme = ResolvedTheme::Dark;
      options.hyperlinks = false;
      options.width = ResolvedWidth::Fixed(80);
    })
    .into_text();

    assert!(out.contains("search"));
    assert!(!out.contains("\x1b]8;;"));
    assert!(!out.contains("[search](https://google.com)"));
  }

  #[test]
  fn test_render_markdown_link_truncates_visible_label() {
    let out = configured(table(["site"], [["[verylonglabel](https://google.com)"]]), |options| {
      options.color = ColorMode::On;
      options.theme = ResolvedTheme::Dark;
      options.width = ResolvedWidth::Fixed(8);
    })
    .into_text();

    assert!(out.contains("\x1b]8;;https://google.com\x1b\\ver…\x1b]8;;\x1b\\"), "{out:?}");
  }

  #[test]
  fn test_render_malformed_markdown_link_stays_raw() {
    let out = configured(table(["site"], [["[search](ftp://example.com)"]]), |options| {
      options.color = ColorMode::On;
      options.theme = ResolvedTheme::Dark;
      options.width = ResolvedWidth::Fixed(80);
    })
    .into_text();

    assert!(out.contains("[search](ftp://example.com)"));
    assert!(!out.contains("\x1b]8;;"));
  }

  #[test]
  fn test_render_title_light_border() {
    let out = configured(table(["a", "b"], [["1", "2"]]), |options| {
      options.border = Border::Light;
      options.color = ColorMode::Off;
      options.title = Some("foo".into());
      options.width = ResolvedWidth::Fixed(80);
    })
    .into_text();
    assert_eq!("   foo   \n─────────\n a    b  \n─────────\n  1    2 \n", out);
  }

  #[test]
  fn test_render_light_border_width_invariant() {
    let out = configured(table(["a", "b"], [["1", "2"], ["3", "4"]]), |options| {
      options.border = Border::Light;
      options.color = ColorMode::Off;
      options.row_numbers = true;
      options.title = Some("foo".into());
      options.footer = Some("done".into());
      options.width = ResolvedWidth::Fixed(80);
    })
    .into_text();
    let widths = out.lines().map(UnicodeWidthStr::width).collect::<Vec<_>>();
    assert!(widths.windows(2).all(|pair| pair[0] == pair[1]), "{widths:?}\n{out}");
  }

  #[test]
  fn test_render_empty() {
    let out =
      configured(table(["name"], [] as [[&str; 1]; 0]), |options| options.width = ResolvedWidth::Fixed(80)).into_text();
    assert!(out.contains("empty table"));
    assert!(out.contains("no data"));
  }

  #[test]
  fn test_render_zero_columns_as_empty() {
    let out = configured(table([] as [&str; 0], [[] as [&str; 0]]), |options| {
      options.width = ResolvedWidth::Fixed(80);
    })
    .into_text();
    assert!(out.contains("empty table"));
    assert!(out.contains("no data"));
  }

  #[test]
  fn test_render_empty_color_resets_chrome() {
    let table = configured(table(["name"], [] as [[&str; 1]; 0]), |options| {
      options.border = Border::Basic;
      options.color = ColorMode::On;
      options.theme = ResolvedTheme::Dark;
      options.width = ResolvedWidth::Fixed(80);
    });
    let first_row = table.into_text().lines().nth(1).unwrap().to_owned();
    assert!(first_row.starts_with("\x1b[38;5;243m|\x1b[0m "));
  }

  #[test]
  fn test_render_row_numbers() {
    let out = configured(table(["name"], [["alice"]]), |options| {
      options.color = ColorMode::Off;
      options.row_numbers = true;
      options.width = ResolvedWidth::Fixed(80);
    })
    .into_text();
    assert!(out.contains("│ #  │ name  │"));
    assert!(out.contains("│  1 │ alice │"));
  }

  #[test]
  fn test_render_row_numbers_multiple_digits() {
    let rows = (0..14).map(|index| [format!("{index:.3}")]).collect::<Vec<_>>();
    let out = configured(table(["carat"], rows), |options| {
      options.color = ColorMode::Off;
      options.row_numbers = true;
      options.width = ResolvedWidth::Fixed(80);
    })
    .into_text();

    assert!(out.contains("│ #  │ carat │"));
    assert!(out.contains("│  1 │"));
    assert!(out.contains("│ 14 │"));
  }

  #[test]
  fn test_render_truncates() {
    let out = configured(table(["name"], [["abcdef"]]), |options| {
      options.color = ColorMode::Off;
      options.width = ResolvedWidth::Fixed(8);
    })
    .into_text();
    assert!(out.contains("…"));
  }

  #[test]
  fn test_render_sanitizes_cell_controls() {
    let out = configured(table(["name"], [["a\tb\nc"]]), |options| {
      options.color = ColorMode::Off;
      options.width = ResolvedWidth::Fixed(80);
    })
    .into_text();
    assert!(out.contains("a b c"));
    assert!(!out.contains("a\tb\nc"));
  }

  #[test]
  fn test_render_fixed_width() {
    let out = configured(
      table(["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbbbbbb", "cccccccccc"], [["x", "y", "z"]]),
      |options| {
        options.color = ColorMode::Off;
        options.width = ResolvedWidth::Fixed(37);
      },
    )
    .into_text();

    assert!(out.contains("aaaaaaa…"), "{out}");
    assert!(!out.contains("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"));
  }

  #[test]
  fn test_render_unicode_cases() {
    let out = configured(
      table(
        ["label", "text", "notes"],
        [
          ["accent", "café noir", "combining acute accent"],
          ["heart", "I ❤️ Rust", "variation selector sequence"],
          ["skin_tone", "thumbs 👍🏽 up", "emoji skin-tone modifier"],
          ["family", "family 👨‍👩‍👧‍👦 test", "ZWJ emoji sequence"],
          ["flag", "go 🇺🇸 now", "regional indicator flag pair"],
        ],
      ),
      |options| {
        options.color = ColorMode::Off;
        options.width = ResolvedWidth::Fixed(40);
      },
    )
    .into_text();

    assert!(out.contains("accent") && out.contains("café noir") && out.contains("combining…"), "{out}");
    assert!(out.contains("heart") && out.contains("I ❤️ Rust") && out.contains("variation…"), "{out}");
    assert!(out.contains("skin_tone") && out.contains("emoji ski…"), "{out}");
    assert!(out.contains("family") && out.contains("ZWJ emoji…"), "{out}");
    assert!(out.contains("flag") && out.contains("go 🇺🇸 now") && out.contains("regional …"), "{out}");
  }

  #[test]
  fn test_render_cjk_cases() {
    let out = configured(
      table(
        ["row", "name", "note"],
        [
          ["1", "香港", "city"],
          ["2", "中西區", "district"],
          ["3", "必列者士街", "street"],
          ["4", "英皇書院同學會小學", "school"],
        ],
      ),
      |options| {
        options.color = ColorMode::Off;
        options.width = ResolvedWidth::Fixed(80);
      },
    )
    .into_text();

    assert!(out.contains("香港"), "{out}");
    assert!(out.contains("英皇書院同學會小學"), "{out}");
  }

  #[test]
  fn test_render_big_columns() {
    let rows = [
      ["0.23", "Ideal", "E", "SI2", "61.5", "55", "326", "3.95", "3.98", "2.43"],
      ["0.24", "Very Good", "J", "VVS2", "62.8", "57", "336", "3.94", "3.96", "2.48"],
    ];
    let headers = ["carat", "cut", "color", "clarity", "depth", "table", "price", "x", "y", "z"];

    let default = configured(table(headers, rows), |options| {
      options.color = ColorMode::Off;
      options.width = ResolvedWidth::Fixed(80);
    })
    .into_text();
    assert!(default.contains("Ide…"), "{default}");
    assert!(!default.contains("Ideal"));

    let big = configured(table(headers, rows), |options| {
      options.color = ColorMode::Off;
      options.width = ResolvedWidth::Fixed(80);
      options.bigs.push(("cut".to_owned(), ColumnBig::Big));
    })
    .into_text();
    assert!(big.contains("Ideal"), "{big}");

    let bigger = configured(table(headers, rows), |options| {
      options.color = ColorMode::Off;
      options.width = ResolvedWidth::Fixed(80);
      options.bigs.push(("cut".to_owned(), ColumnBig::Bigger));
    })
    .into_text();
    assert!(bigger.contains("Ideal"), "{bigger}");

    let biggest = configured(table(headers, rows), |options| {
      options.color = ColorMode::Off;
      options.width = ResolvedWidth::Fixed(80);
      options.bigs.push(("cut".to_owned(), ColumnBig::Biggest));
    })
    .into_text();
    assert!(biggest.contains("Very Good"), "{biggest}");
  }

  #[test]
  fn test_render_diamonds_color_snapshot_shape() {
    let out = configured(
      table(
        ["carat", "cut", "color", "clarity", "depth", "table", "price", "x", "y", "z"],
        [
          ["0.23", "Ideal", "E", "SI2", "61.5", "55", "326", "3.95", "3.98", "2.43"],
          ["0.21", "Premium", "E", "SI1", "59.8", "61", "326", "3.89", "3.84", "2.31"],
          ["0.23", "Good", "E", "VS1", "56.9", "65", "327", "4.05", "4.07", "2.31"],
          ["0.29", "Premium", "I", "VS2", "62.4", "58", "334", "4.2", "4.23", "2.63"],
          ["0.31", "Good", "J", "SI2", "63.3", "58", "335", "4.34", "4.35", "2.75"],
          ["0.24", "Very Good", "J", "VVS2", "62.8", "57", "336", "3.94", "3.96", "2.48"],
          ["0.24", "Very Good", "I", "VVS1", "62.3", "57", "336", "3.95", "3.98", "2.47"],
          ["0.26", "Very Good", "H", "SI1", "61.9", "55", "337", "4.07", "4.11", "2.53"],
          ["0.22", "Fair", "E", "VS2", "", "61", "337", "3.87", "3.78", "2.49"],
          ["0.23", "Very Good", "H", "VS1", "59.4", "61", "338", "4", "4.05", "2.39"],
          ["0.3", "Good", "J", "SI1", "64", "55", "339", "4.25", "4.28", "2.73"],
          ["0.23", "Ideal", "J", "VS1", "62.8", "", "340", "3.93", "3.9", "2.46"],
          ["0.22", "Premium", "F", "SI1", "60.4", "61", "342", "3.88", "3.84", "2.33"],
          ["0.31", "Ideal", "J", "SI2", "62.2", "54", "344", "4.35", "4.37", "2.71"],
        ],
      ),
      |options| {
        options.color = ColorMode::On;
        options.theme = ResolvedTheme::Dark;
        options.title = Some("foo".into());
        options.width = ResolvedWidth::Fixed(80);
      },
    )
    .into_text();

    let first = out.lines().next().unwrap();
    assert!(first.starts_with("\x1b[38;5;243m╭"), "{first:?}");
    assert!(first.ends_with("╮\x1b[0m"), "{first:?}");
    assert!(out.contains("\x1b[1m\x1b[38;5;75m"));
    assert!(out.contains("foo"));
    assert!(out.contains("\x1b[38;5;204m0.230"));
    assert!(out.contains("\x1b[38;5;243m"));
    assert!(out.contains("—"));
    let last = out.lines().last().unwrap();
    assert!(last.contains("╰"));
    assert!(last.contains("╯"));
    assert!(last.contains("┴"));
    assert_eq!(20, out.lines().count());
  }

  #[test]
  fn test_render_zebra() {
    let out = configured(table(["name", "score"], [["alice", "1234"], ["bob", "5678"]]), |options| {
      options.border = Border::Basic;
      options.color = ColorMode::On;
      options.theme = ResolvedTheme::Dark;
      options.zebra = true;
      options.width = ResolvedWidth::Fixed(80);
    })
    .into_text();
    let row = out.lines().find(|line| line.contains("alice")).unwrap();
    let row = row.strip_suffix(RESET).unwrap_or(row);
    assert!(!row.contains(RESET));
    assert!(row.contains("\x1b[48;5;235m"));
  }

  #[test]
  fn test_render_zebra_restores_row_style_after_color_scale() {
    let out = configured(table(["name", "score"], [["alice", "1234"], ["bob", "5678"]]), |options| {
      options.border = Border::Basic;
      options.color = ColorMode::On;
      options.theme = ResolvedTheme::Dark;
      options.zebra = true;
      options.width = ResolvedWidth::Fixed(80);
      options.color_scales.push(("score".to_owned(), crate::ColorScale::GreenRed));
    })
    .into_text();
    let row = out.lines().find(|line| line.contains("alice")).unwrap();
    assert!(row.contains("\x1b[48;2;87;187;138m1,234\x1b[38;5;231m\x1b[48;5;235m"), "{row:?}");
    assert!(row.contains("\x1b[38;2;"), "{row:?}");
  }
}
