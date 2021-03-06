#! /usr/bin/env bash

# Common, useful methods for BASH scripts. The callee is responsible
# for setting the following variables:
#
# * pid_file
# * log
#
# by tkj@vizrt.com

debug=0

function common_bashing_is_loaded() {
  echo 1
}

function get_seconds_since_start() {
  local seconds="n/a"
  
  if [ -n "$pid_file" -a -r "$pid_file" ]; then
    now=`date +%s`
    started=`stat -c %Y $pid_file`
    seconds=$(( now - started ))
  fi
  
  echo "$seconds"
}

function get_id() {
  if [ -n "$id" ]; then
    echo $id
    return
  fi
  
  local timestamp=$(get_seconds_since_start)
  echo "[$(basename $0)-${timestamp}]"
}

function debug() {
  if [ $debug -eq 1 ]; then
    echo "[$(basename $0)-debug]" "$@"
  fi
}

function print() {
  if [[ "$quiet" == 1 ]]; then
    echo $@ | fmt
    return
  fi

  # we break the text early to have space for the ID.
  local id="$(get_id) "
  local text_width=$(( 80 - $(echo $id | wc -c) ))
  echo $@ | fmt --width $text_width | sed "s~^~${id}~g"
}

function printne() {
  echo -ne $(get_id) $@
}

## Will log all messages past to it.
##
## - If the parent directory of the log file doesn't exist, the method
## will try to create it.
##
## - If the log file doesn't exist, the method will try to create it.
##
## $@ :: list of strings
function log() {
  if [ -z $log ]; then
    return
  fi

  # cannot use run wrapper her, it'll trigger an eternal loop.
  fail_safe_run mkdir -p $(dirname $log)
  fail_safe_run touch $log
  echo $(get_id) $@ >> $log
}

function print_and_log() {
  print "$@"
  log "$@"
}

