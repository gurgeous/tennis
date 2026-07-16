use std::fmt::Write as _;

use clap::Arg;

use crate::args::{self, CompletionShell};

//
// Shell completion generation
//

const BASH_TEMPLATE: &str = include_str!("templates/completion.bash");
const ZSH_TEMPLATE: &str = include_str!("templates/completion.zsh");
const FILE_EXTENSIONS: &[&str] = &["csv", "tsv", "db", "json", "jsonl", "ndjson", "sqlite", "sqlite3"];
const FAKE_SHORTS: &[(&str, &str)] = &[("big2", "-bb"), ("big3", "-bbb")];

// Completion metadata derived from clap args.
#[derive(Clone, Debug, Eq, PartialEq)]
struct OptionSpec {
  names: Vec<String>,         // flag spellings
  value_key: String,          // key for value completion
  value_name: Option<String>, // value placeholder
  values: Vec<String>,        // known values
  desc: String,               // help text
}

pub fn script(shell: CompletionShell) -> String {
  let options = options();
  match shell {
    CompletionShell::Bash => write_bash(&options),
    CompletionShell::Zsh => write_zsh(&options),
  }
}

fn options() -> Vec<OptionSpec> {
  let command = args::command();
  let mut options = Vec::new();

  for arg in command.get_arguments() {
    if let Some(option) = option_from_arg(arg) {
      let is_big1 = arg.get_id().as_str() == "big1";
      options.push(option);
      if is_big1 {
        // clap_complete cannot express Tennis's fake multi-letter short flags
        // (`-bb`, `-bbb`) or the curated file globs, so completions stay local.
        options.extend(FAKE_SHORTS.iter().filter_map(|(id, name)| option_from_hidden_arg(&command, id, name)));
      }
    }
  }

  options
}

fn option_from_arg(arg: &Arg) -> Option<OptionSpec> {
  if arg.is_hide_set() || (arg.get_short().is_none() && arg.get_long().is_none()) {
    return None;
  }

  let mut names = Vec::new();
  if let Some(short) = arg.get_short() {
    names.push(format!("-{short}"));
  }
  if let Some(long) = arg.get_long() {
    names.push(format!("--{long}"));
  }
  if let Some(aliases) = arg.get_all_aliases() {
    names.extend(aliases.into_iter().map(|alias| format!("--{alias}")));
  }

  let value_key = arg.get_long().map(|long| format!("--{long}")).unwrap_or_else(|| names[0].clone());
  let value_name = if arg.get_action().takes_values() {
    arg.get_value_names().and_then(|names| names.first()).map(|name| name.to_string())
  } else {
    None
  };
  let values = possible_values(arg);
  let desc = arg.get_help().or_else(|| arg.get_long_help()).map(|help| help.to_string()).unwrap_or_default();

  Some(OptionSpec { names, value_key, value_name, values, desc })
}

fn option_from_hidden_arg(command: &clap::Command, id: &str, name: &str) -> Option<OptionSpec> {
  let arg = command.get_arguments().find(|arg| arg.get_id().as_str() == id)?;
  let value_name = arg.get_value_names().and_then(|names| names.first()).map(|name| name.to_string());
  let desc = arg.get_help().or_else(|| arg.get_long_help()).map(|help| help.to_string()).unwrap_or_default();
  Some(OptionSpec {
    names: vec![name.to_owned()],
    value_key: name.to_owned(),
    value_name,
    values: possible_values(arg),
    desc,
  })
}

fn possible_values(arg: &Arg) -> Vec<String> {
  arg.get_possible_values().into_iter().map(|value| value.get_name().to_owned()).collect()
}

fn write_bash(options: &[OptionSpec]) -> String {
  let mut case_arms = String::new();
  for opt in options.iter().filter(|opt| opt.value_name.is_some()) {
    case_arms.push_str("    ");
    case_arms.push_str(&opt.names.join("|"));
    if let Some(values) = values_for(opt) {
      let values = values.iter().map(|value| bash_word(value)).collect::<Vec<_>>().join(" ");
      let _ = writeln!(case_arms, ") COMPREPLY=($(compgen -W \"{values}\" -- \"${{cur}}\")) ; return ;;");
    } else {
      case_arms.push_str(") COMPREPLY=() ; return ;;\n");
    }
  }

  BASH_TEMPLATE
    .replace("{{case_arms}}", case_arms.trim_end())
    .replace("{{all_flags}}", &all_flags(options).join(" "))
    .replace("{{file_extensions}}", &bash_extension_glob())
}

