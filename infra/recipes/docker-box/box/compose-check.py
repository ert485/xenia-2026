#!/usr/bin/env python3
"""Preview isolation check for a team's compose file (spec section 9, D36).

Usage: compose-check.py <compose-file> <project-dir>

A preview is arbitrary code from a teammate running on the box that holds the gateway and its
keys. This refuses any compose file that would leave its project directory or share a namespace
with the host. Exit 1 with one reason per line on stdout; exit 0 when clean. Warnings go to stderr.
"""
import os
import sys

import yaml


class Loader(yaml.SafeLoader):
    """SafeLoader that tolerates Compose's !reset and !override merge tags."""


def _passthrough(loader, node):
    if isinstance(node, yaml.MappingNode):
        return loader.construct_mapping(node, deep=True)
    if isinstance(node, yaml.SequenceNode):
        return loader.construct_sequence(node, deep=True)
    return loader.construct_scalar(node)


for _tag in ("!reset", "!override"):
    Loader.add_constructor(_tag, _passthrough)

DANGEROUS_CAPS = {"ALL", "SYS_ADMIN", "SYS_MODULE", "SYS_RAWIO", "SYS_PTRACE", "SYS_BOOT",
                  "DAC_READ_SEARCH", "BPF", "PERFMON", "NET_ADMIN"}
HOST_NAMESPACE_KEYS = ("network_mode", "pid", "ipc", "uts", "userns_mode", "cgroup")


def truthy(value):
    return value is True or str(value).strip().lower() in ("true", "yes", "on", "1")


def inside(project_dir, path):
    """True when path, resolved against project_dir, stays inside project_dir."""
    if path.startswith("~"):
        return False
    root = os.path.realpath(project_dir)
    full = os.path.realpath(os.path.join(root, path))
    return full == root or full.startswith(root + os.sep)


def is_host_path(source):
    return source.startswith(("/", ".", "~"))


def check_path(reasons, where, what, path, project_dir):
    if "$" in path:
        reasons.append(f"{where}: variable in a host path ({what}): {path}")
    elif not inside(project_dir, path):
        reasons.append(f"{where}: {what} outside the project directory: {path}")


def check_volume(reasons, where, vol, project_dir):
    if isinstance(vol, str):
        source = vol.split(":", 1)[0] if ":" in vol else ""
        kind = "bind" if is_host_path(source) or "$" in source else "volume"
    elif isinstance(vol, dict):
        source = str(vol.get("source", ""))
        kind = str(vol.get("type", "volume"))
    else:
        reasons.append(f"{where}: unreadable volume entry")
        return
    if source.endswith("docker.sock"):
        reasons.append(f"{where}: mounts the Docker socket")
        return
    if "$" in source:
        reasons.append(f"{where}: variable in a host path (volume): {source}")
        return
    if kind == "bind" and not inside(project_dir, source):
        reasons.append(f"{where}: bind mount outside the project directory: {source}")


def check_build(reasons, where, build, project_dir):
    if isinstance(build, str):
        build = {"context": build}
    if not isinstance(build, dict):
        return
    context = str(build.get("context", "."))
    if "://" not in context:
        check_path(reasons, where, "build context", context, project_dir)
    if "dockerfile" in build:
        check_path(reasons, where, "dockerfile", os.path.join(context, str(build["dockerfile"])), project_dir)
    if str(build.get("network", "")).lower() == "host":
        reasons.append(f"{where}: build.network: host")
    if truthy(build.get("privileged", False)) or build.get("entitlements"):
        reasons.append(f"{where}: privileged build")
    extra = build.get("additional_contexts") or {}
    items = extra.values() if isinstance(extra, dict) else [str(e).split("=", 1)[-1] for e in extra]
    for ctx in items:
        ctx = str(ctx)
        if "://" not in ctx and not ctx.startswith("service:"):
            check_path(reasons, where, "build additional context", ctx, project_dir)


