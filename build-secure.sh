#!/bin/bash
# build-secure.sh
# Secure build pipeline with Trivy scanning and security gate
# Automatically fails and deletes image if critical vulnerabilities found

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[⚠]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_section() { echo -e "${CYAN}╔════════════════════════════════════════════════╗${NC}"; \
                echo -e "${CYAN}║  $1${NC}"; \
                echo -e "${CYAN}╚════════════════════════════════════════════════╝${NC}"; }

# Configuration
IMAGE_NAME="localsafe-eth"
IMAGE_TAG="${1:-latest}"
FULL_IMAGE="$IMAGE_NAME:$IMAGE_TAG"
OUTPUT_DIR="./dist-package"
DOCKERFILE="${DOCKERFILE:-Dockerfile}"
FAIL_ON_CRITICAL="${FAIL_ON_CRITICAL:-true}"
FAIL_ON_HIGH="${FAIL_ON_HIGH:-false}"

log_section "localsafe.eth - Secure Build Pipeline"
echo ""

# ============================================
# 1. PRE-BUILDING REQUIREMENTS
# ============================================
log_info "Step 1/6: Checking final requirements..."

if ! command -v trivy &> /dev/null; then
    log_warning "Trivy not found, installing automatically..."
    case "$(uname -s)" in
        Darwin*)
            if command -v brew &> /dev/null; then
                log_info "Installing via Homebrew..."
                brew install trivy
            else
                log_error "Homebrew not found. Install Trivy manually:"
                log_error "https://aquasecurity.github.io/trivy/latest/getting-started/installation/"
                exit 1
            fi
            ;;
        Linux*)
            log_info "Installing via official script..."
            curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | \
                sh -s -- -b /usr/local/bin
            ;;
        *)
            log_error "Unsupported OS for automatic installation"
            log_error "Install Trivy manually: https://aquasecurity.github.io/trivy/"
            exit 1
            ;;
    esac
    
    if command -v trivy &> /dev/null; then
        log_success "Trivy installed successfully"
    else
        log_error "Trivy installation failed"
        exit 1
    fi
else
    log_success "Trivy found: $(trivy --version | head -1 | awk '{print $2}')"
fi

if ! command -v jq &> /dev/null; then
    log_warning "jq not found, installing..."
    case "$(uname -s)" in
        Darwin*) brew install jq ;;
        Linux*) sudo apt-get install -y jq || sudo yum install -y jq ;;
    esac