fn write_zsh(options: &[OptionSpec]) -> String {
  let mut specs = String::new();

  for opt in options {
    for name in &opt.names {
      specs.push_str("    ");
      write_zsh_spec(&mut specs, name, &opt.desc, opt.value_name.as_deref(), values_for(opt));
      specs.push_str(" \\\n")
    }
  }

  ZSH_TEMPLATE.replace("{{specs}}", specs.trim_end()).replace("{{file_extensions}}", &FILE_EXTENSIONS.join("|"))
}

fn write_zsh_spec(out: &mut String, name: &str, desc: &str, value_name: Option<&str>, values: Option<Vec<String>>) {
  let _ = write!(out, "'{}[{}]", zsh_spec(name), zsh_spec(desc));
  if let Some(value_name) = value_name {
    let _ = write!(out, ":{}", zsh_spec(value_name.trim_matches(&['<', '>'][..])));
    if let Some(values) = values {
      out.push(':');
      write_zsh_values(out, &values);
    } else {
      out.push(':');
    }
  }
  out.push('\'');
}

fn write_zsh_values(out: &mut String, values: &[String]) {
  out.push('(');
  for (index, value) in values.iter().enumerate() {
    if index > 0 {
      out.push(' ');
    }
    out.push_str(&zsh_value(value));
  }
  out.push(')');
}

fn values_for(opt: &OptionSpec) -> Option<Vec<String>> {
  if !opt.values.is_empty() {
    return Some(opt.values.clone());
  }

  match opt.value_key.as_str() {
    "--delimiter" => Some(vec![",", ";", "|", "tab"].into_iter().map(str::to_owned).collect()),
    "--digits" => Some((1..=6).map(|n| n.to_string()).collect()),
    "--width" => Some(["auto", "min", "max"].into_iter().map(str::to_owned).collect()),
    _ => None,
  }
}

fn all_flags(options: &[OptionSpec]) -> Vec<String> {
  options.iter().flat_map(|opt| opt.names.clone()).collect()
}

fn bash_extension_glob() -> String {
  format!("@({})", FILE_EXTENSIONS.join("|"))
}

fn bash_word(value: &str) -> String {
  value.replace('\\', "\\\\").replace('"', "\\\"")
}

fn zsh_spec(value: &str) -> String {
  value.replace('\\', "\\\\").replace('\'', "'\\''").replace('[', "\\[").replace(']', "\\]").replace(':', "\\:")
}

fn zsh_value(value: &str) -> String {
  value.replace('\\', "\\\\").replace(';', "\\;").replace('|', "\\|")
}

//
// Tests
//

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_options() {
    let options = options();
    assert!(options.iter().any(|opt| opt.names == ["-t", "--title"] && opt.value_name.as_deref() == Some("string")));
    assert!(options.iter().any(|opt| opt.names == ["-bb"] && opt.value_name.as_deref() == Some("headers")));
    assert!(options.iter().any(|opt| opt.names == ["--shuffle", "--shuf"]));
    assert!(!options.iter().any(|opt| opt.names.iter().any(|name| name == "--_b2")));
  }

  #[test]
  fn test_script() {
    let bash = script(CompletionShell::Bash);
    assert!(bash.contains("-bb -bbb"));
    assert!(bash.contains("@(csv|tsv|db|json|jsonl|ndjson|sqlite|sqlite3)"));
    assert!(bash.contains("auto min max"));

    let zsh = script(CompletionShell::Zsh);
    assert!(zsh.contains("#compdef tennis"));
    assert!(zsh.contains("csv|tsv|db|json|jsonl|ndjson|sqlite|sqlite3"));
    assert!(zsh.contains(":width:(auto min max)"));
    assert!(!zsh.contains("--_b2"));
  }

  #[test]
  fn test_zsh_escaping() {
    let mut out = String::new();
    write_zsh_spec(
      &mut out,
      "--x",
      "don't [break]: specs",
      Some("value:name"),
      Some(vec![";".to_owned(), "|".to_owned()]),
    );
    assert!(out.contains("don'\\''t \\[break\\]\\: specs"));
    assert!(out.contains(":value\\:name:"));
    assert!(out.contains("(\\; \\|)"));
  }
}
