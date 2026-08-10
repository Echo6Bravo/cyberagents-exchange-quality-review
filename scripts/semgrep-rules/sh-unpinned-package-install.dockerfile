# Planted-defect fixture for sh-unpinned-package-install (dim 18, CWE-1357, OWASP A03:2025).
#
# WHY A .dockerfile EXTENSION. The rule is `languages: [generic]` with a `paths:` include list, and a
# generic rule matches ONLY files whose name matches one of those globs. `.dockerfile` is in the list
# and is the same extension the sibling `docker-final-stage-runs-as-root.dockerfile` fixture already
# uses, so `semgrep test` resolves it against the rule. A `.sh` fixture would ALSO work, but only one
# fixture per rule is read (measured elsewhere in this dir), and a Dockerfile can legally carry both
# the RUN-install shapes AND a bare shell line, so every sink lives here in one file.
#
# The rule is lexical (per-line regex), so mixing Dockerfile `RUN` and bare shell commands in one file
# is fine -- generic mode does not care that a real Dockerfile would need `RUN` in front of each.
# Both spellings appear on purpose.
#
# No credential-shaped literals: gitleaks scans full history in CI.
#
# Each must-catch line carries a string that appears EXACTLY ONCE, so the Gate 5 mutation table can
# neutralise one finding at a time without ambiguity.

# ruleid: sh-unpinned-package-install
RUN pip3 install requests validators
# ruleid: sh-unpinned-package-install
RUN pip install flask-cors
# ruleid: sh-unpinned-package-install
RUN python3 -m pip install tqdm
# ruleid: sh-unpinned-package-install
RUN apt-get install gcc-11 g++-11 python3-pip -y
# ruleid: sh-unpinned-package-install
RUN apt install curl
# ruleid: sh-unpinned-package-install
RUN apk add openssl
# ruleid: sh-unpinned-package-install
RUN curl -L https://huggingface.co/eachadea/ggml-vicuna-13b-1.1/resolve/main/ggml-old-vic13b-q4_0.bin -o model.bin

# --- must-NOT-catch: an exact pip pin. This is the fix, and it must not fire.
RUN pip3 install requests==2.32.4
# --- must-NOT-catch: install from a manifest -- versions declared in the referenced file.
RUN pip install -r requirements.txt
# --- must-NOT-catch: editable/local install -- version comes from the local project.
RUN pip install -e .
# --- must-NOT-catch: install from a local wheel -- the artifact IS the pin.
RUN pip install ./dist/mypkg-1.0.0-py3-none-any.whl
# --- must-NOT-catch: apt with a version pin.
RUN apt-get install -y nginx=1.24.0-1
# --- must-NOT-catch: apk with a version pin.
RUN apk add openssl=3.1.4-r5
# --- must-NOT-catch: a model URL pinned to a revision SHA rather than a branch.
RUN curl -L https://huggingface.co/eachadea/ggml-vicuna-13b-1.1/resolve/0c42ebe3d411ec4e24259cefb06dcc322279c7aa/model.bin -o model.bin

# --- DOCUMENTED FALSE POSITIVE, locked here as a tested fact (not a must-NOT-catch). Generic mode
# --- matches raw text and has NO notion of a comment or a string literal, so an install command
# --- mentioned in prose fires exactly like a real one. This is the rule's headline blind spot; the
# --- header documents it, and the must-catch annotation below means a future rewrite that DOES
# --- learn to skip comments will flip the fixture test to fail and force this note to be updated.
# --- (This prose must never spell the annotation keyword followed by a colon: semgrep reads it as a
# --- real annotation wherever it appears -- the same gotcha the yaml-unpinned fixture header hit.)
# ruleid: sh-unpinned-package-install
# a deploy note: run pip install foo before first boot
# ruleid: sh-unpinned-package-install
RUN echo "reminder: apt-get install nginx by hand is not reproducible"
