//! Output pager.

use std::process::{Child, ChildStdin, Command, Stdio};

use crate::{
  Grid,
  error::{Error, Result},
  render::{border::get_border, resolved::Resolved},
  verbose,
};

//
// simple Pager struct
//

pub struct Pager {
  child: Child,
  pub stdin: ChildStdin,
}

impl Pager {
  pub fn spawn(grid: &Grid, options: &Resolved) -> Result<Self> {
    // empty tables put the title where headers go, same layout as no title
    let title = options.title.is_some() && !grid.is_empty();
    let header_lines = get_border(options.border).header_lines(title);

    let pager = env_pager(header_lines);
    let mut parts = shell_words::split(&pager).map_err(|_| Error::PagerStart)?.into_iter();
    let program = parts.next().ok_or(Error::PagerStart)?;

    let mut child = Command::new(program)
      .args(parts)
      .stdin(Stdio::piped())
      .stdout(Stdio::inherit())
      .stderr(Stdio::inherit())
      .spawn()
      .map_err(|_| Error::PagerStart)?; // pager not found

    let stdin = child.stdin.take().ok_or(Error::PagerStart)?;

    Ok(Self { child, stdin })
  }

  pub fn finish(mut self) {
    drop(self.stdin);
    let _ = self.child.wait();
  }
}

//
// default pager
//

fn env_pager(header_lines: usize) -> String {
  match std::env::var("PAGER") {
    Ok(v) if !v.is_empty() => v,
    _ => default_pager(header_lines),
  }
}

// less 608 added --header, which freezes our table headers while scrolling
const LESS_HEADER_VERSION: u32 = 608;

fn default_pager(header_lines: usize) -> String {
  let version = Command::new("less")
    .arg("--version")
    .stdin(Stdio::null())
    .stderr(Stdio::null())
    .output()
    .ok()
    .filter(|output| output.status.success())
    .and_then(|output| less_version(&String::from_utf8_lossy(&output.stdout)));
  let pager = match version {
    Some(version) if version >= LESS_HEADER_VERSION => format!("less -RS --header={header_lines}"),
    _ => "less -RS".to_string(),
  };
  verbose::log(format_args!("less --version => {version:?}, pager={pager:?}"));
  pager
}

// "less 668 (GNU regular expressions)" => 668, also "581.2" => 581 and "643x" => 643
fn less_version(output: &str) -> Option<u32> {
  let rest = output.lines().next()?.strip_prefix("less ")?;
  let end = rest.find(|ch: char| !ch.is_ascii_digit()).unwrap_or(rest.len());
  rest[..end].parse().ok()
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_less_version() {
    for (output, expected) in [
      ("less 668 (GNU regular expressions)\nCopyright (C) 1984-2024", Some(668)),
      ("less 608", Some(608)),
      ("less 581.2 (POSIX regular expressions)", Some(581)),
      ("less 643x (PCRE2 regular expressions)", Some(643)),
      ("", None),
      ("BusyBox v1.36.1 multi-call binary.", None),
      ("less x", None),
    ] {
      assert_eq!(expected, less_version(output), "{output:?}");
    }
  }
}
