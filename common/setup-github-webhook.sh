#!/bin/bash
set -e

echo "================================================"
echo "Setup GitHub Webhook for ArgoCD"
echo "================================================"
echo ""

# Check if gh CLI is installed
if ! command -v gh &>/dev/null; then
    echo "Error: GitHub CLI (gh) not installed"
    echo ""
    echo "Install it from: https://cli.github.com"
    echo "Or use: brew install gh"
    exit 1
fi

# Check if authenticated
if ! gh auth status &>/dev/null; then
    echo "Error: Not authenticated to GitHub"
    echo ""
    echo "Run: gh auth login"
    exit 1
fi

# Check if logged in to OpenShift
if ! oc whoami &>/dev/null; then
    echo "Error: Not logged in to OpenShift"
    echo "Run: oc login"
    exit 1
fi

# Get ArgoCD webhook URL
ARGOCD_ROUTE=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -z "$ARGOCD_ROUTE" ]; then
    echo "Error: OpenShift GitOps not installed or route not found"
    exit 1
fi

WEBHOOK_URL="https://$ARGOCD_ROUTE/api/webhook"

echo "ArgoCD Webhook URL: $WEBHOOK_URL"
echo ""

# Get repository from git remote (if in git repo)
if git remote get-url origin &>/dev/null; then
    GIT_REMOTE=$(git remote get-url origin)
    # Extract owner/repo from various Git URL formats
    REPO=$(echo "$GIT_REMOTE" | sed -E 's|.*github.com[:/]||' | sed 's|\.git$||')
    echo "Detected GitHub repository: $REPO"
else
    echo "Not in a git repository or no origin remote found"
    echo -n "Enter GitHub repository (format: owner/repo): "
    read REPO
fi

echo ""
echo "Creating webhook for: $REPO"
echo ""

# Check if webhook already exists
EXISTING_WEBHOOK=$(gh api "repos/$REPO/hooks" 2>/dev/null | jq -r ".[] | select(.config.url == \"$WEBHOOK_URL\") | .id" || echo "")

if [ -n "$EXISTING_WEBHOOK" ]; then
    echo "Webhook already exists (ID: $EXISTING_WEBHOOK)"
    echo "Webhook URL: $WEBHOOK_URL"
    echo ""
    echo "Testing webhook..."
    gh api "repos/$REPO/hooks/$EXISTING_WEBHOOK/pings" -X POST 2>/dev/null || echo "Test ping sent"
    sleep 2
    
    # Check delivery status
    STATUS=$(gh api "repos/$REPO/hooks/$EXISTING_WEBHOOK/deliveries" 2>/dev/null | jq -r '.[0].status_code' || echo "")
    if [ "$STATUS" = "200" ]; then
        echo "✓ Webhook test successful (HTTP 200)"
    else
        echo "⚠ Webhook test returned status: $STATUS"
    fi
else
    echo "Creating new webhook..."
    RESULT=$(gh api "repos/$REPO/hooks" \
        -X POST \
        -f name=web \
        -f "config[url]=$WEBHOOK_URL" \
        -f "config[content_type]=json" \
        -f "config[insecure_ssl]=0" \
        -f "events[]=push" \
        -F active=true 2>&1)
    
    WEBHOOK_ID=$(echo "$RESULT" | jq -r '.id')
    
    if [ -n "$WEBHOOK_ID" ] && [ "$WEBHOOK_ID" != "null" ]; then
        echo "✓ Webhook created successfully!"
        echo "  ID: $WEBHOOK_ID"
        echo "  URL: $WEBHOOK_URL"
        echo ""
        
        echo "Testing webhook..."
        sleep 1
        gh api "repos/$REPO/hooks/$WEBHOOK_ID/pings" -X POST 2>/dev/null || echo "Test ping sent"
        sleep 2
        
        # Check delivery status
        STATUS=$(gh api "repos/$REPO/hooks/$WEBHOOK_ID/deliveries" 2>/dev/null | jq -r '.[0].status_code' || echo "")
        if [ "$STATUS" = "200" ]; then
            echo "✓ Webhook test successful (HTTP 200)"
        else
            echo "⚠ Webhook test returned status: $STATUS"
        fi
    else
        echo "Error creating webhook:"
        echo "$RESULT"
        exit 1
    fi
fi

echo ""
echo "================================================"
echo "Webhook Setup Complete!"
echo "================================================"
echo ""
echo "Git changes will now trigger instant ArgoCD sync!"
echo ""
echo "To verify:"
echo "  1. Make a change and push to GitHub"
echo "  2. Watch: oc get application -n <namespace> -w"
echo "  3. Changes should sync within seconds"
echo ""
