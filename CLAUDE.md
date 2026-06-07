# VibeUE

## Feature development workflow

Features are developed on dedicated branches cut from `master` and merged into the fork tracking branch.

```
master                    (upstream base — never commit directly)
├── feat/<name>           (feature branch)
└── fork/last-november    (fork tracking branch — receives merges)
```

1. `git checkout -b feat/<name> master`
2. Implement and commit on the feature branch
3. `git push origin feat/<name>`
4. `git checkout fork/last-november && git merge --no-ff feat/<name>`
5. `git push --force-with-lease origin fork/last-november`

When rebasing the fork onto a new master tip, squash any fixup commits on feature branches first so the fork history stays linear.
