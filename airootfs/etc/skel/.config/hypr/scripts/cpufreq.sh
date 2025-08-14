#!/bin/bash
MODE=$(auto-cpufreq --show | grep 'Current mode:' | awk '{print $3}')
case $1 in
  powersave)
    sudo auto-cpufreq --force powersave
    ;;
  performance)
    sudo auto-cpufreq --force performance
    ;;
  reset)
    sudo auto-cpufreq --force reset
    ;;
esac
echo "$MODE"

