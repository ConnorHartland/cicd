#!/bin/bash
# sonar.sh
# Runs SonarQube analysis and posts results to Bitbucket PR
# Requires: SONAR_TOKEN, SONAR_HOST_URL environment variables

set -e

# Check required environment variables
if [ -z "$SONAR_TOKEN" ]; then
  echo "Error: SONAR_TOKEN environment variable is required"
  exit 1
fi

if [ -z "$SONAR_HOST_URL" ]; then
  echo "Error: SONAR_HOST_URL environment variable is required"
  exit 1
fi

# Get project key from package.json name or use env var
PROJECT_KEY=${SONAR_PROJECT_KEY:-$(node -p "require('./package.json').name" 2>/dev/null || echo "")}
PROJECT_VERSION=${SONAR_PROJECT_VERSION:-$(node -p "require('./package.json').version" 2>/dev/null || echo "1.0.0")}

if [ -z "$PROJECT_KEY" ]; then
  echo "Error: Could not determine project key. Set SONAR_PROJECT_KEY or ensure package.json has a name field."
  exit 1
fi

echo "Running SonarQube analysis..."
echo "Project: $PROJECT_KEY"
echo "Version: $PROJECT_VERSION"
echo "Host: $SONAR_HOST_URL"

# Run sonar-scanner
if command -v sonar-scanner &> /dev/null; then
  sonar-scanner \
    -Dsonar.projectKey="$PROJECT_KEY" \
    -Dsonar.projectVersion="$PROJECT_VERSION" \
    -Dsonar.sources=src \
    -Dsonar.host.url="$SONAR_HOST_URL" \
    -Dsonar.token="$SONAR_TOKEN" \
    -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info \
    -Dsonar.testExecutionReportPaths=test-report.xml
elif npm list sonar-scanner &> /dev/null; then
  npx sonar-scanner \
    -Dsonar.projectKey="$PROJECT_KEY" \
    -Dsonar.projectVersion="$PROJECT_VERSION" \
    -Dsonar.sources=src \
    -Dsonar.host.url="$SONAR_HOST_URL" \
    -Dsonar.token="$SONAR_TOKEN" \
    -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info \
    -Dsonar.testExecutionReportPaths=test-report.xml
else
  echo "Error: sonar-scanner not found. Install it globally or add to package.json devDependencies."
  exit 1
fi

echo "SonarQube scan complete. Fetching results..."

# API helper function
API_BASE="${SONAR_HOST_URL}/api"

call_api() {
  local endpoint=$1
  curl -s -u "${SONAR_TOKEN}:" "${API_BASE}${endpoint}"
}

get_metric() {
  local metrics=$1
  local metric_key=$2
  echo "$metrics" | jq -r --arg key "$metric_key" '
    .component.measures[]? |
    select(.metric == $key) |
    .value // "0"
  '
}

# Fetch project info
echo "Fetching project info..."
PROJECT_INFO=$(call_api "/components/show?component=${PROJECT_KEY}")
PROJECT_NAME=$(echo "$PROJECT_INFO" | jq -r '.component.name // "Unknown"')
echo "Project: ${PROJECT_NAME}"

# Fetch measures
echo "Fetching measures..."
METRICS=$(call_api "/measures/component?component=${PROJECT_KEY}&metricKeys=bugs,vulnerabilities,code_smells,coverage,duplicated_lines_density,security_hotspots,sqale_rating,reliability_rating,security_rating")

BUGS=$(get_metric "$METRICS" "bugs")
VULNERABILITIES=$(get_metric "$METRICS" "vulnerabilities")
CODE_SMELLS=$(get_metric "$METRICS" "code_smells")
COVERAGE=$(get_metric "$METRICS" "coverage")
DUPLICATIONS=$(get_metric "$METRICS" "duplicated_lines_density")
HOTSPOTS=$(get_metric "$METRICS" "security_hotspots")

# Fetch quality gate status
echo "Checking quality gate..."
QG=$(call_api "/qualitygates/project_status?projectKey=${PROJECT_KEY}")
QG_STATUS=$(echo "$QG" | jq -r '.projectStatus.status // "NONE"')

