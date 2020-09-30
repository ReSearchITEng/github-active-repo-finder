#!/bin/bash
set -ue

# MAIN is at the end of the file.

## FUNCTION DEFS:

#################################
## usage ########################
#################################
usage(){
  cat <<EOF
  This script helps to identify updated(important) forks of a specified reference repo in github.
  It will search recursively for all branches in all forks of the provided reference repo.
  It will build a json holding not only forks and all their branches info, but also the comparison of those branches with their counterparts in reference repo.
  The final report can be further filtered to return the repos which were updated between specific dates.
  As it's a deep analysis, depending on the number of forks, the report can take from few minutes to several hours.
  Due to high number of calls to the github apis, it will require an auth token (github limits anonymous to very small number of api calls ).
  (github api docs: https://docs.github.com/en/rest/reference/repos#forks)
  PROGRESS: each "." means one curl command
  
  RESUME: The script is capable to resume from fork it left last time, just rerun it with same params.

  ARGUMENTS  
  $0 [-t <token>] [ -a <date> ] [ -b <date> ] [ -c <branch> ] [ -p <path_file_prefix> ] <reference_repo_owner/reference_repo_name> 
  -t|--token github auth token (see https://github.com/settings/tokens ; optional; use token to get higher number of requests limits for api.github.com)
  -a|--after (optional) final report will show only repos updated after this date. it defaults to '2018-01-01T00:00:00Z' 
  -b|--before (optional) final report will show only repos updated before this date. it defaults to '2200-01-01T00:00:00Z' (i.e. all)
  -c|--compare-branch (optional&advanced) When a fork has a branch which does not exist in the reference repo, the branch compare will compare it with referece repo branch from this init_default_compare_branch parameter. It defaults to reference repo's master branch.
  -p|--prefix (optional) Optionally provide the path AND file prefix (e.g. /work/myfileprefix ). If it's a directory only, end it with "/". Defaults to "./"

  reference_repo_owner/reference_repo_name can be in any of these 3 formats:
  octocat/Hello-World
  https://github.com/octocat/Hello-World
  git@github.com:octocat/Hello-World.git

  E.g.
  $0 octocat/Hello-World
  or
  $0 -t 'some-github-account:abcdef1234567890abcdef1234567890abcdef12' -a '2018-01-01T00:00:00Z' -b '2200-01-01T00:00:00Z' -c master https://github.com/octocat/Hello-World

  Known limitations:
  1. it's slow
  2. Does not handle branches with non-ascii names (it's more of github api limitation for compare). (Watch for errors like: "parse error: Invalid numeric literal at line 2, column 7")
EOF
}

#################################
## get forks ####################
## searches recursivelly to build a list of all fork of the reference repo.
## output: ${file_forks_prefix}.json - holds all forks, including forks of forks checked recursivelly
#################################
get_forks(){

  echo "get_forks start - searching recursivelly to build a list of all forks of the reference repo."
  #set -x
  if [[ -s ${file_forks_prefix}.json && ! -s ${file_forks_prefix}.repos_to_process.tmp.lst ]]; then
    echo "  ${file_forks_prefix}.json exists, and ${file_forks_prefix}.repos_to_process.tmp.lst is missing or empty. This means this function (get_forks) ended successfully in a previous run, skipping it"
    return 0
  fi

  if [[ ! -s ${file_forks_prefix}.json ]]; then
    ## SEEDING
    echo "${reference_owner}/${reference_repo}" > ${file_forks_prefix}.repos_to_process.tmp.lst
    echo "[" > ${file_forks_prefix}.json
  else
    echo "  resuming ${file_forks_prefix}.json based on existing ${file_forks_prefix}.repos_to_process.tmp.lst"
  fi

  while [[ -s ${file_forks_prefix}.repos_to_process.tmp.lst ]]; do
    owner=$(head -1 ${file_forks_prefix}.repos_to_process.tmp.lst | cut -d"/" -f1)
    repo=$(head -1 ${file_forks_prefix}.repos_to_process.tmp.lst | cut -d"/" -f2)
    curl_return=0
    last_page_had_data=1

    page=1 # seems that page 0 and page 1 has same data
    while [[ $last_page_had_data -gt 0 && $curl_return -eq 0 ]]; do
      COUNT_SUBFORKS_THIS_PAGE=0
      #[[ $LOG_LEVEL -ge $DEBUG ]] && echo "${owner}/${repo}"
      echo "${owner}/${repo} - page $page"
      $CURL -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/${owner}/${repo}/forks?per_page=100&page=${page}" -o ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json
      curl_return=$?
      echo -n ' .F'

      # remove empty lines which appear when there are no results (empty array)
      sed -i '/^$/d' ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json
      #last_page_had_data=$(grep -c full_name  ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json || true)
      ## remove [ and ] (these are the only charts on first and last line) and check if there is any data
      #/bin/cat ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json
      last_page_had_data=$(cat ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json | sed '1d;$d' | wc -l )

      check_github_msg_exists="$(jq '. | .message' ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json 2>/dev/null || true)"
      if [[ ( $last_page_had_data -gt 0 ) && ( "$check_github_msg_exists" == '"Not Found"' ) ]]; then
        echo -e "\n   WARNING ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json .F - has message: Not Found"
        last_page_had_data=0
      fi
      if [[ $last_page_had_data -gt 0 ]]; then
        ## determine the forks that have forks:
        jq '.[] | select(.forks_count != 0) | .full_name' ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json | tr -d '"' >> ${file_forks_prefix}.repos_to_process.tmp.lst
        COUNT_SUBFORKS_THIS_PAGE=$(jq '.[] | .full_name' ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json | wc -l )
        ## remove [ and ] (first and last line)
        sed -i '1d;$d' ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json
        ## collect the results:
        cat ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json >> ${file_forks_prefix}.json
        ## prepare for an eventual continuation:
        echo "," >> ${file_forks_prefix}.json
      else
        # remove the empty file
        rm -f ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json
      fi
      if [[ $COUNT_SUBFORKS_THIS_PAGE -ge 100 ]]; then
        (( page ++ ))
      else
        # As per_page=100, if we had $COUNT_SUBFORKS_THIS_PAGE it means there won't be anything in next page, so not wasting time to curl for next page
        break;
      fi
    done
    ## log what we processed:280551122
    echo "${owner}/${repo}" >> ${file_forks_prefix}.processed_recursive_fork.lst
    ## remove the repo we've just processed from the queue
    sed -i "/${owner}\/${repo}/d" ${file_forks_prefix}.repos_to_process.tmp.lst
    rm -f ${file_forks_prefix}.tmp.${owner}.${repo}.page_*.json
    #if [[ -s ${file_forks_prefix}.repos_to_process.tmp.lst ]]; then
    #  echo "list of forks or forks of forks left to process:"
    #  cat ${file_forks_prefix}.repos_to_process.tmp.lst
    #fi
  done

  sed -i "/${reference_owner}\/${reference_repo}/d" ${file_forks_prefix}.processed_recursive_fork.lst
  ## some file cleanup:
  rm -f ${file_forks_prefix} ${file_forks_prefix}.repos_to_process.tmp.lst # it's temporary and it's already empty
  rm -f ${file_forks_prefix}.tmp.${owner}.${repo}.page_*.json
  ## remove the "," from the last line:
  sed -i '$d' ${file_forks_prefix}.json

  if [[ ! -s ${file_forks_prefix}.json ]]; then
    echo "HEY, given reference repo has no forks, check https://github.com/${reference_owner}/${reference_repo}/network/members " 
    echo "get_forks() ends and $0 script exits now"
    exit 0
  fi

  ## terminate array:
  echo "]" >> ${file_forks_prefix}.json

  ## Some reports:
  echo "repositories from the forks and forks of forks recursivelly. Total number of repos:"
  grep full_name ${file_forks_prefix}.json | wc -l

  ## Recursive repos processed:
  echo "Recursive repos processed:"
  cat ${file_forks_prefix}.processed_recursive_fork.lst | wc -l

  echo "all the repos (including forks of forks) are under file: ${file_forks_prefix}.json, use jq to process"
  #echo "recursive repo result files are:"
  #ls -l ${file_forks_prefix}*
  echo "get_forks() end"
}

get_commit_per_branch_per_repo(){
##############################################
## Get list of repos to check for branches, ##
## and for each branch get commit info      ##
## and put each set in a big array          ##
## input:  ${file_forks_prefix}.json        ##
## output: ${file_forks_prefix}.branches.json #
##############################################
  echo "get_commit_per_branch_per_repo() - start at: `date`"
  REPOS_PROCESSED_THIS_SESSION=0

  if [[ ! -s ${file_forks_prefix}.repos_to_look_for_commits.lst ]]; then
    jq '.[] | .full_name' ${file_forks_prefix}.json | tr -d '"' > ${file_forks_prefix}.repos_to_look_for_commits.lst
    cp ${file_forks_prefix}.repos_to_look_for_commits.lst ${file_forks_prefix}.repos_to_look_for_commits.bkp.initial_full.lst
  else
    echo "  ${file_forks_prefix}.repos_to_look_for_commits.lst exists, resuming work from last unfinished fork"
  fi
  if [[ ! -s ${file_forks_prefix}.branches.json ]]; then
    echo "  Preparing: ${file_forks_prefix}.branches.json"
    echo "[" > ${file_forks_prefix}.branches.json
  fi

  REPOS_TO_PROCESS_IN_TOTAL=$(cat ${file_forks_prefix}.repos_to_look_for_commits.bkp.initial_full.lst | wc -l )
  REPOS_TO_PROCESS_THIS_SESSION=$(cat ${file_forks_prefix}.repos_to_look_for_commits.lst | wc -l )

  if [[ $REPOS_TO_PROCESS_THIS_SESSION -eq 0 ]]; then
    echo "REPOS_TO_PROCESS_THIS_SESSION=$REPOS_TO_PROCESS_THIS_SESSION"
    echo "get_commit_per_branch_per_repo() - ended"
    return
  fi
  echo "REPOS_TO_PROCESS_THIS_SESSION=$REPOS_TO_PROCESS_THIS_SESSION"
  echo "REPOS_TO_PROCESS_IN_TOTAL=$REPOS_TO_PROCESS_IN_TOTAL"

  while [[ -s ${file_forks_prefix}.repos_to_look_for_commits.lst ]];do
    FORK_PROCESSING_STARTTIME=$(date +%s)
    owner=$(head -1 ${file_forks_prefix}.repos_to_look_for_commits.lst | cut -d"/" -f1)
    repo=$(head -1 ${file_forks_prefix}.repos_to_look_for_commits.lst | cut -d"/" -f2)
    echo ""
    echo "INFO: starts processing ${owner}/${repo} (getting branches, comparing each branch with reference repo equivalent branch)"
    curl_return=0
    last_page_had_data=1
    page=1 # seems that page 0 and page 1 has same data
    while [[ $last_page_had_data -gt 0 && $curl_return -eq 0 ]]; do
      last_page_had_data=0 # init
      $CURL -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/${owner}/${repo}/branches?per_page=100&page=${page}" -o ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json
      echo -n ' .B'
      curl_return=$?
      #branch0=$(cat ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json | jq '.[] | .name' 2>/dev/null | true) 
      # remove empty lines which appear when there are no results (empty array)
      #sed -i '/^$/d' ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json
      ## remove [ and ] (these are the only charts on first and last line) and check if there is any data
      #last_page_had_data=$(cat ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json | sed '1d;$d' | wc -l )
      if [[ -s ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json ]]; then
        if [[ $(jq -r '. | .message' ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json 2>/dev/null ) == "Not Found" ]]; then
          echo -e "\n  WARNING: ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json .B - has message: Not Found"
          last_page_had_data=0
          continue
        fi
        cat ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json | jq '.[] | .name' 2>/dev/null > ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json.hasdata || true 
        if [[ -s ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json.hasdata ]]; then
          last_page_had_data=1
          rm -f ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json.hasdata
        else
          last_page_had_data=0
          rm -f ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json.hasdata
          rm -f ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json
          continue
        fi
      else 
        last_page_had_data=0
        rm -f ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json
        continue
      fi

      ## loop per branch and create entries in the branches.json:
      #for branch_name in $(jq -j '.[] | .name, ",", .commit.url, "\n" ' ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json); do
      for branch_name in $(jq '.[] | .name' ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json); do
          commit_url=$(jq -r ".[] | select (.name == ${branch_name} ) | .commit.url" ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json)
          branch=$(jq -r ".[] | select (.name == ${branch_name} ) | .name" ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json) #to get only required quotes
          $CURL -H "Accept: application/vnd.github.v3+json" $commit_url > ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.commit.tmp.json
          echo -n ' .c'
          adate=$(cat ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.commit.tmp.json | jq -r '. | .commit.author.date ' )
          aname=$(cat ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.commit.tmp.json | jq -r '. | .commit.author.name ' )
          cdate=$(cat ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.commit.tmp.json | jq -r '. | .commit.committer.date ' )
          cname=$(cat ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.commit.tmp.json | jq -r '. | .commit.committer.name ' )
          message=$(cat ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.commit.tmp.json | jq '. | .commit.message ' )
          tree_url=$(cat ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.commit.tmp.json | jq -r '. | .commit.tree.url ' )
          commit_sha=$(cat ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.commit.tmp.json | jq -r '. | .sha ' )

  ### Getting the compare/diffs
          compare_url="https://api.github.com/repos/${reference_owner}/${reference_repo}/compare/${branch}...${owner}:${branch}"
          $CURL -H "Accept: application/vnd.github.v3+json" $compare_url > ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.commit.compare.tmp.json
          echo -n ' .C'
          if [[ "null" == $(jq '. | .status' ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.commit.compare.tmp.json 2>/dev/null || true ) ]]; then
            echo -e "\n  WARNING: branch compare: ${owner}/${repo} has a branch with name $branch, but ${reference_owner}/${reference_repo} does not have it, therefore retrying compare; now comparing ${owner}/${repo} branch $branch with ${reference_owner}/${reference_repo} branch ${init_default_compare_branch}"

            compare_url="https://api.github.com/repos/${reference_owner}/${reference_repo}/compare/${init_default_compare_branch}...${owner}:${branch}"
            $CURL -H "Accept: application/vnd.github.v3+json" $compare_url > ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.commit.compare.tmp.json
            echo -n ' .C'
          fi
          compare_status=$(cat ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.commit.compare.tmp.json | jq '. | .status')
          compare_ahead_by=$(cat ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.commit.compare.tmp.json | jq '. | .ahead_by')
          compare_behind_by=$(cat ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.commit.compare.tmp.json | jq '. | .behind_by')
          cat <<EOF >> ${file_forks_prefix}.branches.json
    {
      "owner": "$owner",
      "repo": "$repo",
      "branch": "$branch",
      "author_date": "$adate",
      "author_name": "$aname",
      "committer_date": "$cdate",
      "committer_name": "$cname",
      "message": $message,
      "commit_sha": "$commit_sha",
      "commit_url": "$commit_url",
      "tree_url": "$tree_url",
      "compare_status": $compare_status,
      "compare_ahead_by": $compare_ahead_by,
      "compare_behind_by": $compare_behind_by,
      "compare_url": "$compare_url"
    }
    ,
EOF
      done

      COUNT_BRANCHES_THIS_PAGE=$(jq '.[] | .name' ${file_forks_prefix}.tmp.${owner}.${repo}.page_${page}.json | wc -l )
      if [[ $COUNT_BRANCHES_THIS_PAGE -ge 100 ]]; then
        (( page ++ ))
      else
        # As per_page=100, if we had $COUNT_BRANCHES_THIS_PAGE it means there won't be anything in next page, so not wasting time to curl for next page
        break;
      fi
    done

    ## remove the repo we've just processed from the queue
    sed -i "/${owner}\/${repo}/d" ${file_forks_prefix}.repos_to_look_for_commits.lst
    rm -f ${file_forks_prefix}.tmp.${owner}.${repo}.page_*.json
    (( REPOS_PROCESSED_THIS_SESSION++ )) || true
    REPOS_LEFT_TO_PROCESS_THIS_SESSION=$(( REPOS_TO_PROCESS_THIS_SESSION - REPOS_PROCESSED_THIS_SESSION ))
    FORK_PROCESSING_ENDTIME=$(date +%s)
    FORK_PROCESSING_TIME=$(( FORK_PROCESSING_ENDTIME - FORK_PROCESSING_STARTTIME ))
    echo ""
    echo "Progress: this repo took $FORK_PROCESSING_TIME seconds to process"
    echo "Progress: repos processed this session/repos to process this session/repos to process in total: $REPOS_PROCESSED_THIS_SESSION/$REPOS_TO_PROCESS_THIS_SESSION/$REPOS_TO_PROCESS_IN_TOTAL"
    echo "Progress: it is expected to finish in $(( REPOS_LEFT_TO_PROCESS_THIS_SESSION*FORK_PROCESSING_TIME/60 ))+ minutes (or equivalent $(( REPOS_LEFT_TO_PROCESS_THIS_SESSION*FORK_PROCESSING_TIME/3600 ))+ hours)"
    echo "Progress: ETA: $(date -d @$((FORK_PROCESSING_ENDTIME+REPOS_LEFT_TO_PROCESS_THIS_SESSION*FORK_PROCESSING_TIME)) )"
  done #end processing for this repo fork

  if [[ $REPOS_PROCESSED_THIS_SESSION -gt 0 ]]; then
    ## remove the last "," and add "]"
    sed -i '$d' ${file_forks_prefix}.branches.json
    echo "]" >> ${file_forks_prefix}.branches.json
  fi

  echo "get_commit_per_branch_per_repo() ended at `date`; results file: ${file_forks_prefix}.branches.json"
  #ls -l ${file_forks_prefix}* | grep -v '.tmp.' || true
}


#######################
## reports :
find_maintained_forks(){
  echo "find_maintained_forks post $FIND_UPDATED_AFTER_DATE from: ${file_forks_prefix}.branches.json "
  jq --arg FIND_UPDATED_AFTER_DATE "$FIND_UPDATED_AFTER_DATE" --arg FIND_UPDATED_BEFORE_DATE "$FIND_UPDATED_BEFORE_DATE" '.[] | select ( .compare_status != "identical" and .compare_status != null and .compare_status != "behind" and .author_date > $FIND_UPDATED_AFTER_DATE and .author_date < $FIND_UPDATED_BEFORE_DATE ) | . ' ${file_forks_prefix}.branches.json | jq -s '.' | tee ${file_forks_prefix}.report_of_updated_repos_branches.json
  echo "report can be found in file: ${file_forks_prefix}.report_of_updated_repos_branches.json "
  echo "links to the repos updated between $FIND_UPDATED_AFTER_DATE and $FIND_UPDATED_BEFORE_DATE: ${file_forks_prefix}.report_of_updated_repos.txt :"
  #jq -r '.[] |[.owner,.repo]| @csv' ${file_forks_prefix}.report_of_updated_repos_branches.json | tr -d '"' | tr ',' '/' | xargs echo -n "https://github.com/" | tr -d " " | tee ${file_forks_prefix}.report_of_updated_repos.txt

  # Some screen/human friendly reportL
  for x in `jq -r '.[] |[.owner,.repo]| @csv'  ${file_forks_prefix}.report_of_updated_repos_branches.json | tr -d '"' | tr ',' '/' ` ; do echo "https://github.com/$x" ; done | uniq | tee ${file_forks_prefix}.report_of_updated_repos.txt

  echo "If required, you may now rerun this script with different --after (and --before) parameters. It will not rebuild the db when it's already in place, so only the report will be rerun which is offline and it's instant. "

}

#############################
############# MAIN ##########
#############################

## read input params ##
[[ $# -lt 1 ]] && usage && exit 1
## when we'll compare each of forks' branches, we'll try to match branches with the ones in ref_repo
## if a branch with same name does not exist in reference repo, we'll look in this one (usually master):
init_default_compare_branch=master
PATH_FILE_PREFIX="${PATH_FILE_PREFIX:-./}"
FIND_UPDATED_AFTER_DATE="${FIND_UPDATED_AFTER_DATE:-2018-01-01T00:00:00Z}"
FIND_UPDATED_BEFORE_DATE="${FIND_UPDATED_BEFORE_DATE:-2200-01-01T00:00:00Z}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t | --token) AUTH="$2" ; shift ;;
    -a | --after) FIND_UPDATED_AFTER_DATE="$2" ; shift ;;
    -b | --before) FIND_UPDATED_BEFORE_DATE="$2" ; shift ;;
    -c | --compare-branch) init_default_compare_branch="$2" ;shift ;;
    -p | --prefix) PATH_FILE_PREFIX="$2" ;shift ;;
    -h | --help) usage ; exit 0;;
    *) repo="$1" ;;
  esac
  shift
