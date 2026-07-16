//! Column color-scale presets and interpolation helpers.

use anstyle::{Color as AnsiColor, RgbColor};

/// Background gradient presets for per-column color scales.
///
/// These render with truecolor ANSI escape sequences. Columns with fewer than
/// two usable distinct values are left unpainted.
#[non_exhaustive]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ColorScale {
  Green,
  Yellow,
  Red,
  Blue,
  GreenWhite,
  YellowWhite,
  RedWhite,
  BlueWhite,
  RedGreen,
  GreenRed,
  GreenYellowRed,
}

//
// color stops
//

const WHITE: Rgb = parse_rgb("#ffffff");
const GREEN: Rgb = parse_rgb("#57bb8a");
const YELLOW: Rgb = parse_rgb("#ffd666");
const RED: Rgb = parse_rgb("#e67c73");
const BLUE: Rgb = parse_rgb("#6c9eeb");

impl ColorScale {
  pub(crate) fn paint(self, t: f64) -> String {
    let bg = self.interpolate(t.clamp(0.0, 1.0));
    let fg = bg.contrast();
    anstyle::Style::new()
      .fg_color(Some(AnsiColor::Rgb(RgbColor(fg.0, fg.1, fg.2))))
      .bg_color(Some(AnsiColor::Rgb(RgbColor(bg.0, bg.1, bg.2))))
      .render()
      .to_string()
  }

  // interpolate t between stops
  fn interpolate(self, t: f64) -> Rgb {
    match self.stops() {
      Stops::Two(a, b) => lerp_rgb(a, b, t),
      Stops::Three(a, b, _) if t < 0.5 => lerp_rgb(a, b, t * 2.0),
      Stops::Three(_, b, c) => lerp_rgb(b, c, (t - 0.5) * 2.0),
    }
  }

  // enum => stops
  fn stops(self) -> Stops {
    use ColorScale::*;
    match self {
      Blue => Stops::Two(WHITE, BLUE),
      BlueWhite => Stops::Two(BLUE, WHITE),
      Green => Stops::Two(WHITE, GREEN),
      GreenRed => Stops::Three(GREEN, WHITE, RED),
      GreenWhite => Stops::Two(GREEN, WHITE),
      GreenYellowRed => Stops::Three(GREEN, YELLOW, RED),
      Red => Stops::Two(WHITE, RED),
      RedGreen => Stops::Three(RED, WHITE, GREEN),
      RedWhite => Stops::Two(RED, WHITE),
      Yellow => Stops::Two(WHITE, YELLOW),
      YellowWhite => Stops::Two(YELLOW, WHITE),
    }
  }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Stops {
  Two(Rgb, Rgb),
  Three(Rgb, Rgb, Rgb),
}

//
// real simple rgb struct
//

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct Rgb(u8, u8, u8);

impl Rgb {
  fn contrast(self) -> Self {
    if self.luma() < 140.0 { Self(255, 255, 255) } else { Self(0, 0, 0) }
  }

  fn luma(self) -> f64 {
    (0.299 * self.0 as f64) + (0.587 * self.1 as f64) + (0.114 * self.2 as f64)
  }
}

fn lerp_rgb(a: Rgb, b: Rgb, t: f64) -> Rgb {
  Rgb(lerp(a.0, b.0, t), lerp(a.1, b.1, t), lerp(a.2, b.2, t))
}

fn lerp(a: u8, b: u8, t: f64) -> u8 {
  (a as f64 + (b as f64 - a as f64) * t).round() as u8
}

// hex => rgb
const fn parse_rgb(hex: &str) -> Rgb {
  let bytes = hex.as_bytes();
  assert!(bytes.len() == 7 && bytes[0] == b'#', "expected #rrggbb");
  Rgb(
    (hex_nibble(bytes[1]) << 4) | hex_nibble(bytes[2]),
    (hex_nibble(bytes[3]) << 4) | hex_nibble(bytes[4]),
    (hex_nibble(bytes[5]) << 4) | hex_nibble(bytes[6]),
  )
}

// helper for hex => rgb
const fn hex_nibble(byte: u8) -> u8 {
  match byte {
    b'0'..=b'9' => byte - b'0',
    b'a'..=b'f' => byte - b'a' + 10,
    b'A'..=b'F' => byte - b'A' + 10,
    _ => panic!("invalid hex digit"),
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_color_scale_paint_is_ansi() {
    let ansi = ColorScale::RedGreen.paint(0.5);
    assert!(ansi.starts_with('\x1b'));
  }

  #[test]
  fn test_color_scale_interpolate_anchors() {
    assert_eq!(RED, ColorScale::RedGreen.interpolate(0.0));
    assert_eq!(WHITE, ColorScale::RedGreen.interpolate(0.5));
    assert_eq!(GREEN, ColorScale::RedGreen.interpolate(1.0));
    assert_eq!(GREEN, ColorScale::Green.interpolate(1.0));
  }
}
