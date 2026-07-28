#!/bin/bash

# Note: Update the JAVA_HOME path if the Java version or directory changes

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_config_java_home.sh..."

# Locate the most recent installed Java 8 path
JAVA_8_PATH=$(find /usr/lib/jvm -maxdepth 1 -type d -name "java-1.8.0-openjdk-*" | sort -V | tail -n 1)
JAVA_BIN="$JAVA_8_PATH/jre/bin/java"

if [[ ! -x "$JAVA_BIN" ]]; then
  echo "Java 8 binary not found or not executable at: $JAVA_BIN"
  exit 1
fi

# Configure alternatives to point to Java 8
sudo alternatives --install /usr/bin/java java "$JAVA_BIN" 1
sudo alternatives --set java "$JAVA_BIN"

# Create /etc/profile.d/java.sh for environment variables
sudo bash -c 'cat > /etc/profile.d/java.sh' <<EOF
JAVA_BIN=\$(readlink -f \$(which java))
JAVA_HOME=\$(dirname \$(dirname "\$JAVA_BIN"))

export JAVA_HOME
export JAVA_BIN
export PATH=\$JAVA_HOME/bin:\$PATH
EOF

sudo chmod +x /etc/profile.d/java.sh

# Apply for current session
source /etc/profile.d/java.sh

# Display Java version to confirm setup
java -version

# Footer indicating the script execution is complete
echo "system_config_java_home.sh execution completed."
