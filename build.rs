// Embed the CLI git revision.

use std::{fs, process::Command};

fn main() {
  println!("cargo:rerun-if-changed=.git/HEAD");
  println!("cargo:rerun-if-changed=.git/refs");
  println!("cargo:rerun-if-changed=.git_sha");

  let sha = archive_sha().or_else(git_sha).unwrap_or_default();
  println!("cargo:rustc-env=TENNIS_GIT_SHA={sha}");
}

fn git_sha() -> Option<String> {
  let output = Command::new("git").args(["rev-parse", "--short=7", "HEAD"]).output().ok()?;
  if !output.status.success() {
    return None;
  }
  Some(String::from_utf8(output.stdout).ok()?.trim().to_owned())
}

// Source tarballs (e.g. Homebrew) have no .git, but `git archive` fills in .git_sha via
// export-subst.
fn archive_sha() -> Option<String> {
  let sha = fs::read_to_string(".git_sha").ok()?;
  let sha = sha.trim();
  if sha.starts_with('$') || sha.len() < 7 {
    return None;
  }
  Some(sha[..7].to_owned())
}
