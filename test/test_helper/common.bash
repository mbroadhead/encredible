_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
load "${_HELPER_DIR}/bats-support/load"
load "${_HELPER_DIR}/bats-assert/load"
load "${_HELPER_DIR}/bats-file/load"

ENCREDIBLE="${_HELPER_DIR}/../../bin/encredible"

# Create a temporary fake Rails project with encrypted credentials.
# Sets RAILS_PROJECT to the path; caller should cd into it.
setup_rails_project() {
  RAILS_PROJECT="$(mktemp -d "$BATS_TEST_TMPDIR/rails.XXXXXX")"

  mkdir -p "$RAILS_PROJECT/config/credentials"

  # Generate a random 128-bit key (hex)
  TEST_KEY="$(ruby -e 'require "securerandom"; print SecureRandom.hex(16)')"
  echo -n "$TEST_KEY" > "$RAILS_PROJECT/config/master.key"

  # Encrypt a simple YAML string using the same scheme as encredible
  ruby -e '
    require "openssl"
    require "base64"
    key = [ARGV[0]].pack("H*")
    plaintext = "secret_key_base: abc123\napi_key: xyz789\n"
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
  ' "$TEST_KEY" "$RAILS_PROJECT/config/credentials.yml.enc"

  # Also create a staging env credential
  STAGING_KEY="$(ruby -e 'require "securerandom"; print SecureRandom.hex(16)')"
  echo -n "$STAGING_KEY" > "$RAILS_PROJECT/config/credentials/staging.key"

  ruby -e '
    require "openssl"
    require "base64"
    key = [ARGV[0]].pack("H*")
    plaintext = "staging_secret: staging123\n"
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
  ' "$STAGING_KEY" "$RAILS_PROJECT/config/credentials/staging.yml.enc"

  # Init a git repo so --deploy works
  git -C "$RAILS_PROJECT" init -q
}
