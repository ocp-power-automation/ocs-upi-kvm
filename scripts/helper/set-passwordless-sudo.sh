#!/bin/bash

# Updates the current user's sudo access such that no password
# is required and thereby eliminating the password prompt. This
# is a prerequisite for automation scripts that perform privileged
# operations.  One has to be a privilege user to do it.

me=$(whoami)

echo "$me ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$me
sudo chmod 640 /etc/sudoers.d/$me
