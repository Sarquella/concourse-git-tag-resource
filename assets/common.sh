export TMPDIR=${TMPDIR:-/tmp}

load_pubkey() {
  local private_key_path=$TMPDIR/git-resource-private-key

  (jq -r '.source.private_key // empty' < $1) > $private_key_path

  if [ -s $private_key_path ]; then
    chmod 0600 $private_key_path

    eval $(ssh-agent) >/dev/null 2>&1
    trap "kill $SSH_AGENT_PID" 0

    SSH_ASKPASS=$(dirname $0)/askpass.sh DISPLAY= ssh-add $private_key_path >/dev/null

    mkdir -p ~/.ssh
    cat > ~/.ssh/config <<EOF
StrictHostKeyChecking no
LogLevel quiet
EOF
    chmod 0600 ~/.ssh/config
  fi
}

configure_git_ssl_verification() {
  skip_ssl_verification=$(jq -r '.source.skip_ssl_verification // false' < $1)
  if [ "$skip_ssl_verification" = "true" ]; then
    export GIT_SSL_NO_VERIFY=true
  fi
}

configure_credentials() {
  local username=$(jq -r '.source.username // ""' < $1)
  local password=$(jq -r '.source.password // ""' < $1)

  rm -f $HOME/.netrc
  if [ "$username" != "" -a "$password" != "" ]; then
    echo "default login $username password $password" > $HOME/.netrc
  fi
}

configure_git_global() {
  local git_config_payload=$(jq -r '.source.git_config // []' < $1)
  eval $(echo "$git_config_payload" | \
    jq -r ".[] | \"git config --global '\\(.name)' '\\(.value)'; \"")
}

configure_git() {
  local payload=$1

  log "Configuring git credentials"

  load_pubkey $payload
  configure_git_ssl_verification $payload
  configure_credentials $payload
  configure_git_global $payload

}

parse_source() {
  local payload=$1

  log "Parsing source"

  uri=$(jq -r '.source.uri // ""' < $payload)
  tag=$(jq -r '.source.tag // ""' < $payload)
}

clone_repo() {
  local destination=$1

  # We're just checking for commits and tags; we don't ever need to fetch LFS files here!
  export GIT_LFS_SKIP_SMUDGE=1

  if [ ! -d "$destination/.git" ]; then
    log "Cloning $uri in $destination"

    git clone --single-branch "$uri" "$destination"
    cd $destination
  else
    log "Reseting $uri in $destination"

    cd $destination
    git reset --hard FETCH_HEAD
  fi
}
