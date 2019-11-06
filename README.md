# Git Tag Resource

A [Concourse](https://concourse-ci.org) resource type for tracking [tags](https://git-scm.com/book/en/v2/Git-Basics-Tagging) in a [git](https://git-scm.com) repository.

![build](https://img.shields.io/docker/cloud/build/sarquella/concourse-git-tag-resource)

## Install

Use this resource by adding the following to the `resource_types` section of a pipeline config:

```yaml
resource_types:
- name: git-tag
  type: docker-image
  source:
    repository: sarquella/concourse-git-tag-resource
```

## Source Configuration

* `uri`: *Required.* The location of the repository.

* `tag_filter`: *Optional (default: \*).* If specified, the resource will only detect tags matching the expression. Patterns are [glob(7)](http://man7.org/linux/man-pages/man7/glob.7.html)
  compatible (as in, bash compatible).
  
 * `private_key`: *Optional.* Private key to use when pulling from the repository.

 * `username`: *Optional.* Username for HTTP(S) auth when pulling from the repository. This is needed when only HTTP/HTTPS protocol for git is available (which does not support private key auth) and auth is required.

 * `password`: *Optional.* Password for HTTP(S) auth when pulling from the repository.

 * `skip_ssl_verification`: *Optional.* Skips git ssl verification by exporting `GIT_SSL_NO_VERIFY=true`. 

 * `git_config`: *Optional.* If specified (as list of pairs `name` and `value`) it will configure git global options, setting each name with each value.

	 This can be useful to set options like `credential.helper` or similar.
	 
	 See the [`git-config(1)` manual page](https://www.kernel.org/pub/software/scm/git/docs/git-config.html)
  for more information and documentation of existing git options.

  
  ### Example
  
  Resource configuration filtering tags matching the expression `v*` (Example: v3 | v1.0 | v2.5.4 | ...):

``` yaml
resources:
- name: tagged-source-code
  type: git-tag
  source:
    uri: git@github.com:concourse/concourse.git
    tag_filter: v*
    private_key: {{concourse-repo-private-key}}
```  

## Behavior

### `check`: Check for new tags.
The repository is cloned (or pulled if already present), and any tag alongside the commit it belongs to are returned.

### `in`: Clone the repository, at the given tag's commit.
Clones the repository to the destination, and locks it down to the last tag's commit. It will return the same tag and commit as version.

### `out`: Not implemented.

