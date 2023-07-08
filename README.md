# github forks comparison tool

## What is it

A script that helps to identify updated forks (active forks) of a specified reference repo in github.
It does so, by mainly calling github's compare branch api for all branches in all forks against those in the reference repository given as input.

## When to use this

If for your use case that github's "/network" functionality is not a match (e.g. https://github.com/octocat/Hello-World/network), read on.   
If https://techgaun.github.io/active-forks/index.html was not exactly what you were looking for.   
If https://www.producthunt.com/posts/github-compare is way too basic for you.   
If you don't want to download all the forks out there on your machine and run various comparison scripts out there.   

This is especially useful when there is a "neglected/dead" project and you are looking to find if there is some fork that maintains it (and original owners did not point to it).

It is useful if the project you are trying to investigate (the reference repo) either:

- has more than 100 forks (gihutb's /network is limited to 100 forks)    
- maintains its main/active branch in something else than master
Forks might be maintained in a branch different from master also.    

Github's /network (and other tools) compare only between master reference repo and master of the fork, which might not be enough.

If all or some from above is true for your case, this project if for you.

Hints for the "neglected/dead" projects:

Besides the script we share here, you may look for other other hints when looking at that project, like: look for open PRs to identify who is active in this project.

Once you manage to identify the most up to date fork(s), you may want to reach out to them, decide who might be willing to maintain it and join the new fork.    
If all goes well, you may want to make a PR to the original project which only updates README.md with the message pointing to the maintained fork.    
Next move: open ticket to github and ask to make your project an independent one (disconnecting it from the initial owner).    
Last step: make a blog posting and notify everyone that project is getting resurected in this new location.    

## How to use

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
  $0 [-t <token>] [ -a <date> ] [ -b <date> ] <reference_repo_owner/reference_repo_name>    
  -t|--token github auth token (see https://github.com/settings/tokens ; optional; use token to get higher number of requests limits for api.github.com)   
  -a|--after (optional) final report will show only repos updated after this date. it defaults to '2018-01-01T00:00:00Z'   
  -b|--before (optional) final report will show only repos updated before this date. it defaults to '2200-01-01T00:00:00Z' (i.e. all)  
  -c|--compare-branch (optional&advanced) When a fork has a branch which does not exist in the reference repo, the branch compare will compare it with referece repo branch from this init_default_compare_branch parameter. It defaults to reference repo's master branch.   

  reference_repo_owner/reference_repo_name can be in any of these 3 formats:   
  octocat/Hello-World   
  https://github.com/octocat/Hello-World   
  git@github.com:octocat/Hello-World.git   
   
  E.g.   
  `$0 octocat/Hello-World`   
  or   
  `$0 -t 'some-github-account:abcdef1234567890abcdef1234567890abcdef12' -a '2018-01-01T00:00:00Z' -b '2200-01-01T00:00:00Z' -c master https://github.com/octocat/Hello-World` -p ~/myfileprefix    

## Known limitations

  1. it's slow (if there are hundres/thounsands of forks with lots of branches, it takes hours)
  2. Does not handle branches with non-ascii names (it's more of github api limitation for compare). (Watch for errors like: "parse error: Invalid numeric literal at line 2, column 7")
  3. MacOS - one needs to first change sed to gsed
     ```shell
     brew install gnu-sed
     sed() { gsed $@ }
     ./active_forks_finder.sh <params>
     ```

## How it's working

  The work is split in 3 main steps

  1. get_forks This first step takes only seconds or max few minutes.
     Input are the provided repo arguments. Output is a file active_forks_finder.${reference_owner}.${reference_repo}.forks.json
     The repos are checked recurrently, so it will find also the forks of the forks.

  2. get_commit_per_branch_per_repo - get list of repos to check for branches and for each branch gets commit info and puts each result set in a big json array.    
  Input file is active_forks_finder.${reference_owner}.${reference_repo}.forks.json (from step 1) which is tranformed in a flat/text list file active_forks_finder.${reference_owner}.${reference_repo}.forks.repos_to_look_for_commits.lst which is actually used to loop on.    
  If during comparison of fork/branchX with reference/branchX it is found that reference/branchX does not exist, the comparison will be run between fork/branchX and reference/master, and a warning will be printed in the form of "WARNING: branch compare:"). The --compare parameter can change from default master to some other default branch in the reference repository.    
  The and output file: active_forks_finder.${reference_owner}.${reference_repo}.forks.branches.json (aka the big json database). The main target of this script is creating this big file.  
  This is the most heavy and most important step, which creates "the database" with information about each branch in each fork and comparison of those branches with their equivalent in the reference repo provided. FYI if anything gets interupted, you may rerun and it will resume work.  
  If you have troubles with a specific fork, simply remove it from active_forks_finder.${reference_owner}.${reference_repo}.forks.repos_to_look_for_commits.lst (first line)
  Example of cases when you will need to do this manual "fork reject" step:
     - github api that lists forks provided a fork which actually no longer exists...
     - the fork has branches with non-acii characters, and github branch compare script rest api does not seem to handle such cases (let me know if you have a solution).

  3. find_maintained_forks - it does a quick/easy query (using jq) in the above active_forks_finder.${reference_owner}.${reference_repo}.forks.branches.json (which is the input for this step).
  The outputs are:
     - `active_forks_finder.${reference_owner}.${reference_repo}.forks.report_of_updated_repos_branches.json`
     - `active_forks_finder.${reference_owner}.${reference_repo}.forks.report_of_updated_repos.txt`
  First is a report in json format with the forks and the exact branches that were updated between the provided dates, and how many commits is ahead of the branch in reference repo, along with name of commiter, etc.  
  Second is a more human friendly report in txt format, with links to the repos which were found as imporant to review.  
  It is expected that the actual user of this script will either run the script with different --after and --before dates, or even create their own jq filters against the big db file on step 2.  
  There is no issue to rerun the script multiple times, as it will identify which steps were finished, and it will go straight to the report execution step which is very fast.  
  
  The default filter will find forks which are either behind/identical(/null) compared to the branches in the reference repo, leaving only the ones which are ahead or diverged.  
  Users might want to create their own jq queries against the db (e.g. filter out also the diverged forks or other conditions). This is our default filter, change/rerun as desired:

  ```shell
  jq --arg FIND_UPDATED_AFTER_DATE "$FIND_UPDATED_AFTER_DATE" --arg FIND_UPDATED_BEFORE_DATE "$FIND_UPDATED_BEFORE_DATE" '.[] | select ( .compare_status != "identical" and .compare_status != null and .compare_status != "behind" and .author_date > $FIND_UPDATED_AFTER_DATE and .author_date < $FIND_UPDATED_BEFORE_DATE ) | . ' active_forks_finder.${reference_owner}.${reference_repo}.forks.branches.json | jq -s '.' | tee active_forks_finder.${reference_owner}.${reference_repo}.forks.report_of_updated_repos_branches.json
  ```

  (https://stedolan.github.io/jq/manual/#Basicfilters is the official doc site for filters)

  Alternativelly, load the active_forks_finder.${reference_owner}.${reference_repo}.forks.branches.json to a db where queries are easier to make.

## Performance

The curl/processing/io takes ~4s/branch/fork.  
So for huge 800+ forks a project with 40+ branches, review and comparison (of 800*40=32000 branches), it takes ~30h and output file (active_forks_finder.${reference_owner}.${reference_repo}.forks.branches.json) is an ~22Mb json.  

**Note:** if this project will become popular, it will worth reviewing which curls/processings can be done in parallel to decrease time (drastically).  

For every api call to github (curl), a "." is printed on the screen.  
' .F' -> when it curls to get forks  
' .B' -> when it curls to get branches  
' .c' -> when it curls to get commit info  
' .C' -> when it curls to make a compare between forks  

A simplistic ETA (not so accurate) and some statistics are printed on the screen during the heavy step 2.

## github apis used

- https://api.github.com/repos/${owner}/${repo}/forks
- https://api.github.com/repos/${owner}/${repo}/branches
- https://api.github.com/repos/${reference_owner}/${reference_repo}/compare/${init_default_compare_branch:-master}...${owner}:${branch}
- https://api.github.com/<commit id>
- https://docs.github.com/en/rest/reference/repos#forks (docs)
- https://github.com/settings/tokens -> very important
