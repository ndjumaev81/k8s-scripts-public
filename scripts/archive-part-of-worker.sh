# Fetch or reuse join token and hash from k8s-master
echo "Checking for existing join token on k8s-master..."
existing_token=$(multipass exec k8s-master -- sudo kubeadm token list | grep -E '[a-z0-9]{6}\.[a-z0-9]{16}' | head -n1 | awk '{print $1}')
if [ -n "$existing_token" ] && echo "$existing_token" | grep -qE '^[a-z0-9]{6}\.[a-z0-9]{16}$'; then
    echo "Found valid existing token: $existing_token"
    TOKEN="$existing_token"
    # Fetch discovery-token-ca-cert-hash
    join_output=$(multipass exec k8s-master -- sudo kubeadm token create --print-join-command 2>&1)
    HASH=$(echo "$join_output" | grep -oE 'sha256:[a-f0-9]{64}' | head -n1)
    if [ -z "$HASH" ]; then
        echo "Error: Could not retrieve discovery-token-ca-cert-hash"
        exit 1
    fi
else
    echo "No valid existing token found, generating new join token..."
    join_output=$(multipass exec k8s-master -- sudo kubeadm token create --print-join-command 2>&1)
    if [ $? -ne 0 ]; then
        echo "Error: Failed to generate token. Output: $join_output"
        exit 1
    fi
    TOKEN=$(echo "$join_output" | grep -oE '[a-z0-9]{6}\.[a-z0-9]{16}' | head -n1)
    HASH=$(echo "$join_output" | grep -oE 'sha256:[a-f0-9]{64}' | head -n1)
    if [ -z "$TOKEN" ] || [ -z "$HASH" ]; then
        echo "Error: Could not parse token or hash from output: $join_output"
        exit 1
    fi
fi
# Validate token format
if ! echo "$TOKEN" | grep -qE '^[a-z0-9]{6}\.[a-z0-9]{16}$'; then
    echo "Error: Invalid token format: $TOKEN"
    exit 1
fi
echo "Using token: $TOKEN, hash: $HASH"