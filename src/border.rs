//! Border definitions.

use crate::{builder::types::Border, util::display_width};

//
// entrypoints
//

/// A fully parsed border definition for rendering
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct BorderDraw {
  pub(crate) top: BorderRule,
  pub(crate) header: BorderRule,
  pub(crate) row: BorderRule,
  pub(crate) bottom: BorderRule,
  pub(crate) left: String,
  pub(crate) mid: String,
  pub(crate) right: String,
}

impl BorderDraw {
  pub(crate) fn chrome_width(&self, ncols: usize) -> usize {
    if ncols == 0 {
      return 0;
    }
    display_width(&self.left)
      + display_width(&self.right)
      + display_width(&self.mid) * ncols.saturating_sub(1)
      + 2 * ncols
  }
}

/// Definition for a "rule", which is a horizontal line
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) enum BorderRule {
  None,
  Continuous { left: String, fill: String, right: String },
  Segmented { left: String, fill: String, mid: String, right: String },
}

impl BorderRule {
  pub(crate) fn title_rule(&self, header: &Self) -> Self {
    match (self, header) {
      (BorderRule::Segmented { mid, .. }, BorderRule::Segmented { left, fill, right, .. }) => {
        BorderRule::Segmented { left: left.clone(), fill: fill.clone(), mid: mid.clone(), right: right.clone() }
      }
      _ => header.clone(),
    }
  }

  pub(crate) fn span(&self) -> Self {
    match self {
      BorderRule::None => BorderRule::None,
      BorderRule::Continuous { .. } => self.clone(),
      BorderRule::Segmented { left, fill, right, .. } => {
        BorderRule::Continuous { left: left.clone(), fill: fill.clone(), right: right.clone() }
      }
    }
  }

  pub(crate) fn footer_rule(&self, bottom: &Self) -> Self {
    match (self, bottom) {
      (BorderRule::Segmented { left, fill, right, .. }, BorderRule::Segmented { mid, .. }) => {
        BorderRule::Segmented { left: left.clone(), fill: fill.clone(), mid: mid.clone(), right: right.clone() }
      }
      _ => self.clone(),
    }
  }
}

//
// Specimens use 3×3 cell grids with markers A-I:
//
// 0: ╭─┬─┬─╮  ← top rule
// 1: │A│B│C│  ← header
// 2: ├─┼─┼─┤  ← header separator
// 3: │D│E│F│  ← first data row
// 4: ├─┼─┼─┤  ← row separator
// 5: │G│H│I│  ← second data row
// 6: ╰─┴─┴─╯  ← bottom rule
//

/// Lookup a Border so we can draw it
pub(crate) fn get_border(name: Border) -> BorderDraw {
  #[rustfmt::skip]
  let specimen = match name {
    Border::AsciiRounded  => ".-----.\n|A|B|C|\n|D|E|F|\n|G|H|I|\n'-----'",
    Border::Basic         => "+-+-+-+\n|A|B|C|\n+-+-+-+\n|D|E|F|\n+-+-+-+\n|G|H|I|\n+-+-+-+",
    Border::BasicCompact  => "+-+-+-+\n|A|B|C|\n|D|E|F|\n|G|H|I|\n+-+-+-+",
    Border::Compact       => "─┬─┬─\nA│B│C\n─┼─┼─\nD│E│F\nG│H│I\n─┴─┴─",
    Border::CompactDouble => "═╦═╦═\nA║B║C\n═╬═╬═\nD║E║F\nG║H║I\n═╩═╩═",
    Border::Dots          => ".......\n:A:B:C:\n:D:E:F:\n:G:H:I:\n:.:.:.:",
    Border::Double        => "╔═╦═╦═╗\n║A║B║C║\n╠═╬═╬═╣\n║D║E║F║\n║G║H║I║\n╚═╩═╩═╝",
    Border::Heavy         => "┏━┳━┳━┓\n┃A┃B┃C┃\n┣━╋━╋━┫\n┃D┃E┃F┃\n┃G┃H┃I┃\n┗━┻━┻━┛",
    Border::Light         => "A B C\n─────\nD E F\nG H I",
    Border::Markdown      => "|A|B|C|\n|-|-|-|\n|D|E|F|\n|G|H|I|",
    Border::None          => "A B C\nD E F\nG H I",
    Border::Psql          => "A|B|C\n-+-+-\nD|E|F\nG|H|I",
    Border::Reinforced    => "┏─┬─┬─┓\n│A│B│C│\n│D│E│F│\n│G│H│I│\n┗─┴─┴─┛",
    Border::Restructured  => "= = =\nA B C\n= = =\nD E F\nG H I\n= = =",
    Border::Rounded       => "╭─┬─┬─╮\n│A│B│C│\n├─┼─┼─┤\n│D│E│F│\n│G│H│I│\n╰─┴─┴─╯",
    Border::Single        => "┌─┬─┬─┐\n│A│B│C│\n├─┼─┼─┤\n│D│E│F│\n│G│H│I│\n└─┴─┴─┘",
    Border::Thin          => "┌─┬─┬─┐\n│A│B│C│\n├─┼─┼─┤\n│D│E│F│\n├─┼─┼─┤\n│G│H│I│\n└─┴─┴─┘",
    Border::WithLove      => "❤❤❤❤❤\nA❤B❤C\n❤❤❤❤❤\nD❤E❤F\nG❤H❤I\n❤❤❤❤❤",
  };
  parse_specimen(specimen)
}

//
// internal
//