def check_service(reasons, warnings, name, svc, project_dir):
    where = f"service {name}"
    if not isinstance(svc, dict):
        reasons.append(f"{where}: unreadable service definition")
        return
    if truthy(svc.get("privileged", False)):
        reasons.append(f"{where}: privileged: true")
    for key in HOST_NAMESPACE_KEYS:
        value = str(svc.get(key, ""))
        if value == "host" or value.startswith("container:"):
            reasons.append(f"{where}: {key}: {value}")
        elif "$" in value:
            reasons.append(f"{where}: variable in {key}")
    for cap in svc.get("cap_add") or []:
        if str(cap).upper().removeprefix("CAP_") in DANGEROUS_CAPS:
            reasons.append(f"{where}: cap_add {cap}")
    for opt in svc.get("security_opt") or []:
        if "unconfined" in str(opt) or "disable" in str(opt):
            reasons.append(f"{where}: security_opt {opt}")
    if svc.get("devices"):
        reasons.append(f"{where}: devices are not allowed in a preview")
    if svc.get("volumes_from"):
        reasons.append(f"{where}: volumes_from is not allowed in a preview")
    if svc.get("external_links"):
        reasons.append(f"{where}: external_links is not allowed in a preview")
    extends = svc.get("extends")
    if isinstance(extends, dict) and "file" in extends:
        reasons.append(f"{where}: extends from another file is not allowed in a preview")
    for vol in svc.get("volumes") or []:
        check_volume(reasons, where, vol, project_dir)
    env_files = svc.get("env_file") or []
    for ef in ([env_files] if isinstance(env_files, (str, dict)) else env_files):
        path = str(ef.get("path", "")) if isinstance(ef, dict) else str(ef)
        check_path(reasons, where, "env_file", path, project_dir)
    if "build" in svc:
        check_build(reasons, where, svc["build"], project_dir)
    nets = svc.get("networks") or []
    for net in (nets if isinstance(nets, list) else nets.keys()):
        if str(net) == "gateway":
            reasons.append(f"{where}: joins the gateway network")
    if svc.get("ports"):
        warnings.append(f"warning: {where}: ports are ignored in previews (the kit's override resets them; Caddy routes pr-<n>.box.)")


def check_top_level(reasons, doc, project_dir):
    if doc.get("include"):
        reasons.append("top-level include: is not allowed in a preview (the checker cannot see included files)")
    for name, net in (doc.get("networks") or {}).items():
        net = net or {}
        external = truthy(net.get("external", False)) if isinstance(net, dict) else False
        explicit = str(net.get("name", "")) if isinstance(net, dict) else ""
        if (external or explicit) and (explicit or name) != "edge":
            reasons.append(f"top-level network {name}: external networks other than edge, and explicit names, are not allowed")
        if isinstance(net, dict) and str(net.get("driver", "")) == "host":
            reasons.append(f"top-level network {name}: driver host")
    for name, vol in (doc.get("volumes") or {}).items():
        vol = vol or {}
        if not isinstance(vol, dict):
            continue
        if truthy(vol.get("external", False)):
            reasons.append(f"top-level volume {name}: external volumes are not allowed")
        if vol.get("name"):
            reasons.append(f"top-level volume {name}: explicit name (it could mount another project's data)")
        if vol.get("driver_opts"):
            reasons.append(f"top-level volume {name}: driver_opts (a bind mount in disguise)")
    for section in ("secrets", "configs"):
        for name, item in (doc.get(section) or {}).items():
            item = item or {}
            if not isinstance(item, dict):
                continue
            if truthy(item.get("external", False)):
                reasons.append(f"top-level {section[:-1]} {name}: external {section} are not allowed")
            if "file" in item:
                check_path(reasons, f"top-level {section[:-1]} {name}", "file", str(item["file"]), project_dir)


def main(argv):
    if len(argv) != 3:
        print("usage: compose-check.py <compose-file> <project-dir>", file=sys.stderr)
        return 2
    compose_file, project_dir = argv[1], argv[2]
    try:
        with open(compose_file, encoding="utf-8") as fh:
            doc = yaml.load(fh, Loader=Loader) or {}
    except (OSError, yaml.YAMLError) as err:
        print(f"cannot read {compose_file}: {err}")
        return 1
    reasons, warnings = [], []
    services = doc.get("services") or {}
    if "web" not in services:
        reasons.append("needs a service named web (the kit routes pr-<n>.box. to it)")
    for name, svc in services.items():
        check_service(reasons, warnings, name, svc, project_dir)
    check_top_level(reasons, doc, project_dir)
    for w in warnings:
        print(w, file=sys.stderr)
    for r in reasons:
        print(r)
    return 1 if reasons else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