fi

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/*.log 2>/dev/null || true

log_success "Output directory: $OUTPUT_DIR"
echo ""

# ============================================
# 2. BUILD IMAGE
# ============================================
log_info "Step 2/6: Building Docker image..."
echo ""

BUILD_START=$(date +%s)

if docker build \
    --file "$DOCKERFILE" \
    --tag "$FULL_IMAGE" \
    --progress=plain \
    --no-cache \
    . 2>&1 | tee "$OUTPUT_DIR/build.log"; then
    
    BUILD_END=$(date +%s)
    BUILD_TIME=$((BUILD_END - BUILD_START))
    
    log_success "Image built in ${BUILD_TIME}s"
else
    log_error "Docker build failed"
    exit 1
fi

echo ""

# Get image size
IMAGE_SIZE=$(docker images "$FULL_IMAGE" --format "{{.Size}}")
log_info "Image size: $IMAGE_SIZE"

echo ""

# ============================================
# 3. SECURITY GATE: VULNERABILITY SCAN
# ============================================
log_section "Step 3/6: Vulnerability Scanning"
echo ""

log_warning "If CRITICAL vulnerabilities are found:"
log_warning "  → Image will be DELETED automatically"
log_warning "  → Build will be marked as FAILED"
echo ""

SCAN_REPORT="$OUTPUT_DIR/vulnerability-scan.txt"
SCAN_JSON="$OUTPUT_DIR/vulnerability-scan.json"

# Update Trivy database
log_info "Updating Trivy vulnerability database..."
trivy image --download-db-only

echo ""
log_info "Scanning image for vulnerabilities..."
echo ""

# Scan with exit code 1 if vulnerabilities found
if trivy image \
    --severity CRITICAL,HIGH \
    --exit-code 1 \
    --format json \
    --output "$SCAN_JSON" \
    "$FULL_IMAGE" 2>&1 | tee /tmp/trivy-scan.log; then
    
    # No vulnerabilities found
    CRITICAL_COUNT=0
    HIGH_COUNT=0
    MEDIUM_COUNT=0
    
    log_success "✅ SECURITY GATE: PASSED"
    echo ""
    log_success "No CRITICAL or HIGH vulnerabilities found"
    
else
    # Vulnerabilities found - process and decide
    CRITICAL_COUNT=$(jq '[.Results[].Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' "$SCAN_JSON" 2>/dev/null || echo "0")
    HIGH_COUNT=$(jq '[.Results[].Vulnerabilities[]? | select(.Severity=="HIGH")] | length' "$SCAN_JSON" 2>/dev/null || echo "0")
    MEDIUM_COUNT=$(jq '[.Results[].Vulnerabilities[]? | select(.Severity=="MEDIUM")] | length' "$SCAN_JSON" 2>/dev/null || echo "0")
    
    echo ""
    log_error "❌ SECURITY GATE: FAILED"
    echo ""
    log_error "Vulnerabilities found:"
    echo "   • CRITICAL: $CRITICAL_COUNT"
    echo "   • HIGH: $HIGH_COUNT"
    echo "   • MEDIUM: $MEDIUM_COUNT"
    echo ""
    
    # Show critical vulnerabilities
    if [ "$CRITICAL_COUNT" -gt 0 ]; then
        echo "CRITICAL Vulnerabilities:"
        jq -r '.Results[].Vulnerabilities[]? | select(.Severity=="CRITICAL") | 
               "  - \(.VulnerabilityID): \(.PkgName) \(.InstalledVersion) → Fix: \(.FixedVersion // "N/A")"' \
               "$SCAN_JSON" 2>/dev/null | head -10
        echo ""
    fi
    
    # Decide if build should fail
    SHOULD_FAIL=false
    
    if [ "$CRITICAL_COUNT" -gt 0 ] && [ "$FAIL_ON_CRITICAL" = "true" ]; then
        SHOULD_FAIL=true
        FAIL_REASON="CRITICAL vulnerabilities"
    elif [ "$HIGH_COUNT" -gt 0 ] && [ "$FAIL_ON_HIGH" = "true" ]; then
        SHOULD_FAIL=true
        FAIL_REASON="HIGH vulnerabilities"
    fi
    
    if [ "$SHOULD_FAIL" = "true" ]; then
        log_warning "DELETING vulnerable image..."
        docker rmi "$FULL_IMAGE" 2>/dev/null || true
        
        echo ""
        log_error "════════════════════════════════════════════════"
        log_error "BUILD REJECTED: $FAIL_REASON found"
        log_error "════════════════════════════════════════════════"
        echo ""
        log_error "Image deleted for security. Cannot distribute. Please contact the Security Team for next steps"
        echo ""
        log_error "Next steps:"
        echo "  1. Update vulnerable dependencies"
        echo "  2. Rebuild"
        echo "  3. Security gate must pass"
        echo ""
        log_error "Full report: $SCAN_JSON"
        exit 1
    else
        log_warning "Continuing with vulnerabilities (policy allows)"
    fi
fi

# Generate human-readable report
trivy image \
    --severity CRITICAL,HIGH,MEDIUM \
    --format table \
    --output "$SCAN_REPORT" \
    "$FULL_IMAGE" 2>/dev/null || true

echo ""

# ============================================
# 4. GENERATE SBOM
# ============================================
log_info "Step 4/6: Generating SBOM (Software Bill of Materials)..."

SBOM_FILE="$OUTPUT_DIR/sbom.json"

trivy image \
    --format spdx-json \
    --output "$SBOM_FILE" \
    "$FULL_IMAGE" 2>/dev/null

PACKAGE_COUNT=$(jq '.packages | length' "$SBOM_FILE" 2>/dev/null || echo "N/A")
log_success "SBOM generated: $PACKAGE_COUNT packages"

echo ""

# ============================================
# 5. EXPORT IMAGE & GET CHECKSUMS
# ============================================
log_info "Step 5/6: Exporting image..."

EXPORT_FILE="$OUTPUT_DIR/$IMAGE_NAME-$IMAGE_TAG.tar.gz"

log_info "Exporting to $EXPORT_FILE..."
docker save "$FULL_IMAGE" | gzip > "$EXPORT_FILE"

FILE_SIZE=$(du -h "$EXPORT_FILE" | cut -f1)
log_success "Exported: $FILE_SIZE"

# SHA256
SHA256=$(shasum -a 256 "$EXPORT_FILE" | awk '{print $1}')
echo "$SHA256  $(basename $EXPORT_FILE)" > "$EXPORT_FILE.sha256"
log_success "SHA256: $SHA256"

# SHA512
SHA512=$(shasum -a 512 "$EXPORT_FILE" | awk '{print $1}')
echo "$SHA512  $(basename $EXPORT_FILE)" > "$EXPORT_FILE.sha512"
log_success "SHA512: $SHA512"

echo ""

# ============================================
# 6. GENERATE SECURITY CERTIFICATE
# ============================================
log_info "Step 6/6: Generating security certificate..."

BUILD_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
BUILDER=$(whoami)
HOST=$(hostname)
DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | tr -d ',')

cat > "$OUTPUT_DIR/SECURITY_CERTIFICATE.md" << EOF
# 🔒 Security Certificate

## Image: $FULL_IMAGE

**Build Date:** $BUILD_DATE  
**Builder:** $BUILDER@$HOST  
**Docker Version:** $DOCKER_VERSION  
**Image Size:** $IMAGE_SIZE  
**SHA256:** \`$SHA256\`

---

## ✅ Security Verification

This image has passed automated security checks:

- [x] Built successfully
- [x] Scanned with Trivy $(trivy --version | head -1 | awk '{print $2}')
- [x] CRITICAL vulnerabilities: $CRITICAL_COUNT
- [x] HIGH vulnerabilities: $HIGH_COUNT
- [x] MEDIUM vulnerabilities: $MEDIUM_COUNT
- [x] Security Gate: $([ "$CRITICAL_COUNT" -eq 0 ] && echo "✅ PASSED" || echo "⚠️ REVIEW REQUIRED")
- [x] SBOM generated ($PACKAGE_COUNT packages)
- [x] Checksums generated (SHA256, SHA512)

---

## 📊 Security Scan Results

### Summary
- **Total CRITICAL:** $CRITICAL_COUNT
- **Total HIGH:** $HIGH_COUNT
- **Total MEDIUM:** $MEDIUM_COUNT
- **Status:** $([ "$CRITICAL_COUNT" -eq 0 ] && echo "✅ APPROVED FOR DISTRIBUTION" || echo "⚠️ REVIEW REQUIRED")

### Full Report
See: \`vulnerability-scan.txt\` and \`vulnerability-scan.json\`

---

## 🔐 User Verification Instructions

Users do NOT need Trivy. Only verify the checksum:

\`\`\`bash
# Verify SHA256
echo "$SHA256  $IMAGE_NAME-$IMAGE_TAG.tar.gz" | shasum -a 256 -c

# Output should be: OK
# If it fails → DO NOT USE
\`\`\`

---

Build ID: $(echo "$SHA256" | cut -c1-12)  
Certificate Date: $BUILD_DATE  
EOF

log_success "Certificate generated"
echo ""

# ============================================
# FINAL SUMMARY
# ============================================
log_section "Build Complete"
echo ""
echo "📦 Image: $FULL_IMAGE"
echo "💾 Size: $IMAGE_SIZE"
echo "🔐 SHA256: $SHA256"
echo "🐛 Vulnerabilities: $CRITICAL_COUNT CRITICAL, $HIGH_COUNT HIGH"
echo ""

if [ "$CRITICAL_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✅ IMAGE APPROVED FOR DISTRIBUTION${NC}"
else
    echo -e "${YELLOW}⚠️  REVIEW VULNERABILITIES BEFORE DISTRIBUTION${NC}"
fi

echo ""
echo "📋 Generated files:"
ls -lh "$OUTPUT_DIR/" | tail -n +2 | awk '{print "   •", $9, "("$5")"}'
echo ""