function log_call_stack() {
  log "Call stack (top most is the last one, main is the first):"

  # skipping i=0 as this is log_call_stack itself
  for ((i = 1; i < ${#FUNCNAME[@]}; i++)); do
    echo -n  ${BASH_SOURCE[$i]}:${BASH_LINENO[$i-1]}:${FUNCNAME[$i]}"()" >> $log
    if [ -e ${BASH_SOURCE[$i]} ]; then
      echo -n " => " >> $log
      sed -n "${BASH_LINENO[$i-1]}p" ${BASH_SOURCE[$i]} | \
        sed "s#^[ \t]*##g" >> $log
    else
      echo "" >> $log
    fi
  done
}

function remove_pid_and_exit_in_error() {
  if [ -e $pid_file ]; then
    rm $pid_file
  fi

  # this method is also used from bootstrapping methods in scripts
  # where the log file may not yet exist, hence, we test for its
  # existence here before logging the call/stack trace.
  if [ -w $log ]; then
    log_call_stack
  fi
  
  exit 1
}

function exit_on_error() {
  local code=$?
  if [ ${code} -gt 0 ]; then
    print_and_log "The command [${@}] run as user $USER $(red FAILED)" \
      "(the command exited with code ${code}), I'll exit now :-("
    print "See $log for further details."
    remove_pid_and_exit_in_error
  fi
}

function run() {
  "${@}" 1>>$log 2>>$log
  exit_on_error $@
}

function fail_safe_run() {
  "${@}"
  if [ $? -gt 0 ]; then
    echo $(basename $0) $(red FAILED) "executing the command [$@]" \
      "as user" ${USER}"." \
      $(basename $0) "will now exit." | \
      fmt
    exit 1
  fi
}

## Returns 1 if the passed argument is a number, 0 if not.
## $1: the value you wish to test.
function is_number() {
  for (( i = 0; i < ${#1}; i++ )); do
    if [ $(echo ${1:$i:1} | grep [0-9] | wc -l) -lt 1 ]; then
      echo 0
      return
    fi
  done
  
  echo 1
}

## Returns an escaped string useful for sed and other BASH commands.
##
## $1 : the string
function get_escaped_bash_string() {
  local result=$(echo $1 | \
    sed -e 's/\$/\\$/g' \
    -e 's/\*/\\*/g' \
    -e 's#/#\\/#g' \
    -e 's/\./\\./g')
  echo $result
}

# Munin nodes need the IP of the munin gatherer to be escaped. Hence
# this function.
# 
# Parameters:
#
# $1 : the IP
function get_perl_escaped() {
  local escaped_input=$(
    echo $1 | sed 's/\./\\./g'
  )
  echo "^${escaped_input}$"
}

## Returns the inputted string(s) as red
##
## $1: input string
function red() {
  echo -e "\E[37;31m\033[1m${@}\033[0m"
}

## Returns the inputted string(s) as green
##
## $1: input string
function green() {
  echo -e "\E[37;32m\033[1m${@}\033[0m"
}

## Returns the inputted string(s) as yellow
##
## $1: input string
function yellow() {
  echo -e "\E[37;33m\033[1m${@}\033[0m"
}

function blue() {
  echo -e "\E[37;34m\033[1m${@}\033[0m";
};

## $1: full path to the file.
function get_base_dir_from_bundle()
{
    local file_name=$(basename $1)
    suffix=${file_name##*.}
    
    if [ ${suffix} = "zip" ]; then
        # we'll look inside the archive to determine the base_dir
        file_name=$(
            unzip -t $1 2>>$log | \
                awk '{print $2}' | \
                cut -d'/' -f1 | \
                sort | \
                uniq | \
                grep -v errors | \
                grep [a-z]
        )
    else
        for el in .tar.gz .tar.bz2 .zip; do
            file_name=${file_name%$el}
        done
    fi

    debug "get_base_dir_from_bundle file_name="$file_name $1

    echo $file_name
}

## Will assert that all the passed variable names are set, if not, it
## will exit in error.
## 
## $@ : a list of variable names
##
## Requires $conf_file to be set.
function ensure_variable_is_set() {
  local requirements_failed=0
  
  for el in $@; do
    if [ -n "$(eval echo $`echo $el`)" ]; then
      continue
    fi
    
    print_and_log "You need to specifiy '$el' in your $conf_file"
    requirements_failed=1
  done
  
  if [ $requirements_failed -eq 1 ]; then
    remove_pid_and_exit_in_error
  fi
}

## $1 : the archive to check, must be a local file
function is_archive_healthy() {
  if [[ "$1" == *".ear" || "$1" == *".zip" ]]; then
    unzip -t $1 2>/dev/null 1>/dev/null
  elif [[ "$1" == *".tar.gz" ]]; then
    tar tzf $1 2>&1 > /dev/null
  else
    echo 0
    return
  fi
  
  if [ $? -eq 0 ]; then
    echo 1
  else
    echo 0
  fi
}

## $1 :: the archive
## $2 :: optionally, the target directory
function extract_archive() {
  if [[ "$1" == *".tar.gz" || "$1" == *".tgz" ]]; then
    if [[ -n "$2" && -d "$2" ]]; then
      run tar xzf $1 -C $2
    else
      run tar xzf $1
    fi
  elif [[ "$1" == *".tar.bz2" ]]; then
    if [[ -n "$2" && -d "$2" ]]; then
      run tar xjf $1 -C $2
    else
      run tar xjf $1
    fi
  elif [[ "$1" == *".zip" ]]; then
    if [[ -n "$2" && -d "$2" ]]; then
      run unzip -q $1 -d $2
    else
      run unzip -q $1
    fi
  fi
}

# the next steps printed when the user has installed his/her
# components.
next_steps=()

## Parameters:
## $1 : your added line
function add_next_step() {
  next_steps[${#next_steps[@]}]="$@"
  return
  
  if [ -n "$next_steps" ]; then
    next_steps=${next_steps}$'\n'"[$(basename $0)] "${1}
  else
    next_steps="[$(basename $0)] $@"
  fi
}

function print_next_step_list() {
  for (( i = 0; i < ${#next_steps[@]}; i++ )); do
    print "  - " ${next_steps[$i]}
  done
}

## Method will return 1 if the user/pass is unauthorized to access the
## URL in question. Hence, a 0 means that the user CAN access the URL.
## $1 user
## $2 pass
## $3 URL
function is_unauthorized_to_access_url() {
  curl --silent --connect-timeout 20 --head  --user ${1}:${2} ${3} | \
    head -1 | \
    grep "401 Unauthorized" | \
    wc -l
}

## Will return 1 if the user can access the URL.
## $1 user
## $2 pass
## $3 URL
function is_authorized_to_access_url() {
  curl --silent --connect-timeout 20 --head --user ${1}:${2} ${3} | \
    head -1 | \
    grep "200 OK" | \
    wc -l
}


## $1 the string to which you want to remove any leading white spaces.
function ltrim() {
  echo $1 | sed 's/^[ ]*//g'
}

## $1    : the character on to wich to split it
## $@[1] : the rest of the arguments is the string(s) you want to have
##         splitted.
function split_string() {
  if [[ -z $1 || -z $2 ]]; then
    return
  fi
  
  local delimeter=$1
  shift;
  
  local old_ifs=$IFS
  IFS=$delimeter
  read splitted_string <<< $@
  IFS=$old_ifs

  echo $splitted_string
}

## Creates $1 PID file if possible
function create_pid_if_doesnt_exist() {
  if [ -z $1 ]; then
    return
  elif [ -e $1 ]; then
    return
  fi    
  
  local dir=$(dirname $1)

  # since this method can be called really early in scripts, we cannot
  # use the run wrapper here.
  fail_safe_run mkdir -p $(dirname $1)
  fail_safe_run touch $1
}

function remove_pid_if_exists() {
  if [ -z $1 ]; then
    return
  elif [ ! -e $1 ]; then
    return
  fi
  
  fail_safe_run rm $1
}
