#!/bin/bash
# report_utils.sh - Shared utilities for security reports

# Temp directory for large JSON files (avoids "Argument list too long" errors)
# Uses local .tmp dir for CI/CD isolation (cleaned up with workspace)
REPORT_TMP_DIR="${BITBUCKET_CLONE_DIR:-.}/.tmp/report_$$"
mkdir -p "$REPORT_TMP_DIR"

# Cleanup temp files on exit
cleanup_report_tmp() {
  rm -rf "$REPORT_TMP_DIR"
}
trap cleanup_report_tmp EXIT

#######################################
# Get project key from sonar-project.properties
#######################################
get_project_key() {
  local key
  key=$(grep "^sonar.projectKey=" sonar-project.properties 2>/dev/null | cut -d'=' -f2 || echo "")
  echo "${key:-${SONAR_PROJECT_KEY:-unknown}}"
}

#######################################
# Run npm audit and export NPM_* variables
# Uses temp files to avoid "Argument list too long" errors
#######################################
run_npm_audit() {
  echo "Running npm audit..."

  NPM_AUDIT_FILE="$REPORT_TMP_DIR/npm_audit.json"
  # npm audit returns non-zero when vulnerabilities found, so don't use ||
  npm audit --json > "$NPM_AUDIT_FILE" 2>&1 || true

  # Ensure file exists and has valid JSON
  if [ ! -s "$NPM_AUDIT_FILE" ] || ! jq empty < "$NPM_AUDIT_FILE" 2>/dev/null; then
    echo '{}' > "$NPM_AUDIT_FILE"
  fi

  NPM_CRITICAL=$(jq '.metadata.vulnerabilities.critical // 0' < "$NPM_AUDIT_FILE")
  NPM_HIGH=$(jq '.metadata.vulnerabilities.high // 0' < "$NPM_AUDIT_FILE")
  NPM_MODERATE=$(jq '.metadata.vulnerabilities.moderate // 0' < "$NPM_AUDIT_FILE")
  NPM_LOW=$(jq '.metadata.vulnerabilities.low // 0' < "$NPM_AUDIT_FILE")
  NPM_TOTAL=$(jq '.metadata.vulnerabilities.total // 0' < "$NPM_AUDIT_FILE")

  export NPM_AUDIT_FILE NPM_CRITICAL NPM_HIGH NPM_MODERATE NPM_LOW NPM_TOTAL
}