QG_CONDITIONS=""
if [ "$QG_STATUS" = "ERROR" ]; then
  QG_CONDITIONS=$(echo "$QG" | jq -r '
    .projectStatus.conditions[] |
    select(.status == "ERROR") |
    "- **\(.metricKey)**: \(.actualValue) (threshold: \(.errorThreshold))"
  ')
fi

# Fetch issues
echo "Fetching issues..."
ISSUES=$(call_api "/issues/search?componentKeys=${PROJECT_KEY}&resolved=false&ps=500")

BUG_COUNT=$(echo "$ISSUES" | jq '[.issues[] | select(.type == "BUG")] | length')
VULN_COUNT=$(echo "$ISSUES" | jq '[.issues[] | select(.type == "VULNERABILITY")] | length')
SMELL_COUNT=$(echo "$ISSUES" | jq '[.issues[] | select(.type == "CODE_SMELL")] | length')

BLOCKER=$(echo "$ISSUES" | jq '[.issues[] | select(.severity == "BLOCKER")] | length')
HIGH=$(echo "$ISSUES" | jq '[.issues[] | select(.severity == "CRITICAL")] | length')
MEDIUM=$(echo "$ISSUES" | jq '[.issues[] | select(.severity == "MAJOR")] | length')

# Print results
echo ""
echo "=== SonarQube Results ==="
echo "Quality Gate: ${QG_STATUS}"
echo "Bugs: ${BUGS}"
echo "Vulnerabilities: ${VULNERABILITIES}"
echo "Code Smells: ${CODE_SMELLS}"
echo "Coverage: ${COVERAGE}%"
echo "Duplications: ${DUPLICATIONS}%"
echo "Security Hotspots: ${HOTSPOTS}"
echo ""
echo "Issue breakdown - Bugs: ${BUG_COUNT}, Vulnerabilities: ${VULN_COUNT}, Code Smells: ${SMELL_COUNT}"
echo "By severity - Blocker: ${BLOCKER}, High: ${HIGH}, Major: ${MEDIUM}"
echo ""

# Build PR comment
COMMENT="## :chart_with_upwards_trend: SonarQube Analysis\n\n"
COMMENT+="**Project:** ${PROJECT_NAME}\n\n"
COMMENT+="[View Full Report](${SONAR_HOST_URL}/dashboard?id=${PROJECT_KEY})\n\n"
COMMENT+="---\n\n"

# Quality gate section
if [ "$QG_STATUS" = "OK" ]; then
  COMMENT+="### :white_check_mark: Quality Gate: PASSED\n\n"
elif [ "$QG_STATUS" = "ERROR" ]; then
  COMMENT+="### :x: Quality Gate: FAILED\n\n"
  if [ -n "$QG_CONDITIONS" ]; then
    COMMENT+="**Failed Conditions:**\n${QG_CONDITIONS}\n\n"
  fi
else
  COMMENT+="### Quality Gate: ${QG_STATUS}\n\n"
fi

# Metrics table
COMMENT+="### Metrics Overview\n\n"
COMMENT+="| Metric | Value |\n"
COMMENT+="|--------|-------|\n"
COMMENT+="| :bug: Bugs | **${BUGS}** |\n"
COMMENT+="| :lock: Vulnerabilities | **${VULNERABILITIES}** |\n"
COMMENT+="| :poop: Code Smells | **${CODE_SMELLS}** |\n"
COMMENT+="| :fire: Security Hotspots | **${HOTSPOTS}** |\n"
COMMENT+="\n"

# Severity table
COMMENT+="### Severity Overview\n\n"
COMMENT+="| Severity | Value |\n"
COMMENT+="|--------|-------|\n"
COMMENT+="| :octagonal_sign: Blocker | **${BLOCKER}** |\n"
COMMENT+="| :bangbang: High | **${HIGH}** |\n"
COMMENT+="| :warning: Medium | **${MEDIUM}** |\n"

COMMENT=$(echo -e "$COMMENT")

# Post to Bitbucket PR if in PR context
if [ -n "$BITBUCKET_PR_ID" ]; then
  echo "Posting to PR #${BITBUCKET_PR_ID}..."

  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    -u "${BITBUCKET_EMAIL}:${BITBUCKET_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    "https://api.bitbucket.org/2.0/repositories/${BITBUCKET_WORKSPACE}/${BITBUCKET_REPO_SLUG}/pullrequests/${BITBUCKET_PR_ID}/comments" \
    -d "{\"content\": {\"raw\": $(echo "$COMMENT" | jq -Rs .)}}")

  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  BODY=$(echo "$RESPONSE" | head -n-1)

  if [ "$HTTP_CODE" = "201" ]; then
    echo "Comment posted successfully"
  else
    echo "Failed to post comment (HTTP ${HTTP_CODE})"
    echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
  fi
else
  echo "Not in PR context - skipping comment post"
fi

# Fail pipeline if quality gate failed
if [ "$QG_STATUS" = "ERROR" ]; then
  echo "Quality gate failed - failing pipeline"
  exit 1
fi

echo "SonarQube analysis complete"
