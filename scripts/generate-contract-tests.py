"""
Citadel Contract Test Generator

Generates .http contract test files from OpenAPI spec files.
Reads specs under bicep/infra/modules/apim/ and produces
ready-to-use HTTP request files for each API surface.

Usage:
    python scripts/generate-contract-tests.py
    python scripts/generate-contract-tests.py --spec bicep/infra/modules/apim/universal-llm-api/Universal-LLM-Basic-API.openapi.yaml
    python scripts/generate-contract-tests.py --output src/testing/generated
"""

import argparse
import glob
import json
import os
import sys

try:
    import yaml
except ImportError:
    print("PyYAML is required. Install with: pip install pyyaml")
    sys.exit(1)


def load_spec(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def generate_sample_body(schema: dict, spec: dict, depth: int = 0) -> dict | list | str:
    """Generate a minimal sample request body from an OpenAPI schema."""
    if depth > 5:
        return {}

    if "$ref" in schema:
        ref_path = schema["$ref"].lstrip("#/").split("/")
        resolved = spec
        for part in ref_path:
            resolved = resolved.get(part, {})
        return generate_sample_body(resolved, spec, depth + 1)

    schema_type = schema.get("type", "object")

    if schema_type == "array":
        items = schema.get("items", {})
        return [generate_sample_body(items, spec, depth + 1)]

    if schema_type == "object" or "properties" in schema:
        result = {}
        props = schema.get("properties", {})
        required = schema.get("required", [])
        for name, prop in props.items():
            if name in required or len(result) < 3:
                result[name] = generate_sample_value(name, prop, spec, depth)
        return result

    return generate_sample_value("", schema, spec, depth)


def generate_sample_value(name: str, schema: dict, spec: dict, depth: int) -> object:
    """Generate a sample value for a schema property."""
    if "$ref" in schema:
        return generate_sample_body(schema, spec, depth + 1)

    if "example" in schema:
        return schema["example"]

    if "default" in schema:
        return schema["default"]

    if "enum" in schema:
        return schema["enum"][0]

    schema_type = schema.get("type", "string")
    type_samples = {
        "string": f"sample-{name}" if name else "sample",
        "integer": 1,
        "number": 1.0,
        "boolean": True,
        "array": [],
        "object": {},
    }
    return type_samples.get(schema_type, "")


def generate_http_tests(spec_path: str, spec: dict, base_url_var: str) -> str:
    """Generate .http file content from an OpenAPI spec."""
    lines = []
    title = spec.get("info", {}).get("title", os.path.basename(spec_path))
    version = spec.get("info", {}).get("version", "unknown")

    lines.append(f"# Contract Tests: {title} (v{version})")
    lines.append(f"# Auto-generated from: {spec_path}")
    lines.append(f"# Run with VS Code REST Client or httpYac")
    lines.append("")
    lines.append(f'@baseUrl = {{{{{base_url_var}}}}}')
    lines.append('@apiKey = ""')
    lines.append("")

    paths = spec.get("paths", {})
    for path, methods in paths.items():
        for method in ["get", "post", "put", "patch", "delete"]:
            if method not in methods:
                continue

            operation = methods[method]
            op_id = operation.get("operationId", f"{method}_{path}")
            summary = operation.get("summary", op_id)
            tags = operation.get("tags", [])
            tag_str = f" [{', '.join(tags)}]" if tags else ""

            lines.append(f"### {summary}{tag_str}")

            # Build query parameters
            query_params = []
            for param in operation.get("parameters", []):
                if param.get("in") == "query":
                    default = param.get("schema", {}).get("default", "")
                    if param.get("required") and default:
                        query_params.append(f"{param['name']}={default}")

            query_string = f"?{'&'.join(query_params)}" if query_params else ""
            lines.append(f"{method.upper()} {{{{baseUrl}}}}{path}{query_string}")
            lines.append("Content-Type: application/json")
            lines.append("api-key: {{apiKey}}")

            # Add request body for POST/PUT/PATCH
            if method in ("post", "put", "patch"):
                body_content = (
                    operation.get("requestBody", {})
                    .get("content", {})
                    .get("application/json", {})
                )
                body_schema = body_content.get("schema", {})
                body_example = body_content.get("example")

                if body_example:
                    sample = body_example
                elif body_schema:
                    sample = generate_sample_body(body_schema, spec)
                else:
                    sample = {}

                lines.append("")
                lines.append(json.dumps(sample, indent=2))

            lines.append("")

    return "\n".join(lines)


def get_base_url_var(spec_path: str) -> str:
    """Derive a base URL variable name from the spec path."""
    dir_name = os.path.basename(os.path.dirname(spec_path))
    clean = dir_name.replace("-", "_").replace(" ", "_")
    return f"{clean}_base_url"


def main():
    parser = argparse.ArgumentParser(description="Generate contract tests from OpenAPI specs")
    parser.add_argument(
        "--spec",
        help="Path to a specific OpenAPI spec file. If omitted, processes all specs.",
    )
    parser.add_argument(
        "--output",
        default="src/testing/generated",
        help="Output directory for generated .http files (default: src/testing/generated)",
    )
    args = parser.parse_args()

    # Find repo root (where .spectral.yaml lives)
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(repo_root)

    if args.spec:
        spec_files = [args.spec]
    else:
        spec_files = sorted(
            glob.glob("bicep/infra/modules/apim/**/*.yaml", recursive=True)
        )

    if not spec_files:
        print("No spec files found.")
        sys.exit(1)

    os.makedirs(args.output, exist_ok=True)

    generated = 0
    for spec_path in spec_files:
        try:
            spec = load_spec(spec_path)
        except Exception as e:
            print(f"  SKIP {spec_path}: {e}")
            continue

        if not isinstance(spec, dict) or "openapi" not in spec:
            continue

        paths = spec.get("paths", {})
        if not paths:
            print(f"  SKIP {spec_path}: no paths defined")
            continue

        base_url_var = get_base_url_var(spec_path)
        content = generate_http_tests(spec_path, spec, base_url_var)

        # Output filename from spec filename
        basename = os.path.splitext(os.path.basename(spec_path))[0]
        output_file = os.path.join(args.output, f"{basename}.http")

        with open(output_file, "w", encoding="utf-8") as f:
            f.write(content)

        op_count = sum(
            1
            for methods in paths.values()
            for m in methods
            if m in ("get", "post", "put", "patch", "delete")
        )
        print(f"  OK   {output_file} ({op_count} operations)")
        generated += 1

    print(f"\nGenerated {generated} contract test file(s) in {args.output}/")


if __name__ == "__main__":
    main()
