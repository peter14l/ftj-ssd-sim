LICENSING & THIRD-PARTY NOTICE

Summary:
- This repository contains proprietary simulation code and documentation (per README).
- It also includes/depends on WinFsp headers and code (memfs.h and WinFsp SDK). WinFsp includes components under GPLv3 for memfs sample code; WinFsp also offers a commercial license.

Action items / risks:
1. Verify which WinFsp sources/headers are copied into this repo. If GPL-licensed code is present verbatim, redistribution may be subject to GPLv3 obligations.
2. If you intend to keep the repo proprietary, remove or relicense any GPL-origin files, or obtain a commercial license from WinFsp where necessary.
3. Document third-party dependencies (WinFsp, any other libraries) and their licenses in repository root LICENSES/NOTICE files.

Recommendation: Consult legal counsel before public distribution. If preferred, replace GPL sample files with references to the upstream WinFsp SDK and do not commit upstream GPL sources.