#######################################
# Extract npm vulnerability details (critical/high)
# Uses temp files to avoid "Argument list too long" errors
#######################################
extract_npm_details() {
  NPM_DETAILS=""
  if [ "$NPM_CRITICAL" -gt 0 ] || [ "$NPM_HIGH" -gt 0 ]; then
    NPM_DETAILS=$(jq -r '
      .vulnerabilities | to_entries[] |
      select(.value.severity == "critical" or .value.severity == "high") |
      "\(.value.severity | ascii_upcase)|\(.key)|\(.value.via[0].title // .value.via[0] // "N/A")"
    ' < "$NPM_AUDIT_FILE" 2>/dev/null | head -50 || true)
  fi
  export NPM_DETAILS
}

#######################################
# Run Snyk scan and export SNYK_* variables
# Uses temp files to avoid "Argument list too long" errors
#######################################
run_snyk_scan() {
  echo "Running Snyk scan..."

  SNYK_FILE="$REPORT_TMP_DIR/snyk.json"
  SNYK_CRITICAL=0
  SNYK_HIGH=0
  SNYK_MEDIUM=0
  SNYK_LOW=0

  if [ -n "$SNYK_TOKEN" ]; then
    # snyk returns non-zero when vulnerabilities found, so don't use ||
    snyk test --json > "$SNYK_FILE" 2>&1 || true

    # Ensure file exists and has valid JSON
    if [ ! -s "$SNYK_FILE" ] || ! jq empty < "$SNYK_FILE" 2>/dev/null; then
      echo '{}' > "$SNYK_FILE"
    fi

    SNYK_CRITICAL=$(jq '[.vulnerabilities[]? | select(.severity == "critical")] | length' < "$SNYK_FILE")
    SNYK_HIGH=$(jq '[.vulnerabilities[]? | select(.severity == "high")] | length' < "$SNYK_FILE")
    SNYK_MEDIUM=$(jq '[.vulnerabilities[]? | select(.severity == "medium")] | length' < "$SNYK_FILE")
    SNYK_LOW=$(jq '[.vulnerabilities[]? | select(.severity == "low")] | length' < "$SNYK_FILE")
  else
    echo '{}' > "$SNYK_FILE"
  fi

  export SNYK_FILE SNYK_CRITICAL SNYK_HIGH SNYK_MEDIUM SNYK_LOW
}

#######################################
# Extract Snyk vulnerability details (critical/high)
# Uses temp files to avoid "Argument list too long" errors
#######################################
extract_snyk_details() {
  SNYK_DETAILS=""
  if [ -n "$SNYK_TOKEN" ]; then
    if [ "$SNYK_CRITICAL" -gt 0 ] || [ "$SNYK_HIGH" -gt 0 ]; then
      SNYK_DETAILS=$(jq -r '
        [.vulnerabilities[]? | select(.severity == "critical" or .severity == "high")] |
        unique_by(.id) | .[:50][] |
        "\(.severity | ascii_upcase)|\(.packageName)|\(.title // "N/A")"
      ' < "$SNYK_FILE" 2>/dev/null || true)
    fi
  fi
  export SNYK_DETAILS
}

#######################################
# Fetch SonarQube metrics and export SONAR_* variables
#######################################
fetch_sonarqube() {
  local project_key=$1
  echo "Fetching SonarQube results..."

  SONAR_BUGS="-"
  SONAR_VULNS="-"
  SONAR_SMELLS="-"
  SONAR_COVERAGE="-"
  SONAR_HOTSPOTS="-"
  SONAR_QG_STATUS="N/A"

  if [ -n "$SONAR_TOKEN" ] && [ -n "$SONAR_HOST_URL" ]; then
    local api_base="${SONAR_HOST_URL}/api"

    # Fetch quality gate status
    local qg
    qg=$(curl -s -u "${SONAR_TOKEN}:" "${api_base}/qualitygates/project_status?projectKey=${project_key}" || true)
    SONAR_QG_STATUS=$(echo "$qg" | jq -r '.projectStatus.status // "N/A"')

    # Fetch project measures
    local metrics
    metrics=$(curl -s -u "${SONAR_TOKEN}:" \
      "${api_base}/measures/component?component=${project_key}&metricKeys=bugs,vulnerabilities,code_smells,coverage,security_hotspots" || true)

    if [ -n "$metrics" ]; then
      SONAR_BUGS=$(echo "$metrics" | jq -r '.component.measures[]? | select(.metric == "bugs") | .value // "-"')
      SONAR_VULNS=$(echo "$metrics" | jq -r '.component.measures[]? | select(.metric == "vulnerabilities") | .value // "-"')
      SONAR_SMELLS=$(echo "$metrics" | jq -r '.component.measures[]? | select(.metric == "code_smells") | .value // "-"')
      SONAR_COVERAGE=$(echo "$metrics" | jq -r '.component.measures[]? | select(.metric == "coverage") | .value // "-"')
      SONAR_HOTSPOTS=$(echo "$metrics" | jq -r '.component.measures[]? | select(.metric == "security_hotspots") | .value // "-"')
    fi
  fi

  export SONAR_BUGS SONAR_VULNS SONAR_SMELLS SONAR_COVERAGE SONAR_HOTSPOTS SONAR_QG_STATUS
}

#######################################
# Fetch SonarQube blocker/critical issues
#######################################
fetch_sonar_issues() {
  local project_key=$1
  SONAR_DETAILS=""

  if [ -n "$SONAR_TOKEN" ] && [ -n "$SONAR_HOST_URL" ]; then
    local issues_json
    issues_json=$(curl -s -u "${SONAR_TOKEN}:" \
      "${SONAR_HOST_URL}/api/issues/search?componentKeys=${project_key}&severities=BLOCKER,CRITICAL&resolved=false&ps=50" || true)

    if [ -n "$issues_json" ]; then
      SONAR_DETAILS=$(echo "$issues_json" | jq -r '
        .issues[]? |
        "\(.severity)|\(.message | gsub("\\|"; "-") | .[0:80])|\(.component | split(":") | last)"
      ' 2>/dev/null || true)
    fi
  fi

  export SONAR_DETAILS
}

#######################################
# Post comment to Bitbucket PR
# Returns: HTTP status code
# Uses temp file to avoid "Argument list too long" errors
#######################################
post_to_pr() {
  local content=$1

  if [ -z "$BITBUCKET_PR_ID" ]; then
    echo "Not in PR context - skipping PR comment"
    return 1
  fi

  echo "Posting report to PR #${BITBUCKET_PR_ID}..."

  # Write content to temp file, then build JSON payload
  local content_file="$REPORT_TMP_DIR/pr_content.txt"
  local payload_file="$REPORT_TMP_DIR/pr_payload.json"

  printf '%s' "$content" > "$content_file"

  # Build JSON payload using jq with file input
  jq -n --rawfile content "$content_file" '{"content": {"raw": $content}}' > "$payload_file"

  local response
  response=$(curl -s -w "\n%{http_code}" -X POST \
    -u "${BITBUCKET_EMAIL}:${BITBUCKET_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    "https://api.bitbucket.org/2.0/repositories/${BITBUCKET_WORKSPACE}/${BITBUCKET_REPO_SLUG}/pullrequests/${BITBUCKET_PR_ID}/comments" \
    -d @"$payload_file")

  local http_code
  http_code=$(echo "$response" | tail -n1)

  if [ "$http_code" = "201" ]; then
    echo "Report posted successfully"
    return 0
  else
    echo "Failed to post report (HTTP ${http_code})"
    echo "$response" | head -n -1
    return 1
  fi
}

#######################################
# Get git commit summary (commits in this branch not in main)
#######################################
get_git_summary() {
  local limit=${1:-20}
  GIT_COMMITS=""
  GIT_COMMITS_JSON="[]"

  # Try to get commits since branching from main/master
  local base_branch=""
  if git rev-parse --verify origin/main >/dev/null 2>&1; then
    base_branch="origin/main"
  elif git rev-parse --verify origin/master >/dev/null 2>&1; then
    base_branch="origin/master"
  elif git rev-parse --verify main >/dev/null 2>&1; then
    base_branch="main"
  elif git rev-parse --verify master >/dev/null 2>&1; then
    base_branch="master"
  fi

  if [ -n "$base_branch" ]; then
    # Get commits since branching from main
    GIT_COMMITS=$(git log "${base_branch}..HEAD" --pretty=format:"%h|%s|%an" -n "$limit" 2>/dev/null || true)
  fi

  # Fallback to recent commits if no base branch or no commits found
  if [ -z "$GIT_COMMITS" ]; then
    GIT_COMMITS=$(git log --pretty=format:"%h|%s|%an" -n "$limit" 2>/dev/null || true)
  fi

  # Build JSON array
  if [ -n "$GIT_COMMITS" ]; then
    GIT_COMMITS_JSON=$(echo "$GIT_COMMITS" | jq -R -s '
      split("\n") | map(select(length > 0)) | map(
        split("|") | {
          sha: .[0],
          message: .[1],
          author: .[2]
        }
      )
    ' 2>/dev/null || echo "[]")
  fi

  export GIT_COMMITS GIT_COMMITS_JSON
}

#######################################
# Get current timestamp in Central Time
#######################################
get_timestamp() {
  TZ='America/Chicago' date '+%Y-%m-%d %H:%M:%S CT'
}

#######################################
# Get ISO timestamp for JSON
#######################################
get_iso_timestamp() {
  TZ='America/Chicago' date '+%Y-%m-%dT%H:%M:%S-06:00'
}

#######################################
# Determine status icon based on values
#######################################
get_status_icon() {
  local type=$1
  local critical=$2
  local high=$3
  local medium=${4:-0}

  case $type in
    sonar)
      if [ "$SONAR_QG_STATUS" = "ERROR" ]; then
        echo ":x:"
      elif [ "$SONAR_QG_STATUS" = "N/A" ] || [ "$SONAR_QG_STATUS" = "-" ]; then
        echo ":grey_question:"
      elif [ "$critical" -gt 0 ] || [ "$high" -gt 0 ]; then
        echo ":warning:"
      else
        echo ":white_check_mark:"
      fi
      ;;
    npm|snyk)
      if [ "$critical" -gt 0 ] || [ "$high" -gt 0 ]; then
        echo ":x:"
      elif [ "$medium" -gt 0 ]; then
        echo ":warning:"
      else
        echo ":white_check_mark:"
      fi
      ;;
    *)
      echo ":grey_question:"
      ;;
  esac
}
