#!/usr/bin/env bats

load test_helper/common

# -----------------------------------------------------------------------
# Help / usage
# -----------------------------------------------------------------------

@test "--version prints version" {
  run "$ENCREDIBLE" --version
  assert_success
  assert_output --regexp '^encredible [0-9]+\.[0-9]+\.[0-9]+'
}

@test "-v prints version" {
  run "$ENCREDIBLE" -v
  assert_success
  assert_output --regexp '^encredible [0-9]+\.[0-9]+\.[0-9]+'
}

@test "-h prints help and exits 0" {
  run "$ENCREDIBLE" -h
  assert_success
  assert_output --partial "Incredibly simple Rails credentials management"
}

@test "--help prints help and exits 0" {
  run "$ENCREDIBLE" --help
  assert_success
  assert_output --partial "USAGE:"
  assert_output --partial "OPTIONS:"
}

@test "no arguments exits 1 with usage hint" {
  run "$ENCREDIBLE"
  assert_failure
  assert_output --partial "No command specified"
  assert_output --partial "encredible -h"
}

@test "unknown flag exits 1" {
  run "$ENCREDIBLE" --bogus
  assert_failure
  assert_output --partial "Unknown argument: --bogus"
  assert_output --partial "encredible -h"
}

# -----------------------------------------------------------------------
# Show
# -----------------------------------------------------------------------

@test "--show decrypts default credentials" {
  setup_rails_project
  cd "$RAILS_PROJECT"

  run "$ENCREDIBLE" --show
  assert_success
  assert_output --partial "secret_key_base: abc123"
  assert_output --partial "api_key: xyz789"
}

@test "-s is an alias for --show" {
  setup_rails_project
  cd "$RAILS_PROJECT"

  run "$ENCREDIBLE" -s
  assert_success
  assert_output --partial "secret_key_base: abc123"
}

@test "--show --env staging decrypts env-specific credentials" {
  setup_rails_project
  cd "$RAILS_PROJECT"

  run "$ENCREDIBLE" --show --env staging
  assert_success
  assert_output --partial "staging_secret: staging123"
}

@test "--show with RAILS_ENV selects environment" {
  setup_rails_project
  cd "$RAILS_PROJECT"

  RAILS_ENV=staging run "$ENCREDIBLE" --show
  assert_success
  assert_output --partial "staging_secret: staging123"
}

@test "--env flag overrides RAILS_ENV" {
  setup_rails_project
  cd "$RAILS_PROJECT"

  # RAILS_ENV=staging but --env points to nonexistent env, so falls back to default
  RAILS_ENV=staging run "$ENCREDIBLE" --show --env production
  assert_success
  assert_output --partial "secret_key_base: abc123"
}

@test "RAILS_MASTER_KEY env var works instead of key file" {
  setup_rails_project
  cd "$RAILS_PROJECT"

  local key
  key="$(cat "$RAILS_PROJECT/config/master.key")"
  rm "$RAILS_PROJECT/config/master.key"

  RAILS_MASTER_KEY="$key" run "$ENCREDIBLE" --show
  assert_success
  assert_output --partial "secret_key_base: abc123"
}

# -----------------------------------------------------------------------
# Missing key
# -----------------------------------------------------------------------

@test "--show fails when key is missing" {
  setup_rails_project
  cd "$RAILS_PROJECT"

  rm "$RAILS_PROJECT/config/master.key"

  run "$ENCREDIBLE" --show
  assert_failure
  assert_output --partial "Key not found"
}

# -----------------------------------------------------------------------
# Textconv
# -----------------------------------------------------------------------

@test "--textconv decrypts a file to stdout" {
  setup_rails_project
  cd "$RAILS_PROJECT"

  run "$ENCREDIBLE" --textconv config/credentials.yml.enc
  assert_success
  assert_output --partial "secret_key_base: abc123"
}

@test "-t is an alias for --textconv" {
  setup_rails_project
  cd "$RAILS_PROJECT"

  run "$ENCREDIBLE" -t config/credentials.yml.enc
  assert_success
  assert_output --partial "secret_key_base: abc123"
}

@test "--textconv without file arg prints error" {
  run "$ENCREDIBLE" --textconv
  assert_output --partial "--textconv requires a file path"
}

# -----------------------------------------------------------------------
# Deploy
# -----------------------------------------------------------------------

@test "--deploy registers git config entries" {
  setup_rails_project
  cd "$RAILS_PROJECT"

  run "$ENCREDIBLE" --deploy
  assert_success
  assert_output --partial "mergetool 'encredible'"
  assert_output --partial "difftool 'encredible'"
  assert_output --partial "textconv 'encredible'"

  # Verify git config was written
  run git config mergetool.encredible.cmd
  assert_success

  run git config difftool.encredible.cmd
  assert_success

  run git config diff.encredible.textconv
  assert_success

  run git config diff.encredible.cachetextconv
  assert_success
  assert_output "true"
}