fn parse_specimen(input: &str) -> BorderDraw {
  let lines = input.lines().collect::<Vec<_>>();

  // find lines in there
  let head = find_line(&lines, 'A');
  let one = find_line(&lines, 'D');
  let two = find_line(&lines, 'G');

  // parse header
  let header = lines[head];
  let a = glyph_index(header, 'A');
  let left = glyph_range(header, 0, a);
  let b = glyph_index(header, 'B');
  let mid = glyph_range(header, a + 1, b);
  let c = glyph_index(header, 'C');
  let right = glyph_range(header, c + 1, header.chars().count());

  BorderDraw {
    top: if head > 0 { parse_rule(lines[0], &left, &mid, &right) } else { BorderRule::None },
    header: if one > head + 1 { parse_rule(lines[head + 1], &left, &mid, &right) } else { BorderRule::None },
    row: if two > one + 1 { parse_rule(lines[one + 1], &left, &mid, &right) } else { BorderRule::None },
    bottom: if two + 1 < lines.len() { parse_rule(lines[two + 1], &left, &mid, &right) } else { BorderRule::None },
    left,
    mid,
    right,
  }
}

fn parse_rule(line: &str, left: &str, mid: &str, right: &str) -> BorderRule {
  let leftg = left.chars().count();
  let fill = glyph_range(line, leftg, leftg + 1);
  let midg = mid.chars().count();

  // positions:  [left][fill][mid][fill][mid]...
  // index:       0    l    l+1  l+1+m ...
  let mid1_start = leftg + 1;
  let mid2_start = leftg + 2 + midg;
  let sep1 = glyph_range(line, mid1_start, mid1_start + midg);
  let sep2 = glyph_range(line, mid2_start, mid2_start + midg);

  let nglyphs = line.chars().count();
  let rightg = right.chars().count();

  let left = glyph_range(line, 0, leftg);
  let right = glyph_range(line, nglyphs - rightg, nglyphs);
  if fill == sep1 && fill == sep2 {
    BorderRule::Continuous { left, fill, right }
  } else {
    BorderRule::Segmented { left, fill, mid: sep1, right }
  }
}

fn find_line(lines: &[&str], marker: char) -> usize {
  lines.iter().position(|line| line.contains(marker)).expect("border specimen contains marker")
}

fn glyph_index(line: &str, marker: char) -> usize {
  line.chars().position(|ch| ch == marker).expect("border specimen contains cell marker")
}

fn glyph_range(line: &str, start: usize, end: usize) -> String {
  line.chars().skip(start).take(end - start).collect()
}

#[cfg(test)]
mod tests {
  use super::*;

  const BORDERS: &[Border] = &[
    Border::AsciiRounded,
    Border::Basic,
    Border::BasicCompact,
    Border::Compact,
    Border::CompactDouble,
    Border::Dots,
    Border::Double,
    Border::Heavy,
    Border::Light,
    Border::Markdown,
    Border::None,
    Border::Psql,
    Border::Reinforced,
    Border::Restructured,
    Border::Rounded,
    Border::Single,
    Border::Thin,
    Border::WithLove,
  ];

  #[test]
  fn test_all_borders_parse() {
    for border in BORDERS {
      let draw = get_border(*border);
      assert_valid_border(*border, &draw);
    }
  }

  #[test]
  fn test_get_border() {
    let basic = get_border(Border::Basic);
    assert_eq!("|", basic.left);
    assert_eq!("|", basic.mid);
    assert_eq!("|", basic.right);

    let rounded = get_border(Border::Rounded);
    assert_eq!("│", rounded.left);
    assert!(matches!(rounded.top, BorderRule::Segmented { .. }));

    let light = get_border(Border::Light);
    assert_eq!("", light.left);
    assert_eq!(" ", light.mid);
    assert_eq!("", light.right);
    assert_eq!(BorderRule::None, light.top);
    assert_eq!(BorderRule::None, light.bottom);

    let thin = get_border(Border::Thin);
    assert!(matches!(thin.header, BorderRule::Segmented { .. }));
    assert!(matches!(thin.row, BorderRule::Segmented { .. }));

    let dots = get_border(Border::Dots);
    assert!(matches!(dots.top, BorderRule::Continuous { .. }));
    assert!(matches!(dots.bottom, BorderRule::Segmented { .. }));
  }

  #[test]
  fn test_span_rule_title_rule_footer_rule() {
    let rounded = get_border(Border::Rounded);
    assert!(matches!(rounded.top.span(), BorderRule::Continuous { .. }));
    assert!(matches!(rounded.top.title_rule(&rounded.header), BorderRule::Segmented { .. }));

    let thin = get_border(Border::Thin);
    assert_eq!(
      BorderRule::Segmented {
        left: "├".to_owned(), fill: "─".to_owned(), mid: "┴".to_owned(), right: "┤".to_owned()
      },
      thin.row.footer_rule(&thin.bottom)
    );
  }

  fn assert_valid_border(border: Border, draw: &BorderDraw) {
    assert_eq!(draw.left.chars().count(), draw.right.chars().count(), "{border:?}");
    assert_valid_rule(border, &draw.top);
    assert_valid_rule(border, &draw.header);
    assert_valid_rule(border, &draw.row);
    assert_valid_rule(border, &draw.bottom);
  }

  fn assert_valid_rule(border: Border, rule: &BorderRule) {
    match rule {
      BorderRule::None => {}
      BorderRule::Continuous { fill, .. } => assert!(!fill.is_empty(), "{border:?}"),
      BorderRule::Segmented { fill, mid, .. } => {
        assert!(!fill.is_empty(), "{border:?}");
        assert!(!mid.is_empty(), "{border:?}");
      }
    }
  }
}
