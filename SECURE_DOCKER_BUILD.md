# localsafe.eth - Secure Docker Distribution

Security pipeline for building, scanning, and distributing localsafe-eth docker images

## 🎯 Overview

The system provides:

- ✅ Hardened Docker image with security best practices
- ✅ Automated vulnerability scanning with Trivy
- ✅ Security gate (auto-fails on critical vulnerabilities)
- ✅ IPFS distribution (decentralised)
- ✅ Checksum verification
- ✅ SBOM (Software Bill of Materials)

---

## Quick Start

Clone the repository:

```
git clone https://github.com/0x31071/localsafe.eth
cd localsafe.eth
```

Secure built: [**Recommended**]
```
chmod +x build-secure.sh
./build-secure.sh
docker run -p 30003:30003 localsafe-eth:latest &
# Open http://localhost:30003
```

Fast (**insecure**) built: [**Only for development and testing**]

```
docker build --progress=plain --no-cache -t localsafe-eth:test .
docker run -p 30003:30003 localsafe-eth:test &
# Open http://localhost:30003
```
---
## System Description

```
# 1. Check requirements for secure building
	- Automatically install Trivy if not found
	- Create directory for secure distribution

# 2. Build the Docker image
	- Update system and install build dependencies
	- Build application
	- Clean up unnecessary files to reduce attack surface
	- Create non-root user with minimal privileges
	- Set strict file permissions
	- Remove unnecessary packages
	- Health check configuration

# 3. Vulnerability Scanning (Trivy)
	- OS vulnerabilities
	- Language-specific vulnerabilities
	- Critical dependencies
	- Found CRITICAL?  (Security Gate)
            ↓
          YES → Delete image + FAIL
          NO  → Export + Generate checksums

# 4. Generate SBOM (Software Bill of Materials)
	- Create a json report using 'trivy image' command

# 5. Export image and generate checksums
	- Create export file (.tar.gz)
	- Obtain SHA256 + SHA512 checksums

# 6. Generate Security Certificate
	- Security Checks passed
	- Scan Results
	- Generate reports
```

```
Output:

# dist-secure/
# ├── localsafe-eth-latest.tar.gz
# ├── localsafe-eth-latest.tar.gz.sha256
# ├── localsafe-eth-latest.tar.gz.sha512
# ├── SECURITY_CERTIFICATE.md
# ├── vulnerability-scan.json
# ├── vulnerability-scan.txt
# ├── sbom.json
# └── build.log
```
---

## 🔒 Security Features

### Dockerfile Hardening

1. **Non-root user** - Runs as `nextjs:1001`
2. **Strict permissions** - Files are 'least privilege'
3. **Minimal base** - Alpine Linux with only required packages
4. **Attack surface reduction** - Removed unnecessary tools
6. **Health checks** - Automatic container monitoring

### Build Pipeline Security

1. **Trivy scanning** - Automated vulnerability detection
2. **Security gate** - Fails on CRITICAL vulnerabilities
3. **Auto-deletion** - Vulnerable images deleted automatically
4. **SBOM generation** - Complete software inventory
5. **Checksum generation** - SHA256 + SHA512

### Distribution Security

1. **IPFS** - Content-addressed (CID = integrity)
2. **Checksums** - Mandatory verification before use
4. **Chain of trust** - Builder → Scan → Checksum → User

---

## 🌐 IPFS Distribution

### Upload

```bash
CID=$(ipfs add -Q localsafe-eth-latest.tar.gz)
ipfs pin add "$CID"

```

### Download (Users)

```bash
# Option 1: IPFS CLI
ipfs get <CID> -o localsafe-eth-latest.tar.gz

# Option 2: Gateway
wget https://ipfs.io/ipfs/<CID> -O localsafe-eth-latest.tar.gz

```
---

## User Manual

1. ✅ ALWAYS verify checksum before loading
2. ✅ Never use image if checksum fails
3. ✅ Report checksum failures immediately
4. ✅ Keep Docker updated
5. ✅ Run container with minimal privileges

### User Workflow

```
1. Receive CID + Checksums (SHA256, SHA512)
   ↓
2. Download image
   ↓
3. Verify checksum
   ↓
4. Load into Docker
   ↓
5. Run container
```
### Usage Example

```bash
# get the image
ipfs get $CID -o localsafe-eth-latest.tar.gz

# verify the file - if checksums don't match, please abort and contact the Security Team
shasum -a 256 localsafe-eth-latest.tar.gz

# load the image
gunzip localsafe-eth-latest.tar.gz
docker load -i localsafe-eth-latest.tar

# run the app
docker run -p 30003:30003 localsafe-eth:latest
```
---

## 🆘 Support

### Issues

1. Check `dist-secure/build.log` for build errors
2. Check `dist-secure/vulnerability-scan.txt` for security issues
3. Verify all dependencies are up to date

## License

See project repository for license information.

