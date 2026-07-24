#!/bin/bash

# Build GNU Emacs from source (terminal-only, no X11/GUI)
# https://ftp.gnu.org/gnu/emacs/

# Enable strict mode for better error handling
set -euo pipefail

# Header indicating the script execution
echo "Executing system_add_emacs.sh..."

EMACS_VERSION="30.2"
EMACS_TARBALL="emacs-${EMACS_VERSION}.tar.xz"
EMACS_URL="https://ftpmirror.gnu.org/emacs/${EMACS_TARBALL}"
EMACS_SIG_URL="${EMACS_URL}.sig"
GNU_KEYRING_URL="https://ftpmirror.gnu.org/gnu-keyring.gpg"

echo "EMACS_VERSION=${EMACS_VERSION}"

# Install build dependencies
sudo dnf install -y -d0 \
    autoconf \
    gcc \
    gnutls-devel \
    libgccjit-devel \
    make \
    ncurses-devel \
    sqlite-devel \
    zlib-devel

# Download tarball and GPG signature
# Use curl instead of wget — the gnutls-devel install above can upgrade
# the GnuTLS shared library, breaking wget's SSL in the same session.
cd /tmp
curl -fsSL --retry 3 --retry-delay 5 -L -o "${EMACS_TARBALL}" "${EMACS_URL}"
curl -fsSL --retry 3 --retry-delay 5 -L -o "${EMACS_TARBALL}.sig" "${EMACS_SIG_URL}"

# Verify GPG signature
curl -fsSL --retry 3 --retry-delay 5 -L -o gnu-keyring.gpg "${GNU_KEYRING_URL}"
gpg --import gnu-keyring.gpg
gpg --verify "${EMACS_TARBALL}.sig" "${EMACS_TARBALL}"

# Build and install
tar xf "${EMACS_TARBALL}"
cd "emacs-${EMACS_VERSION}"
./configure --without-x --without-sound --without-xpm --without-jpeg --without-tiff --without-gif --without-png --without-rsvg --without-imagemagick --with-gnutls --without-json --without-tree-sitter --with-native-compilation=no
make -j"$(nproc)"
sudo make install

# Cleanup
cd /tmp
rm -rf "emacs-${EMACS_VERSION}" "${EMACS_TARBALL}" "${EMACS_TARBALL}.sig" gnu-keyring.gpg

# Verify installation
emacs --version

# Install Magit system-wide from MELPA
echo "Installing Magit..."
SITE_LISP="/usr/local/share/emacs/site-lisp"
sudo mkdir -p "${SITE_LISP}"

sudo /usr/local/bin/emacs --batch --eval "
(progn
  (require 'package)
  (setq package-user-dir \"${SITE_LISP}/elpa\")
  (add-to-list 'package-archives '(\"melpa\" . \"https://melpa.org/packages/\") t)
  (package-initialize)
  (package-refresh-contents)
  (package-install 'magit))"

# Create site-start.el so the system elpa directory is on the load-path for all users
sudo tee "${SITE_LISP}/site-start.el" > /dev/null <<'SITESTART'
;; Load system-wide ELPA packages (installed during AMI build)
(let ((site-elpa (expand-file-name "elpa" (file-name-directory load-file-name))))
  (when (file-directory-p site-elpa)
    (dolist (pkg-dir (directory-files site-elpa t "\\`[^.]"))
      (when (file-directory-p pkg-dir)
        (add-to-list 'load-path pkg-dir)
        (let ((autoload-file (expand-file-name
                              (concat (file-name-nondirectory pkg-dir) "-autoloads.el")
                              pkg-dir)))
          (when (file-exists-p autoload-file)
            (load autoload-file t t)))))))
SITESTART

echo "Magit installed to ${SITE_LISP}/elpa"

# Footer indicating the script execution is complete
echo "system_add_emacs.sh execution completed."
