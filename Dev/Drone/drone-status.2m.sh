#!/usr/local/bin/bash -l

# <bitbar.title>Drone Status</bitbar.title>
# <bitbar.version>v2.0</bitbar.version>
# <bitbar.author>Christoph Schlosser</bitbar.author>
# <bitbar.author.github>christophschlosser</bitbar.author.github>
# <bitbar.desc>Checks the status of the builds from Drone CI</bitbar.desc>
# <bitbar.image>https://user-images.githubusercontent.com/10169201/65250890-9c43a680-daf6-11e9-9e4d-1cbf0c712c97.png</bitbar.image>
# <bitbar.dependencies>jq,bash,curl,awk</bitbar.dependencies>

# contributor
# <bitbar.author>Yogesh Lonkar</bitbar.author>
# <bitbar.author.github>yogeshlonkar</bitbar.author.github>
#################
# User Settings #
#################

# Needed for jq, curl, awk. If you install jq somewhere else you have to add it here as well
######################################################################################################################
## REQUIRES NERD-FONTS all or just https://github.com/ryanoasis/nerd-fonts/tree/master/patched-fonts/DejaVuSansMono ##
######################################################################################################################
export PATH="/usr/local/bin:/usr/bin:$PATH"

# Get jq from here: https://stedolan.github.io/jq/

# URL to Drone Web Interface. Expected to be set in .bash_profile as bash -l will source it
DRONE_URL=$DRONE_SERVER

# The Account token from Webinterface -> Account -> Show Token. Expected to be set in .bash_profile as bash -l will source it
TOKEN=$DRONE_TOKEN

# Specify projects and their tracked branches to check
# declare -A REPO_BRANCHES=(
#    [owner1/project1]=master
#    [owner2/project2]=master,dev,feature/abc
# )

# Spefify order of projects if required to be explicit.
# repo should be present in REPO_BRANCHES
# REPO_ORDER=(
#   owner3/project4
#   owner1/project1
#   owner2/project3
#   owner1/project2
# )

##################
# Implementation #
##################
DRONE_IMAGE_GREEN=$(cat `dirname "$0"`/images/drone_green_18px.png | base64)
DRONE_IMAGE_YELLOW=$(cat `dirname "$0"`/images/drone_yellow_18px.png | base64)
DRONE_IMAGE_RED=$(cat `dirname "$0"`/images/drone_red_18px.png | base64)

color_red='\033[1;31m'
color_green='\033[1;32m'
color_yellow='\033[1;33m'
color_blue='\033[1;34m'
ansi_clear='\033[0m'

success=0
failure=0
running=0

output=

function line_parms()
{
  local OPTIND o a
  while getopts ":ac:fh:i:rs:t:T" o; do
    case "${o}" in
      a)
        printf 'ansi=true '
        ;;
      c)
        printf "color=${OPTARG} "
        ;;
      f)
        printf 'font=DejaVuSansMonoNerdFontCompleteM-Book '
        ;;
      h)
        printf "href=${OPTARG} "
        ;;
      i)
        printf "image=${OPTARG} "
        ;;
      s)
        printf "size=${OPTARG} "
        ;;
      r)
        printf "refresh=true "
        ;;
      t)
        printf "templateImage=${OPTARG} "
        ;;
      T)
        printf "terminal=false "
        ;;
    esac
  done
  shift $((OPTIND-1))
}

