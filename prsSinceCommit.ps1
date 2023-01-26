param (
    [Parameter(Mandatory)]
    [string]
    $RepoName,

    [string]
    $CommitHash,

    [string]
    $EndCommitHash,

    [string]
    $ClientRepo,

    [switch]
    $FindRisk
)

$OwnerRepo = "TechSmith/$RepoName"

#Write-Output "REPO = $RepoName"

function Get-SubmoduleHash {
    param ( [string] $ClientRepo,
            [string] $SubmoduleName )

    $GRAPHQL_QUERY=@"
query allSubmodules(`$org: String!, `$repo: String!)
{
organization(login: `$org) 
  {
    repository(name: `$repo)
    {
      submodules(first: 100)
      {
        nodes
        {
          name
          path
          subprojectCommitOid
        }
      }
    }
  }
}
"@

    $Json = gh api graphql -F org=TechSmith -F repo=$ClientRepo -f query="$GRAPHQL_QUERY" | ConvertFrom-Json

    $SubmodInfo = $Json.data.organization.repository.submodules.nodes | Where-Object { $_.name -eq "$SubmoduleName" }

    $SubmodInfo.subprojectCommitOid
}

if ( $CommitHash -and $ClientRepo ) {
    Write-Output "Warning: When using ClientRepo it will retrieve the commit hash and use that disregarding any passed CommitHash."
}

# If using client repo to find the commit hash
if ( $ClientRepo )
{
    #Note passing in ClientRepo & RepoName  (e.g. CommonCpp not TechSmith/CommonCpp)
    $CommitHash = Get-SubmoduleHash -ClientRepo $ClientRepo -SubmoduleName $RepoName
}

function Get-PrNumber {
   param ( $GitHubPRString )

   $Output = $GitHubPRString -replace '\s+', ' ' # Replace multiple spaces with one space so the next operation will work
   $CurrentPR = $Output.Split(" ")[0] # Extract the actual PR number

   "$CurrentPR"
}

function Get-Risks {
   param ( [string] $PRText )

   $RiskEnd = '\n*### \*\*How Did You Verify Quality\?\*\*'
   $RiskBegin = '### \*\*What do clients need to know about this PR\?\*\*\n*'
   $RiskPattern = "$RiskBegin((.|\n)*?)$RiskEnd"

   $RiskResult = [regex]::Match($PRText,$RiskPattern).Groups[1].Value

   if( !$RiskResult ) {
      $OldRiskBegin = '### \*\*What Are The Risks Associated With This PR\?\*\*\n*'
      $OldRiskPattern = "$OldRiskBegin((.|\n)*?)$RiskEnd"
   
      $RiskResult = [regex]::Match($PRText,$OldRiskPattern).Groups[1].Value
   }

   if( [string]::IsNullOrEmpty( $RiskResult ) ) {
      $RiskResult = 'COULD NOT FIND RISKS! Might want to double-check the PR link'
   }

   $RiskResult
}

$Output = gh pr list --repo $OwnerRepo --search "$CommitHash is:merged"
$CurrentPR = Get-PrNumber -GitHubPRString $Output

Write-Output "Commit hash $CommitHash belongs to PR #$CurrentPR"

$CurrentPRMergeDate = gh pr view $CurrentPR --repo $OwnerRepo --json mergedAt --template '{{.mergedAt}}'

Write-Output "Merge date of PR ``$CurrentPR`` is ``$CurrentPRMergeDate``."

if ( $EndCommitHash.Length -ge 7 ) {
   $Output = gh pr list --repo $OwnerRepo --search "$EndCommitHash is:merged"
   $EndPR = Get-PrNumber -GitHubPRString $Output
   Write-Output ""
   Write-Output "Commit hash ``$EndCommitHash`` belongs to PR https://github.com/$OwnerRepo/pull/$EndPR"
   $EndPRMergeDate = gh pr view $EndPR --repo $OwnerRepo --json mergedAt --jq '.mergedAt'
   Write-Output "And the merge date of that PR is ``$EndPRMergeDate``."
   Write-Output ""
   Write-Output "Finding you the PRs merged:$CurrentPRMergeDate..$EndPRMergeDate"
   Write-Output ""
   $PRs = gh pr list -S "merged:$CurrentPRMergeDate..$EndPRMergeDate sort:merge-date" --limit 500 --repo $OwnerRepo  
}
else {
    Write-Output "Listing all PRs that have been merged since then..."
    $PRs = gh pr list -S "merged:>$CurrentPRMergeDate sort:merge-date" --limit 500 --repo $OwnerRepo
}

foreach($PRSTR in $PRs) {
   $PRNumber = Get-PrNumber -GitHubPRString $PRSTR

   # If commit is part of current PR skip over it.
   if ( $PRNumber -eq $CurrentPR ) {
      continue
   }

   Write-Output "https://github.com/$OwnerRepo/pull/$PRNumber"
   
   if( $FindRisk -eq $true ) {
      $PRText = gh pr view $PRNumber --repo $OwnerRepo
      $Risk = Get-Risks -PRText $PRText
      Write-Output "RISK: $Risk"
   }
}
