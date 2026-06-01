#!/usr/bin/env bash
# PreToolUse hook for Bash — blocks DESTRUCTIVE / CREATIVE datastore operations
# against DynamoDB, S3, Redis, and MongoDB via their CLIs. Reads (describe,
# list, scan, query, get, download, dump, export) are allowed; writes and
# deletes are blocked even in dev/staging. See ../../../STANDARDS.md
# "Safety guardrails".
#
# Non-zero exit = block. Honors a HUMAN-exported CLAUDE_SAFETY_OVERRIDE=1.

set -euo pipefail

LOG_DIR="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}/base-tools"
mkdir -p "$LOG_DIR"

payload="$(cat)"
cmd="$(echo "$payload" | jq -r '.tool_input.command // ""')"

if [ "${CLAUDE_SAFETY_OVERRIDE:-0}" = "1" ]; then
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[$ts] block-datastore-mutations OVERRIDE: $cmd" >> "$LOG_DIR/safety-override.log"
  exit 0
fi

reject() {
  echo "claude-base SAFETY guardrail: $1" >&2
  echo "" >&2
  echo "Datastores (DynamoDB, S3, Redis, Mongo) are read-only for Claude." >&2
  echo "Reads pass; creating/updating/deleting records, buckets, configs, or" >&2
  echo "DB files needs a human — even in dev and staging." >&2
  echo "" >&2
  echo "Ask a human, or — if you ARE the human — export CLAUDE_SAFETY_OVERRIDE=1" >&2
  echo "in your shell (logged & audited). Do NOT inline it or bypass the hook." >&2
  exit 1
}

# --- DynamoDB ---------------------------------------------------------------
ddb_mut='(create-table|delete-table|update-table|put-item|delete-item|update-item|batch-write-item|transact-write-items|create-backup|delete-backup|restore-table-[a-z-]+|update-time-to-live|update-continuous-backups|tag-resource|untag-resource|create-global-table|update-global-table)'
if [[ "$cmd" =~ aws[[:space:]]+dynamodb[[:space:]]+${ddb_mut}([[:space:]]|$) ]]; then
  reject "DynamoDB mutating command blocked."
fi

# --- S3 (high level) --------------------------------------------------------
if [[ "$cmd" =~ aws[[:space:]]+s3[[:space:]]+(rb|rm|mv)([[:space:]]|$) ]]; then
  reject "S3 bucket/object removal or move (rb/rm/mv) blocked."
fi
if [[ "$cmd" =~ aws[[:space:]]+s3[[:space:]]+sync ]] && [[ "$cmd" =~ (^|[[:space:]])--delete([[:space:]]|$) ]]; then
  reject "S3 'sync --delete' can remove objects — blocked."
