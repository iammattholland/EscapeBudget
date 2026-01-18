## Security checklist

### Secret scanning
- Run `scripts/secret_scan.sh` before publishing or sharing the repo.
- If anything sensitive is found, remove it from the repo history and rotate it immediately.

### What should never be committed
- API keys, access tokens, private keys, `.p8` signing keys
- `.env` files, local configuration with credentials
- Exported user data/backups

### Logging
- Avoid logging amounts, filenames, or personal data.
- Prefer the existing `SecurityLogger` patterns and use `.private` for `os.Logger` interpolation.

