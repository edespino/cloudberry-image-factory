#!/bin/bash

# Rocky 10 has no Java 8. The shared system_config_java_home.sh looks for
# java-1.8.0-openjdk and exits if it is absent. This script sets JAVA_HOME
# to the Java 21 install that AppStream actually ships.

set -euo pipefail

echo "Executing system_config_java21_home.sh..."

JAVA_LINK=/usr/lib/jvm/java-21-openjdk/bin/java
if [[ ! -x "$JAVA_LINK" ]]; then
  echo "Java 21 binary not found or not executable at: $JAVA_LINK"
  exit 1
fi

JAVA_BIN=$(readlink -f "$JAVA_LINK")
JAVA_HOME=$(dirname "$(dirname "$JAVA_BIN")")

sudo alternatives --install /usr/bin/java java "$JAVA_BIN" 2100000
sudo alternatives --set java "$JAVA_BIN"

sudo tee /etc/profile.d/java.sh >/dev/null <<EOF
export JAVA_HOME=${JAVA_HOME}
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
sudo chmod 644 /etc/profile.d/java.sh

java -version
echo "system_config_java21_home.sh execution completed."
