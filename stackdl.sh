#!/bin/sh

[ ! "$1" ] && echo "Usage: $0 https://something.stackstorage.com/s/blahblahblah" && exit 1

useragent="${USER_AGENT:-Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/83.0.4103.61 Safari/537.36}"
accept='text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9'

printargs() {
  for arg in "$@"; do
    printf "'%s' " "${arg}"
  done
  echo
}

dotrace() {
  [ "$STACKDL_DEBUG" ] && printargs "$@"
  "$@"
}

request() {
  arg=--show-error
  [ "$STACKDL_DEBUG" ] && arg=--verbose
  dotrace curl \
    "${arg}" \
    -H 'Connection: keep-alive' \
    -H 'Cache-Control: max-age=0' \
    -H 'Upgrade-Insecure-Requests: 1' \
    -H "User-Agent: ${useragent}" \
    -H 'Sec-Fetch-User: ?1' \
    -H 'Accept-Language: en-US,en;q=0.9' \
    --compressed \
    "$@"
}

download() {
  jar="$2"
  base="$(echo "$1" | grep -o 'http[s]\?://[^/]\+/')" || return
  id="$(echo "$1" | sed 's|http[s]\?://[^/]\+/s/||g' | sed 's|/.*||g')" || return

  [ "$STACKDL_DEBUG" ] && echo "=== downloading file ${id} from ${base}"
  [ "$STACKDL_DEBUG" ] && echo "=== initializing session..."

  csrf_token=$(
    request --silent --url "$1" --cookie-jar "${jar}" --junk-session-cookies \
      -H "Accept: ${accept}" \
      -H 'Sec-Fetch-Site: none' \
      -H 'Sec-Fetch-Mode: navigate' \
      -H 'Sec-Fetch-Dest: document' |
    sed -n 's/^.*<meta name="csrf-token" content="\([^"]*\)">.*$/\1/p'
  ) || return

  [ "$STACKDL_DEBUG" ] && echo "csrf token: ${csrf_token}"

  tstamp="$(( $(date +%s) * 1000 ))"
  filename=$(
    request --silent \
      --url "${base}public-share/${id}/list/?public=true&token=${id}&type=file&_=${tstamp}" \
      -H 'Accept: application/json, text/javascript, */*; q=0.01' \
      -H 'Omit-Authentication-Header: true' \
      -H 'Sec-Fetch-Site: same-origin' \
      -H 'Sec-Fetch-Mode: cors' \
      -H 'Sec-Fetch-Dest: empty' \
      -H "X-CSRF-Token: ${csrf_token}" \
      -H 'X-Requested-With: XMLHttpRequest' \
      -H 'Content-Type: application/json' \
      -H "Referer: $1" \
      --cookie "${jar}" |
    sed -n 's/^.*"path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*$/\1/p'
  )
  filename="./${filename}"

  echo "=== downloading to ${filename}"
  mkdir -p "$(dirname "${filename}")" || exit
  [ -f "${filename}" ] && echo "file already exists. skipping" && exit 0

  if [ "$STACKDL_DEBUG" ]; then
    echo
    echo "cookies:"
    grep '^[^#].*' < "${jar}"
    echo
  fi

  [ "${csrf_token}" ] || return 1

  request --url "${base}public-share/${id}/download/" \
    -H "Accept: ${accept}" \
    -H "Origin: ${base}" \
    -H 'Sec-Fetch-Site: same-origin' \
    -H 'Sec-Fetch-Mode: navigate' \
    -H 'Sec-Fetch-Dest: iframe' \
    -H "Referer: $1" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --cookie "${jar}" \
    --data-raw "archive=zip&all=false&CSRF-Token=${csrf_token}&paths%5B%5D=%2F" \
    --output "${filename}"  || return
}


jar="$(mktemp)" || exit
download "$1" "${jar}"
res=$?
rm "${jar}"
exit ${res}
