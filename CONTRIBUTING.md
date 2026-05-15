# Contributing to Citadel Governance Hub

This project welcomes contributions and suggestions. Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit [Contributor License Agreements](https://cla.opensource.microsoft.com).

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

- [Code of Conduct](#coc)
- [Issues and Bugs](#issue)
- [Feature Requests](#feature)
- [Submission Guidelines](#submit)
- [Spec-Driven Development](#spec-driven)
- [Development Environment](#dev-env)

## <a name="coc"></a> Code of Conduct

Help us keep this project open and inclusive. Please read and follow our [Code of Conduct](https://opensource.microsoft.com/codeofconduct/).

## <a name="issue"></a> Found an Issue?

If you find a bug in the source code or a mistake in the documentation, you can help us by
[submitting an issue](#submit-issue) to the GitHub Repository. Even better, you can
[submit a Pull Request](#submit-pr) with a fix.

## <a name="feature"></a> Want a Feature?

You can *request* a new feature by [submitting an issue](#submit-issue) to the GitHub
Repository. If you would like to *implement* a new feature, please submit an issue with
a proposal for your work first, to be sure that we can use it.

* **Small Features** can be crafted and directly [submitted as a Pull Request](#submit-pr).

## <a name="submit"></a> Submission Guidelines

### <a name="submit-issue"></a> Submitting an Issue

Before you submit an issue, search the archive, maybe your question was already answered.

If your issue appears to be a bug, and hasn't been reported, open a new issue.
Help us to maximize the effort we can spend fixing issues and adding new
features, by not reporting duplicate issues. Providing the following information will increase the
chances of your issue being dealt with quickly:

* **Overview of the Issue** - if an error is being thrown a non-minified stack trace helps
* **Version** - what version is affected (e.g. 0.1.2)
* **Motivation for or Use Case** - explain what are you trying to do and why the current behavior is a bug for you
* **Reproduce the Error** - provide a live example or an unambiguous set of steps
* **Related Issues** - has a similar issue been reported before?
* **Suggest a Fix** - if you can't fix the bug yourself, perhaps you can point to what might be
  causing the problem (line of code or commit)

You can file new issues at the [GitHub Issues](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/issues/new) page.

### <a name="submit-pr"></a> Submitting a Pull Request (PR)

Before you submit your Pull Request (PR) consider the following guidelines:

* Search the repository's [pull requests](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/pulls) for an open or closed PR
  that relates to your submission. You don't want to duplicate effort.
* Make your changes in a new git fork.
* Commit your changes using a descriptive commit message.
* Push your fork to GitHub.
* In GitHub, create a pull request.
* If we suggest changes then:
  * Make the required updates.
  * Rebase your fork and force push to your GitHub repository (this will update your Pull Request):

    ```shell
    git rebase main -i
    git push -f
    ```

That's it! Thank you for your contribution!

---

## <a name="spec-driven"></a> Spec-Driven Development

Citadel follows a **spec-driven development** approach. If your contribution involves API changes, you must follow the spec-first workflow. For the full guide, see [Spec-Driven Development Guide](./guides/spec-driven-development.md).

### Before You Code

1. **Define or update the OpenAPI spec** under `bicep/infra/modules/apim/`.
2. **Lint the spec locally**:
   ```bash
   npm install    # first time only
   npm run lint:specs
   ```
3. **Check for breaking changes** if modifying an existing spec:
   ```bash
   oasdiff breaking <original-spec> <modified-spec>
   ```

### PR Checklist for API Changes

Before submitting your pull request, ensure:

- [ ] **Spec linting passes** — `npm run lint:specs` exits with 0 errors
- [ ] **No unintended breaking changes** — oasdiff reports no breaking changes, or they are intentional and documented
- [ ] **New specs follow naming conventions** — `*-api-spec.yaml` or `*.openapi.yaml`
- [ ] **Operations have `operationId`** — required for all API operations
- [ ] **Operations are tagged** — recommended for API Center categorization
- [ ] **`info.version` is set** — required in all spec files
- [ ] **Bicep modules updated** — if adding a new API, wire it into the APIM Bicep modules
- [ ] **Documentation updated** — update relevant guides if behavior changes

### Types of Contributions

| Type | Guidelines |
|------|-----------|
| 🐛 **Bug Fixes** | Describe the bug and the fix in the PR description |
| 📐 **API Spec Changes** | Follow the [Spec-Driven Development Guide](./guides/spec-driven-development.md). Breaking changes require a new versioned spec file |
| 🏗️ **Infrastructure (Bicep)** | Test with `azd provision --no-prompt` in a dev environment. Follow existing naming patterns in `bicep/infra/modules/` |
| 📖 **Documentation** | Keep guides in `guides/` directory. Update the README if adding new guides or features |
| 🔐 **Access Contracts** | Follow the [Access Contracts Guide](./bicep/infra/citadel-access-contracts/README.md). Ensure referenced APIs have validated specs |

---

## <a name="dev-env"></a> Development Environment

### Prerequisites

- **Node.js 20+** — for spec linting tooling
- **Azure CLI** — for infrastructure deployment
- **Azure Developer CLI (azd)** — for `azd up` / `azd deploy`
- **Python 3.10+** — for validation notebooks
- **Jupyter** — for running validation notebooks

### Useful Commands

| Command | Description |
|---------|-------------|
| `npm run lint:specs` | Lint all API specs (errors fail CI) |
| `npm run lint:spec -- <file>` | Lint a specific spec file |
| `npm run validate` | Run all validations |
| `azd provision` | Provision Azure infrastructure |
| `azd deploy` | Deploy application components |

### CI/CD Pipelines

| Pipeline | Trigger | What it does |
|----------|---------|-------------|
| `azure-dev.yml` | Push to `main` | Provisions infrastructure and deploys |
| `spec-validation.yml` (GitHub) | PRs modifying specs | Lints specs + detects breaking changes |
| `spec-validation.yml` (ADO) | PRs modifying specs | Lints specs + detects breaking changes |
