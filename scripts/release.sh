#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$ROOT_DIR/.local/release"
STATE_FILE="$STATE_DIR/state.env"
VERSION_FILE="$ROOT_DIR/VERSION"

mode="${1:-start}"

mkdir -p "$STATE_DIR"

die() {
  echo "[release] $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

repo_slug() {
  git -C "$ROOT_DIR" remote get-url origin | sed -E 's#^git@github.com:##; s#^https://github.com/##; s#\.git$##'
}

load_state() {
  if [ -f "$STATE_FILE" ]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
  fi
}

write_state() {
  mkdir -p "$STATE_DIR"
  cat >"$STATE_FILE" <<EOF
RELEASE_VERSION=${RELEASE_VERSION}
RELEASE_TAG=${RELEASE_TAG}
RELEASE_COMMIT=${RELEASE_COMMIT}
RELEASE_BRANCH=${RELEASE_BRANCH}
RELEASE_REPO=${RELEASE_REPO:-}
POST_RELEASE_BUMP=${POST_RELEASE_BUMP:-}
NEXT_VERSION=${NEXT_VERSION:-}
STEP_VALIDATE_DONE=${STEP_VALIDATE_DONE:-0}
STEP_TESTS_DONE=${STEP_TESTS_DONE:-0}
STEP_RELEASE_IMAGES_DONE=${STEP_RELEASE_IMAGES_DONE:-0}
STEP_GIT_TAG_DONE=${STEP_GIT_TAG_DONE:-0}
STEP_GIT_PUSH_DONE=${STEP_GIT_PUSH_DONE:-0}
STEP_GITHUB_RELEASE_DONE=${STEP_GITHUB_RELEASE_DONE:-0}
STEP_POST_BUMP_DONE=${STEP_POST_BUMP_DONE:-0}
EOF
}

current_branch() {
  git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD
}

current_commit() {
  git -C "$ROOT_DIR" rev-parse HEAD
}

read_version() {
  [ -f "$VERSION_FILE" ] || die "missing VERSION file: $VERSION_FILE"
  tr -d '[:space:]' < "$VERSION_FILE"
}

validate_semver() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid semantic version: $1"
}

bump_version() {
  local version="$1"
  local kind="$2"
  IFS='.' read -r major minor patch <<<"$version"
  case "$kind" in
    patch) patch=$((patch + 1)) ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    major) major=$((major + 1)); minor=0; patch=0 ;;
    none) echo "$version"; return 0 ;;
    *) die "unsupported bump kind: $kind" ;;
  esac
  echo "${major}.${minor}.${patch}"
}

ensure_clean_worktree() {
  local status
  status="$(git -C "$ROOT_DIR" status --short)"
  [ -z "$status" ] || die "worktree is not clean; commit or stash changes before releasing"
}

ensure_main_branch() {
  local branch
  branch="$(current_branch)"
  [ "$branch" = "main" ] || die "releases are only allowed from main; current branch is $branch"
}

ensure_branch_pushed() {
  git -C "$ROOT_DIR" fetch origin main --tags >/dev/null 2>&1 || die "failed to fetch origin/main before release"

  local local_commit remote_commit base_commit
  local_commit="$(git -C "$ROOT_DIR" rev-parse HEAD)"
  remote_commit="$(git -C "$ROOT_DIR" rev-parse origin/main)"
  base_commit="$(git -C "$ROOT_DIR" merge-base HEAD origin/main)"

  if [ "$local_commit" != "$remote_commit" ]; then
    if [ "$base_commit" = "$remote_commit" ]; then
      die "local main has unpushed commits; push origin main before releasing"
    fi
    if [ "$base_commit" = "$local_commit" ]; then
      die "local main is behind origin/main; pull or reset before releasing"
    fi
    die "local main and origin/main have diverged; reconcile before releasing"
  fi
}

ensure_state_matches_repo() {
  local commit branch
  commit="$(current_commit)"
  branch="$(current_branch)"
  [ "$RELEASE_COMMIT" = "$commit" ] || die "current HEAD $commit does not match release commit $RELEASE_COMMIT; reset or finish the existing release state"
  [ "$RELEASE_BRANCH" = "$branch" ] || die "current branch $branch does not match release branch $RELEASE_BRANCH; reset or finish the existing release state"
}

run_make() {
  make -C "$ROOT_DIR" "$@"
}

step_validate() {
  require_cmd git
  require_cmd docker
  require_cmd gh
  require_cmd make
  require_cmd bash
  ensure_main_branch
  ensure_clean_worktree
  ensure_branch_pushed
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated"
  RELEASE_VERSION="$(read_version)"
  validate_semver "$RELEASE_VERSION"
  RELEASE_TAG="v${RELEASE_VERSION}"
  RELEASE_COMMIT="$(current_commit)"
  RELEASE_BRANCH="$(current_branch)"
  RELEASE_REPO="$(repo_slug)"
  [ -n "$RELEASE_REPO" ] || die "could not determine origin repository slug"
  STEP_VALIDATE_DONE=1
  write_state
}

step_tests() {
  ensure_state_matches_repo
  run_make test-unit
  STEP_TESTS_DONE=1
  write_state
}

step_release_images() {
  ensure_state_matches_repo
  run_make bi
  run_make tag-release-images
  run_make push-release-images
  STEP_RELEASE_IMAGES_DONE=1
  write_state
}

