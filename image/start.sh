#!/bin/bash
# PID 1 for this image. RunPod's /start.sh uses the same hook order
# (pre_start, SSH when PUBLIC_KEY is set, export env, post_start, sleep).
# nginx is not started: it bound port 8001 on runpod/base and blocked Caddy.
# Jupyter is not started here. post_start's stt-start serves it on 127.0.0.1
# and Caddy publishes port 8888 behind WEB_PASSWORD.
set -e

execute_script() {
    local script_path=$1
    local script_msg=$2
    if [[ -f ${script_path} ]]; then
        echo "${script_msg}"
        bash "${script_path}"
    fi
}

setup_ssh() {
    if [[ -z ${PUBLIC_KEY:-} ]]; then
        echo "PUBLIC_KEY is not set; SSH is not started. / PUBLIC_KEY が無いので SSH は起動しません"
        return 0
    fi
    echo "Setting up SSH..."
    mkdir -p ~/.ssh
    echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys
    chmod 700 -R ~/.ssh

    if [[ ! -f /etc/ssh/ssh_host_rsa_key ]]; then
        ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -q -N ''
    fi
    if [[ ! -f /etc/ssh/ssh_host_ecdsa_key ]]; then
        ssh-keygen -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -q -N ''
    fi
    if [[ ! -f /etc/ssh/ssh_host_ed25519_key ]]; then
        ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -q -N ''
    fi
    mkdir -p /var/run/sshd
    service ssh start
}

export_env_vars() {
    echo "Exporting environment variables..."
    printenv | grep -E '^[A-Z_][A-Z0-9_]*=' | grep -v '^PUBLIC_KEY' | awk -F = '{ val = $0; sub(/^[^=]*=/, "", val); print "export " $1 "=\"" val "\"" }' > /etc/rp_environment
    touch ~/.bashrc
    if ! grep -q 'source /etc/rp_environment' ~/.bashrc; then
        echo 'source /etc/rp_environment' >> ~/.bashrc
    fi
}

execute_script "/pre_start.sh" "Running pre-start script..."

echo "Pod Started"

setup_ssh
export_env_vars

echo "Start script(s) finished, Pod is ready to use."

execute_script "/post_start.sh" "Running post-start script..."

sleep infinity
