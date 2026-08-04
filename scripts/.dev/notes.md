# IT 140 IDE Setup Scripts

## Setup Script MVP

### Bootstrap the course MVP setup script

```bash
sudo apt update
sudo apt install -y git
git clone --depth 1 https://github.com/GC-STEM/it140.git "$HOME/repos/it140"
chmod +x "$HOME/repos/it140/scripts/cvd/setup_it140.sh"
"$HOME/repos/it140/scripts/cvd/setup_it140.sh"
```

### MVP Setup Script

```bash
#!/bin/bash
# Install system dependencies.

# Install Python 3.12
```

## 0. Manually setup a GitHub account

## 1. Prepare for the course IDE (initial bootstrap)

- Start logging the initial bootstrap process.
- Install {{Git and/or GitHub CLI}} on the local machine.
- Configure {{Git and/or GitHub CLI}} with user credentials.
- Fork the main course repository to student's GitHub account.
- Clone the forked main course repository to the {{platform}}.
- Add `~/it140/scripts/{{platform}}` to the PATH environment variable.
- Stop logging the initial bootstrap process
- Push new/modified log file to the course repository so instructor or tech support can review it, if needed.

>[!IMPORTANT]
> Would need to make absolutely sure that no PII or other FERPA-protected information is included in log files that is not part of GitHub public information.

## 2. Install the course IDE

- Start logging the course IDE installation process.

## 3. Configure the course IDE

## 4. Verify the course IDE

## 5. Maintain the course IDE