step_git_tag() {
  ensure_state_matches_repo
  if git -C "$ROOT_DIR" rev-parse "$RELEASE_TAG" >/dev/null 2>&1; then
    local tagged_commit
    tagged_commit="$(git -C "$ROOT_DIR" rev-list -n 1 "$RELEASE_TAG")"
    [ "$tagged_commit" = "$RELEASE_COMMIT" ] || die "existing tag $RELEASE_TAG points to $tagged_commit instead of $RELEASE_COMMIT"
  else
    git -C "$ROOT_DIR" tag -a "$RELEASE_TAG" -m "Release $RELEASE_TAG"
  fi
  STEP_GIT_TAG_DONE=1
  write_state
}

step_git_push() {
  ensure_state_matches_repo
  git -C "$ROOT_DIR" push origin "$RELEASE_BRANCH"
  git -C "$ROOT_DIR" push origin "$RELEASE_TAG"
  STEP_GIT_PUSH_DONE=1
  write_state
}

step_github_release() {
  ensure_state_matches_repo
  if gh release view "$RELEASE_TAG" --repo "$RELEASE_REPO" >/dev/null 2>&1; then
    :
  else
    gh release create "$RELEASE_TAG" --repo "$RELEASE_REPO" --title "$RELEASE_TAG" --generate-notes
  fi
  STEP_GITHUB_RELEASE_DONE=1
  write_state
}

ask_post_release_bump() {
  if [ -n "${POST_RELEASE_BUMP:-}" ]; then
    echo "$POST_RELEASE_BUMP"
    return 0
  fi

  local choice
  if [ ! -t 1 ] && [ ! -e /dev/tty ]; then
    die "no interactive terminal available for next-version prompt; set POST_RELEASE_BUMP=patch|minor|major|none"
  fi

  {
    echo "[release] choose next version bump after releasing ${RELEASE_VERSION}:"
    echo "  1) patch"
    echo "  2) minor"
    echo "  3) major"
    echo "  4) none"
    printf '[release] selection: '
  } >&2

  if [ -e /dev/tty ]; then
    read -r choice < /dev/tty
  else
    read -r choice
  fi

  case "$choice" in
    1|patch) echo patch ;;
    2|minor) echo minor ;;
    3|major) echo major ;;
    4|none|'') echo none ;;
    *) die "invalid selection: $choice" ;;
  esac
}

step_post_bump() {
  if [ -z "${POST_RELEASE_BUMP:-}" ]; then
    POST_RELEASE_BUMP="$(ask_post_release_bump)"
    write_state
  fi

  if [ "$POST_RELEASE_BUMP" = "none" ]; then
    STEP_POST_BUMP_DONE=1
    write_state
    return 0
  fi

  ensure_state_matches_repo
  NEXT_VERSION="$(bump_version "$RELEASE_VERSION" "$POST_RELEASE_BUMP")"
  printf '%s\n' "$NEXT_VERSION" > "$VERSION_FILE"
  git -C "$ROOT_DIR" add VERSION
  git -C "$ROOT_DIR" commit -m "release: start v${NEXT_VERSION}"
  git -C "$ROOT_DIR" push origin "$RELEASE_BRANCH"
  STEP_POST_BUMP_DONE=1
  write_state
}

resume_release() {
  [ -f "$STATE_FILE" ] || die "no release state found; run start first"
  load_state
  [ "${STEP_VALIDATE_DONE:-0}" = "1" ] || step_validate
  [ "${STEP_TESTS_DONE:-0}" = "1" ] || step_tests
  [ "${STEP_RELEASE_IMAGES_DONE:-0}" = "1" ] || step_release_images
  [ "${STEP_GIT_TAG_DONE:-0}" = "1" ] || step_git_tag
  [ "${STEP_GIT_PUSH_DONE:-0}" = "1" ] || step_git_push
  [ "${STEP_GITHUB_RELEASE_DONE:-0}" = "1" ] || step_github_release
  [ "${STEP_POST_BUMP_DONE:-0}" = "1" ] || step_post_bump
  echo "[release] completed ${RELEASE_TAG}"
}

start_release() {
  if [ -f "$STATE_FILE" ]; then
    die "release state already exists at $STATE_FILE; run resume or reset"
  fi
  RELEASE_VERSION=""
  RELEASE_TAG=""
  RELEASE_COMMIT=""
  RELEASE_BRANCH=""
  RELEASE_REPO=""
  POST_RELEASE_BUMP=""
  NEXT_VERSION=""
  STEP_VALIDATE_DONE=0
  STEP_TESTS_DONE=0
  STEP_RELEASE_IMAGES_DONE=0
  STEP_GIT_TAG_DONE=0
  STEP_GIT_PUSH_DONE=0
  STEP_GITHUB_RELEASE_DONE=0
  STEP_POST_BUMP_DONE=0
  write_state
  resume_release
}

show_status() {
  if [ ! -f "$STATE_FILE" ]; then
    echo "[release] no active release state"
    exit 0
  fi
  load_state
  cat "$STATE_FILE"
}

reset_state() {
  rm -f "$STATE_FILE"
  echo "[release] state cleared"
}

case "$mode" in
  start) start_release ;;
  resume) resume_release ;;
  status) show_status ;;
  reset) reset_state ;;
  *) die "usage: $0 {start|resume|status|reset}" ;;
esac
