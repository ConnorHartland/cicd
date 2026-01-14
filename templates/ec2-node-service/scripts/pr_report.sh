#!/bin/bash
# pr_report.sh
# Posts a condensed security report to PRs (sonar + npm audit + snyk)

set -e

# Skip if not in PR context
if [ -z "$BITBUCKET_PR_ID" ]; then
  echo "Not in PR context - skipping PR report"
  exit 0
fi

echo "=== Generating PR Security Report ==="

# Get project key from sonar-project.properties
PROJECT_KEY=$(grep "^sonar.projectKey=" sonar-project.properties 2>/dev/null | cut -d'=' -f2 || echo "")
if [ -z "$PROJECT_KEY" ]; then
  PROJECT_KEY=${SONAR_PROJECT_KEY:-"unknown"}
fi

#######################################
# NPM AUDIT
#######################################
echo "Running npm audit..."
NPM_AUDIT_JSON=$(npm audit --json 2>/dev/null || true)

NPM_CRITICAL=$(echo "$NPM_AUDIT_JSON" | jq '.metadata.vulnerabilities.critical // 0')
NPM_HIGH=$(echo "$NPM_AUDIT_JSON" | jq '.metadata.vulnerabilities.high // 0')
NPM_MODERATE=$(echo "$NPM_AUDIT_JSON" | jq '.metadata.vulnerabilities.moderate // 0')
NPM_LOW=$(echo "$NPM_AUDIT_JSON" | jq '.metadata.vulnerabilities.low // 0')
NPM_TOTAL=$(echo "$NPM_AUDIT_JSON" | jq '.metadata.vulnerabilities.total // 0')

#######################################
# SNYK
#######################################
echo "Running Snyk scan..."
SNYK_CRITICAL=0
SNYK_HIGH=0
SNYK_MEDIUM=0
SNYK_LOW=0

if [ -n "$SNYK_TOKEN" ]; then
  SNYK_JSON=$(snyk test --json 2>/dev/null || true)
  if [ -n "$SNYK_JSON" ]; then
    SNYK_CRITICAL=$(echo "$SNYK_JSON" | jq '[.vulnerabilities[]? | select(.severity == "critical")] | length')
    SNYK_HIGH=$(echo "$SNYK_JSON" | jq '[.vulnerabilities[]? | select(.severity == "high")] | length')
    SNYK_MEDIUM=$(echo "$SNYK_JSON" | jq '[.vulnerabilities[]? | select(.severity == "medium")] | length')
    SNYK_LOW=$(echo "$SNYK_JSON" | jq '[.vulnerabilities[]? | select(.severity == "low")] | length')
  fi
fi

#######################################
# SONARQUBE (PR-specific issues)
#######################################
echo "Fetching SonarQube PR results..."
SONAR_STATUS="-"
SONAR_BUGS=0
SONAR_VULNS=0
SONAR_SMELLS=0

if [ -n "$SONAR_TOKEN" ] && [ -n "$SONAR_HOST_URL" ]; then
  # Fetch PR-specific quality gate status
  QG=$(curl -s -u "${SONAR_TOKEN}:" "${SONAR_HOST_URL}/api/qualitygates/project_status?projectKey=${PROJECT_KEY}&pullRequest=${BITBUCKET_PR_ID}" || true)
  SONAR_STATUS=$(echo "$QG" | jq -r '.projectStatus.status // "N/A"')

  # Fetch PR-specific issues (NEW issues introduced by this PR)
  ISSUES=$(curl -s -u "${SONAR_TOKEN}:" \
    "${SONAR_HOST_URL}/api/issues/search?componentKeys=${PROJECT_KEY}&pullRequest=${BITBUCKET_PR_ID}&resolved=false&ps=500" || true)

  if [ -n "$ISSUES" ]; then
    SONAR_BUGS=$(echo "$ISSUES" | jq '[.issues[]? | select(.type == "BUG")] | length')
    SONAR_VULNS=$(echo "$ISSUES" | jq '[.issues[]? | select(.type == "VULNERABILITY")] | length')
    SONAR_SMELLS=$(echo "$ISSUES" | jq '[.issues[]? | select(.type == "CODE_SMELL")] | length')
  fi
