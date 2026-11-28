
# XMOS Application Note Agent Guidance

Before making changes, read the repository-specific guidance below and the
[XMOS agent instructions](https://github.com/xmos/xskills/blob/main/AGENTS.md).
Follow the central instructions to identify and consult relevant xskills guidance.

If central guidance is inaccessible, use this repository's README and relevant
documentation, and report the access limitation and any material verification gaps.

## Repository-Specific Guidance

<!--
Add only information an agent needs that this repository's README and
documentation do not already cover. Link to that documentation rather than
repeating it, and do not duplicate shared xskills instructions. Leave this
section empty if there is nothing to add.
-->

This application note is example code. Implementation choices favour small,
readable code over completeness, so review any code you reuse against your
product's requirements. Known limitations are listed in the README and in the
application note's "Web demo and limitations" section. In addition:

- The demonstration TCP in `app_an02062/src/eth_tcp/` ignores incoming
  acknowledgements, always starts at sequence number 0, tracks at most four
  connections keyed on the client's source port, and closes each connection
  with its single response segment. The DHCP server offers one address with no
  lease tracking. For a product network stack, use a maintained stack such as
  lib_xtcp rather than building on this code.
- The NCM transport does not handle the host halting its endpoints.

