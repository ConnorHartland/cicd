#!/bin/bash
# release_report.sh
# Generates a consolidated security/quality report for releases
# Posts combined SonarQube + Snyk + npm audit results to Bitbucket PR

set -e

echo "=== Generating Release Security Report ==="

# Extract version from branch name (release/X.X.X)
VERSION=${BITBUCKET_BRANCH#release/}
echo "Release Version: ${VERSION}"

# Get project info
# Get project key from sonar-project.properties
PROJECT_KEY=$(grep "^sonar.projectKey=" sonar-project.properties 2>/dev/null | cut -d'=' -f2 || echo "")
if [ -z "$PROJECT_KEY" ]; then
  PROJECT_KEY=${SONAR_PROJECT_KEY:-"unknown"}
fi
PROJECT_NAME=$(node -p "require('./package.json').name" 2>/dev/null || echo "Unknown Project")

#######################################
# NPM AUDIT
#######################################
echo ""
echo "Running npm audit..."

NPM_AUDIT_JSON=$(npm audit --json 2>/dev/null || true)

NPM_CRITICAL=$(echo "$NPM_AUDIT_JSON" | jq '.metadata.vulnerabilities.critical // 0')
NPM_HIGH=$(echo "$NPM_AUDIT_JSON" | jq '.metadata.vulnerabilities.high // 0')
NPM_MODERATE=$(echo "$NPM_AUDIT_JSON" | jq '.metadata.vulnerabilities.moderate // 0')
NPM_LOW=$(echo "$NPM_AUDIT_JSON" | jq '.metadata.vulnerabilities.low // 0')
NPM_TOTAL=$(echo "$NPM_AUDIT_JSON" | jq '.metadata.vulnerabilities.total // 0')

# Extract critical/high vulnerability details
NPM_DETAILS=""
if [ "$NPM_CRITICAL" -gt 0 ] || [ "$NPM_HIGH" -gt 0 ]; then
  NPM_DETAILS=$(echo "$NPM_AUDIT_JSON" | jq -r '
    .vulnerabilities | to_entries[] |
    select(.value.severity == "critical" or .value.severity == "high") |
    "| \(.value.severity | ascii_upcase) | \(.key) | \(.value.via[0].title // .value.via[0] // "N/A") |"
  ' 2>/dev/null | head -20 || true)
fi

echo "npm audit - Critical: ${NPM_CRITICAL}, High: ${NPM_HIGH}, Moderate: ${NPM_MODERATE}, Low: ${NPM_LOW}"

#######################################
# SNYK
#######################################
echo ""
echo "Running Snyk scan..."

SNYK_JSON=""
SNYK_CRITICAL=0
SNYK_HIGH=0
SNYK_MEDIUM=0
SNYK_LOW=0

SNYK_DETAILS=""
if [ -n "$SNYK_TOKEN" ]; then
  SNYK_JSON=$(snyk test --json 2>/dev/null || true)

  if [ -n "$SNYK_JSON" ]; then
    SNYK_CRITICAL=$(echo "$SNYK_JSON" | jq '[.vulnerabilities[]? | select(.severity == "critical")] | length')
    SNYK_HIGH=$(echo "$SNYK_JSON" | jq '[.vulnerabilities[]? | select(.severity == "high")] | length')
    SNYK_MEDIUM=$(echo "$SNYK_JSON" | jq '[.vulnerabilities[]? | select(.severity == "medium")] | length')
    SNYK_LOW=$(echo "$SNYK_JSON" | jq '[.vulnerabilities[]? | select(.severity == "low")] | length')

    # Extract critical/high vulnerability details
    if [ "$SNYK_CRITICAL" -gt 0 ] || [ "$SNYK_HIGH" -gt 0 ]; then
      SNYK_DETAILS=$(echo "$SNYK_JSON" | jq -r '
        [.vulnerabilities[]? | select(.severity == "critical" or .severity == "high")] |
        unique_by(.id) | .[:20][] |
        "| \(.severity | ascii_upcase) | \(.packageName) | \(.title // "N/A") |"
      ' 2>/dev/null || true)
    fi
  fi
  echo "Snyk - Critical: ${SNYK_CRITICAL}, High: ${SNYK_HIGH}, Medium: ${SNYK_MEDIUM}, Low: ${SNYK_LOW}"
else
  echo "SNYK_TOKEN not set - skipping Snyk scan"
fi

#######################################
# SONARQUBE
#######################################
echo ""
echo "Fetching SonarQube results..."

SONAR_BUGS="-"
SONAR_VULNS="-"
SONAR_SMELLS="-"
SONAR_COVERAGE="-"
SONAR_HOTSPOTS="-"
SONAR_QG_STATUS="N/A"
SONAR_DETAILS=""

if [ -n "$SONAR_TOKEN" ] && [ -n "$SONAR_HOST_URL" ]; then
  API_BASE="${SONAR_HOST_URL}/api"

  # Fetch measures
  METRICS=$(curl -s -u "${SONAR_TOKEN}:" \
    "${API_BASE}/measures/component?component=${PROJECT_KEY}&metricKeys=bugs,vulnerabilities,code_smells,coverage,security_hotspots" || true)

  if [ -n "$METRICS" ]; then
    SONAR_BUGS=$(echo "$METRICS" | jq -r '.component.measures[]? | select(.metric == "bugs") | .value // "-"')
    SONAR_VULNS=$(echo "$METRICS" | jq -r '.component.measures[]? | select(.metric == "vulnerabilities") | .value // "-"')
    SONAR_SMELLS=$(echo "$METRICS" | jq -r '.component.measures[]? | select(.metric == "code_smells") | .value // "-"')
    SONAR_COVERAGE=$(echo "$METRICS" | jq -r '.component.measures[]? | select(.metric == "coverage") | .value // "-"')
    SONAR_HOTSPOTS=$(echo "$METRICS" | jq -r '.component.measures[]? | select(.metric == "security_hotspots") | .value // "-"')
  fi

  # Fetch quality gate
  QG=$(curl -s -u "${SONAR_TOKEN}:" "${API_BASE}/qualitygates/project_status?projectKey=${PROJECT_KEY}" || true)
  SONAR_QG_STATUS=$(echo "$QG" | jq -r '.projectStatus.status // "N/A"')

  # Fetch blocker/critical issues
  ISSUES_JSON=$(curl -s -u "${SONAR_TOKEN}:" \
    "${API_BASE}/issues/search?componentKeys=${PROJECT_KEY}&severities=BLOCKER,CRITICAL&resolved=false&ps=20" || true)
  if [ -n "$ISSUES_JSON" ]; then
    SONAR_DETAILS=$(echo "$ISSUES_JSON" | jq -r '
      .issues[]? |
      "| \(.severity) | \(.message[0:60] | gsub("\\|"; "-"))... | \(.component | split(":") | last) |"
    ' 2>/dev/null || true)
  fi

  echo "SonarQube - QG: ${SONAR_QG_STATUS}, Bugs: ${SONAR_BUGS}, Vulns: ${SONAR_VULNS}"
else
  echo "SONAR_TOKEN/SONAR_HOST_URL not set - skipping SonarQube"
fi

#######################################
# BUILD REPORT
#######################################
echo ""
echo "Building release report..."

# Determine overall status
OVERALL_STATUS=":white_check_mark: PASSED"
if [ "$SONAR_QG_STATUS" = "ERROR" ] || [ "$NPM_CRITICAL" -gt 0 ] || [ "$SNYK_CRITICAL" -gt 0 ]; then
  OVERALL_STATUS=":x: FAILED"
elif [ "$NPM_HIGH" -gt 0 ] || [ "$SNYK_HIGH" -gt 0 ]; then
  OVERALL_STATUS=":warning: WARNINGS"
fi

REPORT="## :package: Release Report - v${VERSION}\n\n"
REPORT+="**Project:** ${PROJECT_NAME}\n"
REPORT+="**Branch:** ${BITBUCKET_BRANCH}\n"
REPORT+="**Commit:** ${BITBUCKET_COMMIT:0:7}\n"
REPORT+="**Overall Status:** ${OVERALL_STATUS}\n\n"
REPORT+="---\n\n"

# SonarQube Section
REPORT+="### :mag: Code Quality (SonarQube)\n\n"
if [ "$SONAR_QG_STATUS" = "OK" ]; then
  REPORT+=":white_check_mark: **Quality Gate: PASSED**\n\n"
elif [ "$SONAR_QG_STATUS" = "ERROR" ]; then
  REPORT+=":x: **Quality Gate: FAILED**\n\n"
else
  REPORT+="**Quality Gate:** ${SONAR_QG_STATUS}\n\n"
fi

REPORT+="| Metric | Value |\n"
REPORT+="|--------|-------|\n"
REPORT+="| :bug: Bugs | ${SONAR_BUGS} |\n"
REPORT+="| :lock: Vulnerabilities | ${SONAR_VULNS} |\n"
REPORT+="| :poop: Code Smells | ${SONAR_SMELLS} |\n"
REPORT+="| :fire: Security Hotspots | ${SONAR_HOTSPOTS} |\n"
REPORT+="| :bar_chart: Coverage | ${SONAR_COVERAGE}% |\n\n"

# Add collapsible blocker/critical issues
if [ -n "$SONAR_DETAILS" ]; then
  SONAR_ISSUE_COUNT=$(echo "$SONAR_DETAILS" | grep -c "^|" || echo "0")
  REPORT+="<details>\n"
  REPORT+="<summary>View Blocker/Critical Issues (${SONAR_ISSUE_COUNT})</summary>\n\n"
  REPORT+="| Severity | Message | File |\n"
  REPORT+="|----------|---------|------|\n"
  REPORT+="${SONAR_DETAILS}\n\n"
  REPORT+="</details>\n\n"
fi

if [ -n "$SONAR_HOST_URL" ]; then
  REPORT+="[View Full SonarQube Report](${SONAR_HOST_URL}/dashboard?id=${PROJECT_KEY})\n\n"
fi

# npm audit Section
REPORT+="---\n\n"
REPORT+="### :package: Dependency Audit (npm)\n\n"

if [ "$NPM_TOTAL" -eq 0 ]; then
  REPORT+=":white_check_mark: **No vulnerabilities found**\n\n"
else
  REPORT+="| Severity | Count |\n"
  REPORT+="|----------|-------|\n"
  REPORT+="| :octagonal_sign: Critical | ${NPM_CRITICAL} |\n"
  REPORT+="| :bangbang: High | ${NPM_HIGH} |\n"
  REPORT+="| :warning: Moderate | ${NPM_MODERATE} |\n"
  REPORT+="| :information_source: Low | ${NPM_LOW} |\n"
  REPORT+="| **Total** | **${NPM_TOTAL}** |\n\n"

  # Add collapsible critical/high vulnerabilities
  if [ -n "$NPM_DETAILS" ]; then
    NPM_DETAIL_COUNT=$((NPM_CRITICAL + NPM_HIGH))
    REPORT+="<details>\n"
    REPORT+="<summary>View Critical/High Vulnerabilities (${NPM_DETAIL_COUNT})</summary>\n\n"
    REPORT+="| Severity | Package | Description |\n"
    REPORT+="|----------|---------|-------------|\n"
    REPORT+="${NPM_DETAILS}\n\n"
    REPORT+="</details>\n\n"
  fi
fi

# Snyk Section
REPORT+="---\n\n"
REPORT+="### :shield: Security Scan (Snyk)\n\n"

if [ -z "$SNYK_TOKEN" ]; then
  REPORT+="_Snyk scan skipped (SNYK_TOKEN not configured)_\n\n"
elif [ "$SNYK_CRITICAL" -eq 0 ] && [ "$SNYK_HIGH" -eq 0 ] && [ "$SNYK_MEDIUM" -eq 0 ] && [ "$SNYK_LOW" -eq 0 ]; then
  REPORT+=":white_check_mark: **No vulnerabilities found**\n\n"
else
  REPORT+="| Severity | Count |\n"
  REPORT+="|----------|-------|\n"
  REPORT+="| :octagonal_sign: Critical | ${SNYK_CRITICAL} |\n"
  REPORT+="| :bangbang: High | ${SNYK_HIGH} |\n"
  REPORT+="| :warning: Medium | ${SNYK_MEDIUM} |\n"
  REPORT+="| :information_source: Low | ${SNYK_LOW} |\n\n"

  # Add collapsible critical/high vulnerabilities
  if [ -n "$SNYK_DETAILS" ]; then
    SNYK_DETAIL_COUNT=$((SNYK_CRITICAL + SNYK_HIGH))
    REPORT+="<details>\n"
    REPORT+="<summary>View Critical/High Vulnerabilities (${SNYK_DETAIL_COUNT})</summary>\n\n"
    REPORT+="| Severity | Package | Description |\n"
    REPORT+="|----------|---------|-------------|\n"
    REPORT+="${SNYK_DETAILS}\n\n"
    REPORT+="</details>\n\n"
  fi
fi

# Footer
REPORT+="---\n\n"
REPORT+="_Generated by CI/CD Pipeline | $(TZ='America/Chicago' date '+%Y-%m-%d %H:%M:%S CT')_\n"

REPORT=$(echo -e "$REPORT")

# Print report to console
echo ""
echo "=== Release Report ==="
echo -e "$REPORT"

#######################################
# POST TO BITBUCKET PR
#######################################
if [ -n "$BITBUCKET_PR_ID" ]; then
  echo ""
  echo "Posting report to PR #${BITBUCKET_PR_ID}..."

  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    -u "${BITBUCKET_EMAIL}:${BITBUCKET_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    "https://api.bitbucket.org/2.0/repositories/${BITBUCKET_WORKSPACE}/${BITBUCKET_REPO_SLUG}/pullrequests/${BITBUCKET_PR_ID}/comments" \
    -d "{\"content\": {\"raw\": $(echo "$REPORT" | jq -Rs .)}}")

  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  BODY=$(echo "$RESPONSE" | head -n-1)

  if [ "$HTTP_CODE" = "201" ]; then
    echo "Release report posted successfully"
  else
    echo "Failed to post report (HTTP ${HTTP_CODE})"
    echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
  fi
else
  echo ""
  echo "Not in PR context - report printed to console only"
fi

#######################################
# SAVE REPORT ARTIFACTS
#######################################
echo ""
echo "Saving report artifacts..."

# Save JSON report
cat > release-report.json << EOF
{
  "version": "${VERSION}",
  "project": "${PROJECT_NAME}",
  "branch": "${BITBUCKET_BRANCH}",
  "commit": "${BITBUCKET_COMMIT}",
  "timestamp": "$(TZ='America/Chicago' date '+%Y-%m-%dT%H:%M:%S-06:00')",
  "sonarqube": {
    "qualityGate": "${SONAR_QG_STATUS}",
    "bugs": "${SONAR_BUGS}",
    "vulnerabilities": "${SONAR_VULNS}",
    "codeSmells": "${SONAR_SMELLS}",
    "coverage": "${SONAR_COVERAGE}",
    "securityHotspots": "${SONAR_HOTSPOTS}"
  },
  "npmAudit": {
    "critical": ${NPM_CRITICAL},
    "high": ${NPM_HIGH},
    "moderate": ${NPM_MODERATE},
    "low": ${NPM_LOW},
    "total": ${NPM_TOTAL}
  },
  "snyk": {
    "critical": ${SNYK_CRITICAL},
    "high": ${SNYK_HIGH},
    "medium": ${SNYK_MEDIUM},
    "low": ${SNYK_LOW}
  }
}
EOF

echo "Saved release-report.json"

echo ""
echo "=== Release Report Complete ==="
