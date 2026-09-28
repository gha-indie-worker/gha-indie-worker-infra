# Ephemeral runner substrate

This directory defines the Kubernetes security substrate for remote/prod
GHA Indie Worker jobs. It intentionally does **not** define a long-lived shared
runner Deployment.

The GIW control plane creates one ephemeral execution per job. Every runner pod
or Job must:

- run in `gha-indie-worker-runners`;
- carry label `indiebuild.dev/execution=ephemeral-job`;
- use service account `giw-ephemeral-runner`;
- set `automountServiceAccountToken: false`;
- run as non-root with `RuntimeDefault` seccomp;
- set `allowPrivilegeEscalation: false`, `privileged: false`, and drop all capabilities;
- use a read-only root filesystem plus bounded `emptyDir` scratch/workspace volumes;
- set explicit CPU, memory, ephemeral-storage, and wall-clock limits;
- set `restartPolicy: Never`, a bounded `activeDeadlineSeconds`, and a short
  `ttlSecondsAfterFinished`;
- never use host networking, host PID/IPC, hostPath, Docker/containerd sockets,
  or reusable host workspaces.

The default NetworkPolicy denies all ingress and all egress. The labeled
ephemeral jobs receive DNS plus public HTTPS only, with private, loopback,
link-local, metadata, CGNAT, documentation/test, multicast, and reserved ranges
excluded.

If a workflow needs a private service, add a narrow capability-specific policy;
do not widen the default public-web rule.

The cluster source of truth remains `ORESoftware/k8s-cluster`. Production
should select a sandbox RuntimeClass (gVisor/Kata/Scintilla isolation) there,
because the exact RuntimeClass name is cluster-owned.