done
REFERENCE_REPO=$(echo -n "$repo" | sed 's!^https://github.com/!!g' | sed -E 's!^git@github.com:(.*)\.git$!\1!g' )

reference_owner=$(echo $REFERENCE_REPO | cut -d'/' -f1 )
reference_repo=$(echo $REFERENCE_REPO | cut -d'/' -f2 )


cat <<EOF
  going to use following inputs:
  AUTH=$AUTH
  reference_owner=$reference_owner
  reference_repo=$reference_repo
  FIND_UPDATED_AFTER_DATE=$FIND_UPDATED_AFTER_DATE
  FIND_UPDATED_BEFORE_DATE=$FIND_UPDATED_BEFORE_DATE
  init_default_compare_branch=$init_default_compare_branch
  PATH_FILE_PREFIX=$PATH_FILE_PREFIX
EOF

######### DEFs and Tests ##################
file_forks_prefix="${PATH_FILE_PREFIX}active_forks_finder.${reference_owner}.${reference_repo}.forks"

if [[ -n $AUTH ]]; then
  CURL="curl -sL -u ${AUTH}"
else
  echo -e "\n  WARNING, no token was provided, github will limit to a small number of api calls; Use only for small tests... More on:https://github.com/settings/tokens"
  echo "proceeding anyway ..."
  CURL="curl -sL"
fi

## TEST CURL works fine:
echo -n "testing curl github access:"
$CURL -H "Accept: application/vnd.github.v3+json" https://api.github.com >/dev/null
[[ $? -ne 0 ]] && echo "error while trying to reach https://api.github.com using provided arguments" && exit 1
echo "  OK."

#############################
### CALL worker functions ###
get_forks
get_commit_per_branch_per_repo
find_maintained_forks
echo "$0 - ended, bye"