fi
# `aws s3 cp <local> s3://...` is an upload (creates objects). Block when the
# DESTINATION (last positional) is an s3:// URI; downloads (s3:// source) pass.
# Options that take a value (e.g. --exclude '*.txt', --sse, --metadata) must NOT
# be mistaken for positionals, or an upload could slip past by appending one
# after the destination. We therefore skip the value following any non-boolean
# option; a small allowlist of store-true flags do NOT consume a value.
if [[ "$cmd" =~ aws[[:space:]]+s3[[:space:]]+cp([[:space:]]|$) ]]; then
  read -ra _toks <<< "$cmd"
  _seen_aws=0 _seen_s3=0 _seen_cp=0
  _skip_next=0
  _pos=()
  # store-true flags for `aws s3 cp` — these do not take a following value.
  _bool_re='^--(dryrun|quiet|recursive|no-progress|follow-symlinks|no-follow-symlinks|no-guess-mime-type|only-show-errors|ignore-glacier-warnings|force-glacier-transfer|debug|no-sign-request|no-verify-ssl|no-paginate)$'
  for t in "${_toks[@]}"; do
    if [ "$_seen_cp" = 1 ]; then
      if [ "$_skip_next" = 1 ]; then _skip_next=0; continue; fi
      if [[ "$t" == -* ]]; then
        # A long/short option with no inline `=value` consumes the next token
        # as its value, unless it is a known boolean (store-true) flag.
        if [[ "$t" != *=* ]] && ! [[ "$t" =~ $_bool_re ]]; then _skip_next=1; fi
        continue
      fi
      _pos+=("$t")
      continue
    fi
    if [ "$_seen_aws" = 1 ] && [ "$_seen_s3" = 1 ] && [ "$t" = "cp" ]; then _seen_cp=1; continue; fi
    if [ "$_seen_aws" = 1 ] && [ "$t" = "s3" ]; then _seen_s3=1; continue; fi
    if [ "$t" = "aws" ]; then _seen_aws=1; _seen_s3=0; fi
  done
  if [ "${#_pos[@]}" -ge 1 ]; then
    _last="${_pos[$(( ${#_pos[@]} - 1 ))]}"
    if [[ "$_last" == s3://* ]]; then
      reject "S3 upload ('aws s3 cp <local> s3://...') creates objects — blocked."
    fi
  fi
fi

# --- S3 (api level) ---------------------------------------------------------
s3api_mut='(create-bucket|delete-bucket|delete-bucket-[a-z-]+|put-bucket-[a-z-]+|delete-object|delete-objects|put-object|put-object-[a-z-]+|copy-object|restore-object|create-multipart-upload|complete-multipart-upload|abort-multipart-upload)'
if [[ "$cmd" =~ aws[[:space:]]+s3api[[:space:]]+${s3api_mut}([[:space:]]|$) ]]; then
  reject "S3 (s3api) mutating command blocked."
fi

# --- Redis ------------------------------------------------------------------
# redis-cli invoking a write/destructive command. Case-insensitive; the command
# may be quoted or passed as args.
if [[ "$cmd" =~ redis-cli ]]; then
  redis_mut='(FLUSHALL|FLUSHDB|DEL|UNLINK|SET|SETEX|SETNX|GETSET|MSET|MSETNX|APPEND|SETRANGE|GETDEL|HSET|HMSET|HSETNX|HDEL|HINCRBY|LPUSH|RPUSH|LPOP|RPOP|LSET|LREM|LINSERT|SADD|SREM|SPOP|SMOVE|ZADD|ZREM|ZINCRBY|INCR|DECR|INCRBY|DECRBY|EXPIRE|PEXPIRE|EXPIREAT|PERSIST|RENAME|RENAMENX|MOVE|COPY|RESTORE|MIGRATE|SWAPDB|PFADD|PFMERGE|GEOADD|XADD|XDEL|SETBIT)'
  if echo "$cmd" | grep -qiE "(^|[^A-Za-z])redis-cli([^A-Za-z].*)?[^A-Za-z]${redis_mut}([^A-Za-z]|$)"; then
    reject "Redis write/destructive command via redis-cli blocked."
  fi
  if echo "$cmd" | grep -qiE "(^|[^A-Za-z])CONFIG[[:space:]]+SET([^A-Za-z]|$)|(^|[^A-Za-z])SCRIPT[[:space:]]+FLUSH([^A-Za-z]|$)"; then
    reject "Redis CONFIG SET / SCRIPT FLUSH via redis-cli blocked."
  fi
fi

# --- MongoDB ----------------------------------------------------------------
if [[ "$cmd" =~ (^|[[:space:]])mongoimport([[:space:]]|$) ]] || [[ "$cmd" =~ (^|[[:space:]])mongorestore([[:space:]]|$) ]]; then
  reject "MongoDB write tool (mongoimport/mongorestore) blocked."
fi
if [[ "$cmd" =~ (^|[[:space:]])(mongo|mongosh)([[:space:]]|$) ]]; then
  mongo_mut='(dropDatabase|\.drop\(|createCollection|renameCollection|deleteOne|deleteMany|\.remove\(|insertOne|insertMany|\.insert\(|updateOne|updateMany|\.update\(|replaceOne|bulkWrite|findOneAndDelete|findOneAndUpdate|findOneAndReplace|createIndex|dropIndex)'
  if echo "$cmd" | grep -qE "$mongo_mut"; then
    reject "MongoDB destructive/write operation in mongo/mongosh blocked."
  fi
fi

exit 0
