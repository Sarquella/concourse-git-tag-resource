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
  tag_filter=$(jq -r '.source.tag_filter // "*"' < $payload)
}

parse_version() {
  local payload=$1

  log "Parsing version"

  tag=$(jq -r '.version.tag // ""' < $payload)
  commit=$(jq -r '.version.commit // ""' < $payload)
}

clone_repo() {
  local destination=$1
  local clone_flags=$2

  if [ ! -d "$destination/.git" ]; then
    log "Cloning into '$destination'"

    git clone $clone_flags "$uri" "$destination"
    cd $destination
  else
    log "Reseting into '$destination'"

    cd $destination
    git reset --hard FETCH_HEAD
  fi
}

checkout_commit() {
  local commit=$1
  local checkout_flags=$2

  log "Checking out to '$commit'"

  git checkout $checkout_flags $commit
}

update_tags() {
  log "Updating tags"

  git tag -l | xargs git tag -d #Delete all local tags
  git fetch --tags #Fetch tags to be up to date with remote
}

get_tags() {
  log "Retrieving tags"

  echo "$(git tag)"
}

filter_tags() {
  local tags=$1
  local filter=$2

  log "Filtering tags matching $filter"

  for tag in $tags; do
    if [[ $tag == $filter ]]; then
      echo $tag
    fi 
  done
}

get_commits() {
  local tags=$1

  log "Retrieving commits"

  for tag in $tags; do
    echo $(git rev-list -n 1 $tag)
  done
}

format_output() {
  local tags=($1)
  local commits=($2)

  log "Formatting output"

  output=""
  for i in ${!tags[@]}; do
    output+="{tag: \"${tags[$i]}\", commit: \"${commits[$i]}\"}"
  done

  echo "[$output]" | sed "s/}{/},{/g"
}

add_git_metadata_basic() {
  local commit=$(git rev-parse HEAD | jq -R .)
  local author=$(git log -1 --format=format:%an | jq -s -R .)
  local author_date=$(git log -1 --format=format:%ai | jq -R .)

  jq ". + [
    {name: \"commit\", value: ${commit}},
    {name: \"author\", value: ${author}},
    {name: \"author_date\", value: ${author_date}, type: \"time\"}
  ]"
}

add_git_metadata_committer() {
  local author=$(git log -1 --format=format:%an | jq -s -R .)
  local author_date=$(git log -1 --format=format:%ai | jq -R .)
  local committer=$(git log -1 --format=format:%cn | jq -s -R .)
  local committer_date=$(git log -1 --format=format:%ci | jq -R .)

  if [ "$author" = "$committer" ] && [ "$author_date" = "$committer_date" ]; then
    jq ". + [
      {name: \"committer\", value: ${committer}},
      {name: \"committer_date\", value: ${committer_date}, type: \"time\"}
    ]"
  else
    cat
  fi
}

add_git_metadata_branch() {
  local branch=$(git show-ref --heads | \
    sed -n "s/^$(git rev-parse HEAD) refs\/heads\/\(.*\)/\1/p" |  \
    jq -R  ". | select(. != \"\")" | jq -r -s "map(.) | join (\",\")")

  if [ -n "${branch}" ]; then
    jq ". + [
      {name: \"branch\", value: \"${branch}\"}
    ]"
  else
    cat
  fi
}

add_git_metadata_tags() {
  local tags=$(git tag --points-at HEAD | \
    jq -R  ". | select(. != \"\")" | \
    jq -r -s "map(.) | join(\",\")")

  if [ -n "${tags}" ]; then
    jq ". + [
      {name: \"tags\", value: \"${tags}\"}
    ]"
  else
    cat
  fi
}

add_git_metadata_message() {
  local message=$(git log -1 --format=format:%B | jq -s -R .)

  jq ". + [
    {name: \"message\", value: ${message}, type: \"message\"}
  ]"
}

add_git_metadata_url() {
  local commit=$(git rev-parse HEAD)
  local origin=$(git remote get-url --all origin) 2> /dev/null

  if echo $origin | grep github.com > /dev/null; then

    # git@github.com:concourse/git-resource.git     -> concourse/git-resource
    # https://github.com/concourse/git-resource.git -> concourse/git-resource
    local ownerRepo=$(echo $origin | sed -e' s/.*github.com[:\/]//; s/\.git$//')
    local url=$(echo "https://github.com/$ownerRepo/commit/$commit" | jq -R . )

    jq ". + [
        {name: \"url\", value: ${url}}
    ]"
  else
    jq ". + []"
  fi
}

git_metadata() {
  jq -n "[]" | \
    add_git_metadata_basic | \
    add_git_metadata_committer | \
    add_git_metadata_branch | \
    add_git_metadata_tags | \
    add_git_metadata_message | \
    add_git_metadata_url
}
