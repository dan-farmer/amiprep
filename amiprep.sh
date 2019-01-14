#!/bin/bash
# 
# Author: Dan Farmer
# License: GPL3
#   See the "LICENSE" file for full details
#
# Prepare an AWS EC2 instance for AMI generation by removing installed software
# agents and related config
#
# WARNING: This will deliberately leave agents and instance configuration
#          broken, so should ONLY be run on a throw-away instance that is
#          intended solely for AMI preparation

function main {
  handle_args "$@"
  detect_distribution
  compile_services_packages_paths
  stop_services
  remove_packages
  remove_paths
  cleanup
  finish 0
}

function handle_args {
  while getopts ":htd:a:" OPT; do
    case "$OPT" in
      h) print_usage; finish 0;;
      t) DEBUG="log DEBUG ";; # Test/debug mode; disruptive commands will be prefixed
      d) DISTRIBUTION_FAMILY="$OPTARG";;  # Override distribution detection
      a) AGENTS_TO_REMOVE="$OPTARG";; # Comma-separated list of agents to remove
      \?) log ERROR "Invalid option: -$OPT"; print_usage; finish 1;;
      :) log ERROR "Option -$OPT requires an argument"; print_usage; finish 1;;
    esac
  done

  if [[ ! -v AGENTS_TO_REMOVE ]]; then
    # Default list of agents to remove
    AGENTS_TO_REMOVE="codedeploy,cfn,cloudwatch"
  fi

  IFS=',' read -ra AGENTS <<< "$AGENTS_TO_REMOVE"
  for AGENT in "${AGENTS[@]}"; do
    case "$AGENT" in
      ssm) REMOVE_SSM=true;;
      codedeploy) REMOVE_CODEDEPLOY=true;;
      cfn) REMOVE_CFN=true;;
      cloudwatch) REMOVE_CW=true;;
      *) log ERROR "Option -a requires a list of agents to remove"
         log ERROR "Valid agents: ssm,codedeploy,cfn,cloudwatch"
         print_usage; finish 1;;
    esac
  done
}

function detect_distribution {
  if [[ -v DISTRIBUTION_FAMILY ]]; then
    # $DISTRIBUTION_FAMILY was set manually; check it
    if [[ "$DISTRIBUTION_FAMILY" != "rh" ]] && [[ "$DISTRIBUTION_FAMILY" != "deb" ]]; then
      log ERROR "Distribution family should be one of \"rh\", \"deb\""
      print_usage; finish 2
    fi
  else
    # $DISTRIBUTION_FAMILY was not set; attempt to detect automatically
    if (/bin/grep -qE "Amazon|CentOS|Red Hat" /etc/os-release); then
      DISTRIBUTION_FAMILY="rh"
    elif (/bin/grep -qE "Debian|Ubuntu" /etc/os-release); then
      DISTRIBUTION_FAMILY="deb"
    else
      log ERROR "Couldn't detect a supported Linux distribution"
      finish 10
    fi
  fi
}

