# Test case 11 & 12

load '../helpers/load'
RD_FILE_RAMDISK_SIZE=12 # We need more disk to run the Rancher image.

local_setup() {
    needs_port 443
}

add_helm_repo() {
    helm repo add jetstack https://charts.jetstack.io
    helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
    helm repo update
}

get_host() {
    if is_windows; then
        local LB_IP
        LB_IP=$(kubectl get svc traefik --namespace kube-system | awk 'NR==2{print $4}')
        echo "$LB_IP.sslip.io"
    else
        echo "localhost"
    fi
}

deploy_rancher() {
    helm upgrade \
        --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --set installCRDs=true \
        --set "extraArgs[0]=--enable-certificate-owner-ref=true" \
        --create-namespace
    helm upgrade \
        --install rancher rancher-latest/rancher \
        --version "${RD_RANCHER_IMAGE_TAG#v}" \
        --namespace cattle-system \
        --set hostname="$(get_host)" \
        --wait \
        --timeout=10m \
        --create-namespace
}

verify_rancher() {
    run try --max 9 --delay 10 curl --insecure --silent --show-error "https://$(get_host)/dashboard/auth/login"
    assert_success
    assert_output --partial "Rancher Dashboard"
    run kubectl get secret --namespace cattle-system bootstrap-secret -o json
    assert_success
    assert_output --partial "bootstrapPassword"
}

uninstall_rancher() {
    run helm uninstall rancher --namespace cattle-system --wait
    assert_nothing
    run helm uninstall cert-manager --namespace cert-manager --wait
    assert_nothing
}

# Need to dynamically register the test to make sure it is executed first.
bats_test_function -- add_helm_repo

foreach_k3s_version \
    factory_reset \
    start_kubernetes \
    wait_for_kubelet \
    deploy_rancher \
    verify_rancher \
    uninstall_rancher