fi

#######################################
# BUILD REPORT
#######################################
echo "Building PR report..."

# Determine status icons
SONAR_ICON=":white_check_mark:"
if [ "$SONAR_STATUS" = "ERROR" ]; then
  SONAR_ICON=":x:"
elif [ "$SONAR_STATUS" = "N/A" ] || [ "$SONAR_STATUS" = "-" ]; then
  SONAR_ICON=":grey_question:"
elif [ "$SONAR_BUGS" -gt 0 ] || [ "$SONAR_VULNS" -gt 0 ]; then
  SONAR_ICON=":warning:"
fi

NPM_ICON=":white_check_mark:"
[ "$NPM_CRITICAL" -gt 0 ] || [ "$NPM_HIGH" -gt 0 ] && NPM_ICON=":x:"
[ "$NPM_MODERATE" -gt 0 ] && NPM_ICON=":warning:"

SNYK_ICON=":white_check_mark:"
if [ -z "$SNYK_TOKEN" ]; then
  SNYK_ICON=":grey_question:"
else
  [ "$SNYK_CRITICAL" -gt 0 ] || [ "$SNYK_HIGH" -gt 0 ] && SNYK_ICON=":x:"
  [ "$SNYK_MEDIUM" -gt 0 ] && SNYK_ICON=":warning:"
fi

# Build compact report
SONAR_TOTAL=$((SONAR_BUGS + SONAR_VULNS + SONAR_SMELLS))
REPORT="## :shield: PR Security Report\\n\\n"
REPORT+="_Issues introduced in this PR:_\\n\\n"
REPORT+="| Check | Status | Details |\\n"
REPORT+="|-------|--------|---------|\\n"
REPORT+="| SonarQube | ${SONAR_ICON} ${SONAR_STATUS} | ${SONAR_BUGS} bugs, ${SONAR_VULNS} vulns, ${SONAR_SMELLS} smells |\\n"
REPORT+="| npm audit | ${NPM_ICON} ${NPM_TOTAL} issues | C:${NPM_CRITICAL} H:${NPM_HIGH} M:${NPM_MODERATE} L:${NPM_LOW} |\\n"

if [ -z "$SNYK_TOKEN" ]; then
  REPORT+="| Snyk | ${SNYK_ICON} Skipped | SNYK_TOKEN not configured |\\n"
else
  SNYK_TOTAL=$((SNYK_CRITICAL + SNYK_HIGH + SNYK_MEDIUM + SNYK_LOW))
  REPORT+="| Snyk | ${SNYK_ICON} ${SNYK_TOTAL} issues | C:${SNYK_CRITICAL} H:${SNYK_HIGH} M:${SNYK_MEDIUM} L:${SNYK_LOW} |\\n"
fi

if [ -n "$SONAR_HOST_URL" ]; then
  REPORT+="\\n[View SonarQube Dashboard](${SONAR_HOST_URL}/dashboard?id=${PROJECT_KEY})\\n"
fi

REPORT=$(echo -e "$REPORT")

# Print to console
echo ""
echo "=== PR Security Report ==="
echo -e "$REPORT"

#######################################
# POST TO BITBUCKET PR
#######################################
echo ""
echo "Posting report to PR #${BITBUCKET_PR_ID}..."

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  -u "${BITBUCKET_EMAIL}:${BITBUCKET_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  "https://api.bitbucket.org/2.0/repositories/${BITBUCKET_WORKSPACE}/${BITBUCKET_REPO_SLUG}/pullrequests/${BITBUCKET_PR_ID}/comments" \
  -d "{\"content\": {\"raw\": $(echo "$REPORT" | jq -Rs .)}}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

if [ "$HTTP_CODE" = "201" ]; then
  echo "Report posted successfully"
else
  echo "Failed to post report (HTTP ${HTTP_CODE})"
fi

echo ""
echo "=== PR Report Complete ==="