function compile_services_packages_paths {
  SERVICES=()
  PACKAGES=()
  PATHS=()

  # cloud-init & common locations
  PATHS+=(/home/{ec2-user,centos,ubuntu,admin}/aws*
          /home/{ec2-user,centos,ubuntu,admin}/.bash_history
          /var/lib/cloud
          /var/log/amazon
          /var/log/cloud*
          /var/log/aws*
          /var/tmp/*
          /tmp/*)
  if [[ $DISTRIBUTION_FAMILY == "rh" ]]; then
    SERVICES+=(crond)
  elif [[ $DISTRIBUTION_FAMILY == "deb" ]]; then
    SERVICES+=(cron)
  fi

  if [[ $REMOVE_SSM = true ]]; then
    PACKAGES+=(amazon-ssm-agent)
  fi

  if [[ $REMOVE_CODEDEPLOY = true ]]; then
    PACKAGES+=(codedeploy-agent)
    PATHS+=(/etc/codedeploy-agent/
            /opt/codedeploy-agent/)
  fi

  if [[ $REMOVE_CFN = true ]]; then
    PATHS+=(/etc/cfn/
            /var/log/cfn*
            /var/lib/cfn*)
  fi

  if [[ $REMOVE_CW = true ]]; then
    PACKAGES+=(amazon-cloudwatch-agent)
    PATHS+=(/opt/aws/amazon-cloudwatch-agent/
            /tmp/cwagentpkg/)
  fi
}

function stop_services {
  for ((i = 0; i < ${#SERVICES[@]}; i++)); do
    log INFO "Stopping service ${SERVICES[$i]}"
    $DEBUG /usr/sbin/service "${SERVICES[$i]}" stop
  done
}

function remove_packages {
  log INFO "Removing packages:" "${PACKAGES[@]}"
  if [[ "$DISTRIBUTION_FAMILY" == "rh" ]]; then
    $DEBUG /usr/bin/yum remove -y "${PACKAGES[@]}"
  elif [[ "$DISTRIBUTION_FAMILY" == "deb" ]]; then
    $DEBUG /usr/bin/apt purge -y "${PACKAGES[@]}"
  fi
}

function remove_paths {
  for ((i = 0; i < ${#PATHS[@]}; i++)); do
    log INFO "Removing path ${PATHS[$i]}"
    $DEBUG /bin/rm -rf "${PATHS[$i]}"
  done
}

function cleanup {
  if [[ "$DISTRIBUTION_FAMILY" == "rh" ]]; then
    log INFO "Cleaning yum temp files"
    $DEBUG /usr/bin/yum clean all
  elif [[ "$DISTRIBUTION_FAMILY" == "deb" ]]; then
    log INFO "Cleaning apt temp files"
    $DEBUG /usr/bin/apt clean
  fi

  sync
}

function log {
  if [[ -t 1 ]] && [[ -t 2 ]]; then
    # If stdout & stderr are TTYs, output with pretty colour control chars
    case "$1" in
      ERROR) FMT="\\e[1;31m";; # Bold, red
      WARN) FMT="\\e[1;33m";;  # Bold, yellow
      INFO) FMT="\\e[1;32m";;  # Bold, green
      DEBUG) FMT="\\e[1;34m";; # Bold, blue
      *) return 1;;
    esac
    RST="\\e[0m"               # Reset formatting
  fi

  LOGTIME=$(/bin/date "+%T" | /usr/bin/tr -d "\\n")

  if [[ "$1" == "ERROR" ]] || [[ "$1" == "WARN" ]]; then
    echo -e "$LOGTIME ${FMT}$1${RST}:" "${@:2}" 1>&2
  else
    echo -e "$LOGTIME ${FMT}$1${RST}:" "${@:2}"
  fi
}

function finish {
  if [[ -n $1 ]]; then
    EXITCODE=$1
  else
    # If we reached this function without an arg, assume generic failure
    EXITCODE=1
  fi

  # Insert optional code to report success or failure to an API endpoint here
  # Use $EXITCODE, FUNCTION="${FUNCNAME[1]}", etc for debugging

  exit "$EXITCODE"
}

function print_usage {
  echo "amiprep.sh: Prepare EC2 instance for AMI generation by removing"
  echo "            installed software agents and related config"
  echo
  echo "Usage:"
  echo "amiprep.sh -h           Show help/usage"
  echo "amiprep.sh [OPTIONS]    Test/debug/dry-run mode"
  echo
  echo "Options:"
  echo "  -t                    Test mode (debug/dry-run)"
  echo "  -d (rh|deb)           Override Linux distribution family detection"
  echo "  -a agent_list         Comma-separated list of agents to remove"
  echo "                        Valid agents: ssm,codedeploy,cfn,cloudwatch"
  echo "                        Default: codedeploy,cfn,cloudwatch"
}

trap finish SIGHUP SIGINT SIGTERM

main "$@"
