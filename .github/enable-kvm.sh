#!/usr/bin/env bash
#
# enable-kvm.sh - let the runner user open /dev/kvm.
#
# GitHub-hosted x86_64 Linux runners support nested virtualisation, but the
# device node is not accessible to the unprivileged runner user by default.
# Without this every VM test silently falls back to TCG emulation, which is
# ~10-20x slower and turns timeouts into false failures.
#
# This is a CI-host setting only; it does not change SimulationOS. If the
# runner has no KVM at all the tests still run under TCG (scripts use
# "kvm:tcg"), so this never fails the job.
set -u

if [ ! -e /dev/kvm ]; then
    echo "::notice::no /dev/kvm on this runner - VM tests will use TCG emulation (slow)"
    exit 0
fi
echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' \
    | sudo tee /etc/udev/rules.d/99-kvm4all.rules >/dev/null
sudo udevadm control --reload-rules
sudo udevadm trigger --name-match=kvm
sleep 1
ls -l /dev/kvm
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    echo "KVM available to $(id -un)"
else
    echo "::notice::/dev/kvm exists but is not accessible - VM tests will use TCG emulation (slow)"
fi
