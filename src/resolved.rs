//! Resolved render-time settings.

use std::io;

use crate::{
  ColorScale,
  builder::{
    Options,
    options::ColumnBig,
    types::{Border, ColorMode, ThemeMode, WidthMode},
  },
  util::read_bool_env,
};

//
// resolved options, including defaults and no more Auto
//

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct Resolved {
  pub(crate) bigs: Vec<(String, ColumnBig)>,
  pub(crate) border: Border,
  pub(crate) color: ColorMode,
  pub(crate) color_scales: Vec<(String, ColorScale)>,
  pub(crate) digits: usize,
  pub(crate) footer: Option<String>,
  pub(crate) hyperlinks: bool,
  pub(crate) row_numbers: bool,
  pub(crate) theme: ResolvedTheme,
  pub(crate) title: Option<String>,
  pub(crate) titleize: bool,
  pub(crate) vanilla: bool,
  pub(crate) width: ResolvedWidth,
  pub(crate) zebra: bool,
}

impl Resolved {
  pub(crate) fn new(options: Options) -> Self {
    let color = resolve_color(options.color);
    let mut this = Self {
      bigs: options.bigs,
      border: options.border.unwrap_or(Border::Rounded),
      color,
      color_scales: options.color_scales,
      digits: options.digits.unwrap_or(3),
      footer: options.footer,
      hyperlinks: options.hyperlinks.unwrap_or(true),
      row_numbers: options.row_numbers.unwrap_or(false),
      theme: resolve_theme(color, options.theme),
      title: options.title,
      titleize: options.titleize.unwrap_or(false),
      vanilla: options.vanilla.unwrap_or(false),
      width: ResolvedWidth::Natural,
      zebra: options.zebra.unwrap_or(false),
    };
    this.width = match options.width.unwrap_or(WidthMode::Auto) {
      WidthMode::Auto => ResolvedWidth::Fixed(terminal_width()),
      WidthMode::Fixed(width) => ResolvedWidth::Fixed(width),
      WidthMode::Header => ResolvedWidth::Header,
      WidthMode::Natural => ResolvedWidth::Natural,
    };
    this
  }

  //
  // column option lookup
  //

  pub(crate) fn column_big(&self, raw_name: &str) -> ColumnBig {
    self.bigs.iter().rev().find(|(n, _)| matches_header(n, raw_name)).map(|(_, big)| *big).unwrap_or(ColumnBig::Normal)
  }

  pub(crate) fn color_scale(&self, raw_name: &str) -> Option<ColorScale> {
    self.color_scales.iter().rev().find(|(n, _)| matches_header(n, raw_name)).map(|(_, scale)| *scale)
  }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum ResolvedTheme {
  Dark,
  Light,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum ResolvedWidth {
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
fn resolve_color(color: Option<ColorMode>) -> ColorMode {
  let cc = color_choice_with_env(color, read_bool_env("FORCE_COLOR"), read_bool_env("NO_COLOR"));
  let autostream = anstream::AutoStream::new(io::stdout(), cc);
  let current = autostream.current_choice();
  let resolved = if current == anstream::ColorChoice::Never { ColorMode::Off } else { ColorMode::On };
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
// the app/crate. Don't turn it off lightly.
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

fn resolve_theme(color: ColorMode, theme: Option<ThemeMode>) -> ResolvedTheme {
  // Never run terminal theme detection when color is off; it can hang under
  // process managers and does not matter when ANSI will be stripped.
  let requested = theme.unwrap_or(ThemeMode::Auto);
  let resolved = match (color, requested) {
    (ColorMode::Off, _) => ResolvedTheme::Dark,
    (ColorMode::On, ThemeMode::Auto) => terminal_theme(),
    (ColorMode::On, ThemeMode::Dark) => ResolvedTheme::Dark,
    (ColorMode::On, ThemeMode::Light) => ResolvedTheme::Light,
    (ColorMode::Auto, _) => unreachable!("color was resolved above"),
  };
  crate::verbose::log(format_args!("Resolved.resolve_theme color={color:?} requested={requested:?} => {resolved:?}"));
  resolved
}

fn terminal_theme() -> ResolvedTheme {
  #[cfg(not(test))]
  {
    use std::time::Duration;

    let mut options = terminal_colorsaurus::QueryOptions::default();
    options.timeout = Duration::from_millis(100);
    crate::verbose::log(format_args!("Resolved.colorsaurus() start"));
    let result = terminal_colorsaurus::theme_mode(options);
    crate::verbose::log(format_args!("Resolved.colorsaurus() => {result:?}",));
    match result {
      Ok(terminal_colorsaurus::ThemeMode::Light) => ResolvedTheme::Light,
      Ok(terminal_colorsaurus::ThemeMode::Dark) | Err(_) => ResolvedTheme::Dark,
    }
  }

  #[cfg(test)]
  {
    THEME_PROBE_COUNT.with(|count| count.set(count.get() + 1));
    ResolvedTheme::Dark
  }
}

fn terminal_width() -> usize {
  terminal_size::terminal_size().map_or(80, |(width, _)| width.0 as usize)
}

#[cfg(test)]
std::thread_local! {
  static THEME_PROBE_COUNT: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
}

#[cfg(test)]
mod tests {
  use super::*;

  fn reset_theme_probe_count() {
    THEME_PROBE_COUNT.with(|count| count.set(0));
  }

  fn theme_probe_count() -> usize {
    THEME_PROBE_COUNT.with(std::cell::Cell::get)
  }

  #[test]
  fn test_resolved_converts_auto_width_to_fixed_width() {
    let options = Options {
      color: Some(ColorMode::On),
      theme: Some(ThemeMode::Dark),
      width: Some(WidthMode::Auto),
      ..Options::default()
    };

    let resolved = Resolved::new(options);
    assert!(matches!(resolved.width, ResolvedWidth::Fixed(_)));
  }

  #[test]
  fn test_resolved_theme_dark() {
    let options = Options { color: Some(ColorMode::On), theme: Some(ThemeMode::Dark), ..Options::default() };
    assert_eq!(ResolvedTheme::Dark, Resolved::new(options).theme);
  }

  #[test]
  fn test_resolved_theme_light() {
    let options = Options { color: Some(ColorMode::On), theme: Some(ThemeMode::Light), ..Options::default() };
    assert_eq!(ResolvedTheme::Light, Resolved::new(options).theme);
  }

  #[test]
  fn test_resolved_uses_dark_when_color_is_off() {
    reset_theme_probe_count();
    let options = Options { color: Some(ColorMode::Off), theme: Some(ThemeMode::Auto), ..Options::default() };
    let resolved = Resolved::new(options);

    assert_eq!(ColorMode::Off, resolved.color);
    assert_eq!(ResolvedTheme::Dark, resolved.theme);
    assert_eq!(0, theme_probe_count());
  }

  #[test]
  fn test_resolved_probes_when_color_is_on_and_theme_is_auto() {
    reset_theme_probe_count();
    let options = Options { color: Some(ColorMode::On), theme: Some(ThemeMode::Auto), ..Options::default() };
    let resolved = Resolved::new(options);

    assert_eq!(ColorMode::On, resolved.color);
    assert_eq!(ResolvedTheme::Dark, resolved.theme);
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
