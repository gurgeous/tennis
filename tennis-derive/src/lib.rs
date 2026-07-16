//! Derive macro for tennis Record structs.

use proc_macro::TokenStream;
use quote::quote;
use syn::{
  Attribute, Data, DeriveInput, Error, Fields, LitInt, LitStr, Path, Result, Token, Type, meta::ParseNestedMeta,
  parse_macro_input,
};

/// Derive `Record` for a named struct so it can be loaded with
/// `Builder::load_records`.
///
/// Field attrs:
/// - `rename = "..."`
/// - `skip`
/// - `big`, `bigger`, `biggest`
/// - `scale = "..."`
///
/// Struct attrs:
/// - `title = "..."`
/// - `footer = "..."`
/// - `border = "..."`
/// - `crate_path = "..."`
/// - `width = 80`
/// - `digits = 3`
/// - `zebra` or `zebra = true|false`
/// - `row_numbers` or `row_numbers = true|false`
/// - `vanilla` or `vanilla = true|false`
/// - `titleize` or `titleize = true|false`
/// - `hyperlinks` or `hyperlinks = true|false`
#[proc_macro_derive(Record, attributes(tennis))]
pub fn derive_record(input: TokenStream) -> TokenStream {
  match expand_record(parse_macro_input!(input as DeriveInput)) {
    Ok(tokens) => tokens.into(),
    Err(error) => error.to_compile_error().into(),
  }
}

