# Kubernetes example

This directory contains a working example of the phased install running in Kubernetes. It is intentionally minimal — adapt it to your cluster's storage class, image registry, and network policy.

## What you get

- A `StatefulSet` running `dockurr/windows` with a persistent volume for `/storage` (the VM disk).
- A `ConfigMap` mounted into `/shared/.runtime/` so the OEM dispatcher reads `php-config.ini`, `post-install.bat`, and the phase scripts straight from k8s.
- A `Service` exposing the web viewer (8006) and RDP (3389).
- A pod-template `checksum/runtime` annotation so any edit to the ConfigMap rolls the pod automatically — which fires the dispatcher with the new config on next boot.

## Requirements

- A node with `/dev/kvm` exposed (bare-metal, or a kubevirt-managed cluster, or GKE/EKS with nested-virt enabled).
- The KubeVirt device plugin (or equivalent) advertising `devices.kubevirt.io/kvm` and `devices.kubevirt.io/tun`.
- A `StorageClass` that supports `ReadWriteOnce` and `volumeBindingMode: WaitForFirstConsumer`.

## Wiring

The dispatcher's source of truth is what's mounted at `\\host.lan\Data\.runtime\` from inside the VM. In compose that is `./shared/.runtime/`. In Kubernetes that has to be a *writable* path (the VM also writes `install.done` and project files there), so a pure read-only ConfigMap volume isn't enough.

The pattern this example uses:

1. The orchestrator files live in a ConfigMap mounted read-only at `/runtime-config`.
2. An init container copies them into the writable `/shared/.runtime/` directory inside the shared PVC.
3. dockur exposes `/shared` over SMB at `\\host.lan\Data`, so the dispatcher reads `\\host.lan\Data\.runtime\dispatcher.bat` etc.

## First deploy

```bash
kubectl apply -f k8s/
kubectl wait --for=condition=ready pod/windows-0 --timeout=40m   # first boot is slow
```

## Re-deploys

Edit values in your ConfigMap (e.g. bump the PHP version in `php-config.ini`), then:

```bash
kubectl apply -f k8s/
# The checksum annotation on the StatefulSet pod template changes,
# k8s rolls the pod, Windows reboots from the same PVC, dispatcher
# detects the new hash and re-runs only phase-php.
```

## Golden-image pattern (optional)

Once `windows-0` has finished phase-base for the first time, snapshot the PVC:

```bash
kubectl apply -f - <<'EOF'
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: windows-base
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source:
    persistentVolumeClaimName: windows-storage-windows-0
EOF
```

New tenants then provision a PVC `dataSourceRef`'d from this snapshot. They skip phase-base (already done on the snapshot) and only run phase-php + phase-code on first boot — about 2 minutes instead of 30.
