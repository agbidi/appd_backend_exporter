#!/usr/bin/env bash

# filename          : appd_backend_exporter.sh
# description       : A script that extracts backends of AppDynamics Applications via the AppD API.
# author            : Alexander Agbidinoukoun
# email             : aagbidin@cisco.com
# date              : 2025/25/03
# version           : 0.1
# usage             : ./Usage: appd_backend_exporter.sh [-h] [-v] -c config_file
# notes             : 
#   0.1: first release
# 
#==============================================================================

set -Euo pipefail

#
# Prerequisites
#

# is jq installed?
if ! command -v jq >/dev/null; then
  echo "Please install jq to use this tool (sudo yum install -y jq)"
  exit 1
fi

#
# Global Variables
#
PREV_IFS=$IFS
MY_IFS='|'
csv_separator=','
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
log_file=$(echo ${BASH_SOURCE[0]} | sed 's/sh$/log/')
timestamp=$(date +%Y%m%d%H%M%S)
appd_oauth_token=''
appd_cookie_path=.appd_cookie

#
# Template Functions
#

usage() {
  cat << EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v] -c config_file

A script that extracts backends of AppDynamics Applications.

Available options:

-h, --help        Print this help and exit
-v, --verbose     Print script debug info
-c, --config      Path to config file

EOF
  exit
}

setup_colors() {
  if [ -t 2 ] && [ -z "${NO_COLOR-}" ] && [ "${TERM-}" != "dumb" ]; then
    NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[0;33m'
  else
    NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
  fi
}

log() {
  echo >&2 -e "${1-}" >> ${log_file}
}

msg() {
  echo >&2 -e "${1-}"
}

die() {
  local msg=$1
  local code=${2-1} # default exit status 1
  local date=$(date '+%Y-%m-%d %H:%M:%S')
  msg "${date}: ${RED}ERROR:${NOFORMAT} $msg"
  log "${date}: ERROR: $msg"
  exit $code
}

warn() {
  local msg=$1
  local date=$(date '+%Y-%m-%d %H:%M:%S')
  msg "${date}: ${YELLOW}WARN:${NOFORMAT} $msg"
  log "${date}: WARN: $msg"
}

info() {
  local msg=$1
  local date=$(date '+%Y-%m-%d %H:%M:%S')
  msg "${date}: ${GREEN}INFO:${NOFORMAT} $msg"
  log "${date}: INFO: $msg"
}

debug() {
  local msg=$1
  local date=$(date '+%Y-%m-%d %H:%M:%S')
  msg "${date}: ${PURPLE}DEBUG:${NOFORMAT} $msg"
  log "${date}: DEBUG: $msg"
}

parse_params() {
  # default values of variables set from params

  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) set -x ;;
    --no-color) NO_COLOR=1 ;;
    -c | --config)
      config="${2-}"
      shift
      ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  args=("$@")

  # check required params and arguments
  [ -z "${config-}" ] &&  warn "Missing required parameter: config" && usage

  #[ ${#args[@]} -eq 0 ] && die "Missing script arguments"

  return 0
}

setup_colors

parse_params "$@"

#
# Start script logic here
#

#
# Utility Functions
#

my_curl() {
  auth=$1; shift

  x_csrf_header=''
  [ ! -z "${x_csrf_token-}" ] && x_csrf_header="-H X-CSRF-TOKEN:$x_csrf_token"

  if [ "$auth" == "true" -a ! -z "${appd_oauth_token-}" ]; then
    curl -s -H "Authorization:Bearer $appd_oauth_token" ${appd_proxy} "$@"
  elif [ "$auth" == "true" -a ! -z "${appd_api_password-}" ]; then
    curl -s -u "${appd_api_user}@${appd_account}:${appd_api_password}" ${appd_proxy} --cookie $appd_cookie_path $x_csrf_header "$@"
  else
    curl -s "$@"
  fi
}

