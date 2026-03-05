# encredible

Incredibly simple Rails credentials management and conflict resolution.

Uses Ruby stdlib (`openssl`, `base64`) — no gems required.

## Install

```sh
git clone https://github.com/pmtbox/encredible.git ~/.encredible
ln -s ~/.encredible/bin/encredible /usr/local/bin/encredible
```

Or add the `bin/` directory to your `PATH`:

```sh
export PATH="$HOME/.encredible/bin:$PATH"
```

## Usage

Run all commands from your Rails project root.

```sh
# Decrypt and print credentials
encredible --show

# Edit credentials in $EDITOR
encredible --edit

# Target a specific environment
encredible --show --env staging

# Set up git mergetool, difftool, and textconv
encredible --deploy

# Resolve merge conflicts on .yml.enc files
encredible --resolve
```

## Git integration

`encredible --deploy` registers the tool in your repo's `.git/config` and adds `.gitattributes` entries so that:

- `git diff` automatically decrypts `.yml.enc` files
- `git log -p -- config/credentials.yml.enc` shows decrypted history
- `git mergetool --tool=encredible` resolves encrypted credential conflicts
- `git difftool --tool=encredible` shows side-by-side decrypted diffs

## Requirements

- Ruby in `PATH` (no gems needed)
- The appropriate key file (`config/master.key` or `config/credentials/<env>.key`) or `RAILS_MASTER_KEY` env var