function truncate_n_pad()
{
  expected_length=${2}
  do_pad=${3-true}
  if [[ -z "${expected_length}" ]]; then
    expected_length=30
  fi
  if (( ${#1} < ${expected_length} )) && [[ ${do_pad} == true ]]; then
    pad=$(printf '%0.1s' " "{1..1000})
    printf '%s' "${1}"
    printf '%*.*s' 0 $(( ${expected_length} - ${#1})) "${pad}"
  else
    echo ${1} | awk -v len=${expected_length} '{ if (length($0) > len) print substr($0, 1, len-3) "..."; else print; }'
  fi
}

if [[ ${#REPO_BRANCHES[*]} == 0 ]]; then
  output="no projects configured"
else
  if (( ${#REPO_ORDER[*]} != ${#REPO_BRANCHES[*]} )); then
    REPO_ORDER=${!REPO_BRANCHES[@]}
  fi
  for repo in ${REPO_ORDER[*]}; do

    if [[ -z "${REPO_BRANCHES[${repo}]}" ]]; then
      output="no branch configured for ${repo}"
      break
    fi

    build_location="repos/${repo}/builds"
    # Get the status of the builds from the repo
    json=$(curl --silent -sb -H "Accept: application/json" -H "Authorization: ${TOKEN}" -X GET "${DRONE_URL}/api/${build_location}")
    output+="\\n$(truncate_n_pad ${repo/*\//})| href=${DRONE_URL}/${repo}"
    branch_output_prefix=" "
    IFS=',' read -ra branches <<< "${REPO_BRANCHES[${repo}]}"
    if (( ${#branches[*]} == 1 )) ; then
      # ìf single branch is track don't put it in submenu
      branch_output_prefix="\\n"${branch_output_prefix}
    else
      branch_output_prefix="\\n--"${branch_output_prefix}
      repo_success=0
      repo_failure=0
      repo_running=0
      for branch in "${branches[@]}"; do
        result=$(echo "${json}" | jq "[.[] | select(.branch == \"${branch}\")] | max_by(.number) | {status: .status}" | grep "status" | awk '{print $2}' | head -n 1)
        result=${result:1:${#result}-2}
        case ${result} in
          "success")
            repo_success=$((repo_success + 1))
            ;;
          "failure")
            repo_failure=$((repo_failure + 1))
            ;;
          "running")
            repo_running=$((repo_running + 1))
            ;;
        esac
      done
      output+="\\n"
      if (( ${repo_success} > 0 )); then
        output+="${color_green}${repo_success} "
      fi
      if (( ${repo_failure} > 0 )); then
        output+="${color_red}${repo_failure} x"
      fi
      if (( ${repo_running} > 0 )); then
        output+="${color_yellow}${repo_running} "
      fi
      if (( ${repo_success} == 0 && ${repo_failure} == 0 && ${repo_running} == 0 )); then
        output+="no builds"
      fi
      output+="${ansi_clear}| $(line_parms -f -h ${DRONE_URL}/${repo})"
    fi
    # process result for tracked branches
    for branch in "${branches[@]}"; do
      branch_name=$(echo $branch | sed -E -e 's/(features?)(\/.*)/F\2/g' -e 's/(hotfix)(\/.*)/H\2/g' -e 's/(releases?)(\/.*)/R\2/g' -e 's/(bugfix)(\/.*)/B\2/g' -e 's/(issues?)(\/.*)/I\2/g')
      if (( ${#branches[*]} == 1 )) ; then
        branch_output=${branch_output_prefix}"${color_blue}$(truncate_n_pad ${branch_name} 10 false) "
      else
        branch_output=${branch_output_prefix}"${color_blue}$(truncate_n_pad ${branch_name} 30) "
      fi

      build=$(echo "${json}" | jq -r "[.[] | select(.branch == \"${branch}\")] | max_by(.number) | .number")
      result=$(echo "${json}" | jq "[.[] | select(.branch == \"${branch}\")] | max_by(.number) | {status: .status}" | grep "status" | awk '{print $2}' | head -n 1)
      result=${result:1:${#result}-2}

      case ${result} in
        "success")
          output+=${branch_output}"${color_green}$(truncate_n_pad "#${build}" 6) ${ansi_clear}"
          success=$((success + 1))
          ;;
        "failure")
          output+=${branch_output}"${color_red}$(truncate_n_pad "#${build}" 6) x${ansi_clear}"
          failure=$((failure + 1))
          ;;
        "running")
          output+=${branch_output}"${color_yellow}$(truncate_n_pad "#${build}" 6) ${ansi_clear}"
          running=$((running + 1))
          ;;
      esac
      output+="| $(line_parms -s 12 -f -a -h ${DRONE_URL}/${repo}/${build})"
    done
  done
fi
output+="\\nRefresh 痢| $(line_parms -f -T -r)"

status_excon=${DRONE_IMAGE}

if [[ ${failure} -gt 0 ]]; then
  status_icon=${DRONE_IMAGE_RED}
elif [[ ${running} -gt 0 ]]; then
  status_icon=${DRONE_IMAGE_YELLOW}
else
  status_icon=${DRONE_IMAGE_GREEN}
fi
echo -e "| $(line_parms -i ${status_icon})\\n---\\n${output}"


