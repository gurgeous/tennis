//! Resolved render-time settings.

use std::io;

use anstyle::RgbColor;

use super::{
  color_scale::ColorScale,
  options::{Border, ColorMode, ColumnBig, ThemeMode},
};
use crate::util::read_bool_env;

//
// resolved options, including defaults and no more Auto
//

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ResolvedOptions {
  pub bigs: Vec<(String, ColumnBig)>,
  pub border: Border,
  pub color: bool,
  pub color_scales: Vec<(String, ColorScale)>,
  pub digits: usize,
  pub footer: Option<String>,
  pub row_numbers: bool,
  pub termbg: Option<RgbColor>,
  pub theme: ResolvedTheme,
  pub title: Option<String>,
  pub vanilla: bool,
  pub width: ResolvedWidth,
  pub zebra: bool,
}

impl ResolvedOptions {
  //
  // column option lookup
  //

  pub fn column_big(&self, name: &str) -> ColumnBig {
    self.bigs.iter().rev().find(|(n, _)| matches_header(n, name)).map(|(_, big)| *big).unwrap_or(ColumnBig::Normal)
  }

  pub fn color_scale(&self, name: &str) -> Option<ColorScale> {
    self.color_scales.iter().rev().find(|(n, _)| matches_header(n, name)).map(|(_, scale)| *scale)
  }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ResolvedTheme {
  Dark,
  Light,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ResolvedWidth {
  Fixed(usize),
  Header,
  Natural,
}

//
// helpers
//

fn matches_header(name: &str, header: &str) -> bool {
  name.eq_ignore_ascii_case(header)
}

// resolve `color` arg to either ON or OFF, considering FORCE_COLOR and NO_COLOR
pub(super) fn resolve_color(color: Option<ColorMode>) -> bool {
  let cc = color_choice_with_env(color, read_bool_env("FORCE_COLOR"), read_bool_env("NO_COLOR"));
  let autostream = anstream::AutoStream::new(io::stdout(), cc);
  let current = autostream.current_choice();
  let resolved = current != anstream::ColorChoice::Never;
  crate::verbose::log(format_args!(
    "Resolved.resolve_color requested={color:?} FORCE_COLOR={} NO_COLOR={} => {resolved:?}",
    read_bool_env("FORCE_COLOR"),
    read_bool_env("NO_COLOR")
  ));
  resolved
}

// Resolve our `color` to anstream auto/never/always. Note that both None and
// Auto honor the env variables, but None biases toward turning color on (as
// opposed to Auto). Tennis is all about color, that's like the whole purpose of
// the app. Don't turn it off lightly.
//
fn color_choice_with_env(color: Option<ColorMode>, force_color: bool, no_color: bool) -> anstream::ColorChoice {
  match color {
    Some(ColorMode::On) => anstream::ColorChoice::Always,
    Some(ColorMode::Off) => anstream::ColorChoice::Never,
    None | Some(ColorMode::Auto) => {
      if force_color {
        // env wins with none/auto
        anstream::ColorChoice::Always
      } else if no_color {
        // env wins with none/auto
        anstream::ColorChoice::Never
      } else if color.is_none() {
        // None, turn on. We love color!
        anstream::ColorChoice::Always
      } else {
        // Auto, this looks at stdout tty and stuff
        anstream::ColorChoice::Auto
      }
    }
  }
}

pub(super) fn resolve_theme(color: bool, requested: ThemeMode) -> (ResolvedTheme, Option<RgbColor>) {
  // Never run terminal theme detection when color is off; it can hang under
  // process managers and does not matter when ANSI will be stripped.
  let resolved = match (color, requested) {
    (false, _) => (ResolvedTheme::Dark, None),
    (true, ThemeMode::Auto) => terminal_theme(),
    (true, ThemeMode::Dark) => (ResolvedTheme::Dark, None),
    (true, ThemeMode::Light) => (ResolvedTheme::Light, None),
  };
  crate::verbose::log(format_args!("Resolved.resolve_theme color={color:?} requested={requested:?} => {resolved:?}"));
  resolved
}

fn terminal_theme() -> (ResolvedTheme, Option<RgbColor>) {
  #[cfg(not(test))]
  {
    use std::time::Duration;

    let mut options = terminal_colorsaurus::QueryOptions::default();
    options.timeout = Duration::from_millis(200);
    crate::verbose::log(format_args!("Resolved.colorsaurus() start"));
    let result = terminal_colorsaurus::color_palette(options);
    crate::verbose::log(format_args!("Resolved.colorsaurus() => {result:?}"));
    match result {
      Ok(palette) => {
        let theme = match palette.theme_mode() {
          terminal_colorsaurus::ThemeMode::Dark => ResolvedTheme::Dark,
          terminal_colorsaurus::ThemeMode::Light => ResolvedTheme::Light,
        };
        (theme, Some(palette.background.into()))
      }
      Err(_) => (ResolvedTheme::Dark, None),
    }
  }

  #[cfg(test)]
  {
    THEME_PROBE_COUNT.with(|count| count.set(count.get() + 1));
    // Simulate successful dark-background detection without probing the terminal.
    (ResolvedTheme::Dark, Some(RgbColor(0, 0, 0)))
  }
}

pub(super) fn terminal_width() -> usize {
  terminal_size::terminal_size().map_or(80, |(width, _)| width.0 as usize)
}

#[cfg(test)]
std::thread_local! {
  static THEME_PROBE_COUNT: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::{RenderOptions, WidthMode};

  fn reset_theme_probe_count() {
    THEME_PROBE_COUNT.with(|count| count.set(0));
  }

  fn theme_probe_count() -> usize {
    THEME_PROBE_COUNT.with(std::cell::Cell::get)
  }

  #[test]
  fn test_resolved_converts_auto_width_to_fixed_width() {
    let options = RenderOptions {
      color: Some(ColorMode::On),
      theme: ThemeMode::Dark,
      width: WidthMode::Auto,
      ..RenderOptions::default()
    };

    let resolved = options.resolve();
    assert!(matches!(resolved.width, ResolvedWidth::Fixed(_)));
  }

  #[test]
  fn test_resolved_theme_dark() {
    let options = RenderOptions { color: Some(ColorMode::On), theme: ThemeMode::Dark, ..RenderOptions::default() };
    let resolved = options.resolve();
    assert_eq!(ResolvedTheme::Dark, resolved.theme);
    assert_eq!(None, resolved.termbg);
  }

  #[test]
  fn test_resolved_theme_light() {
    let options = RenderOptions { color: Some(ColorMode::On), theme: ThemeMode::Light, ..RenderOptions::default() };
    let resolved = options.resolve();
    assert_eq!(ResolvedTheme::Light, resolved.theme);
    assert_eq!(None, resolved.termbg);
  }

  #[test]
  fn test_resolved_uses_dark_when_color_is_off() {
    reset_theme_probe_count();
    let options = RenderOptions { color: Some(ColorMode::Off), theme: ThemeMode::Auto, ..RenderOptions::default() };
    let resolved = options.resolve();

    assert!(!resolved.color);
    assert_eq!(ResolvedTheme::Dark, resolved.theme);
    assert_eq!(None, resolved.termbg);
    assert_eq!(0, theme_probe_count());
  }

  #[test]
  fn test_resolved_probes_when_color_is_on_and_theme_is_auto() {
    reset_theme_probe_count();
    let options = RenderOptions { color: Some(ColorMode::On), theme: ThemeMode::Auto, ..RenderOptions::default() };
    let resolved = options.resolve();

    assert!(resolved.color);
    assert_eq!(ResolvedTheme::Dark, resolved.theme);
    assert!(!resolved.zebra);
    assert_eq!(Some(RgbColor(0, 0, 0)), resolved.termbg);
    assert_eq!(1, theme_probe_count());
  }

  #[test]
  fn test_color_choice_with_env() {
    assert_eq!(
      anstream::ColorChoice::Always,
      color_choice_with_env(None, true, false),
      "FORCE_COLOR should force default color on"
    );
    assert_eq!(
      anstream::ColorChoice::Never,
      color_choice_with_env(None, false, true),
      "NO_COLOR should disable default color"
    );
    assert_eq!(
      anstream::ColorChoice::Always,
      color_choice_with_env(Some(ColorMode::Auto), true, true),
      "FORCE_COLOR should win over NO_COLOR for auto"
    );
    assert_eq!(
      anstream::ColorChoice::Never,
      color_choice_with_env(Some(ColorMode::Off), true, false),
      "explicit off should stay off"
    );
  }
}