get_appd_oauth_token() {
  # curl request
  response=$(my_curl true -X POST -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=${appd_api_user}@${appd_account}&client_secret=${appd_api_secret}" \
  ${appd_url}/controller/api/oauth/access_token)
  # validate response
  [ -z "$(echo $response | grep "access_token\":")" ] && die "Could not retrieve oauth token: $response"

  # extract token from response
  echo -n $response | sed 's/[[:blank:]]//g' | sed -E 's/^.*"access_token":"([^"]*)".*$/\1/'
}

get_appd_cookie() {

  # curl request
  my_curl true --cookie-jar $appd_cookie_path ${appd_url}/controller/auth?action=login
  
  x_csrf_token="$(grep X-CSRF-TOKEN $appd_cookie_path | sed 's/^.*X-CSRF-TOKEN[[:blank:]]*\(.*\)$/\1/')"

  # validate response
  [ -z "$x_csrf_token" ] && warn "Could not retrieve AppDynamics login cookie"
}


init() {
  # source config file
  [ ! -r $config ] && die "$config is not readable"
  . $config

  # check required config entries
  [ -z "${appd_url-}" ] && die "Missing required config entry: appd_url"
  [ -z "${appd_account-}" ] && die "Missing required config entry: appd_account"
  [ -z "${appd_api_user-}" ] && die "Missing required config entry: appd_api_user"
  [ -z "${appd_api_password-}" ] && [ -z "${appd_api_secret-}" ] && die "Missing required config entry: appd_api_password or appd_api_secret"
  [ -z "${application_names-}" ] && die "Missing required config entry: application_names"
  [ -z "${backend_type-}" ] && die "Missing required config entry: backend_type"
  [ -z "${skip_thread_tasks-}" ] && die "Missing required config entry: search_thread_tasks"
  [ -z "${output_file-}" ] && die "Missing required config entry: output_file"

  # proxy
  [ ! -z "${appd_proxy-}" ] && appd_proxy="--proxy ${appd_proxy}"

  # display key config
  info "Running AppDynamics Backend Exporter"
  info "Using AppDynamics URL: ${appd_url}"
  info "Using application name regex: ${application_names}"
  info "Using backend type regex: ${backend_type}"

  # retrieve appd token
  if [ ! -z "${appd_api_secret-}" ]; then
    info "Retrieving AppDynamics oauth token at ${appd_url}"
    appd_oauth_token=$(get_appd_oauth_token)
  fi

  return 0
}

trap cleanup SIGINT SIGTERM EXIT
cleanup() {
  trap - SIGINT SIGTERM EXIT
  # do clean up here
}

#
# Export functions
#

get_applications_info() {

  url="${appd_url}/controller/rest/applications?output=json"
  regex=$application_names

  response=$(my_curl true $url)
  infos=$(jq ".[] | select(.name | test(\"$regex\")) | .name,.id" <<<$response | tr -d '"'| tr -d '\')

  res=""
  last_info='id'
  app_count=0

  PREV_IFS=$IFS
  IFS=$'\n'
  for info in ${infos}; do
    if [ `echo ${info} | grep -E '^[0-9]+$'` ] ; then  # app id
      res+="=${info}$MY_IFS"
      last_info='id'
      app_count=$(($app_count + 1))
    else
      if [ $last_info == 'id' ]; then # app name
        res+="${info}"
      else # app name with space
        res+=" ${info}"
      fi
      last_info='name'
    fi
  done
  IFS=$PREV_IFS

  info "Found $app_count applications matching criteria."

  echo -n ${res}
}

get_metric_entities()
{
  app_id=$1
  path=$2
  name_regex=$3
  type_regex=$4
  
  # sanitize path
  path=$(echo -n "$path" | sed 's/ /%20/g')

  url="${appd_url}/controller/rest/applications/${app_id}/metrics?output=json&metric-path=${path}"
  response=`my_curl true $url`

  # select entities that match criteria
  res=$(jq ".[] | select(.name | test(\"$name_regex\")) | select(.type | test(\"$type_regex\")) | .name" <<<$response | tr -d '"'| tr -d '\'| tr '\n' $MY_IFS)

  echo -n ${res}
}

extract_backends() {

  # retrieve applications names & ids
  applications_info=$(get_applications_info)

  # loop over applications
  PREV_IFS=$IFS
  IFS=$MY_IFS
  for info in ${applications_info}; do
    IFS=$PREV_IFS
    app=$(echo ${info} | cut -d '=' -f 1)
    id=$(echo ${info} | cut -d '=' -f 2)

    info "Exporting backends for application $app ($id)"
    tiers=$(get_metric_entities $id "Overall Application Performance" '.*' 'folder')
    # loop over tiers
    PREV_IFS=$IFS
    IFS=$MY_IFS
    for tier in ${tiers}; do
      IFS=$PREV_IFS
      info "Exporting backends for tier $tier"

      # retrieve synchronously called backends
      backends=$(get_metric_entities $id "Overall Application Performance|$tier|External Calls" "$backend_type" 'folder')

      # retrieve asynchronously called backends
      if [ "$skip_thread_tasks" != "true" ]; then
        thread_tasks=$(get_metric_entities $id "Overall Application Performance|$tier|Thread Tasks" '.*' 'folder')
        # loop over thread_tasks
        PREV_IFS=$IFS
        IFS=$MY_IFS
        for thread_task in ${thread_tasks}; do
          IFS=$PREV_IFS
          backends+=$(get_metric_entities $id "Overall Application Performance|$tier|Thread Tasks|$thread_task|External Calls" "$backend_type" 'folder')
        done
        IFS=$PREV_IFS
      fi

      # loop over backends
      PREV_IFS=$IFS
      IFS=$MY_IFS
      backend_info=''
      backend_count=0
      for backend in ${backends}; do
        IFS=$PREV_IFS

        backend_name=$(echo "$backend" | sed -E 's/.* to [^-]* - (.*)$/\1/')
        # skip if we have already added backend
        [ "$skip_thread_tasks" != "true" ] && echo "$backend_info" | grep -q "$backend_name" && continue
        back_type=$(echo "$backend" | sed -E 's/Call-([A-Za-z]*) .*$/\1/')
        backend_info+="$app,$tier,$back_type,$backend_name\n"
        backend_count=$(($backend_count + 1))
      done
      # output backends
      info "Found $backend_count backends."
      echo -n -e "$backend_info" >> $output_file
      # debug "$backend_info"
      IFS=$PREV_IFS
    done
    IFS=$PREV_IFS
  done
  IFS=$PREV_IFS

  return 0
}

#
# Main
#

init
echo 'application_name,tier_name,backend_type,backend_name' > $output_file
extract_backends