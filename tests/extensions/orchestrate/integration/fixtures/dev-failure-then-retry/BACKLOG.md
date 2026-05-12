# Fixture: Dev failure followed by --retry-failed

Two features. Feature 002's Dev fails on the first invocation. A second run
WITHOUT `--retry-failed` leaves it failed; a third run WITH `--retry-failed`
resets and completes.

- [ ] Add user login — Email/password.
- [ ] Profile page — Display user data.
