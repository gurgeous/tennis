//! These are user options setup through derive or builder. Each field is
//! optional. Later we will resolve these into more concrete options (not
//! optional).

use crate::{
  ColorScale,
  builder::{
    ColumnOperation,
    types::{Border, ColorMode, ThemeMode, WidthMode},
  },
};

//
// options
//

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub(crate) struct Options {
  pub(crate) bigs: Vec<(String, ColumnBig)>,
  pub(crate) border: Option<Border>,
  pub(crate) color: Option<ColorMode>,
  pub(crate) color_scales: Vec<(String, ColorScale)>,
  pub(crate) digits: Option<usize>,
  pub(crate) footer: Option<String>,
  pub(crate) hyperlinks: Option<bool>,
  pub(crate) row_numbers: Option<bool>,
  pub(crate) theme: Option<ThemeMode>,
  pub(crate) title: Option<String>,
  pub(crate) titleize: Option<bool>,
  pub(crate) vanilla: Option<bool>,
  pub(crate) width: Option<WidthMode>,
  pub(crate) zebra: Option<bool>,
}

//
// col hints
//

impl Options {
  pub(crate) fn set_color_scale(&mut self, column: impl Into<String>, scale: ColorScale) {
    self.color_scales.push((column.into(), scale));
  }

  pub(crate) fn add_big(&mut self, column: impl Into<String>, big: ColumnBig) {
    self.bigs.push((column.into(), big));
  }

  /// Merges two option layers, with `other` taking precedence where set
  pub(crate) fn merge(mut self, mut other: Options) -> Self {
    self.bigs.append(&mut other.bigs);
    self.border = other.border.or(self.border);
    self.color = other.color.or(self.color);
    self.color_scales.append(&mut other.color_scales);
    self.digits = other.digits.or(self.digits);
    self.footer = other.footer.or(self.footer);
    self.hyperlinks = other.hyperlinks.or(self.hyperlinks);
    self.row_numbers = other.row_numbers.or(self.row_numbers);
    self.theme = other.theme.or(self.theme);
    self.title = other.title.or(self.title);
    self.titleize = other.titleize.or(self.titleize);
    self.vanilla = other.vanilla.or(self.vanilla);
    self.width = other.width.or(self.width);
    self.zebra = other.zebra.or(self.zebra);
    self
  }
}

#[repr(u8)]
#[derive(Clone, Copy, Debug, Default, Eq, Ord, PartialEq, PartialOrd)]
pub(crate) enum ColumnBig {
  #[default]
  Normal = 0,
  Big = 1,
  Bigger = 2,
  Biggest = 3,
}

impl ColumnBig {
  pub(crate) fn operation(self) -> Option<ColumnOperation> {
    match self {
      Self::Normal => None,
      Self::Big => Some(ColumnOperation::Big),
      Self::Bigger => Some(ColumnOperation::Bigger),
      Self::Biggest => Some(ColumnOperation::Biggest),
    }
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::resolved::Resolved;

  fn resolved(options: &Options) -> Resolved {
    Resolved::new(options.clone())
  }

  #[test]
  fn test_color_scale_lookup_matches_raw_headers() {
    let mut options = Options::default();
    options.set_color_scale("person_id", ColorScale::Blue);
    assert_eq!(Some(ColorScale::Blue), resolved(&options).color_scale("person_id"));

    options.set_color_scale("Person", ColorScale::Red);
    assert_eq!(Some(ColorScale::Blue), resolved(&options).color_scale("person_id"));
  }

  #[test]
  fn test_merge_keeps_last_color_scale() {
    let mut defaults = Options::default();
    defaults.set_color_scale("score", ColorScale::Green);

    let mut overrides = Options::default();
    overrides.set_color_scale("score", ColorScale::RedGreen);

    let options = defaults.merge(overrides);
    assert_eq!(Some(ColorScale::RedGreen), Resolved::new(options).color_scale("score"));
  }

  #[test]
  fn test_options_accessors() {
    let options = Options {
      border: Some(Border::Basic),
      color: Some(ColorMode::Off),
      theme: Some(ThemeMode::Light),
      width: Some(80.into()),
      title: Some("title".into()),
      footer: Some("footer".into()),
      digits: Some(2),
      row_numbers: Some(true),
      zebra: Some(true),
      vanilla: Some(true),
      titleize: Some(true),
      hyperlinks: Some(false),
      ..Options::default()
    };

    assert_eq!(Some(Border::Basic), options.border);
    assert_eq!(Some(ColorMode::Off), options.color);
    assert_eq!(Some(ThemeMode::Light), options.theme);
    assert_eq!(Some(WidthMode::Fixed(80)), options.width);
    assert_eq!(Some("title"), options.title.as_deref());
    assert_eq!(Some("footer"), options.footer.as_deref());
    assert_eq!(Some(2), options.digits);
    assert_eq!(Some(true), options.row_numbers);
    assert_eq!(Some(true), options.zebra);
    assert_eq!(Some(true), options.vanilla);
    assert_eq!(Some(true), options.titleize);
    assert_eq!(Some(false), options.hyperlinks);
  }

  #[test]
  fn test_column_big_is_last_wins() {
    let mut options = Options::default();
    options.add_big("name", ColumnBig::Biggest);
    options.add_big("name", ColumnBig::Big);
    assert_eq!(ColumnBig::Big, resolved(&options).column_big("name"));

    options.add_big("name", ColumnBig::Bigger);
    assert_eq!(ColumnBig::Bigger, resolved(&options).column_big("name"));
  }

  #[test]
  fn test_column_big_keeps_literal_names() {
    let mut options = Options::default();
    options.add_big(" name ", ColumnBig::Big);
    assert_eq!(ColumnBig::Normal, resolved(&options).column_big("name"));
    assert_eq!(ColumnBig::Big, resolved(&options).column_big(" NAME "));
  }

  #[test]
  fn test_column_big_matches_raw_headers() {
    let mut options = Options::default();
    options.add_big("person_id", ColumnBig::Big);
    assert_eq!(ColumnBig::Big, resolved(&options).column_big("person_id"));

    options.add_big("Person", ColumnBig::Bigger);
    assert_eq!(ColumnBig::Big, resolved(&options).column_big("person_id"));
  }

  #[test]
  fn test_merge_uses_other_precedence_for_newer_fields_and_bigs() {
    let mut defaults = Options { titleize: Some(true), hyperlinks: Some(false), ..Options::default() };
    defaults.add_big("name", ColumnBig::Biggest);

    let mut overrides = Options { titleize: Some(false), hyperlinks: Some(true), ..Options::default() };
    overrides.add_big("name", ColumnBig::Big);

    let options = defaults.merge(overrides);
    assert_eq!(Some(false), options.titleize);
    assert_eq!(Some(true), options.hyperlinks);
    assert_eq!(ColumnBig::Big, Resolved::new(options).column_big("name"));
  }
}
