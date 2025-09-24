# NiFi Registry CI/CD Automation

## 📖 Overview

This repository contains a set of Bash scripts designed to demostrate how to automate a **Continuous Integration / Continuous Deployment (CI/CD)** workflow for **Apache NiFi flows**.

The automation is triggered by a NiFi Registry event (e.g., `CREATE_FLOW_VERSION`), and uses `hook_script.sh` to:

- Export the flow from a development NiFi Registry.
- Transfer it securely to a production host.
- Execute `import_script.sh` on the production host to complete the deployment based on flags in the commit message.

---

## 📜 Scripts

### `hook_script.sh`

The **entry point** for the automation, designed to be triggered by a NiFi Registry hook.

#### Core Functions:

- **Export**: Exports a specific flow version as a JSON file.
- **Remote Transfer**: Uses `scp` to securely copy the flow's JSON file to the production host.
- **Conditional Execution**: Executes `import_script.sh` on the remote host using SSH, based on deployment flags found in the commit comment (`PRODREADY`, `AUTO`, `NEW`).

---

### `import_script.sh`

Runs on the **production host** and handles the actual import and optional deployment.

#### Core Functions:

- **Mapping Lookup**: Uses `mapping.tsv` to map the development flow ID to the production flow ID and process group ID.
- **Import**: Imports the new flow version into the production NiFi Registry.
- **Conditional Deployment**:
  - Create a new process group.
  - Update an existing one.
  - Only import into NiFi Registry (without deploying to the canvas).

---

## ⚙️ Configuration Files

The following configuration files are required and should be present in the repository:

- `cli.properties` and `registrycli.properties`: Configuration files for NiFi CLI and NiFi Registry CLI.
- `mapping.tsv`: Tab-separated file mapping:
  - **REMOTE FLOWID** (from dev) → **LOCAL FLOWID** and **LOCAL PROCESS GROUP** (on prod).

---

## ✅ Prerequisites

Ensure the following dependencies are met on **both** the development and production hosts:

- **Bash**: Scripts must run in a Unix/Linux environment.
- **Kerberos**: A valid Kerberos principal/keytab (e.g., `gtorres@MIT.SUPPORTLAB.COM`) must be configured.
- **SSH**: Password-less SSH access between hosts using private/public keys.
- **CLI Tools**:
  - NiFi CLI (`cli.sh`)
  - NiFi Registry CLI (`cli.sh`)
- **jq**: JSON processor for parsing API responses.

---

## 🚀 Usage

### Script Invocation

The `hook_script.sh` must be added in the NiFi Registry configuration as a ScriptEventHookProvider, for more details please refer to the NiFi Registry admin doc:
https://nifi.apache.org/docs/nifi-registry-docs/html/administration-guide.html#scripteventhookprovider


The script is invoked by NiFi Registry as follows:
```bash
hook_script.sh <EVENT> <BUCKET_ID> <FLOW_ID> <VERSION> <AUTHOR> <COMMENT>

| Argument    | Description                                          |
| ----------- | ---------------------------------------------------- |
| `EVENT`     | Must be `CREATE_FLOW_VERSION` to trigger the script. |
| `BUCKET_ID` | The unique ID of the source bucket.                  |
| `FLOW_ID`   | The unique ID of the flow.                           |
| `VERSION`   | The version number to export.                        |
| `AUTHOR`    | The author of the version change.                    |
| `COMMENT`   | A string containing deployment flags.                |


```

## Deployment Flags in COMMENT

These flags control behavior on the remote (production) host:

`PRODREADY`: Required flag to trigger deployment.

`AUTO`: If also present, the new flow version is automatically applied to the process group on the canvas.

`NEW`: If combined with PRODREADY and AUTO, this creates a new flow and process group. Without it, the script assumes it is updating an existing group.


## 📂 Example Workflow

1. A developer commits a change to a flow in the development NiFi Registry.

2. The hook script is triggered by NiFi Registry, for example:

```
hook_script.sh CREATE_FLOW_VERSION "id-bucket-123" "id-flow-456" "1" "dev-user" "Added new processor. PRODREADY AUTO"
```

3. hook_script.sh:

  Exports the flow as JSON.

  Copies it to the production host.

  Executes import_script.sh remotely with deployment flags.

4. import_script.sh on the production host:

  Imports the new version.

  Updates the target process group on the NiFi canvas.

