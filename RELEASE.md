# Release Checklist

1. Update the repo
   1. `just check`
   2. Update `README.md` changelog
   3. Update version in `Cargo.toml`
   4. commit/push

1. Tag:

   ```sh
   git tag -a vX.X.X -m "release vX.X.X"
   git push origin main vX.X.X
   ```

1. Wait for the `Release` workflow to finish.

1. Verify GitHub release assets:

   ```text
   tennis_X.X.X_darwin_amd64.tar.gz
   tennis_X.X.X_darwin_arm64.tar.gz
   tennis_X.X.X_linux_amd64.tar.gz
   tennis_X.X.X_windows_amd64.zip
   ```

1. Update our homebrew tap:

   ```sh
   bin/homebrew-update
   ```

1. Review and publish the tap update:

   ```sh
   cd ../homebrew-tap
   git diff
   git add tennis.rb && git commit -m "release vX.X.X" && git push
   ```

1. Test the Homebrew install:
   ```sh
   brew update
   brew install gurgeous/tap/tennis
   tennis --version
   ```

# Need to reset?

```sh
gh release delete vX.X.X --yes
git push origin --delete vX.X.X
git tag -d vX.X.X
```

# Other helpful commands

```sh
gh repo edit --accept-visibility-change-consequences --visibility public
gh repo edit --accept-visibility-change-consequences --visibility private
```