@test "--deploy creates .gitattributes entries" {
  setup_rails_project
  cd "$RAILS_PROJECT"

  run "$ENCREDIBLE" --deploy
  assert_success

  assert_file_exist "$RAILS_PROJECT/.gitattributes"
  run cat "$RAILS_PROJECT/.gitattributes"
  assert_output --partial "config/credentials.yml.enc diff=encredible"
  assert_output --partial "config/credentials/*.yml.enc diff=encredible"
}

@test "--deploy is idempotent for .gitattributes" {
  setup_rails_project
  cd "$RAILS_PROJECT"

  "$ENCREDIBLE" --deploy
  "$ENCREDIBLE" --deploy

  run grep -c "diff=encredible" "$RAILS_PROJECT/.gitattributes"
  assert_output "2"  # exactly 2 lines, not 4
}

@test "-d is an alias for --deploy" {
  setup_rails_project
  cd "$RAILS_PROJECT"

  run "$ENCREDIBLE" -d
  assert_success
  assert_output --partial "mergetool 'encredible'"
}

# -----------------------------------------------------------------------
# Diff tool
# -----------------------------------------------------------------------

@test "--diff-tool decrypts and diffs two blobs" {
  setup_rails_project
  cd "$RAILS_PROJECT"

  # Create a second encrypted blob with different content
  local tmp_v2
  tmp_v2="$(mktemp)"
  ruby -e '
    require "openssl"
    require "base64"
    key = [ARGV[0]].pack("H*")
    plaintext = "secret_key_base: abc123\napi_key: CHANGED\n"
    marshaled = Marshal.dump(plaintext)
    cipher = OpenSSL::Cipher.new("aes-128-gcm")
    cipher.encrypt
    cipher.key = key
    iv = cipher.random_iv
    cipher.auth_data = ""
    encrypted = cipher.update(marshaled) + cipher.final
    auth_tag = cipher.auth_tag(16)
    result = [encrypted, iv, auth_tag].map { |p| Base64.strict_encode64(p) }.join("--")
    File.binwrite(ARGV[1], result + "\n")
  ' "$(cat "$RAILS_PROJECT/config/master.key")" "$tmp_v2"

  run "$ENCREDIBLE" --diff-tool \
    "$RAILS_PROJECT/config/credentials.yml.enc" \
    "$tmp_v2" \
    "$RAILS_PROJECT/config/credentials.yml.enc"
  assert_success
  assert_output --partial "-api_key: xyz789"
  assert_output --partial "+api_key: CHANGED"

  rm -f "$tmp_v2"
}

@test "--diff-tool fails with fewer than 2 args" {
  setup_rails_project
  cd "$RAILS_PROJECT"

  run "$ENCREDIBLE" --diff-tool onefile
  assert_failure
  assert_output --partial "requires at least 2 arguments"
}

# -----------------------------------------------------------------------
# Merge tool argument validation
# -----------------------------------------------------------------------

@test "--merge-tool fails without 3 args" {
  setup_rails_project
  cd "$RAILS_PROJECT"

  run "$ENCREDIBLE" --merge-tool file1 file2
  assert_failure
  assert_output --partial "requires exactly 3 arguments"
}

# -----------------------------------------------------------------------
# Edit (non-interactive — just verify it starts)
# -----------------------------------------------------------------------

@test "--edit with EDITOR=true does a no-op round trip" {
  setup_rails_project
  cd "$RAILS_PROJECT"

  local before
  before="$(cat "$RAILS_PROJECT/config/credentials.yml.enc")"

  EDITOR=true run "$ENCREDIBLE" --edit
  assert_success
  assert_output --partial "No changes detected"

  local after
  after="$(cat "$RAILS_PROJECT/config/credentials.yml.enc")"
  [ "$before" = "$after" ]
}

# -----------------------------------------------------------------------
# Round-trip encrypt/decrypt
# -----------------------------------------------------------------------

@test "edit round-trip preserves content" {
  setup_rails_project
  cd "$RAILS_PROJECT"

  # Decrypt original
  local original
  original="$("$ENCREDIBLE" --show)"

  # Edit with a script that appends a line
  local editor_script
  editor_script="$(mktemp)"
  cat > "$editor_script" <<'SH'
#!/bin/sh
echo "new_key: new_value" >> "$1"
SH
  chmod +x "$editor_script"

  EDITOR="$editor_script" "$ENCREDIBLE" --edit

  # Verify new content
  run "$ENCREDIBLE" --show
  assert_success
  assert_output --partial "secret_key_base: abc123"
  assert_output --partial "new_key: new_value"

  rm -f "$editor_script"
}