fn expand_record(input: DeriveInput) -> Result<proc_macro2::TokenStream> {
  let name = input.ident;
  let generics = input.generics;
  let struct_options = StructOptions::parse(&input.attrs)?;
  let crate_path = struct_options.crate_path()?;
  let fields = match input.data {
    Data::Struct(data) => match data.fields {
      Fields::Named(fields) => fields.named,
      Fields::Unnamed(_) | Fields::Unit => {
        return Err(Error::new_spanned(name, "Record can only be derived for structs with named fields"));
      }
    },
    _ => {
      return Err(Error::new_spanned(name, "Record can only be derived for structs"));
    }
  };

  let mut headers = Vec::new();
  let mut cells = Vec::new();
  let mut hints = Vec::new();
  let mut color_scales = Vec::new();

  for field in fields {
    let attrs = FieldOptions::parse(&field.attrs)?;
    if attrs.skip {
      continue;
    }
    let ident = field.ident.as_ref().expect("named fields have idents");
    let header = attrs.rename.unwrap_or_else(|| ident.to_string());
    headers.push(header.clone());
    if let Some(hint) = attrs.hint {
      hints.push((hint, header.clone()));
    }
    if let Some(scale) = attrs.scale {
      color_scales.push((scale, header.clone()));
    }
    cells.push(cell_expr(ident, &field.ty));
  }

  let builder = builder_expr(&crate_path, struct_options, hints, color_scales);
  let (impl_generics, ty_generics, where_clause) = generics.split_for_impl();

  Ok(quote! {
    impl #impl_generics #crate_path::Record for #name #ty_generics #where_clause {
      fn headers() -> ::std::vec::Vec<::std::string::String> {
        ::std::vec![#(::std::string::String::from(#headers)),*]
      }

      fn builder(builder: #crate_path::Builder) -> #crate_path::Builder {
        #builder
      }

      fn to_cells(&self) -> ::std::vec::Vec<::std::string::String> {
        ::std::vec![#(#cells),*]
      }
    }
  })
}

fn cell_expr(ident: &syn::Ident, ty: &Type) -> proc_macro2::TokenStream {
  if is_option(ty) {
    quote! {
      self.#ident
        .as_ref()
        .map(::std::string::ToString::to_string)
        .unwrap_or_default()
    }
  } else {
    quote! {
      ::std::string::ToString::to_string(&self.#ident)
    }
  }
}

fn builder_expr(
  crate_path: &Path,
  options: StructOptions,
  hints: Vec<(Hint, String)>,
  color_scales: Vec<(String, String)>,
) -> proc_macro2::TokenStream {
  let mut calls = Vec::new();
  if let Some(border) = options.border {
    let border = border_expr(crate_path, &border).expect("validated border has an expression");
    calls.push(quote!(builder = builder.border(#border);));
  }
  if let Some(digits) = options.digits {
    calls.push(quote!(builder = builder.digits(#digits);));
  }
  if let Some(footer) = options.footer {
    calls.push(quote!(builder = builder.footer(#footer);));
  }
  if let Some(hyperlinks) = options.hyperlinks {
    calls.push(quote!(builder = builder.hyperlinks(#hyperlinks);));
  }
  if let Some(row_numbers) = options.row_numbers {
    calls.push(quote!(builder = builder.row_numbers(#row_numbers);));
  }
  if let Some(title) = options.title {
    calls.push(quote!(builder = builder.title(#title);));
  }
  if let Some(titleize) = options.titleize {
    calls.push(quote!(builder = builder.titleize(#titleize);));
  }
  if let Some(vanilla) = options.vanilla {
    calls.push(quote!(builder = builder.vanilla(#vanilla);));
  }
  if let Some(width) = options.width {
    calls.push(quote!(builder = builder.width(#width);));
  }
  if let Some(zebra) = options.zebra {
    calls.push(quote!(builder = builder.zebra(#zebra);));
  }
  for (hint, header) in hints {
    calls.push(match hint {
      Hint::Big => quote!(builder = builder.big(#header);),
      Hint::Bigger => quote!(builder = builder.bigger(#header);),
      Hint::Biggest => quote!(builder = builder.biggest(#header);),
    });
  }
  for (scale, header) in color_scales {
    let scale = color_scale_expr(crate_path, &scale).expect("validated color scale has an expression");
    calls.push(quote!(builder = builder.color_scale(#header, #scale);));
  }
  if calls.is_empty() {
    return quote!(builder);
  }
  quote!({
    let mut builder = builder;
    #(#calls)*
    builder
  })
}

fn border_expr(crate_path: &Path, border: &str) -> Option<proc_macro2::TokenStream> {
  Some(match normalize(border).as_str() {
    "ascii_rounded" => quote!(#crate_path::Border::AsciiRounded),
    "basic" => quote!(#crate_path::Border::Basic),
    "basic_compact" => quote!(#crate_path::Border::BasicCompact),
    "compact" => quote!(#crate_path::Border::Compact),
    "compact_double" => quote!(#crate_path::Border::CompactDouble),
    "dots" => quote!(#crate_path::Border::Dots),
    "double" => quote!(#crate_path::Border::Double),
    "heavy" => quote!(#crate_path::Border::Heavy),
    "light" => quote!(#crate_path::Border::Light),
    "markdown" => quote!(#crate_path::Border::Markdown),
    "none" => quote!(#crate_path::Border::None),
    "psql" => quote!(#crate_path::Border::Psql),
    "reinforced" => quote!(#crate_path::Border::Reinforced),
    "restructured" => quote!(#crate_path::Border::Restructured),
    "rounded" => quote!(#crate_path::Border::Rounded),
    "single" => quote!(#crate_path::Border::Single),
    "thin" => quote!(#crate_path::Border::Thin),
    "with_love" => quote!(#crate_path::Border::WithLove),
    _ => return None,
  })
}

fn color_scale_expr(crate_path: &Path, scale: &str) -> Option<proc_macro2::TokenStream> {
  Some(match normalize(scale).as_str() {
    "green" => quote!(#crate_path::ColorScale::Green),
    "yellow" => quote!(#crate_path::ColorScale::Yellow),
    "red" => quote!(#crate_path::ColorScale::Red),
    "blue" => quote!(#crate_path::ColorScale::Blue),
    "green_white" => quote!(#crate_path::ColorScale::GreenWhite),
    "yellow_white" => quote!(#crate_path::ColorScale::YellowWhite),
    "red_white" => quote!(#crate_path::ColorScale::RedWhite),
    "blue_white" => quote!(#crate_path::ColorScale::BlueWhite),
    "red_green" | "rg" => quote!(#crate_path::ColorScale::RedGreen),
    "green_red" | "gr" => quote!(#crate_path::ColorScale::GreenRed),
    "green_yellow_red" | "gyr" => quote!(#crate_path::ColorScale::GreenYellowRed),
    _ => return None,
  })
}

#[derive(Default)]
struct StructOptions {
  border: Option<String>,
  crate_path: Option<LitStr>,
  digits: Option<LitInt>,
  footer: Option<LitStr>,
  hyperlinks: Option<bool>,
  row_numbers: Option<bool>,
  title: Option<LitStr>,
  titleize: Option<bool>,
  vanilla: Option<bool>,
  width: Option<LitInt>,
  zebra: Option<bool>,
}

impl StructOptions {
  fn crate_path(&self) -> Result<Path> {
    match &self.crate_path {
      Some(path) => path.parse(),
      None => syn::parse_str("::tennis"),
    }
  }

  fn parse(attrs: &[Attribute]) -> Result<Self> {
    let mut options = Self::default();
    for attr in attrs.iter().filter(|attr| attr.path().is_ident("tennis")) {
      attr.parse_nested_meta(|meta| {
        if meta.path.is_ident("border") {
          let value: LitStr = meta.value()?.parse()?;
          if border_expr(&syn::parse_str("::tennis")?, &value.value()).is_none() {
            return Err(Error::new_spanned(value, "unsupported tennis border"));
          }
          options.border = Some(value.value());
        } else if meta.path.is_ident("crate_path") {
          options.crate_path = Some(meta.value()?.parse()?);
        } else if meta.path.is_ident("digits") {
          options.digits = Some(meta.value()?.parse()?);
        } else if meta.path.is_ident("footer") {
          options.footer = Some(meta.value()?.parse()?);
        } else if meta.path.is_ident("hyperlinks") {
          options.hyperlinks = Some(bool_attr(meta)?);
        } else if meta.path.is_ident("row_numbers") {
          options.row_numbers = Some(bool_attr(meta)?);
        } else if meta.path.is_ident("title") {
          options.title = Some(meta.value()?.parse()?);
        } else if meta.path.is_ident("titleize") {
          options.titleize = Some(bool_attr(meta)?);
        } else if meta.path.is_ident("vanilla") {
          options.vanilla = Some(bool_attr(meta)?);
        } else if meta.path.is_ident("width") {
          options.width = Some(meta.value()?.parse()?);
        } else if meta.path.is_ident("zebra") {
          options.zebra = Some(bool_attr(meta)?);
        } else {
          return Err(meta.error("unsupported tennis struct attribute"));
        }
        Ok(())
      })?;
    }
    Ok(options)
  }
}

#[derive(Default)]
struct FieldOptions {
  scale: Option<String>,
  rename: Option<String>,
  hint: Option<Hint>,
  skip: bool,
}

impl FieldOptions {
  fn parse(attrs: &[Attribute]) -> Result<Self> {
    let mut options = Self::default();
    for attr in attrs.iter().filter(|attr| attr.path().is_ident("tennis")) {
      attr.parse_nested_meta(|meta| {
        if meta.path.is_ident("big") {
          options.set_hint(Hint::Big, meta.error("only one width hint is allowed"))?;
        } else if meta.path.is_ident("bigger") {
          options.set_hint(Hint::Bigger, meta.error("only one width hint is allowed"))?;
        } else if meta.path.is_ident("biggest") {
          options.set_hint(Hint::Biggest, meta.error("only one width hint is allowed"))?;
        } else if meta.path.is_ident("scale") {
          let value: LitStr = meta.value()?.parse()?;
          if color_scale_expr(&syn::parse_str("::tennis")?, &value.value()).is_none() {
            return Err(Error::new_spanned(value, "unsupported tennis color scale"));
          }
          options.scale = Some(value.value());
        } else if meta.path.is_ident("rename") {
          let value: LitStr = meta.value()?.parse()?;
          options.rename = Some(value.value());
        } else if meta.path.is_ident("skip") {
          options.skip = true;
        } else {
          return Err(meta.error("unsupported tennis field attribute"));
        }
        Ok(())
      })?;
    }
    Ok(options)
  }

  fn set_hint(&mut self, hint: Hint, error: Error) -> Result<()> {
    if self.hint.is_some() {
      return Err(error);
    }
    self.hint = Some(hint);
    Ok(())
  }
}

#[derive(Clone, Copy)]
enum Hint {
  Big,
  Bigger,
  Biggest,
}

fn normalize(value: &str) -> String {
  value
    .chars()
    .enumerate()
    .flat_map(|(index, ch)| {
      if ch == '-' || ch == ' ' {
        vec!['_']
      } else if ch.is_uppercase() {
        let mut out = Vec::new();
        if index > 0 {
          out.push('_');
        }
        out.extend(ch.to_lowercase());
        out
      } else {
        vec![ch]
      }
    })
    .collect()
}

fn bool_attr(meta: ParseNestedMeta<'_>) -> Result<bool> {
  if meta.input.peek(Token![=]) { Ok(meta.value()?.parse::<syn::LitBool>()?.value) } else { Ok(true) }
}

fn is_option(ty: &Type) -> bool {
  let Type::Path(path) = ty else {
    return false;
  };
  path.path.segments.last().is_some_and(|segment| segment.ident == "Option")
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_rejects_invalid_border() {
    let input = syn::parse_quote! {
      #[tennis(border = "invalid")]
      struct Person {
        name: String,
      }
    };
    let error = expand_record(input).unwrap_err();
    assert!(error.to_string().contains("unsupported tennis border"));
  }

  #[test]
  fn test_rejects_invalid_color_scale() {
    let input = syn::parse_quote! {
      struct Person {
        #[tennis(scale = "invalid")]
        name: String,
      }
    };
    let error = expand_record(input).unwrap_err();
    assert!(error.to_string().contains("unsupported tennis color scale"));
  }

  #[test]
  fn test_parses_bare_and_explicit_bool_attrs() {
    let options = StructOptions::parse(&[syn::parse_quote! {
      #[tennis(zebra, row_numbers = true, vanilla = false, titleize, hyperlinks = false)]
    }])
    .unwrap();

    assert_eq!(Some(true), options.zebra);
    assert_eq!(Some(true), options.row_numbers);
    assert_eq!(Some(false), options.vanilla);
    assert_eq!(Some(true), options.titleize);
    assert_eq!(Some(false), options.hyperlinks);
  }

  #[test]
  fn test_rejects_unknown_struct_attribute() {
    let input = syn::parse_quote! {
      #[tennis(unknown)]
      struct Person {
        name: String,
      }
    };
    let error = expand_record(input).unwrap_err();
    assert!(error.to_string().contains("unsupported tennis struct attribute"));
  }

  #[test]
  fn test_rejects_unit_struct() {
    let input = syn::parse_quote! {
      struct Person;
    };
    let error = expand_record(input).unwrap_err();
    assert!(error.to_string().contains("Record can only be derived for structs with named fields"));
  }
}
