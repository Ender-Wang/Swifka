---
name: Bug report
about: Create a report to help us improve
title: "\U0001F41B Bug report: "
labels: bug
assignees: Ender-Wang

---

**Describe the bug**

A clear and concise description of what the bug is.

**To Reproduce**

Steps to reproduce the behavior:

1. Go to '...'
2. Click on '...'
3. See error

**Expected behavior**

A clear and concise description of what you expected to happen.

**Screenshots**

If applicable, add screenshots to help explain your problem.

**Environment**

- macOS version: [e.g. 15.7]
- Swifka version: [e.g. v0.23]
- Kafka cluster: [e.g. Redpanda, Confluent, Apache Kafka]

**Cluster configuration (if relevant)**

- Number of brokers: [e.g. 3]
- Authentication: [e.g. None, SASL/PLAIN, SASL/SCRAM]
- Schema Registry: [Yes/No]

**Console.app logs**

Swifka uses Apple's unified logging. To capture logs:

1. Open **Console.app** (Spotlight → "Console")
2. In the search bar, type: `subsystem:io.github.ender-wang.Swifka`
3. Click the **Action menu** (gear icon) → check **Include Info Messages** and **Include Debug Messages**
4. Click **Start Streaming**
5. Reproduce the issue in Swifka
6. Select the relevant log entries → **Edit → Copy** (Cmd+C)
7. Paste below:

<details>
<summary>Console.app logs</summary>

```

Paste logs here

```

</details>

**Additional context**

Add any other context about the problem here.
