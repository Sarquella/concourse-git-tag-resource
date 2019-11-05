log() {
  local message="$(date -u '+%F %T') - $1"
  echo "$message" >&2
}
