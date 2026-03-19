# Migration Path: Local AAI -> Remote Controlled AAI

1. Install host control-plane runtime.
2. Register project with /aai-remote-register.
3. Confirm project portable config exists in docs/ai/project-overrides/remote-control.yaml.
4. Verify host bindings exist only in host runtime DB.
5. Run Telegram intake and approval flow for one work item.
6. Validate report/manifests and downstream sync boundaries.
