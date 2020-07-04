#!/bin/sh

# Generate json.sh path matching string
json_path() {
	if [ ! "${1}" = "-p" ]; then
		printf '"%s"' "${1}"
	else
		printf '%s' "${2}"
	fi
}

# Get string value from json dictionary
get_json_string_value() {
  local filter
  filter="$(printf 's/.*\[%s\]\s*"\([^"]*\)"/\\1/p' "$(json_path "${1:-}" "${2:-}")")"
  sed -n "${filter}"
}

# Get array values from json dictionary
get_json_array_values() {
  grep -E '^\["'"$1"'",[0-9]*\]' | sed -e 's/\[[^\]*\]\s*//g' -e 's/^"//' -e 's/"$//'
}

# Get sub-dictionary from json
get_json_dict_value() {
  local filter
	echo "$(json_path "${1:-}" "${2:-}")"
  filter="$(printf 's/.*\[%s\]\s*\(.*\)/\\1/p' "$(json_path "${1:-}" "${2:-}")")"
  sed -n "${filter}" | jsonsh
}

# Get integer value from json
get_json_int_value() {
  local filter
  filter="$(printf 's/.*\[%s\]\s*\([^"]*\)/\\1/p' "$(json_path "${1:-}" "${2:-}")")"
  sed -n "${filter}"
}

jsonsh() {
  # Modified from https://github.com/dominictarr/JSON.sh
  # Original Copyright (c) 2011 Dominic Tarr
  # Licensed under The MIT License

  throw() {
    echo "$*" >&2
    exit 1
  }

  awk_egrep () {
    local pattern_string=$1

    gawk '{
      while ($0) {
        start=match($0, pattern);
        token=substr($0, start, RLENGTH);
        print token;
        $0=substr($0, start+RLENGTH);
      }
    }' pattern="$pattern_string"
  }

  tokenize () {
    local GREP
    local ESCAPE
    local CHAR

    if echo "test string" | egrep -ao --color=never "test" >/dev/null 2>&1
    then
      GREP='egrep -ao --color=never'
    else
      GREP='egrep -ao'
    fi

    if echo "test string" | egrep -o "test" >/dev/null 2>&1
    then
      ESCAPE='(\\[^u[:cntrl:]]|\\u[0-9a-fA-F]{4})'
      CHAR='[^[:cntrl:]"\\]'
    else
      GREP=awk_egrep
      ESCAPE='(\\\\[^u[:cntrl:]]|\\u[0-9a-fA-F]{4})'
      CHAR='[^[:cntrl:]"\\\\]'
    fi

    local STRING="\"$CHAR*($ESCAPE$CHAR*)*\""
    local NUMBER='-?(0|[1-9][0-9]*)([.][0-9]*)?([eE][+-]?[0-9]*)?'
    local KEYWORD='null|false|true'
    local SPACE='[[:space:]]+'

    # Force zsh to expand $A into multiple words
    local is_wordsplit_disabled=$(unsetopt 2>/dev/null | grep -c '^shwordsplit$')
    if [ $is_wordsplit_disabled != 0 ]; then setopt shwordsplit; fi
    $GREP "$STRING|$NUMBER|$KEYWORD|$SPACE|." | egrep -v "^$SPACE$"
    if [ $is_wordsplit_disabled != 0 ]; then unsetopt shwordsplit; fi
  }

  parse_array () {
    local index=0
    local ary=''
    read -r token
    case "$token" in
      ']') ;;
      *)
        while :
        do
          parse_value "$1" "$index"
          index=$((index+1))
          ary="$ary""$value"
          read -r token
          case "$token" in
            ']') break ;;
            ',') ary="$ary," ;;
            *) throw "EXPECTED , or ] GOT ${token:-EOF}" ;;
          esac
          read -r token
        done
        ;;
    esac
    value=$(printf '[%s]' "$ary") || value=
    :
  }

  parse_object () {
    local key
    local obj=''
    read -r token
    case "$token" in
      '}') ;;
      *)
        while :
        do
          case "$token" in
            '"'*'"') key=$token ;;
            *) throw "EXPECTED string GOT ${token:-EOF}" ;;
          esac
          read -r token
          case "$token" in
            ':') ;;
            *) throw "EXPECTED : GOT ${token:-EOF}" ;;
          esac
          read -r token
          parse_value "$1" "$key"
          obj="$obj$key:$value"
          read -r token
          case "$token" in
            '}') break ;;
            ',') obj="$obj," ;;
            *) throw "EXPECTED , or } GOT ${token:-EOF}" ;;
          esac
          read -r token
        done
      ;;
    esac
    value=$(printf '{%s}' "$obj") || value=
    :
  }

  parse_value () {
    local jpath="${1:+$1,}${2:-}" isleaf=0 isempty=0 print=0
    case "$token" in
      '{') parse_object "$jpath" ;;
      '[') parse_array  "$jpath" ;;
      # At this point, the only valid single-character tokens are digits.
      ''|[!0-9]) throw "EXPECTED value GOT ${token:-EOF}" ;;
      *) value=$token
         # replace solidus ("\/") in json strings with normalized value: "/"
         value=$(echo "$value" | sed 's#\\/#/#g')
         isleaf=1
         [ "$value" = '""' ] && isempty=1
         ;;
    esac
    [ "$value" = '' ] && return
    [ -z "$jpath" ] && return # do not print head

    printf "[%s]\t%s\n" "$jpath" "$value"
    :
  }

  parse () {
    read -r token
    parse_value
    read -r token
    case "$token" in
      '') ;;
      *) throw "EXPECTED EOF GOT $token" ;;
    esac
  }

  tokenize | parse
}
# vi: expandtab sw=2 ts=2
