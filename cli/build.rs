// Embed the CLI git revision.

use std::process::Command;

fn main() {
  println!("cargo:rerun-if-changed=../.git/HEAD");
  println!("cargo:rerun-if-changed=../.git/refs");

  let output = Command::new("git").args(["rev-parse", "--short=7", "HEAD"]).output();
  let sha = match output {
    Ok(output) if output.status.success() => String::from_utf8(output.stdout).unwrap_or_default().trim().to_owned(),
    _ => String::new(),
  };

  println!("cargo:rustc-env=TENNIS_GIT_SHA={sha}");
}
