# 0018. Run the FinTS helper in the app sandbox

Status: Accepted

This decision amends [ADR 0014](0014-fints-through-hbci4java.md). It replaces the sentence "Only the helper gets the entitlement `com.apple.security.cs.allow-jit`" with the entitlements below, and moves the java of the helper out of `runtime/bin`.

## Context

The security review of #26 found that the java of the FinTS helper had only `com.apple.security.cs.allow-jit` (issue #326). The JVM holds the PIN and the TANs and parses the answers of the bank with hbci4java and JAXB. It could read and write the whole home folder: SSH keys, documents, the database file, and the "Extensions" folder. A flaw in a parser, set off by a compromised bank server or a bad entry in the bank directory, would give that access together with the PIN.

The extension host faces the same kind of risk and runs in the app sandbox with network access only ([ADR 0015](0015-extension-program.md)). The FinTS helper is the more sensitive process.

A test on 16 November 2026 on macOS 26 signed the java of the helper with the app sandbox, the network client, and JIT, and ran it as the app does. It showed what the sandbox allows:

- The app is not sandboxed, so the helper gets a sandbox of its own and inherits nothing from the app. Its container is named after its signing identifier. Without `--identifier`, codesign takes `net.java.openjdk.java` from the Info.plist inside the java of the JDK, a name that any other app with a sandboxed JDK can share.
- The sandbox lets java read the folder of its own executable and the folders of the libraries that it loads at start, and nothing else of the app bundle. With java in `runtime/bin`, the JVM read `runtime/bin` and `runtime/lib`, and stopped with "Error loading java.security file", because `runtime/conf` and the jars in `lib` were outside both. An extra `LC_RPATH` entry does not widen this, because only the folders of loaded libraries count.
- With java one level up, at `Contents/Resources/FinTSHelper/java`, the sandbox lets it read that folder with the runtime and the jars, and still refuses `Contents/Resources` and the home folder. The JVM finds its home from the place of `libjli.dylib`, so the runtime stays in `runtime`.
- A local server stood in for the bank: an HTTPS proxy on 127.0.0.1 that answered the CONNECT itself and never forwarded it. The sandboxed helper fetched the bank directory, asked for the PIN, sent the server's certificate to the app, sent the encrypted dialog start, read the answer 9800, and ended with status 0. The sandbox reported no denial. The same run without the network client failed with "Operation not permitted".
- With the hardened runtime, the JVM ends with SIGTRAP without `allow-jit`, also in the sandbox.

## Decision

- The java of the FinTS helper has exactly three entitlements: `com.apple.security.app-sandbox`, `com.apple.security.network.client`, and `com.apple.security.cs.allow-jit`. It has no temporary exceptions.
- The java sits at the top of the helper folder, `Contents/Resources/FinTSHelper/java`, next to `runtime` and `lib`. `scripts/build-fints-helper.sh` moves it there and changes its search path for `libjli.dylib` to `runtime/lib`.
- `scripts/build-app.sh` signs it with the identifier of the app followed by `.FinTSHelper`, so its container is `~/Library/Containers/<app identifier>.FinTSHelper`. The helper keeps no data of its own (ADR 0014), so the container holds only the temporary files of the JVM.
- `scripts/build-app.sh` fails when the java has other entitlements, and when it cannot fetch the bank directory in its sandbox.

## Consequences

- A flaw in hbci4java, JAXB, or the JVM reaches the network and the files of the helper, but not the home folder, the database file, or the "Extensions" folder.
- The helper still reaches any host, as the extension host does. It sends the PIN only to the FinTS address that the bank directory names for the bank code, and macOS judges the certificate of that server.
- What the sandbox lets the helper read depends on how macOS sets up the sandbox of a program without a bundle of its own. A change in a later macOS fails the check of `scripts/build-app.sh` on that macOS, not a refresh of a user who built on another one. The check runs on every build.
- Each user gets one more folder in `~/Library/Containers`.
- The helper gets absolute paths only. The sandbox hides the working folder, so a relative class path fails.

## Alternatives

- **A temporary exception for the path of the helper.** The path of the app is not known when it is signed, and an exception for the home folder would undo the gain. Rejected.
- **An XPC service or a bundle around the java.** The sandbox would then grant the bundle, but the JDK expects its own layout, and codesign would treat the bundle as nested code. The move of one file gets the same result. Rejected.
- **Pass the files through the pipe.** The JVM reads its runtime and its configuration itself, before the helper runs. Rejected.
- **`com.apple.security.inherit`.** It needs a sandboxed parent, and the app is not sandboxed. Not possible.
