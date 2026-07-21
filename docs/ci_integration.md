# CI/CD Integration Guide

This document describes how to integrate ocp-evals with OpenShift CI for automated periodic evaluations.

## Overview

OCP evaluations run periodically on OpenShift CI infrastructure to continuously validate upgrade workflows against real OpenShift clusters.

## Repository Structure in openshift/release

### Configuration Location

```
openshift/release/
├── ci-operator/
│   ├── config/
│   │   └── openshift/
│   │       └── ocp-evals/
│   │           └── openshift-ocp-evals-main__4.21.yaml
│   └── jobs/
│       └── openshift/
│           └── ocp-evals/
│               └── openshift-ocp-evals-main-periodics.yaml (auto-generated)
```

### Configuration File Template

Create `ci-operator/config/openshift/ocp-evals/openshift-ocp-evals-main__4.21.yaml`:

```yaml
base_images:
  upi-installer:
    name: "4.21"
    namespace: ocp
    tag: upi-installer

build_root:
  image_stream_tag:
    name: release
    namespace: openshift
    tag: golang-1.22

resources:
  '*':
    limits:
      memory: 4Gi
    requests:
      cpu: 100m
      memory: 200Mi

tests:
  - as: ocp-eval-periodics
    cron: "30 14 * * *"  # Daily at 14:30 UTC
    cluster_claim:
      product: ocp
      architecture: amd64
      cloud: aws
      owner: openshift-ci
      timeout: 2h0m0s
      version: "4.21"
    steps:
      cluster_profile: aws-qe
      env:
        MODEL: gpt-4o-mini
      test:
        - as: run-ocp-eval
          commands: |
            #!/bin/bash
            set -euo pipefail
            
            # Install dependencies
            python3 -m venv venv
            source venv/bin/activate
            pip install -r requirements.txt
            
            # Set up service account and RBAC
            oc apply -f config/rbac-ocp-evals.yaml || true
            export API_KEY=$(oc create token ocp-eval-user -n openshift-lightspeed --duration=2h)
            
            # Run evaluations
            make eval
            
            # Copy results to artifacts
            mkdir -p "${ARTIFACT_DIR}/eval_results"
            cp -r eval_output/* "${ARTIFACT_DIR}/eval_results/"
          credentials:
            - mount_path: /var/run/openai-secret
              name: openai-api-key
              namespace: test-credentials
            - mount_path: /var/run/ocp-eval-secret
              name: ocp-eval-api-key
              namespace: test-credentials
          from: upi-installer
          resources:
            requests:
              cpu: 1000m
              memory: 2Gi
```

## Required Secrets

### OpenAI API Key

```bash
# Create secret in test-credentials namespace
oc create secret generic openai-api-key \
  --from-literal=OPENAI_API_KEY="your-openai-api-key" \
  -n test-credentials
```

### OCP Eval API Key (Optional)

```bash
# If using API-enabled evaluations
oc create secret generic ocp-eval-api-key \
  --from-literal=API_KEY="your-api-key" \
  -n test-credentials
```

## RBAC Configuration

Create `config/rbac-ocp-evals.yaml`:

```yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ocp-eval-user
  namespace: openshift-lightspeed
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ocp-eval-reader
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-reader
subjects:
- kind: ServiceAccount
  name: ocp-eval-user
  namespace: openshift-lightspeed
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ocp-eval-monitoring-edit
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: monitoring-edit
subjects:
- kind: ServiceAccount
  name: ocp-eval-user
  namespace: openshift-lightspeed
```

## Workflow

### 1. Configuration Update

Edit the config file in `openshift/release`:

```bash
cd ~/openshift/release
vi ci-operator/config/openshift/ocp-evals/openshift-ocp-evals-main__4.21.yaml
```

### 2. Generate Jobs

```bash
make update
```

This generates:
- Prow job definitions in `ci-operator/jobs/`
- Other CI configurations

### 3. Validate Configuration

```bash
make checkconfig
```

### 4. Commit and Create PR

```bash
git add ci-operator/
git commit -m "ocp-evals: Add periodic evaluation job for 4.21"
git push origin my-branch
gh pr create --title "ocp-evals: Add periodic evaluation job"
```

### 5. Merge and Monitor

After merge:
- Job runs according to cron schedule
- View results in [OpenShift CI Dashboard](https://prow.ci.openshift.org/)
- Artifacts stored in GCS

## Artifacts

Evaluation results are stored as job artifacts:

```
gs://origin-ci-test/logs/periodic-ci-openshift-ocp-evals-main-4.21-ocp-eval-periodics/[build-id]/artifacts/
└── ocp-eval-periodics/
    └── run-ocp-eval/
        └── artifacts/
            └── eval_results/
                ├── evaluation_*_detailed.csv
                ├── evaluation_*_summary.json
                └── graphs/
```

## Notifications

Configure Slack notifications in the job definition:

```yaml
tests:
  - as: ocp-eval-periodics
    cron: "30 14 * * *"
    # ... other config ...
    postsubmit: true  # Enable for postsubmit notifications
```

Add to `.ci-operator.yaml` in ocp-evals repo:

```yaml
slack_reporter:
- channel: "#openshift-lightspeed-ci"
  job_states_to_report:
  - failure
  - error
  report_template: 'Job *{{.Spec.Job}}* ended with *{{.Status.State}}*. <{{.Status.URL}}|View logs>'
```

## Monitoring

### View Job Status

```bash
# List recent runs
oc get prowjobs -n ci \
  -l prow.k8s.io/job=periodic-ci-openshift-ocp-evals-main-4.21-ocp-eval-periodics \
  --sort-by=.status.startTime

# View specific job
oc describe prowjob <job-name> -n ci
```

### Access Logs

1. Go to https://prow.ci.openshift.org/
2. Search for "ocp-eval"
3. Click on specific build
4. View logs and artifacts

## Troubleshooting

### Job Fails to Start

Check:
- Cluster claim configuration (product, version, cloud)
- Resource requests/limits
- Base image availability

### Secrets Not Found

Ensure secrets exist in correct namespace:

```bash
oc get secrets -n test-credentials | grep -E 'openai|ocp-eval'
```

### RBAC Errors

Verify service account and bindings:

```bash
oc get sa ocp-eval-user -n openshift-lightspeed
oc get clusterrolebinding ocp-eval-reader
oc get clusterrolebinding ocp-eval-monitoring-edit
```

### Evaluation Failures

Review artifacts:
1. Download artifacts from GCS
2. Check CSV/JSON for specific metric failures
3. Review error logs in job output

## Best Practices

1. **Schedule Wisely** - Avoid peak hours and :00/:30 minutes
2. **Test Locally** - Run evaluations locally before CI integration
3. **Monitor Results** - Set up Slack notifications
4. **Version Pin** - Pin framework version in requirements.txt
5. **Resource Limits** - Set appropriate CPU/memory limits
6. **Timeout** - Set cluster claim timeout based on eval duration

## References

- [OpenShift CI Documentation](https://docs.ci.openshift.org/)
- [Prow Job Configuration](https://docs.ci.openshift.org/docs/architecture/ci-operator/)
- [Step Registry](https://docs.ci.openshift.org/docs/architecture/step-registry/)
