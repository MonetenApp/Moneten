# CSV export gate round 1

These images come from the debug harness snapshot command, using a private app process and made-up demo data. No screen capture or other app was used.

A probe injects a two-second delay into file sync. Before the fix, snapshot commands could run only after the delay and no progress sheet appeared. After the fix, both light and dark progress sheets were captured while the destination file was still absent. Canceling during sync preserved an existing destination and removed the temporary file.

The PNG files live only on media/pr-212-r1. They do not belong on the implementation branch or main.
